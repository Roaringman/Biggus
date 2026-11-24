-- Biggus sync: carries the bank, run, death and loot messages between the guild's Biggus users.
--
-- Forever's live realms refuse addon messages sent to the guild channel, but hidden whispers get
-- through (ForeverTrading found the same). So everything goes by hidden whisper, player to player:
--  * Hello: on login, and when a guild member comes online, Biggus whispers "H" to the online guild
--    members it knows have Biggus, and - at most once a day each - to the ones it doesn't know yet.
--    Those with Biggus answer "HA"; from then on they are known (saved, per guild). Players without
--    Biggus never see any of it.
--  * Catch-up: when two copies meet (an H or HA arrives), each sends the other everything it learned
--    since they last met - bank entries, the bank's gold, the goal, runs with their deaths and loot.
--    So members who were offline get what they missed, and it spreads from copy to copy.
--  * Live: what happens while you play (a new run, a death, a drop, a bank visit) goes straight to
--    every known Biggus user online.
-- Duplicates are harmless: every message is merged so that getting it twice changes nothing.
-- The game lets each message prefix send about one message a second, so Biggus sends on three
-- prefixes ("lanes") at once: three messages a second, live ones before catch-up.
--
-- Messages: "H" / "HA" hello and its answer: kind, protocol, Biggus version. Bank (B, M, G):
-- Biggus.lua. Runs (R, X, L): Dungeons.lua.

local ADDON, B = ...
local S = {}
B.Sync = S

local PREFIXES = { "BIGGUS", "BIGGUS2", "BIGGUS3" }
local PROTO = "2"
local MARGIN = 2 * 3600         -- a catch-up starts this long before the last one, to be safe
local PROBE_EVERY = 24 * 3600   -- guild members not known to have Biggus are asked at most this often
local FAIL_PAUSE = 5            -- seconds to stop sending after a refused message
local MAX_TRIES = 3

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local VERSION = (GetMetadata and GetMetadata(ADDON, "Version")) or "?"

local live, bulk = {}, {}       -- waiting messages: { to = whisper target, msg = text, tries = n }
local online = {}               -- name -> whisper target: guild members online now
local helloed = {}              -- name -> true: said hello this session (forgotten when they log off)
local caughtUp = {}             -- name -> GetTime() of the last catch-up sent to them
local whisperedAt = {}          -- whisper target -> GetTime(): for hiding the game's "no player named"
local counts = { sent = 0, received = 0, failed = 0 }
local lastError, lastFrom
local pausedUntil = 0

local function Store()
    local g = B.Guild()
    if not g then return nil end
    g.peers = g.peers or {}     -- name -> { target, version, seen, lastSync }
    g.probed = g.probed or {}   -- name -> when a hello last went to them
    return g
end

local function Me()
    return B.UnitName("player")
end

local function IsOurs(prefix)
    for _, p in ipairs(PREFIXES) do
        if p == prefix then return true end
    end
    return false
end

-- where to whisper a player: as the game wrote their name in their last message, else the roster's
local function Target(name)
    local g = Store()
    local peer = g and g.peers[name]
    return (peer and peer.target) or online[name]
end

local function Push(queue, to, msg)
    if not to then return nil end
    for _, item in ipairs(queue) do
        if item.to == to and item.msg == msg then return item end
    end
    local item = { to = to, msg = msg, tries = 0 }
    table.insert(queue, item)
    return item
end

---------------------------------------------------------------------------------------------------
-- Sending

local function SendNow(prefix, item)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "no addon message API" end
    whisperedAt[item.to] = GetTime()
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, prefix, item.msg, "WHISPER", item.to)
    if not ok then return false, tostring(res) end
    if res == false then return false, "refused" end
    -- newer clients answer with a result code: Success (0) is "sent"
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    if type(res) == "number" and res ~= success then return false, "result code " .. res end
    return true
end

-- every second: up to one message per lane
local function Tick()
    if GetTime() < pausedUntil then return end
    for _, prefix in ipairs(PREFIXES) do
        local queue = live[1] and live or bulk
        local item = table.remove(queue, 1)
        if not item then return end
        local ok, err = SendNow(prefix, item)
        if ok then
            counts.sent = counts.sent + 1
            if item.syncDone then item.syncDone() end -- the last message of a catch-up went out
        else
            counts.failed = counts.failed + 1
            lastError = err .. " (to " .. item.to .. ")"
            item.tries = item.tries + 1
            if item.tries < MAX_TRIES then table.insert(queue, item) end
            pausedUntil = GetTime() + FAIL_PAUSE
            return
        end
    end
end

-- a live message to every known Biggus user online
function S.Broadcast(msg)
    if not B.Opt("share") then return end
    local g = Store()
    if not g then return end
    for name in pairs(online) do
        if g.peers[name] then Push(live, Target(name), msg) end
    end
end

---------------------------------------------------------------------------------------------------
-- Hello and catch-up

local function Hello(name, answer)
    local to = Target(name)
    local g = Store()
    if not to or not g then return end
    helloed[name] = true
    g.probed[name] = B.Now()
    Push(live, to, table.concat({ answer and "HA" or "H", PROTO, VERSION }, "\t"))
end

-- everything learned since we last caught this player up
local function CatchUp(name)
    if not B.Opt("share") then return end
    if caughtUp[name] and GetTime() - caughtUp[name] < 60 then return end -- both sides said hello at once
    local g = Store()
    local peer = g and g.peers[name]
    local to = Target(name)
    if not peer or not to then return end
    caughtUp[name] = GetTime()
    local since, now = (peer.lastSync or 0) - MARGIN, B.Now()
    local msgs = B.BankCatchUp(since)
    for _, msg in ipairs(B.Dungeons.CatchUp(since)) do table.insert(msgs, msg) end
    local last
    for _, msg in ipairs(msgs) do last = Push(bulk, to, msg) end
    -- it counts as caught up once the last message has gone (not when you log off before that)
    local function Done() peer.lastSync = now end
    if last then last.syncDone = Done else Done() end
end

local function ScanRoster()
    local g = Store()
    if not g or not GetNumGuildMembers then return end
    local me, now, seen = Me(), B.Now(), {}
    for i = 1, (GetNumGuildMembers() or 0) do
        local rosterName, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        local name = B.Canon(rosterName)
        if name and isOnline and name ~= me then
            seen[name] = true
            online[name] = online[name] or (rosterName:gsub("%-$", ""))
            if not helloed[name] then
                local probed = g.probed[name]
                if g.peers[name] or not probed or now - probed > PROBE_EVERY then Hello(name) end
            end
        end
    end
    for name in pairs(online) do
        if not seen[name] then
            online[name], helloed[name] = nil, nil
        end
    end
end

local function RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

---------------------------------------------------------------------------------------------------
-- Receiving

local function Receive(prefix, text, sender)
    if not IsOurs(prefix) or type(text) ~= "string" or type(sender) ~= "string" then return end
    local from = B.Canon(sender)
    if not from or from == Me() then return end
    local g = Store()
    if not g then return end
    counts.received = counts.received + 1
    lastFrom = from
    local peer = g.peers[from] or {}
    g.peers[from] = peer
    peer.target = sender:gsub("%-$", "")
    peer.seen = B.Now()
    online[from] = online[from] or peer.target

    local f = { strsplit("\t", text) }
    local kind = f[1]
    if kind == "H" or kind == "HA" then
        peer.version = f[3]
        if kind == "H" then Hello(from, true) end
        CatchUp(from)
    elseif kind == "R" or kind == "X" or kind == "L" then
        B.Dungeons.Receive(f)
    elseif kind == "B" or kind == "M" or kind == "G" then
        B.BankReceive(f)
    end
end

---------------------------------------------------------------------------------------------------
-- The game's "No player named 'X' is currently playing." for our hidden whispers: hidden, and that
-- player taken as offline

local notFoundPattern
local function HideNotFound(_, _, msg)
    if not notFoundPattern then
        local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
        notFoundPattern = "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
    end
    local target = type(msg) == "string" and msg:match(notFoundPattern)
    if target and whisperedAt[target] and GetTime() - whisperedAt[target] < 10 then
        local name = B.Canon(target)
        if name then online[name], helloed[name] = nil, nil end
        return true
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- Status and /biggus sync

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function OnlinePeers()
    local g, n = Store(), 0
    if not g then return 0 end
    for name in pairs(online) do
        if g.peers[name] then n = n + 1 end
    end
    return n
end

-- one line for the window
function S.Status()
    if not B.Opt("share") then return "sharing is off" end
    local waiting = #live + #bulk
    return OnlinePeers() .. " Biggus users online" .. (waiting > 0 and (" · " .. waiting .. " messages to send") or "")
end

local function Ago(t)
    if not t then return "never" end
    local s = B.Now() - t
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " days ago"
end

function S.Command(arg)
    local g = Store()
    if not g then
        B.Say("you're not in a guild.")
        return
    end
    if arg == "now" then
        helloed, caughtUp = {}, {}
        for name in pairs(g.probed) do g.probed[name] = nil end
        RequestRoster()
        C_Timer.After(2, ScanRoster)
        B.Say("saying hello to every guild member online. /biggus sync in a minute shows who answered.")
        return
    end
    B.Say("sync - Biggus " .. VERSION .. ", protocol " .. PROTO .. (B.Opt("share") and "" or " · |cffff4444sharing is off in settings|r"))
    B.Say("you are \"" .. (Me() or "?") .. "\" · guild members online: " .. Count(online)
        .. " · Biggus users known: " .. Count(g.peers) .. " (" .. OnlinePeers() .. " online)")
    local names = {}
    for name in pairs(g.peers) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local peer = g.peers[name]
        B.Say("  " .. name .. " - " .. (online[name] and "|cff33ff33online|r" or "offline") .. ", Biggus "
            .. (peer.version or "?") .. ", last heard " .. Ago(peer.seen) .. ", last caught up " .. Ago(peer.lastSync))
    end
    if #names == 0 then
        B.Say("  no other Biggus users found yet. They show up once they log in with Biggus 0.4 or newer.")
    end
    B.Say("messages: " .. #live .. " live and " .. #bulk .. " catch-up waiting · this session: sent "
        .. counts.sent .. ", received " .. counts.received .. ", failed " .. counts.failed
        .. (lastFrom and (" · last from " .. lastFrom) or ""))
    B.Say("last error: " .. (lastError or "none"))
end

---------------------------------------------------------------------------------------------------

local rosterPending = false
local function ScanSoon()
    if rosterPending then return end
    rosterPending = true
    C_Timer.After(2, function()
        rosterPending = false
        ScanRoster()
    end)
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE" }) do
    pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(_, event, a1, a2, _, a4)
    if event == "CHAT_MSG_ADDON" then
        Receive(a1, a2, a4) -- prefix, text, channel, sender
    elseif event == "GUILD_ROSTER_UPDATE" then
        ScanSoon()
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            for _, prefix in ipairs(PREFIXES) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix) end
        end
        if ChatFrame_AddMessageEventFilter then
            ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", HideNotFound)
        end
        C_Timer.NewTicker(1, Tick)
        -- the roster: now (after the login rush), then every minute so logins are noticed
        C_Timer.After(8, RequestRoster)
        C_Timer.NewTicker(60, RequestRoster)
    end
end)
