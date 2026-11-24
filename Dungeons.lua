-- Biggus dungeons: the dungeon runs guild members do together, who died in them, and who got the loot.
--
--  * Entering a 5-player dungeon with at least one other guild member in the group logs a run. Guild
--    members who join later are added to it. Coming back in (after a wipe, say) within an hour, with
--    some of the same people, is still the same run.
--  * Deaths: while you're in a run, the guild members in it are watched; each one going from alive to
--    dead counts a death in that run.
--  * Loot: rare (blue) and better items a guild member in the run loots, read from the loot messages.
--  * All of it is passed on to the other Biggus users in the guild (Sync.lua carries the messages), so
--    each copy counts the whole guild, not only its owner. Copies that were offline catch up the next
--    time they meet one that has it.
--  * Several group members with Biggus all report the same run, deaths and loot; it's recognised as
--    the same (same dungeon, same time, same people), and deaths and loot take the highest count
--    anyone saw rather than adding them up.
--
-- Messages (fields separated by tabs):
--   R  run:    "R", start, last seen, instance ID, dungeon, members (comma separated)
--   X  deaths: "X", run start, instance ID, member, deaths in that run
--   L  loot:   "L", run start, instance ID, member, item ID, how many, quality
--   W  roll won over guildies: "W", run start, instance ID, winner, item ID, "need" or "greed",
--              how many times, how many other guildies rolled on it

local ADDON, B = ...
local D = {}
B.Dungeons = D

local SAME_RUN = 3600       -- seconds: this close in time, same dungeon and same people = the same run
local MIN_LOOT_QUALITY = 3  -- rare (blue) and better
local EPIC = 4
local UNITS = { "player", "party1", "party2", "party3", "party4" }

local DEATH_QUIPS = {
    "%s died. The floor says hi.",
    "%s is inspecting the floor again.",
    "%s has fallen. Someone write it down. (We did.)",
    "%s tried to tank it with their face.",
    "RIP %s. Gone, but very much counted.",
}

local ENVY_QUIPS = {
    "%s got %s. Envy level: high.",
    "%s got %s. Not that anyone's jealous.",
    "%s got %s. The RNG gods have favorites.",
    "%s got %s. Some people have all the luck.",
}

local SELF_LOOT_QUIPS = {
    "You got %s. The guild is pretending to be happy for you.",
    "You got %s. Try not to brag. (Brag a little.)",
}

local BLUE_QUIPS = {
    "%s got %s. Blue, but it counts.",
    "%s got %s. Not purple, but we'll allow it.",
    "%s got %s. A respectable shade of blue.",
}

local SELF_BLUE_QUIPS = {
    "You got %s. A blue! Modest, but yours.",
    "You got %s. Blue suits you.",
}

local Now = B.Now

local function Pick(list)
    return list[math.random(#list)]
end

local statsCache = {}
local function Dirty()
    statsCache = {}
end

-- Biggus 0.3 kept names as "Muliens-Bubbleskull" and had an outbox for the guild channel
local function Migrate(g)
    if g.runsV2 then return end
    for _, r in ipairs(g.runs) do
        for i, x in ipairs(r.members) do r.members[i] = B.Canon(x) or x end
        table.sort(r.members)
        local deaths = {}
        for who, n in pairs(r.deaths or {}) do deaths[B.Canon(who) or who] = n end
        r.deaths = deaths
        local loot = {}
        for _, e in pairs(r.loot or {}) do
            e.who = B.Canon(e.who) or e.who
            loot[e.who .. "|" .. e.id] = e
        end
        r.loot = loot
    end
    g.outbox = nil
    g.runsV2 = true
    Dirty()
end

local function Runs()
    local g = B.Guild()
    if not g then return nil, nil end
    g.runs = g.runs or {}
    Migrate(g)
    D.Prune(g.runs)
    return g.runs, g
end

---------------------------------------------------------------------------------------------------
-- Who's in the group

local FullName = B.UnitName

-- you and the guild members in your party
local function GuildmatesInGroup()
    local names = {}
    local me = FullName("player")
    if me then table.insert(names, me) end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitIsPlayer(unit) and UnitIsInMyGuild(unit) then
            local name = FullName(unit)
            if name then table.insert(names, name) end
        end
    end
    table.sort(names)
    return names
end

-- the run's member with this name (with or without the realm)
local function MemberNamed(r, who)
    who = B.Canon(who)
    if not who then return nil end
    local short = B.ShortName(who)
    for _, x in ipairs(r.members) do
        if x == who or B.ShortName(x) == short then return x end
    end
end

---------------------------------------------------------------------------------------------------
-- Storing runs

local function Overlap(a, b)
    local set, n = {}, 0
    for _, x in ipairs(a) do set[x] = true end
    for _, x in ipairs(b) do
        if set[x] then n = n + 1 end
    end
    return n
end

local function Union(into, names)
    local set, changed = {}, false
    for _, x in ipairs(into) do set[x] = true end
    for _, x in ipairs(names) do
        if not set[x] then
            table.insert(into, x)
            set[x] = true
            changed = true
        end
    end
    if changed then table.sort(into) end
    return changed
end

local function FindRun(runs, run)
    for i = #runs, 1, -1 do
        local r = runs[i]
        if r.id == run.id and run.at <= r.last + SAME_RUN and run.last >= r.at - SAME_RUN
            and Overlap(r.members, run.members) >= 2 then
            return r
        end
    end
end

-- the run of this dungeon around that time that has this member
local function FindRunWith(runs, id, at, who)
    for i = #runs, 1, -1 do
        local r = runs[i]
        if r.id == id and at >= r.at - SAME_RUN and at <= r.last + SAME_RUN and MemberNamed(r, who) then
            return r
        end
    end
end

-- Adds a run, or merges it into the one already known. Returns the stored run, whether it is new,
-- and whether anything about it changed.
local function Record(runs, run)
    Dirty()
    local r = FindRun(runs, run)
    if not r then
        r = { at = run.at, last = run.last, id = run.id, zone = run.zone, members = {}, deaths = {}, loot = {},
              u = Now() } -- u: when this copy last learned something about it (what a catch-up sends)
        Union(r.members, run.members)
        table.insert(runs, r)
        return r, true, true
    end
    local changed = Union(r.members, run.members)
    if run.at < r.at then r.at, changed = run.at, true end
    if run.last > r.last then r.last = run.last end
    if changed then r.u = Now() end
    return r, false, changed
end

-- Deaths and loot keep the highest count anyone saw. src: who reported it (nil: seen by this copy).
local function SetDeaths(r, who, n, src)
    r.deaths = r.deaths or {}
    if n > (r.deaths[who] or 0) then
        r.deaths[who] = n
        r.deathSrc = r.deathSrc or {}
        r.deathSrc[who] = src
        r.u = Now()
        Dirty()
    end
end

local function SetLoot(r, who, itemID, n, quality, src)
    r.loot = r.loot or {}
    local key = who .. "|" .. itemID
    local e = r.loot[key]
    if not e then
        e = { who = who, id = itemID, q = quality, n = 0 }
        r.loot[key] = e
    end
    if n > e.n then
        e.n, e.src = n, src
        r.u = Now()
        Dirty()
    end
end

-- Roll wins over guildies, per run: "winner|item|need" -> { who, id, kind = "need" or "greed", n, beat }
-- n: how many times; beat: how many other guildies rolled on it too. Highest count anyone saw wins.
local function SetRoll(r, who, itemID, kind, n, beat, src)
    r.rolls = r.rolls or {}
    local key = who .. "|" .. itemID .. "|" .. kind
    local e = r.rolls[key]
    if not e then
        e = { who = who, id = itemID, kind = kind, n = 0, beat = 0 }
        r.rolls[key] = e
    end
    if (beat or 0) > e.beat then e.beat = beat end
    if n > e.n then
        e.n, e.src = n, src
        r.u = Now()
        Dirty()
        return true
    end
end

---------------------------------------------------------------------------------------------------
-- Sharing with other Biggus users (Sync.lua carries the messages)

local function Queue(msg)
    B.Sync.Broadcast(msg)
end

local function RunMsg(r)
    return table.concat({ "R", r.at, r.last, r.id or 0, r.zone or "?", table.concat(r.members, ",") }, "\t")
end

local function DeathMsg(r, who)
    return table.concat({ "X", r.at, r.id or 0, who, r.deaths[who] or 0 }, "\t")
end

local function LootMsg(r, e)
    return table.concat({ "L", r.at, r.id or 0, e.who, e.id, e.n, e.q }, "\t")
end

local function RollMsg(r, e)
    return table.concat({ "W", r.at, r.id or 0, e.who, e.id, e.kind, e.n, e.beat }, "\t")
end

-- Everything this copy learned about runs after `since` (server time): each run, then its deaths and
-- loot. That includes runs you only heard about from someone else, so a run keeps spreading from copy
-- to copy after the people who were in it log off.
function D.CatchUp(since, oldest)
    local msgs = {}
    for _, r in ipairs(Runs() or {}) do
        if (r.u or 0) > since and r.last >= (oldest or 0) then
            table.insert(msgs, RunMsg(r))
            for who in pairs(r.deaths or {}) do table.insert(msgs, DeathMsg(r, who)) end
            for _, e in pairs(r.loot or {}) do table.insert(msgs, LootMsg(r, e)) end
            for _, e in pairs(r.rolls or {}) do table.insert(msgs, RollMsg(r, e)) end
        end
    end
    return msgs
end

-- Limits on what one message may claim
local MAX_MEMBERS = 5          -- a 5-player dungeon
local MAX_RUN_SECONDS = 8 * 3600
local MAX_DEATHS = 25          -- per person per run
local MAX_LOOT = 5             -- of one item, per person per run
local MAX_QUALITY = 7

-- f: a message's fields; from: who sent it. Runs are passed on second-hand too (the guild trusts each
-- other), so the sender doesn't have to be in the run. Deaths and loot must still be of the people in
-- the run, and the first reporter of each run is kept (r.src) for /biggus forget.
function D.Receive(f, from)
    local runs = Runs()
    if not runs or not from then return end
    if f[1] == "R" then
        local at, last, id = B.Time(f[2]), B.Time(f[3]), B.Num(f[4], 0, 10000000)
        local zone = B.Text(f[5], 60)
        if not at or not last or not id or not zone or last < at or last - at > MAX_RUN_SECONDS
            or type(f[6]) ~= "string" then
            return
        end
        local members, seen = {}, {}
        for _, x in ipairs({ strsplit(",", f[6]) }) do
            local name = B.CleanName(x)
            if name and not seen[name] then
                seen[name] = true
                table.insert(members, name)
            end
        end
        if #members < 2 or #members > MAX_MEMBERS then return end
        table.sort(members)
        local run = { at = at, last = last, id = id, zone = zone, members = members }
        local existing = FindRun(runs, run)
        if existing then -- adding these people must not make the run bigger than a group can be
            local all = {}
            for _, x in ipairs(existing.members) do all[x] = true end
            for _, x in ipairs(members) do all[x] = true end
            local size = 0
            for _ in pairs(all) do size = size + 1 end
            if size > MAX_MEMBERS then return end
        end
        local r, new = Record(runs, run)
        if new then r.src = from end
    elseif f[1] == "X" or f[1] == "L" or f[1] == "W" then
        local at, id, who = B.Time(f[2]), B.Num(f[3], 0, 10000000), B.CleanName(f[4])
        local r = at and id and who and FindRunWith(runs, id, at, who)
        if not r then return end -- that run's message hasn't come yet
        who = MemberNamed(r, who)
        if f[1] == "X" then
            local n = B.Num(f[5], 1, MAX_DEATHS)
            if n then SetDeaths(r, who, n, from) end
        elseif f[1] == "W" then
            local itemID, kind = B.Num(f[5], 1, 10000000), (f[6] == "need" or f[6] == "greed") and f[6] or nil
            local n, beat = B.Num(f[7], 1, MAX_LOOT), B.Num(f[8], 1, MAX_MEMBERS - 1)
            if itemID and kind and n and beat then SetRoll(r, who, itemID, kind, n, beat, from) end
        else
            local itemID, n, q = B.Num(f[5], 1, 10000000), B.Num(f[6], 1, MAX_LOOT), B.Num(f[7], MIN_LOOT_QUALITY, MAX_QUALITY)
            if itemID and n and q then SetLoot(r, who, itemID, n, q, from) end
        end
    else
        return
    end
    B.Refresh()
end

-- /biggus forget: drops the runs a player reported first and the deaths and loot they reported.
-- Returns how many things went.
function D.Forget(name)
    local runs = Runs()
    if not runs then return 0 end
    local n = 0
    for i = #runs, 1, -1 do
        local r = runs[i]
        if r.src == name then
            table.remove(runs, i)
            n = n + 1
        else
            for who, src in pairs(r.deathSrc or {}) do
                if src == name then
                    r.deaths[who], r.deathSrc[who] = nil, nil
                    n = n + 1
                end
            end
            for key, e in pairs(r.loot or {}) do
                if e.src == name then
                    r.loot[key] = nil
                    n = n + 1
                end
            end
            for key, e in pairs(r.rolls or {}) do
                if e.src == name then
                    r.rolls[key] = nil
                    n = n + 1
                end
            end
        end
    end
    Dirty()
    return n
end

-- once a session: runs older than 400 days go, and there are never more than 3000
local pruned = false
local function Prune(runs)
    if pruned then return end
    pruned = true
    local oldest = Now() - 400 * 86400
    for i = #runs, 1, -1 do
        if runs[i].at < oldest then table.remove(runs, i) end
    end
    while #runs > 3000 do table.remove(runs, 1) end
end
D.Prune = Prune

---------------------------------------------------------------------------------------------------
-- The run you're in

local current           -- the stored run you're in (kept after you step out, until another starts)
local inside = false    -- whether you're in its dungeon right now
local seenDeaths, seenLoot, seenRolls, wasDead = {}, {}, {}, {}
local pendingRolls = {} -- item ID -> { choices = { name -> "need"/"greed" } }: rolls still open

local function SetCurrent(r)
    if r == current then return end
    current = r
    seenDeaths, seenLoot, seenRolls, wasDead, pendingRolls = {}, {}, {}, {}, {}
    if r then
        for who, n in pairs(r.deaths or {}) do seenDeaths[who] = n end
        for key, e in pairs(r.loot or {}) do seenLoot[key] = e.n end
        for key, e in pairs(r.rolls or {}) do seenRolls[key] = e.n end
    end
end

local function Ordinal(n)
    local last2, last = n % 100, n % 10
    if last2 >= 11 and last2 <= 13 then return n .. "th" end
    return n .. (last == 1 and "st" or last == 2 and "nd" or last == 3 and "rd" or "th")
end

local function RunsTogether(runs, a, b)
    local n = 0
    for _, r in ipairs(runs) do
        local hasA, hasB = false, false
        for _, x in ipairs(r.members) do
            if x == a then hasA = true elseif x == b then hasB = true end
        end
        if hasA and hasB then n = n + 1 end
    end
    return n
end

local function Check()
    local isInside, kind = IsInInstance()
    inside = isInside and kind == "party"
    if not inside then return end
    local runs = Runs()
    if not runs then return end
    local members = GuildmatesInGroup()
    if #members < 2 then return end
    local zone, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    zone, instanceID = B.Text(B.Plain(zone), 60), B.Plain(instanceID)
    if not zone or not instanceID then return end -- hidden right now (a fight): tried again on the next event
    local now = Now()
    local r, new, changed = Record(runs, { at = now, last = now, id = instanceID, zone = zone, members = members })
    SetCurrent(r)
    if changed then Queue(RunMsg(r)) end
    if new and B.Opt("chatRuns") then
        local me = FullName("player")
        local others, buddy = {}, nil
        for _, x in ipairs(r.members) do
            if x ~= me then
                table.insert(others, B.ShortName(x))
                buddy = buddy or x
            end
        end
        B.Say(zone .. " with " .. table.concat(others, ", ") .. " - run logged. That's your "
            .. Ordinal(RunsTogether(runs, me, buddy)) .. " run with " .. B.ShortName(buddy) .. ".")
    end
    B.Refresh()
end

-- Every second while you're in a run: who went from alive to dead. Someone seen for the first time
-- (a ghost coming back in after a wipe, say) only sets where they stand.
local function WatchDeaths()
    if not current or not inside then return end
    for _, unit in ipairs(UNITS) do
        local name = UnitExists(unit) and FullName(unit)
        if name and MemberNamed(current, name) == name then
            local raw = UnitIsDeadOrGhost(unit)
            local dead
            if not (issecretvalue and issecretvalue(raw)) then dead = raw and true or false end
            if dead == nil then
                -- hidden from addons right now: skip this unit until the game shows it again
            elseif dead and wasDead[name] == false then
                seenDeaths[name] = (seenDeaths[name] or 0) + 1
                SetDeaths(current, name, seenDeaths[name])
                Queue(DeathMsg(current, name))
                if B.Opt("chatDeaths") then
                    B.Say(Pick(DEATH_QUIPS):format(B.ShortName(name)) .. " ("
                        .. Ordinal(current.deaths[name]) .. " death this run)")
                end
                B.Refresh()
            end
            if dead ~= nil then wasDead[name] = dead and true or false end
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Loot

-- the game's "%s receives loot: %s." as a pattern: "^(.+) receives loot: (.+)%.$"
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("%%s", "(.+)")
    p = p:gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local lootPatterns
local function LootPatterns()
    if lootPatterns then return lootPatterns end
    lootPatterns = {}
    -- the ones with a count first: the plain ones would match them too
    for _, spec in ipairs({
        { LOOT_ITEM_MULTIPLE, false }, { LOOT_ITEM, false },
        { LOOT_ITEM_SELF_MULTIPLE, true }, { LOOT_ITEM_SELF, true },
    }) do
        local p = ToPattern(spec[1])
        if p then table.insert(lootPatterns, { p, spec[2] }) end
    end
    return lootPatterns
end

-- A chat line without the extras the client can put round names: a "[Loot]: " tag (a lootHistory
-- link), player links and colours. Item links are kept. (Forever does this; ForeverDungeonJournal
-- found the same.)
local function CleanLine(text)
    return (text:gsub("|HlootHistory:[^|]*|h.-|h:?%s*", "")
        :gsub("|Hplayer:[^|]*|h%[?([^%]|]*)%]?|h", "%1")
        :gsub("|c%x%x%x%x%x%x%x%x([^|]*)|r", "%1"))
end

-- who, item link, how many
local function ParseLoot(text)
    local line = CleanLine(text) -- not the raw line: "(.+)" would take link codes into the name
    for _, l in ipairs(LootPatterns()) do
        local a, b, c = line:match(l[1])
        if a then
            if l[2] then return FullName("player"), a, tonumber(b) or 1 end
            return a, b, tonumber(c) or 1
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Loot rolls: who rolled Need or Greed on what, and who won it

-- A game message with numbered or plain placeholders ("%1$s won: %2$s", "%s won: %s") as a
-- pattern, with the order its captures come in. Not anchored at the start: a tag can come first.
local function RollPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local out, order, i = {}, {}, 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local pos, conv = fmt:match("^%%(%d)%$([sd])", i)
            local skip = 4
            if not conv then
                conv = fmt:match("^%%([sd])", i)
                skip = 2
            end
            if conv then
                table.insert(order, tonumber(pos) or (#order + 1))
                table.insert(out, conv == "d" and "(%d+)" or "(.-)")
                i = i + skip
            else
                table.insert(out, "%%")
                i = i + ((fmt:sub(i + 1, i + 1) == "%") and 2 or 1)
            end
        elseif c:find("[%(%)%.%+%-%*%?%[%]%^%$]") then
            table.insert(out, "%" .. c)
            i = i + 1
        else
            table.insert(out, c)
            i = i + 1
        end
    end
    return { pattern = table.concat(out) .. "$", order = order }
end

-- the message's values in the game's order (args[1] is %1$s), or nil
local function RollMatch(p, text)
    if not p then return nil end
    -- Always the cleaned line (item links survive the cleaning): matched against the raw one, "(.-)"
    -- would happily take link and colour codes into a player's name. From its start first, then
    -- anywhere in it (a tag before it).
    local clean = CleanLine(text)
    for _, try in ipairs({ { clean, "^" .. p.pattern }, { clean, p.pattern } }) do
        local caps = { try[1]:match(try[2]) }
        if #caps > 0 then
            local args = {}
            for k, index in ipairs(p.order) do args[index] = caps[k] end
            return args
        end
    end
end

local rollPatterns
local function RollPatterns()
    if rollPatterns then return rollPatterns end
    rollPatterns = {
        youWon = RollPattern(LOOT_ROLL_YOU_WON),          -- "You won: %s"
        won = RollPattern(LOOT_ROLL_WON),                 -- "%s won: %s"
        allPassed = RollPattern(LOOT_ROLL_ALL_PASSED),    -- "Everyone passed on: %s"
        needSelf = RollPattern(LOOT_ROLL_NEED_SELF),      -- "You have selected Need for: %s"
        greedSelf = RollPattern(LOOT_ROLL_GREED_SELF),
        needOther = RollPattern(LOOT_ROLL_NEED),          -- "%s has selected Need for: %s"
        greedOther = RollPattern(LOOT_ROLL_GREED),
        rolledNeed = RollPattern(LOOT_ROLL_ROLLED_NEED),  -- "Need Roll - %d for %s by %s"
        rolledNeedBonus = RollPattern(LOOT_ROLL_ROLLED_NEED_ROLE_BONUS),
        rolledGreed = RollPattern(LOOT_ROLL_ROLLED_GREED),
    }
    return rollPatterns
end

local function ItemIDOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- someone picked Need or Greed on an item
local function Choose(link, who, kind)
    local id, name = ItemIDOf(link), B.CleanName(who)
    if not id or not name then return end
    pendingRolls[id] = pendingRolls[id] or { choices = {} }
    local choices = pendingRolls[id].choices
    if choices[name] ~= "need" then choices[name] = kind end -- a Need stays a Need
end

local ROLL_QUIPS = {
    need = { "%s won %s on Need over %d guildie%s. The dice have chosen.",
             "%s needed %s and beat %d guildie%s to it. Bold." },
    greed = { "%s won %s on Greed over %d guildie%s. Greed is good.",
              "%s greeded %s past %d guildie%s. Pure luck. Probably." },
}

-- the roll on an item is over: counted when a guildie in the run won it over at least one other
-- guildie who rolled Need or Greed on it too
local function Won(link, who)
    local id, name = ItemIDOf(link), B.CleanName(who)
    local roll = id and pendingRolls[id]
    if id then pendingRolls[id] = nil end
    if not roll or not name or not current or not inside then return end
    local kind = roll.choices[name]
    local winner = MemberNamed(current, name)
    if (kind ~= "need" and kind ~= "greed") or not winner then return end
    local beat = 0
    for other, k in pairs(roll.choices) do
        if other ~= name and (k == "need" or k == "greed") and MemberNamed(current, other) then beat = beat + 1 end
    end
    if beat == 0 then return end -- no guildie rolled against them
    local key = winner .. "|" .. id .. "|" .. kind
    seenRolls[key] = (seenRolls[key] or 0) + 1
    SetRoll(current, winner, id, kind, seenRolls[key], beat)
    Queue(RollMsg(current, current.rolls[key]))
    if B.Opt("chatLoot") then
        B.Say(Pick(ROLL_QUIPS[kind]):format(B.ShortName(winner), link, beat, beat == 1 and "" or "s"))
    end
    B.Refresh()
end

-- a loot-roll line: true when it was one
local function OnRollLine(text)
    local p, me = RollPatterns(), FullName("player")
    local a = RollMatch(p.youWon, text)
    if a then Won(a[1], me) return true end
    a = RollMatch(p.won, text)
    if a then Won(a[2], a[1]) return true end
    a = RollMatch(p.allPassed, text)
    if a then
        local id = ItemIDOf(a[1])
        if id then pendingRolls[id] = nil end
        return true
    end
    a = RollMatch(p.needSelf, text)
    if a then Choose(a[1], me, "need") return true end
    a = RollMatch(p.greedSelf, text)
    if a then Choose(a[1], me, "greed") return true end
    a = RollMatch(p.needOther, text)
    if a then Choose(a[2], a[1], "need") return true end
    a = RollMatch(p.greedOther, text)
    if a then Choose(a[2], a[1], "greed") return true end
    a = RollMatch(p.rolledNeed, text) or RollMatch(p.rolledNeedBonus, text)
    if a then Choose(a[2], a[3], "need") return true end
    a = RollMatch(p.rolledGreed, text)
    if a then Choose(a[2], a[3], "greed") return true end
    return false
end

local QUALITY_COLORS = { ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6 }

local function Quality(link)
    local _, _, q = GetItemInfo(link)
    if q then return q end
    local color = link:match("|c%x%x(%x%x%x%x%x%x)")
    return color and QUALITY_COLORS[color:lower()]
end

local function OnLoot(text)
    text = B.Plain(text)
    if not current or not inside or type(text) ~= "string" then return end
    if OnRollLine(text) then return end
    local who, link, count = ParseLoot(text)
    if not who then return end
    local member = MemberNamed(current, who)
    local itemID = tonumber(link:match("item:(%d+)"))
    if not member or not itemID then return end
    local q = Quality(link)
    if not q or q < MIN_LOOT_QUALITY then return end
    local key = member .. "|" .. itemID
    seenLoot[key] = (seenLoot[key] or 0) + count
    SetLoot(current, member, itemID, seenLoot[key], q)
    Queue(LootMsg(current, current.loot[key]))
    if B.Opt("chatLoot") then
        local epic = q >= EPIC
        if member == FullName("player") then
            B.Say(Pick(epic and SELF_LOOT_QUIPS or SELF_BLUE_QUIPS):format(link))
        else
            B.Say(Pick(epic and ENVY_QUIPS or BLUE_QUIPS):format(B.ShortName(member), link))
        end
    end
    B.Refresh()
end

---------------------------------------------------------------------------------------------------
-- Events

local checkPending = false
local function CheckSoon()
    if checkPending then return end
    checkPending = true
    C_Timer.After(3, function()
        checkPending = false
        Check()
    end)
end

local itemRefreshPending = false
local function RefreshForItems()
    if itemRefreshPending then return end
    itemRefreshPending = true
    C_Timer.After(1, function()
        itemRefreshPending = false
        Dirty()
        B.Refresh()
    end)
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
                         "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_LOOT",
                         "GET_ITEM_INFO_RECEIVED" }) do
    pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(_, event, a1)
    if event == "CHAT_MSG_LOOT" then
        pcall(OnLoot, a1) -- newer clients may hide chat text from addons in instances
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        RefreshForItems()
    elseif event == "PLAYER_LOGIN" then
        C_Timer.NewTicker(1, function() pcall(WatchDeaths) end)
        C_Timer.NewTicker(60, function()
            if current and inside then current.last = Now() end -- still in the dungeon
        end)
    else
        CheckSoon()
    end
end)

---------------------------------------------------------------------------------------------------
-- Who runs with whom, who dies, who gets the loot

local function Top(counts)
    local best, n
    for k, v in pairs(counts) do
        if not n or v > n or (v == n and k < best) then best, n = k, v end
    end
    return best, n or 0
end

local function ItemLevel(itemID)
    local _, _, _, level = GetItemInfo(itemID)
    return level or 0
end

-- the person with the most of field (at least min)
local function Most(list, field, min)
    local best
    for _, p in ipairs(list) do
        if p[field] >= (min or 1) and (not best or p[field] > best[field]) then best = p end
    end
    return best
end

-- hours: only runs this recent (nil: all)
function D.Stats(hours)
    local key = hours or "all"
    if statsCache[key] then return statsCache[key][1], statsCache[key][2] end
    local runs = Runs() or {}
    local since = hours and (Now() - hours * 3600)
    local people, zones, total = {}, {}, 0
    for _, r in ipairs(runs) do
        if not since or r.at >= since then
            total = total + 1
            zones[r.zone] = (zones[r.zone] or 0) + 1
            for _, a in ipairs(r.members) do
                local p = people[a]
                if not p then
                    p = { name = a, runs = 0, buddies = {}, zones = {}, deaths = 0, epics = 0, rares = 0,
                          needWins = 0, greedWins = 0 }
                    people[a] = p
                end
                p.runs = p.runs + 1
                p.zones[r.zone] = (p.zones[r.zone] or 0) + 1
                for _, b in ipairs(r.members) do
                    if b ~= a then p.buddies[b] = (p.buddies[b] or 0) + 1 end
                end
            end
            for who, n in pairs(r.deaths or {}) do
                if people[who] then people[who].deaths = people[who].deaths + n end
            end
            for _, e in pairs(r.loot or {}) do
                local p = people[e.who]
                if p then
                    if e.q >= EPIC then p.epics = p.epics + e.n else p.rares = p.rares + e.n end
                    if not p.best or e.q > p.bestQ or (e.q == p.bestQ and ItemLevel(e.id) > ItemLevel(p.best)) then
                        p.best, p.bestQ = e.id, e.q
                    end
                end
            end
            for _, e in pairs(r.rolls or {}) do
                local p = people[e.who]
                if p then
                    if e.kind == "need" then p.needWins = p.needWins + e.n else p.greedWins = p.greedWins + e.n end
                end
            end
        end
    end
    local list, duo = {}, nil
    for _, p in pairs(people) do
        p.buddy, p.buddyRuns = Top(p.buddies)
        p.zone, p.zoneRuns = Top(p.zones)
        p.drops = p.epics + p.rares
        p.rollWins = p.needWins + p.greedWins
        p.buddyCount = 0
        for _ in pairs(p.buddies) do p.buddyCount = p.buddyCount + 1 end
        if p.buddy and (not duo or p.buddyRuns > duo.runs) then
            duo = { a = p.name, b = p.buddy, runs = p.buddyRuns }
        end
        table.insert(list, p)
    end
    table.sort(list, function(x, y)
        if x.runs ~= y.runs then return x.runs > y.runs end
        return x.name < y.name
    end)
    local zone, zoneRuns = Top(zones)
    local sum = {
        total = total, duo = duo, zone = zone, zoneRuns = zoneRuns,
        inspector = Most(list, "deaths", 3),
        luckiest = Most(list, "epics", 1),
        goblin = Most(list, "drops", 1),
        diceLord = Most(list, "rollWins", 2),
    }
    statsCache[key] = { list, sum }
    return list, sum
end

local function Title(p, list, sum)
    local duo = sum.duo
    if p == list[1] and p.runs >= 3 then return "|cffffd700Lives in Dungeons|r" end
    if p == sum.inspector then return "|cffaaaaaaFloor Inspector|r" end
    if duo and duo.runs >= 3 and (p.name == duo.a or p.name == duo.b) then return "|cffff8800Ride or Die|r" end
    if p.runs >= 5 and p.deaths == 0 then return "Unkillable" end
    if p.buddyCount >= 8 then return "Social Butterfly" end
    if p.runs >= 3 and p.buddyCount == 1 then return "One-Friend Wonder" end
    if p.zoneRuns >= 5 and p.zoneRuns * 2 >= p.runs then return "Regular at " .. p.zone end
    if p.runs == 1 then return "Dungeon Tourist" end
    return "Reliable Dungeon Buddy"
end

local function LootTitle(p, sum)
    if p == sum.luckiest then return "|cffa335eeLuckiest " .. B.GuildName() .. "|r" end
    if p == sum.diceLord then return "|cffff8800Dice Lord|r" end
    if p == sum.goblin then return "|cff0070ddLoot Goblin|r" end
    if p.needWins >= 3 and p.needWins >= 2 * p.greedWins then return "Needs Everything" end
    if p.runs >= 5 and p.drops == 0 then return "|cffaaaaaaCursed by RNG|r" end
    if p.drops == 0 then return "Still Waiting" end
    return "Fair Share"
end

local function ItemText(itemID)
    local _, link = GetItemInfo(itemID)
    if link then return link end
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return "item " .. itemID
end

D.Columns = {
    { title = "#", width = 22, justify = "RIGHT" },
    { title = "Name", width = 120 },
    { title = "Runs", width = 40, justify = "RIGHT" },
    { title = "Deaths", width = 46, justify = "RIGHT" },
    { title = "Best buddy", width = 110 },
    { title = "Favorite dungeon", width = 124 },
    { title = "Title", width = 140 },
}

function D.Rows(hours)
    local list, sum = D.Stats(hours)
    local rows = {}
    for i, p in ipairs(list) do
        rows[i] = {
            i .. ".",
            B.ShortName(p.name),
            p.runs,
            p.deaths,
            p.buddy and (B.ShortName(p.buddy) .. " (" .. p.buddyRuns .. ")") or "-",
            p.zone and (p.zone .. " (" .. p.zoneRuns .. ")") or "-",
            Title(p, list, sum),
        }
    end
    return rows
end

D.LootColumns = {
    { title = "#", width = 22, justify = "RIGHT" },
    { title = "Name", width = 116 },
    { title = "Epics", width = 38, justify = "RIGHT" },
    { title = "Blues", width = 38, justify = "RIGHT" },
    { title = "Rolls won N / G", width = 90, justify = "RIGHT" },
    { title = "Best drop", width = 170 },
    { title = "Title", width = 118 },
}

function D.LootRows(hours)
    local list, sum = D.Stats(hours)
    local sorted = {}
    for i, p in ipairs(list) do sorted[i] = p end
    table.sort(sorted, function(x, y)
        if x.epics ~= y.epics then return x.epics > y.epics end
        if x.rares ~= y.rares then return x.rares > y.rares end
        if x.rollWins ~= y.rollWins then return x.rollWins > y.rollWins end
        return x.name < y.name
    end)
    local rows = {}
    for i, p in ipairs(sorted) do
        rows[i] = {
            i .. ".",
            B.ShortName(p.name),
            p.epics,
            p.rares,
            p.needWins .. " / " .. p.greedWins, -- rolls won over guildies: Need / Greed
            p.best and ItemText(p.best) or "-",
            LootTitle(p, sum),
        }
    end
    return rows
end

function D.Info()
    local runs = Runs()
    if not runs then return "You're not in a guild." end
    return #runs .. " runs with guild members logged · " .. B.Sync.Status()
end

function D.Highlight(hours)
    local _, sum = D.Stats(hours)
    if not sum.duo then return "No runs with guild members yet. Group up!" end
    return "Ride or Die: " .. B.ShortName(sum.duo.a) .. " & " .. B.ShortName(sum.duo.b) .. ", "
        .. sum.duo.runs .. " runs together"
end

function D.LootHighlight(hours)
    local _, sum = D.Stats(hours)
    local parts = {}
    if sum.luckiest then
        table.insert(parts, "Luckiest " .. B.GuildName() .. ": " .. B.ShortName(sum.luckiest.name) .. ", " .. sum.luckiest.epics .. " epics")
    end
    if sum.diceLord then
        table.insert(parts, "Dice Lord: " .. B.ShortName(sum.diceLord.name) .. ", " .. sum.diceLord.rollWins
            .. " rolls won over guildies")
    end
    if #parts == 0 then return "No epic drops or roll wins logged yet. The RNG gods are watching." end
    return table.concat(parts, " · ")
end

function D.Report(hours, label)
    local list, sum = D.Stats(hours)
    if #list == 0 then
        B.Say("no dungeon runs to report for " .. label:lower() .. ".")
        return
    end
    local lines = { B.GuildName() .. " dungeon report, " .. label:lower() .. ": " .. sum.total .. " runs together" }
    local top = list[1]
    table.insert(lines, "{triangle} Lives in Dungeons: " .. B.ShortName(top.name) .. " (" .. top.runs .. " runs)")
    if sum.duo then
        table.insert(lines, "{moon} Ride or Die: " .. B.ShortName(sum.duo.a) .. " & " .. B.ShortName(sum.duo.b)
            .. " (" .. sum.duo.runs .. " runs together)")
    end
    if sum.inspector then
        table.insert(lines, "{cross} Floor Inspector: " .. B.ShortName(sum.inspector.name)
            .. " (" .. sum.inspector.deaths .. " deaths)")
    end
    if sum.zone then
        table.insert(lines, "{square} Guild favorite: " .. sum.zone .. " (" .. sum.zoneRuns .. " runs)")
    end
    B.SendLines(lines)
end

function D.LootReport(hours, label)
    local list, sum = D.Stats(hours)
    if not sum.goblin and not sum.diceLord then
        B.Say("no blue or epic drops or roll wins to report for " .. label:lower() .. ".")
        return
    end
    local lines = { B.GuildName() .. " loot envy report, " .. label:lower() .. ":" }
    local lucky = sum.luckiest
    if lucky then
        local _, link = GetItemInfo(lucky.best)
        table.insert(lines, "{star} Luckiest " .. B.GuildName() .. ": " .. B.ShortName(lucky.name) .. " (" .. lucky.epics
            .. " epics" .. (link and (", best: " .. link) or "") .. ")")
    end
    if sum.goblin and sum.goblin ~= lucky then
        table.insert(lines, "{diamond} Loot Goblin: " .. B.ShortName(sum.goblin.name) .. " ("
            .. sum.goblin.drops .. " blues and epics)")
    end
    if sum.diceLord then
        local d = sum.diceLord
        table.insert(lines, "{triangle} Dice Lord: " .. B.ShortName(d.name) .. " (" .. d.rollWins
            .. " rolls won over guildies: " .. d.needWins .. " Need, " .. d.greedWins .. " Greed)")
    end
    local cursed
    for _, p in ipairs(list) do
        if p.drops == 0 and p.runs >= 3 and (not cursed or p.runs > cursed.runs) then cursed = p end
    end
    if cursed then
        table.insert(lines, "{skull} Cursed by RNG: " .. B.ShortName(cursed.name) .. " (" .. cursed.runs
            .. " runs, nothing to show for it)")
    end
    B.SendLines(lines)
end

-- for tooltips: a guild member's dungeon stats (all time), their title, and their runs with you
function D.For(name)
    local list, sum = D.Stats(nil)
    local short = B.ShortName(name)
    for _, p in ipairs(list) do
        if B.ShortName(p.name) == short then
            local me = FullName("player")
            return p, Title(p, list, sum), LootTitle(p, sum), (me and p.buddies[me]) or 0
        end
    end
end
