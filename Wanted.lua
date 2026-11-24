-- Biggus Most Wanted: enemy-faction players who killed a guild member, and where.
--
--  * Forever's client keeps the combat log from addons, so nobody can watch another player's death.
--    What a client can read is its own death recap. So when you die, your copy reads the recap, takes
--    the last attacker, and - if that was a player of the other faction - records the kill: killer,
--    you, zone and subzone, time, levels.
--  * "Of the other faction" is known from the attacker's GUID when the recap has one (their race),
--    or from having seen them: every enemy player you hover, target or see a nameplate of in the
--    last 10 minutes is remembered. A killer that can't be confirmed isn't recorded.
--  * Battlegrounds and arenas don't count: those deaths are the point there.
--  * Kills are shared with the guild's Biggus users (Sync.lua), like runs.
--  * Hovering an enemy player shows on the tooltip whether they're on the list (Extras.lua), and
--    targeting one prints a warning.
--  * Revenge: when a guildie kills someone on the list, it's recorded for the Avengers tab. Without
--    the combat log, a kill is seen three ways: the game's PARTY_KILL event (a killing blow by you or
--    someone in your group), your own "You have slain X!", and a wanted player you had targeted in
--    the last 15 seconds dying while you're in combat (that counts as helping). Only guild members
--    are credited, and only for players on the list.
--
-- Messages: K kill:    "K", time, victim, killer, zone, subzone, killer's race, class, level, victim's level
--           V revenge: "V", time, avenger, target, zone, subzone, "blow" (killing blow) or "assist"

local ADDON, B = ...
local W = {}
B.Wanted = W

local SEEN_SECONDS = 600       -- an enemy seen this recently can be confirmed as a killer
local SAME_KILL = 60           -- the same victim and killer this close in time: the same kill
local LIVE_SECONDS = 120       -- a shared kill this fresh gets announced
local WARN_EVERY = 300         -- warn about the same wanted player at most this often
local MAX_KILLS = 2000

-- races by faction, for the GUID route (the game's English race names)
local ALLIANCE = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true, Worgen = true,
                   VoidElf = true, LightforgedDraenei = true, DarkIronDwarf = true, KulTiran = true,
                   Mechagnome = true }
local HORDE = { Orc = true, Scourge = true, Undead = true, Tauren = true, Troll = true, BloodElf = true,
                Goblin = true, Nightborne = true, HighmountainTauren = true, MagharOrc = true,
                ZandalariTroll = true, Vulpera = true }

local KILL_QUIPS = {
    "%s got ganked by %s in %s. Noted. Forever.",
    "%s was killed by %s in %s. The list grows.",
    "%s fell to %s in %s. Vengeance pending.",
}

local ASSIST_SECONDS = 15      -- a wanted player you targeted this recently, dying while you fight: you helped
local MAX_REVENGE = 2000

local seen = {}                -- name -> { race, class, level, at = GetTime() }: enemy players seen lately
local targetedAt = {}          -- name -> GetTime(): enemy players you targeted lately
local warnedAt = {}            -- name -> GetTime() of the last target warning
local lastRecap                -- what the last death recap gave, for /biggus deathcheck

local function Now()
    return B.Now()
end

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Kills()
    local g = B.Guild()
    if not g then return nil, nil end
    g.kills = g.kills or {}
    return g.kills, g
end

local statsCache = {}
local function Dirty()
    statsCache = {}
end

local function MyFaction()
    return UnitFactionGroup("player")
end

local function Zone()
    return B.Text(Plain(GetRealZoneText and GetRealZoneText()), 60) or "?",
        B.Text(Plain(GetSubZoneText and GetSubZoneText()), 60)
end

---------------------------------------------------------------------------------------------------
-- Enemy players around you

local function Observe(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local faction, mine = Plain(UnitFactionGroup(unit)), MyFaction()
    if not faction or not mine or faction == mine or faction == "Neutral" then return end
    local name = B.UnitName(unit)
    name = Plain(name)
    if not name then return end
    local _, class = UnitClass(unit)
    seen[name] = {
        race = Plain(UnitRace(unit)), class = Plain(class), level = Plain(UnitLevel(unit)), at = GetTime(),
    }
    if unit == "target" then targetedAt[name] = GetTime() end
end

local function Forget()
    local now = GetTime()
    for name, s in pairs(seen) do
        if now - s.at > SEEN_SECONDS then seen[name] = nil end
    end
    for name, at in pairs(targetedAt) do
        if now - at > SEEN_SECONDS then targetedAt[name] = nil end
    end
end

-- a player's name from their GUID ("Player-..."), as Biggus keeps names
local function NameFromGUID(guid)
    guid = Plain(guid)
    if type(guid) ~= "string" or not guid:find("^Player%-") or not GetPlayerInfoByGUID then return nil end
    local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
    name, realm = ok and Plain(name), ok and Plain(realm)
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then return B.CleanName(name .. "-" .. realm) end
    return B.CleanName(name)
end

---------------------------------------------------------------------------------------------------
-- Storing kills

local function Record(k)
    local kills = Kills()
    if not kills then return nil end
    for i = #kills, 1, -1 do
        local o = kills[i]
        if o.victim == k.victim and o.killer == k.killer and math.abs(o.at - k.at) <= SAME_KILL then
            return nil -- known already
        end
    end
    k.u = Now()
    table.insert(kills, k)
    while #kills > MAX_KILLS do table.remove(kills, 1) end
    Dirty()
    return k
end

local function KillMsg(k)
    return table.concat({ "K", k.at, k.victim, k.killer, k.zone or "?", k.subzone or "", k.race or "",
                          k.class or "", k.level or 0, k.victimLevel or 0 }, "\t")
end

function W.CatchUp(since, oldest)
    local msgs = {}
    if not B.Opt("wanted") then return msgs end
    for _, k in ipairs(Kills() or {}) do
        if (k.u or 0) > since and k.at >= (oldest or 0) then table.insert(msgs, KillMsg(k)) end
    end
    return msgs
end

function W.Receive(f, from)
    if f[1] ~= "K" or not from or not B.Opt("wanted") then return end
    local k = {
        at = B.Time(f[2]), victim = B.CleanName(f[3]), killer = B.CleanName(f[4]), zone = B.Text(f[5], 60),
        subzone = B.Text(f[6], 60), race = B.Text(f[7], 24), class = B.Text(f[8], 16),
        level = B.Num(f[9], 0, 100), victimLevel = B.Num(f[10], 0, 100), src = from,
    }
    if not k.at or not k.victim or not k.killer or not k.zone or k.victim == k.killer then return end
    if k.level == 0 then k.level = nil end
    if k.victimLevel == 0 then k.victimLevel = nil end
    if Record(k) and Now() - k.at < LIVE_SECONDS and B.Opt("chatWanted") then
        local place = k.subzone and (k.zone .. " - " .. k.subzone) or k.zone
        B.Say(KILL_QUIPS[math.random(#KILL_QUIPS)]:format(B.ShortName(k.victim), "|cffff4444" .. B.ShortName(k.killer) .. "|r", place))
    end
    B.Refresh()
end

-- /biggus forget
function W.Forget(name)
    local kills = Kills()
    if not kills then return 0 end
    local n = 0
    for i = #kills, 1, -1 do
        if kills[i].src == name then
            table.remove(kills, i)
            n = n + 1
        end
    end
    Dirty()
    return n
end

---------------------------------------------------------------------------------------------------
-- Your own death: the recap

local function RecapEvents()
    if C_DeathRecap and C_DeathRecap.GetRecapEvents then
        local ok, events = pcall(C_DeathRecap.GetRecapEvents) -- no ID: the latest death
        if ok and type(events) == "table" and #events > 0 then return events, "C_DeathRecap" end
    end
    if DeathRecap_GetEvents then
        local ok, events = pcall(DeathRecap_GetEvents)
        if ok and type(events) == "table" and #events > 0 then return events, "DeathRecap_GetEvents" end
    end
    return nil, (C_DeathRecap or DeathRecap_GetEvents) and "no recap events" or "no death recap API"
end

-- the attacker of the killing blow: the newest event that names one
local function Killer(events)
    for _, e in ipairs(events) do
        local name = Plain(e.sourceName)
        if type(name) == "string" and name ~= "" and not Plain(e.hideCaster) then
            return name, Plain(e.sourceGUID or e.srcGUID), e
        end
    end
end

-- an enemy-faction player? Returns what's known about them, or nil
local function EnemyPlayer(name, guid, flags)
    local mine = MyFaction()
    if type(guid) == "string" and guid:find("^Player%-") and GetPlayerInfoByGUID then
        local ok, _, class, race, englishRace = pcall(GetPlayerInfoByGUID, guid)
        if ok and englishRace then
            local faction = ALLIANCE[englishRace] and "Alliance" or HORDE[englishRace] and "Horde"
            if faction and faction ~= mine then return { race = race, class = class }, "GUID" end
            if faction == mine then return nil, "same faction" end
        end
    end
    local s = seen[B.Canon(name)]
    if s and GetTime() - s.at <= SEEN_SECONDS then return s, "seen nearby" end
    -- the recap's sourceFlags (plain on Forever, seen in the game): a hostile player. Used only when the
    -- GUID route gave no race. (Duels never kill - they end at 1 health - so a hostile player who killed
    -- you is an enemy.)
    if type(flags) == "number" and bit and bit.band then
        local PLAYER, HOSTILE = 0x400, 0x40 -- COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_REACTION_HOSTILE
        if bit.band(flags, PLAYER) ~= 0 and bit.band(flags, HOSTILE) ~= 0 then
            return {}, "hostile player (recap flags)"
        end
    end
    return nil, "not confirmed as an enemy player"
end

local function OnDeath()
    if not B.Opt("wanted") then return true end
    local inside, kind = IsInInstance()
    if inside and (kind == "pvp" or kind == "arena") then
        lastRecap = { note = "battleground or arena: not counted" }
        return
    end
    local events, source = RecapEvents()
    if not events then
        lastRecap = { note = source }
        return false -- maybe not ready yet
    end
    local name, guid, event = Killer(events)
    local info, how = nil, "no attacker named"
    if name then info, how = EnemyPlayer(name, guid, Plain(event and event.sourceFlags)) end
    lastRecap = {
        source = source, events = #events, killer = name, guid = guid, how = how,
        fields = {},
    }
    for key, value in pairs(event or events[1] or {}) do
        table.insert(lastRecap.fields, tostring(key) .. "=" .. tostring(Plain(value) or "(secret)"))
    end
    table.sort(lastRecap.fields)
    if not info then return true end

    local zone, subzone = Zone()
    if not B.CleanName(name) then return true end
    local k = Record({
        at = Now(), victim = B.UnitName("player"), killer = B.CleanName(name), zone = zone, subzone = subzone,
        race = info.race, class = info.class, level = info.level, victimLevel = UnitLevel("player"),
    })
    if not k then return true end
    B.Sync.Broadcast(KillMsg(k))
    if B.Opt("chatWanted") then
        local times = 0
        for _, o in ipairs(Kills() or {}) do
            if o.killer == k.killer then times = times + 1 end
        end
        B.Say("killed by |cffff4444" .. name .. "|r" .. (info.race and (" (" .. info.race .. (info.class and (" " .. info.class) or "") .. ")") or "")
            .. " in " .. zone .. (subzone and (" - " .. subzone) or "") .. ". Added to the Most Wanted list"
            .. (times > 1 and (" - that's " .. times .. " guild kills for them.") or "."))
    end
    B.Refresh()
    return true
end

-- the recap may not be ready the moment you die: tried a few times
local function ReadDeathSoon()
    local tries = 0
    local function Try()
        tries = tries + 1
        local ok, done = pcall(OnDeath)
        if ok and done == false and tries < 4 then C_Timer.After(2, Try) end
    end
    C_Timer.After(1, Try)
end

-- /biggus deathcheck: what the game gave for your last death
function W.DeathCheck()
    if not lastRecap then
        B.Say("no death read since you logged in. Die to an enemy player first (sorry), then try again.")
        return
    end
    if lastRecap.note then
        B.Say("last death: " .. lastRecap.note)
        return
    end
    B.Say("last death recap: " .. lastRecap.events .. " events from " .. lastRecap.source .. " · killer: "
        .. tostring(lastRecap.killer or "none") .. " · GUID: " .. tostring(lastRecap.guid or "none")
        .. " · enemy player: " .. tostring(lastRecap.how))
    B.Say("killing event fields: " .. table.concat(lastRecap.fields, ", "))
end

---------------------------------------------------------------------------------------------------
-- Who's wanted

local function Top(counts)
    local best, n
    for k, v in pairs(counts) do
        if not n or v > n or (v == n and k < best) then best, n = k, v end
    end
    return best, n or 0
end

function W.Stats(hours)
    local key = hours or "all"
    if statsCache[key] then return statsCache[key][1], statsCache[key][2] end
    local since = hours and (Now() - hours * 3600)
    local killers, victims, zones, total = {}, {}, {}, 0
    for _, k in ipairs(Kills() or {}) do
        if not since or k.at >= since then
            total = total + 1
            local p = killers[k.killer]
            if not p then
                p = { name = k.killer, kills = 0, victims = {}, zones = {}, last = 0, lowbie = 0 }
                killers[k.killer] = p
            end
            p.kills = p.kills + 1
            p.victims[k.victim] = (p.victims[k.victim] or 0) + 1
            p.zones[k.zone] = (p.zones[k.zone] or 0) + 1
            if k.at > p.last then p.last, p.lastZone = k.at, k.subzone and (k.zone .. " - " .. k.subzone) or k.zone end
            p.race, p.class, p.level = k.race or p.race, k.class or p.class, k.level or p.level
            if k.level and k.victimLevel and k.level - k.victimLevel >= 10 then p.lowbie = p.lowbie + 1 end
            victims[k.victim] = (victims[k.victim] or 0) + 1
            zones[k.zone] = (zones[k.zone] or 0) + 1
        end
    end
    local list = {}
    for _, p in pairs(killers) do
        p.favorite, p.favoriteKills = Top(p.victims)
        p.zone = Top(p.zones)
        table.insert(list, p)
    end
    table.sort(list, function(x, y)
        if x.kills ~= y.kills then return x.kills > y.kills end
        if x.last ~= y.last then return x.last > y.last end
        return x.name < y.name
    end)
    local snack, snackDeaths = Top(victims)
    local zone, zoneKills = Top(zones)
    local sum = { total = total, snack = snack, snackDeaths = snackDeaths, zone = zone, zoneKills = zoneKills }
    statsCache[key] = { list, sum }
    return list, sum
end

local function Title(p, list)
    if p == list[1] and p.kills >= 2 then return "|cffff4444Public Enemy #1|r" end
    if p.favoriteKills >= 3 then return "Has a Vendetta" end
    if p.kills >= 5 then return "Serial Ganker" end
    if p.lowbie >= 2 then return "Picks On Lowbies" end
    if p.kills == 1 then return "One-Hit Wonder" end
    return "Known Menace"
end

local function VictimsText(p)
    local names = {}
    for name, n in pairs(p.victims) do table.insert(names, { name, n }) end
    table.sort(names, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    local parts = {}
    for i = 1, math.min(2, #names) do
        local short = B.ShortName(names[i][1])
        table.insert(parts, names[i][2] > 1 and (short .. " x" .. names[i][2]) or short)
    end
    if #names > 2 then table.insert(parts, "+" .. (#names - 2)) end
    return table.concat(parts, ", ")
end

W.Columns = {
    { title = "#", width = 22, justify = "RIGHT" },
    { title = "Name", width = 120 },
    { title = "Kills", width = 40, justify = "RIGHT" },
    { title = "Victims", width = 130 },
    { title = "Where", width = 100 },
    { title = "Last kill", width = 60, justify = "RIGHT" },
    { title = "Title", width = 110 },
}

function W.Rows(hours)
    local list = W.Stats(hours)
    local rows = {}
    for i, p in ipairs(list) do
        rows[i] = { i .. ".", "|cffff6666" .. B.ShortName(p.name) .. "|r", p.kills, VictimsText(p), p.zone or "?",
                    B.Ago(Now() - p.last), Title(p, list) }
    end
    return rows
end

function W.Info()
    local kills = Kills()
    if not kills then return "You're not in a guild." end
    return #kills .. " guild deaths to enemy players logged · " .. B.Sync.Status()
end

function W.Highlight(hours)
    local _, sum = W.Stats(hours)
    if not sum.snack then return "Nobody's been ganked yet. Suspicious." end
    return "Enemy's Favourite Snack: " .. B.ShortName(sum.snack) .. " (" .. sum.snackDeaths .. " deaths) · Danger Zone: "
        .. sum.zone .. " (" .. sum.zoneKills .. ")"
end

function W.Report(hours, label)
    local list, sum = W.Stats(hours)
    if #list == 0 then
        B.Say("nobody on the Most Wanted list for " .. label:lower() .. ".")
        return
    end
    local lines = { B.GuildName() .. " Most Wanted, " .. label:lower() .. ": " .. sum.total .. " guildies ganked" }
    for i = 1, math.min(3, #list) do
        local p = list[i]
        table.insert(lines, (i == 1 and "{skull} " or "{cross} ") .. "#" .. i .. " " .. B.ShortName(p.name)
            .. (p.race and (" (" .. p.race .. (p.class and (" " .. p.class) or "") .. ")") or "") .. ": "
            .. p.kills .. " kills, last in " .. (p.lastZone or p.zone or "?"))
    end
    table.insert(lines, "{square} Favourite Snack: " .. B.ShortName(sum.snack) .. " (" .. sum.snackDeaths
        .. " deaths) · Danger Zone: " .. sum.zone)
    B.SendLines(lines)
end

-- for tooltips and warnings: a player's place on the list (all time), or nil
-- Only the last FOR_DAYS count here, so the list on tooltips and warnings ages out instead of
-- becoming a permanent grudge (the tabs can still show all time).
local FOR_DAYS = 30
function W.For(name)
    if not name or not B.Opt("wanted") then return nil end
    local list = W.Stats(FOR_DAYS * 24)
    for i, p in ipairs(list) do
        if p.name == name then return p, i, Title(p, list), VictimsText(p) end
    end
end

---------------------------------------------------------------------------------------------------
-- Revenge: guildies who killed someone on the list

local REVENGE_QUIPS = {
    "%s took revenge on %s in %s. Justice, served cold.",
    "%s got %s in %s. The list remembers, and so do we.",
    "%s paid %s back in %s. With interest.",
}

local function Revenges()
    local g = B.Guild()
    if not g then return nil end
    g.revenge = g.revenge or {}
    return g.revenge
end

local function RevengeMsg(v)
    return table.concat({ "V", v.at, v.avenger, v.target, v.zone or "?", v.subzone or "", v.how }, "\t")
end

-- Adds a revenge kill, or upgrades a known one from helping to the killing blow. Returns it when
-- something changed.
local function RecordRevenge(v)
    local list = Revenges()
    if not list then return nil end
    for i = #list, 1, -1 do
        local o = list[i]
        if o.avenger == v.avenger and o.target == v.target and math.abs(o.at - v.at) <= SAME_KILL then
            if o.how == "assist" and v.how == "blow" then
                o.how, o.u = "blow", Now()
                Dirty()
                return o
            end
            return nil
        end
    end
    v.u = Now()
    table.insert(list, v)
    while #list > MAX_REVENGE do table.remove(list, 1) end
    Dirty()
    return v
end

function W.RevengeCatchUp(since, oldest)
    local msgs = {}
    if not B.Opt("wanted") then return msgs end
    for _, v in ipairs(Revenges() or {}) do
        if (v.u or 0) > since and v.at >= (oldest or 0) then table.insert(msgs, RevengeMsg(v)) end
    end
    return msgs
end

local function Announce(v)
    if not B.Opt("chatWanted") then return end
    local place = v.subzone and (v.zone .. " - " .. v.subzone) or v.zone
    B.Say(REVENGE_QUIPS[math.random(#REVENGE_QUIPS)]:format("|cff33ff33" .. B.ShortName(v.avenger) .. "|r",
        B.ShortName(v.target), place) .. (v.how == "assist" and " (helped)" or ""))
end

function W.ReceiveRevenge(f, from)
    if f[1] ~= "V" or not from or not B.Opt("wanted") then return end
    local v = {
        at = B.Time(f[2]), avenger = B.CleanName(f[3]), target = B.CleanName(f[4]), zone = B.Text(f[5], 60),
        subzone = B.Text(f[6], 60), how = (f[7] == "blow" or f[7] == "assist") and f[7] or nil, src = from,
    }
    if not v.at or not v.avenger or not v.target or not v.zone or not v.how then return end
    if not B.Sync.Rank(v.avenger) then return end -- only guild members are credited
    if RecordRevenge(v) and Now() - v.at < LIVE_SECONDS then Announce(v) end
    B.Refresh()
end

-- a guildie (avenger) killed or helped kill target: recorded if target is on the list
local function Credit(avenger, target, how)
    if not B.Opt("wanted") then return end
    local me = B.UnitName("player")
    if not avenger or not target or avenger == target then return end
    if avenger ~= me and not B.Sync.Rank(avenger) then return end -- a guild member, or you
    if not W.For(target) then return end
    local zone, subzone = Zone()
    local v = RecordRevenge({ at = Now(), avenger = avenger, target = target, zone = zone, subzone = subzone, how = how })
    if not v then return end
    B.Sync.Broadcast(RevengeMsg(v))
    if avenger == me and B.Opt("chatWanted") then
        local p, place, _, victims = W.For(target)
        B.Say("|cff33ff33REVENGE!|r You " .. (how == "blow" and "killed " or "helped kill ") .. B.ShortName(target)
            .. ", Most Wanted #" .. place .. " (killed " .. victims .. "). The guild thanks you.")
    else
        Announce(v)
    end
    B.Refresh()
end

-- PARTY_KILL: a killing blow by you or someone in your group
local function OnPartyKill(attackerGUID, targetGUID)
    Credit(NameFromGUID(attackerGUID), NameFromGUID(targetGUID), "blow")
end

-- a wanted player died near you: you helped if you had them targeted lately and are fighting
local function OnDied(name)
    name = B.CleanName(name)
    if not name or not targetedAt[name] or GetTime() - targetedAt[name] > ASSIST_SECONDS then return end
    if not Plain(UnitAffectingCombat("player")) then return end
    Credit(B.UnitName("player"), name, "assist")
end

local slainPattern, diesPattern
local function OnHostileDeath(text)
    if type(text) ~= "string" then return end
    local function Pattern(fmt)
        if type(fmt) ~= "string" then return nil end
        return "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
    end
    slainPattern = slainPattern or Pattern(SELFKILLOTHER or "You have slain %s!")
    diesPattern = diesPattern or Pattern(UNITDIESOTHER or "%s dies.")
    local slain = slainPattern and text:match(slainPattern)
    if slain then
        Credit(B.UnitName("player"), B.CleanName(slain), "blow")
        return
    end
    local dies = diesPattern and text:match(diesPattern)
    if dies then OnDied(dies) end
end

-- /biggus forget
local function ForgetRevenge(name)
    local list = Revenges()
    if not list then return 0 end
    local n = 0
    for i = #list, 1, -1 do
        if list[i].src == name then
            table.remove(list, i)
            n = n + 1
        end
    end
    Dirty()
    return n
end

local forgetKills = W.Forget
function W.Forget(name)
    return forgetKills(name) + ForgetRevenge(name)
end

-- how often guildies got this wanted player, and who did it last
function W.PaidBack(name)
    local n, lastAt, lastBy = 0, 0, nil
    for _, v in ipairs(Revenges() or {}) do
        if v.target == name then
            n = n + 1
            if v.at > lastAt then lastAt, lastBy = v.at, v.avenger end
        end
    end
    return n, lastBy
end

function W.RevengeStats(hours)
    local key = "revenge-" .. (hours or "all")
    if statsCache[key] then return statsCache[key][1], statsCache[key][2] end
    local since = hours and (Now() - hours * 3600)
    local wanted = W.Stats(nil)
    local enemyOne = wanted[1] and wanted[1].kills >= 2 and wanted[1].name
    local killedBy = {} -- "victim|killer" -> true: who killed whom (for settling scores)
    for _, k in ipairs(Kills() or {}) do killedBy[k.victim .. "|" .. k.killer] = true end
    local people, hunted, total = {}, {}, 0
    for _, v in ipairs(Revenges() or {}) do
        if not since or v.at >= since then
            total = total + 1
            local p = people[v.avenger]
            if not p then
                p = { name = v.avenger, total = 0, blows = 0, assists = 0, targets = {}, last = 0, personal = 0 }
                people[v.avenger] = p
            end
            p.total = p.total + 1
            if v.how == "blow" then p.blows = p.blows + 1 else p.assists = p.assists + 1 end
            p.targets[v.target] = (p.targets[v.target] or 0) + 1
            if v.at > p.last then p.last = v.at end
            if killedBy[v.avenger .. "|" .. v.target] then p.personal = p.personal + 1 end
            if v.target == enemyOne then p.bounty = true end
            hunted[v.target] = (hunted[v.target] or 0) + 1
        end
    end
    local list = {}
    for _, p in pairs(people) do
        p.favorite, p.favoriteKills = Top(p.targets)
        table.insert(list, p)
    end
    table.sort(list, function(x, y)
        if x.total ~= y.total then return x.total > y.total end
        if x.blows ~= y.blows then return x.blows > y.blows end
        return x.name < y.name
    end)
    local mostHunted, huntedTimes = Top(hunted)
    local sum = { total = total, mostHunted = mostHunted, huntedTimes = huntedTimes, enemyOne = enemyOne }
    statsCache[key] = { list, sum }
    return list, sum
end

local function RevengeTitle(p, list)
    if p == list[1] and p.total >= 2 then return "|cff33ff33Guild Avenger|r" end
    if p.bounty then return "|cffffd700Bounty Hunter|r" end
    if p.personal >= 1 then return "Settled the Score" end
    if p.favoriteKills >= 3 then return "Won't Let It Go" end
    if p.assists > p.blows then return "Wingman" end
    return "Vigilante"
end

local function TargetsText(p)
    local names = {}
    for name, n in pairs(p.targets) do table.insert(names, { name, n }) end
    table.sort(names, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    local parts = {}
    for i = 1, math.min(2, #names) do
        local short = B.ShortName(names[i][1])
        table.insert(parts, names[i][2] > 1 and (short .. " x" .. names[i][2]) or short)
    end
    if #names > 2 then table.insert(parts, "+" .. (#names - 2)) end
    return table.concat(parts, ", ")
end

W.RevengeColumns = {
    { title = "#", width = 22, justify = "RIGHT" },
    { title = "Name", width = 120 },
    { title = "Revenge", width = 56, justify = "RIGHT" },
    { title = "Blows", width = 44, justify = "RIGHT" },
    { title = "Got", width = 150 },
    { title = "Last", width = 60, justify = "RIGHT" },
    { title = "Title", width = 130 },
}

function W.RevengeRows(hours)
    local list = W.RevengeStats(hours)
    local rows = {}
    for i, p in ipairs(list) do
        rows[i] = { i .. ".", "|cff33ff33" .. B.ShortName(p.name) .. "|r", p.total, p.blows, TargetsText(p),
                    B.Ago(Now() - p.last), RevengeTitle(p, list) }
    end
    return rows
end

function W.RevengeInfo()
    local list = Revenges()
    if not list then return "You're not in a guild." end
    return #list .. " revenge kills logged · " .. B.Sync.Status()
end

function W.RevengeHighlight(hours)
    local _, sum = W.RevengeStats(hours)
    if not sum.mostHunted then return "No revenge yet. The Most Wanted list is waiting." end
    return "Most hunted: " .. B.ShortName(sum.mostHunted) .. " (got " .. sum.huntedTimes .. " times by guildies)"
end

function W.RevengeReport(hours, label)
    local list, sum = W.RevengeStats(hours)
    if #list == 0 then
        B.Say("no revenge kills to report for " .. label:lower() .. ".")
        return
    end
    local lines = { B.GuildName() .. " Avengers, " .. label:lower() .. ": " .. sum.total .. " Most Wanted players paid back" }
    local top = list[1]
    table.insert(lines, "{star} Guild Avenger: " .. B.ShortName(top.name) .. " (" .. top.total .. " revenge kills, "
        .. top.blows .. " killing blows)")
    for _, p in ipairs(list) do
        if p.bounty then
            table.insert(lines, "{diamond} Bounty Hunter: " .. B.ShortName(p.name) .. " got Public Enemy #1 "
                .. B.ShortName(sum.enemyOne))
            break
        end
    end
    table.insert(lines, "{triangle} Most hunted: " .. B.ShortName(sum.mostHunted) .. " (got " .. sum.huntedTimes .. " times)")
    B.SendLines(lines)
end

---------------------------------------------------------------------------------------------------
-- Events

local function WarnTarget()
    if not B.Opt("chatWanted") or not UnitExists("target") or not UnitIsPlayer("target") then return end
    local name = Plain(B.UnitName("target"))
    local p, place, _, victims = W.For(name)
    if not p or (warnedAt[name] and GetTime() - warnedAt[name] < WARN_EVERY) then return end
    warnedAt[name] = GetTime()
    B.Say("|cffff4444careful|r - that's " .. B.ShortName(name) .. ", Most Wanted #" .. place .. ": killed "
        .. victims .. " (" .. p.kills .. " kills), last in " .. (p.lastZone or p.zone or "?") .. " "
        .. B.Ago(Now() - p.last) .. ".")
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_DEAD", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED",
                         "PLAYER_LOGIN", "PARTY_KILL", "UNIT_DIED", "CHAT_MSG_COMBAT_HOSTILE_DEATH" }) do
    pcall(frame.RegisterEvent, frame, event) -- never the combat log: Forever blocks addons that use it
end

frame:SetScript("OnEvent", function(_, event, unit, arg2)
    if event == "PLAYER_DEAD" then
        ReadDeathSoon()
    elseif event == "PARTY_KILL" then
        pcall(OnPartyKill, unit, arg2) -- attacker GUID, target GUID
    elseif event == "UNIT_DIED" then
        pcall(function() OnDied(NameFromGUID(unit)) end) -- the GUID of who died
    elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        pcall(OnHostileDeath, Plain(unit))
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        pcall(Observe, "mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        pcall(Observe, "target")
        pcall(WarnTarget)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        pcall(Observe, unit)
    elseif event == "PLAYER_LOGIN" then
        C_Timer.NewTicker(60, Forget)
    end
end)
