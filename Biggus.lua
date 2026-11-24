-- Biggus: remembers the guild bank log and hands out titles to who gives and who takes.
--
-- How it works:
--  * The game keeps only the last ~25 entries per bank tab (and of the gold log), and only shows them
--    while you stand at the guild bank. So every time you open the bank, Biggus asks for every
--    log, reads what comes back and adds the new entries to its own history (SavedVariables), which
--    never runs out.
--  * The log only says "3 days 4 hours ago", so each entry gets an approximate hour. An entry from an
--    earlier visit is recognised by who / what / how much / which tab, within 2 hours of that time.
--  * /biggus opens the leaderboard, and "Report" (or /biggus report) posts the highlights to guild chat.
--  * Savings goal: the bank's gold against the price of the next bank tab (or a goal you set with
--    /biggus goal 5000 New tabard), shown as a progress bar, on every bank visit and in the report.
--  * The bank history, the bank's gold and the goal are shared with other Biggus users (Sync.lua).
--    Bank messages:
--      B  entry: "B", kind, type, who, item ID, count, copper, tab, hour, how many identical entries
--                came before it (so that two real identical deposits aren't taken for one)
--      M  gold:  "M", copper in the bank, next tab's price, tabs owned, when it was seen
--      G  goal:  "G", when it was set, copper (0: back to the next bank tab), name

local ADDON, B = ... -- B: shared with the addon's other files

local MATCH_HOURS = 2          -- how far apart one entry's time may drift between two reads
local BIG_WITHDRAWAL = 100000  -- 10g: big enough to get a comment

local QUIPS = {
    "The vault remembers.",
    "Nothing escapes the ledger.",
    "Taking notes. Lots of notes.",
    "Somebody's been busy.",
    "The officers have been informed. (They haven't.)",
    "Every copper is accounted for.",
}

local RANGES = {
    { label = "Last 7 days", hours = 7 * 24 },
    { label = "Last 30 days", hours = 30 * 24 },
    { label = "All time" },
}
local rangeIndex = 1
local bankCache, bankCacheAt = nil, 0 -- all-time bank stats for tooltips

---------------------------------------------------------------------------------------------------
-- Helpers

-- Settings (Extras.lua has the window for them): everything is on until it's turned off.
function B.Opt(key)
    local options = BiggusDB and BiggusDB.options
    if options and options[key] ~= nil then return options[key] end
    return true
end

function B.SetOpt(key, value)
    BiggusDB.options = BiggusDB.options or {}
    BiggusDB.options[key] = value
end

local function Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd700Biggus|r: " .. msg)
end

-- server time: players' clocks differ, and times are shared between them
function B.Now()
    return GetServerTime and GetServerTime() or time()
end

local function NowHour()
    return math.floor(B.Now() / 3600)
end

-- Names. On Forever characters have two-part names ("Muliens Bubbleskull") and no realm names: the
-- game hands the second part over where a realm would be ("Muliens-Bubbleskull"). Biggus keeps every
-- name the way the bank log writes it, "Muliens Bubbleskull"; on a normal realm, "Name" or "Name-Realm".
local function OwnRealm()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
end

function B.Canon(name)
    if type(name) ~= "string" or name == "" then return nil end
    name = name:gsub("%-$", "") -- an empty realm: "Name-"
    local own = OwnRealm()
    if own == "" then return (name:gsub("%-", " ")) end
    if name:sub(-#own - 1) == "-" .. own then name = name:sub(1, -#own - 2) end
    return name
end

-- a unit's name as Biggus keeps it
function B.UnitName(unit)
    local name, second = UnitFullName(unit)
    if not name or name == UNKNOWNOBJECT then return nil end
    if second and second ~= "" then return B.Canon(name .. "-" .. second) end
    return name
end

-- Checking what other players send. Everything that arrives by addon message is untrusted: numbers
-- must be in range, times can't be in the future (a future time would win every "newest" contest)
-- or far in the past, and text loses the game's "|" escape codes (which can fake links and icons, and
-- break guild chat when a report posts them) and control characters.
local MAX_COPPER = 2147483647
local KEEP_DAYS = 400 -- older history is dropped

function B.Num(value, min, max)
    local n = tonumber(value)
    if not n or n ~= n or n < min or n > max or n ~= math.floor(n) then return nil end
    return n
end

function B.Time(value)
    local now = B.Now()
    return B.Num(value, now - KEEP_DAYS * 86400, now + 600)
end

function B.Text(value, maxLength)
    if type(value) ~= "string" then return nil end
    local text = value:gsub("|", ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return text:sub(1, maxLength)
end

-- a player name from a message: plain text, no list or field separators, then the usual form
function B.CleanName(value)
    local text = B.Text(value, 48)
    if not text or text:find("[,\t]") then return nil end
    return B.Canon(text)
end

local function HoursAgo(years, months, days, hours)
    return (years or 0) * 8760 + (months or 0) * 730 + (days or 0) * 24 + (hours or 0)
end

local function ShortName(name)
    if Ambiguate then return Ambiguate(name, "guild") end
    return (name:gsub("%-.*$", ""))
end

local function Money(copper)
    copper = math.floor(copper or 0)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return sign .. g .. "g " .. s .. "s" end
    if s > 0 then return sign .. s .. "s " .. c .. "c" end
    return sign .. c .. "c"
end

local function Colored(copper)
    local text = Money(copper)
    if copper > 0 then return "|cff33ff33+" .. text .. "|r" end
    if copper < 0 then return "|cffff4444" .. text .. "|r" end
    return text
end

local function Ago(seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60)) .. " min ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. " h ago" end
    return math.floor(seconds / 86400) .. " days ago"
end

local function ItemID(link)
    return link and tonumber(link:match("item:(%d+)")) or 0
end

---------------------------------------------------------------------------------------------------
-- Saved data, one history per guild

local function Guild()
    local name = GetGuildInfo("player")
    if not name then return nil end
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
    local key = name .. "-" .. realm
    BiggusDB.guilds = BiggusDB.guilds or {}
    local g = BiggusDB.guilds[key]
    if not g then
        g = { log = {}, bankV2 = true }
        BiggusDB.guilds[key] = g
    end
    if not g.bankV2 then B.MigrateBank(g) end
    B.PruneBank(g)
    return g, name
end

---------------------------------------------------------------------------------------------------
-- Savings goal: the next bank tab, unless a goal of your own is set

local GOAL_QUIPS = {
    { 25, "Long way to go, folks." },
    { 50, "Keep the goblins away from the vault." },
    { 75, "Past halfway. Don't spend it all at once." },
    { 100, "So close you can smell it." },
}

local function GoalQuip(pct)
    for _, q in ipairs(GOAL_QUIPS) do
        if pct < q[1] then return q[2] end
    end
    return "We can afford it! Someone tell the guild master."
end

-- name, target (copper), percent - or nil when there is no goal or the bank's gold isn't known yet
local function GoalProgress(g)
    if not g or not g.bankMoney then return nil end
    local name, target
    if g.goal then
        name, target = g.goal.name, g.goal.copper
    elseif g.tabCost and g.tabCost > 0 then
        name, target = "Bank tab " .. ((g.tabsOwned or 0) + 1), g.tabCost
    end
    if not target or target <= 0 then return nil end
    return name, target, math.floor(g.bankMoney / target * 100)
end

local function GoalText(g)
    local name, target, pct = GoalProgress(g)
    if not name then return nil end
    return name .. ": " .. Money(g.bankMoney) .. " / " .. Money(target) .. " (" .. pct .. "%)", pct
end

---------------------------------------------------------------------------------------------------
-- Reading the bank log

local function Supported()
    return GetGuildBankTransaction ~= nil and QueryGuildBankLog ~= nil
end

local function MoneyLogTab()
    return (MAX_GUILDBANK_TABS or 8) + 1
end

local function QueryAll()
    local tabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    -- a little apart, so the server answers all of them
    for tab = 1, tabs do
        C_Timer.After((tab - 1) * 0.3, function() QueryGuildBankLog(tab) end)
    end
    C_Timer.After(tabs * 0.3, function() QueryGuildBankLog(MoneyLogTab()) end)
end

local function ReadLogs()
    local now, found = NowHour(), {}
    local tabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    for tab = 1, tabs do
        for i = 1, (GetNumGuildBankTransactions(tab) or 0) do
            local kind, who, link, count, _, _, y, m, d, h = GetGuildBankTransaction(tab, i)
            if who and link and (kind == "deposit" or kind == "withdraw") then
                table.insert(found, {
                    kind = "item", type = kind, who = B.Canon(who), item = link, id = ItemID(link),
                    count = count or 1, tab = tab, hour = now - HoursAgo(y, m, d, h),
                })
            end
        end
    end
    if GetNumGuildBankMoneyTransactions then
        for i = 1, (GetNumGuildBankMoneyTransactions() or 0) do
            local kind, who, amount, y, m, d, h = GetGuildBankMoneyTransaction(i)
            if who and amount and (kind == "deposit" or kind == "withdraw" or kind == "repair") then
                table.insert(found, {
                    kind = "money", type = kind, who = B.Canon(who), money = amount, hour = now - HoursAgo(y, m, d, h),
                })
            end
        end
    end
    return found
end

local function Signature(e)
    return table.concat({ e.kind, e.type, e.who, e.id or 0, e.count or 0, e.money or 0, e.tab or 0 }, "|")
end

-- Adds what was read and isn't known yet. Returns the new entries.
local function Merge(found)
    local g = Guild()
    if not g then return {} end
    local known = {}
    for _, e in ipairs(g.log) do
        local sig = Signature(e)
        known[sig] = known[sig] or {}
        table.insert(known[sig], e)
    end
    local matched, added = {}, {}
    for _, e in ipairs(found) do
        local same
        for _, old in ipairs(known[Signature(e)] or {}) do
            if not matched[old] and math.abs(old.hour - e.hour) <= MATCH_HOURS then
                same = old
                break
            end
        end
        if same then
            matched[same] = true
        else
            e.u = B.Now() -- when this copy learned it: what a catch-up sends
            table.insert(g.log, e)
            table.insert(added, e)
        end
    end
    g.lastRead = time()
    bankCache = nil
    return added
end

---------------------------------------------------------------------------------------------------
-- Sharing the bank with other Biggus users (Sync.lua carries the messages)

-- how many entries just like e (same signature, within the time window) come before it in the log
local function Occurrence(g, e)
    local sig, n = Signature(e), 0
    for _, other in ipairs(g.log) do
        if other == e then break end
        if Signature(other) == sig and math.abs(other.hour - e.hour) <= MATCH_HOURS then n = n + 1 end
    end
    return n
end

local function BankMsg(g, e)
    return table.concat({ "B", e.kind, e.type, e.who, e.id or 0, e.count or 0, e.money or 0, e.tab or 0,
                          e.hour, Occurrence(g, e) }, "\t")
end

local function MoneyMsg(g)
    return table.concat({ "M", g.bankMoney or 0, g.tabCost or 0, g.tabsOwned or 0, g.moneySeen or 0 }, "\t")
end

local function GoalMsg(g)
    local goal = g.goal or {}
    local name = B.Text(goal.name, 40) or ""
    return table.concat({ "G", g.goalAt or 0, goal.copper or 0, name }, "\t")
end

-- everything this copy learned after `since` (server time). Item-tab entries only when the receiver
-- may see them (Sync.lua decides: a rank at least as high as yours), since lower ranks may not be
-- allowed to view those tabs' logs; the gold log is open to everyone who can open the bank.
function B.BankCatchUp(since, itemsToo)
    local g = Guild()
    local msgs = {}
    if not g then return msgs end
    for _, e in ipairs(g.log) do
        if (e.u or 0) > since and (itemsToo or e.kind == "money") then table.insert(msgs, BankMsg(g, e)) end
    end
    if g.moneySeen and (g.moneyU or 0) > since then table.insert(msgs, MoneyMsg(g)) end
    if g.goalAt and (g.goalU or 0) > since then table.insert(msgs, GoalMsg(g)) end
    return msgs
end

-- Bank entries another player reported that the real bank log contradicted (see Verify): never
-- taken in again, whoever sends them.
local function Rejected(g, e)
    local sig = Signature(e)
    for _, r in ipairs(g.rejected or {}) do
        if r.sig == sig and math.abs(r.hour - e.hour) <= MATCH_HOURS then return true end
    end
    return false
end

local GOAL_RANK = 1 -- the goal is taken only from the guild master (rank 0) and the first officer rank

-- f: a message's fields; from: who sent it; rank: their guild rank (0 = guild master)
function B.BankReceive(f, from, rank)
    local g = Guild()
    if not g then return end
    local now = B.Now()
    if f[1] == "B" then
        local kind, kindType = f[2], f[3]
        local e = { kind = kind, type = kindType, who = B.CleanName(f[4]), hour = B.Num(f[9], 0, NowHour() + 1) }
        if kind == "item" then
            if kindType ~= "deposit" and kindType ~= "withdraw" then return end
            e.id, e.count = B.Num(f[5], 1, 10000000), B.Num(f[6], 1, 10000)
            e.tab = B.Num(f[8], 1, MAX_GUILDBANK_TABS or 8)
            if not e.id or not e.count or not e.tab then return end
        elseif kind == "money" then
            if kindType ~= "deposit" and kindType ~= "withdraw" and kindType ~= "repair" then return end
            e.money = B.Num(f[7], 1, MAX_COPPER)
            if not e.money then return end
        else
            return
        end
        local before = B.Num(f[10], 0, 100)
        if not e.who or not e.hour or not before or e.hour < NowHour() - KEEP_DAYS * 24 then return end
        if Rejected(g, e) then return end
        -- new unless this copy already has as many entries like it as the sender has up to it
        local sig, have = Signature(e), 0
        for _, other in ipairs(g.log) do
            if Signature(other) == sig and math.abs(other.hour - e.hour) <= MATCH_HOURS then have = have + 1 end
        end
        if have > before then return end
        e.u, e.src = now, from -- src: who reported it (entries this copy read itself have none)
        table.insert(g.log, e)
        bankCache = nil
    elseif f[1] == "M" then
        local money, cost, tabs = B.Num(f[2], 0, MAX_COPPER), B.Num(f[3], 0, MAX_COPPER), B.Num(f[4], 0, 8)
        local seen = B.Time(f[5])
        if not money or not cost or not tabs or not seen or seen <= (g.moneySeen or 0) then return end
        g.bankMoney, g.tabCost, g.tabsOwned = money, cost, tabs
        g.moneySeen, g.moneyU, g.moneySrc = seen, now, from
    elseif f[1] == "G" then
        if not rank or rank > GOAL_RANK then return end -- only the guild's leaders set the goal
        local at, copper = B.Time(f[2]), B.Num(f[3], 0, MAX_COPPER)
        if not at or not copper or at <= (g.goalAt or 0) then return end
        g.goal = copper > 0 and { copper = copper, name = B.Text(f[4], 40) or "Savings goal" } or nil
        g.goalAt, g.goalU, g.goalSrc = at, now, from
    end
    B.Refresh()
end

-- After your own bank visit: entries other players reported, from the stretch of time the real log
-- you just read covers, that the real log doesn't have are dropped (and remembered as rejected).
-- Only the covered stretch counts - older entries have scrolled out of the game's log.
local function Verify(found)
    local g = Guild()
    if not g then return end
    local oldest = {} -- log ("money" or tab number) -> oldest hour the real log still shows
    for _, e in ipairs(found) do
        local key = e.kind == "money" and "money" or e.tab
        if not oldest[key] or e.hour < oldest[key] then oldest[key] = e.hour end
    end
    local function Count(list, e, sig)
        local n = 0
        for _, other in ipairs(list) do
            if Signature(other) == sig and math.abs(other.hour - e.hour) <= MATCH_HOURS then n = n + 1 end
        end
        return n
    end
    local dropped, reporters = 0, {}
    for i = #g.log, 1, -1 do
        local e = g.log[i]
        local key = e.kind == "money" and "money" or e.tab
        if e.src and oldest[key] and e.hour >= oldest[key] + MATCH_HOURS then
            local sig = Signature(e)
            if Count(g.log, e, sig) > Count(found, e, sig) then
                table.remove(g.log, i)
                g.rejected = g.rejected or {}
                table.insert(g.rejected, { sig = sig, hour = e.hour })
                if #g.rejected > 500 then table.remove(g.rejected, 1) end
                dropped = dropped + 1
                reporters[e.src] = true
            end
        end
    end
    if dropped > 0 then
        local names = {}
        for name in pairs(reporters) do table.insert(names, name) end
        Say("dropped " .. dropped .. " bank entries the real bank log doesn't have (reported by "
            .. table.concat(names, ", ") .. "). /biggus block <name> ignores a player from now on.")
        bankCache = nil
    end
end

-- /biggus forget: drops everything a player reported about the bank. Returns how much.
function B.ForgetBank(name)
    local g = Guild()
    if not g then return 0 end
    local n = 0
    for i = #g.log, 1, -1 do
        if g.log[i].src == name then
            table.remove(g.log, i)
            n = n + 1
        end
    end
    if g.moneySrc == name then
        g.bankMoney, g.moneySeen, g.moneySrc = nil, nil, nil -- the next bank visit counts it again
        n = n + 1
    end
    if g.goalSrc == name then
        g.goal, g.goalSrc = nil, nil
        n = n + 1
    end
    bankCache = nil
    return n
end

-- once a session: history older than KEEP_DAYS goes, and the log never grows past MAX_LOG entries
local MAX_LOG = 6000
local pruned = false
local function Prune(g)
    if pruned then return end
    pruned = true
    local oldest = NowHour() - KEEP_DAYS * 24
    for i = #g.log, 1, -1 do
        if g.log[i].hour < oldest then table.remove(g.log, i) end
    end
    while #g.log > MAX_LOG do table.remove(g.log, 1) end
end
B.PruneBank = Prune

-- old saved data: names the new way, and the gold and goal ready to share
local function Migrate(g)
    if g.bankV2 then return end
    for _, e in ipairs(g.log) do e.who = B.Canon(e.who) or e.who end
    if g.bankMoney and not g.moneySeen then g.moneySeen = g.lastRead or 1 end
    if g.goal and not g.goalAt then g.goalAt = 1 end
    g.bankV2 = true
end
B.MigrateBank = Migrate

---------------------------------------------------------------------------------------------------
-- Who did what

-- hours: only this recent (nil: all time)
local function Stats(hours)
    local g = Guild()
    local since = hours and (NowHour() - hours)
    local people = {}
    for _, e in ipairs(g and g.log or {}) do
        if not since or e.hour >= since then
            local p = people[e.who]
            if not p then
                p = { name = e.who, goldIn = 0, goldOut = 0, repairs = 0, itemsIn = 0, itemsOut = 0,
                      valueIn = 0, valueOut = 0, junkIn = 0 }
                people[e.who] = p
            end
            if e.kind == "money" then
                if e.type == "deposit" then
                    p.goldIn = p.goldIn + e.money
                else
                    p.goldOut = p.goldOut + e.money
                    if e.type == "repair" then p.repairs = p.repairs + 1 end
                end
            else
                local _, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(e.item or e.id)
                local value = (sellPrice or 0) * e.count
                if e.type == "deposit" then
                    p.itemsIn = p.itemsIn + e.count
                    p.valueIn = p.valueIn + value
                    if quality == 0 then p.junkIn = p.junkIn + e.count end
                else
                    p.itemsOut = p.itemsOut + e.count
                    p.valueOut = p.valueOut + value
                end
            end
        end
    end
    local list = {}
    for _, p in pairs(people) do
        -- items count at what a vendor would pay for them
        p.net = (p.goldIn + p.valueIn) - (p.goldOut + p.valueOut)
        table.insert(list, p)
    end
    table.sort(list, function(a, b) return a.net > b.net end)
    return list
end

local function Title(p, list)
    local gave = p.goldIn + p.itemsIn > 0
    local took = p.goldOut + p.itemsOut > 0
    if p == list[1] and p.net > 0 then return "|cffffd700Patron Saint of the Vault|r" end
    if p == list[#list] and p.net < 0 then return "|cffff4444Chief Goblin Officer|r" end
    if p.junkIn >= 5 then return "Trash Panda" end
    if p.repairs >= 5 then return "Sponsored by Repair Bills" end
    if took and not gave then return "Takes a Penny, Never Leaves One" end
    if gave and not took then return "Selfless Little Bean" end
    if math.abs(p.net) < 10000 then return "Suspiciously Balanced" end
    if p.net < 0 then return "Goblin in Training" end
    return "Upstanding Citizen"
end

local function Best(list, field)
    local best
    for _, p in ipairs(list) do
        if p[field] > 0 and (not best or p[field] > best[field]) then best = p end
    end
    return best
end

local reporting = false -- a report is still being sent

-- Posts lines to guild chat. Sent all at once they can arrive out of order, so they go half a second apart.
local function SendLines(lines)
    if reporting then return end
    reporting = true
    for i, line in ipairs(lines) do
        C_Timer.After((i - 1) * 0.5, function()
            SendChatMessage(line, "GUILD")
            if i == #lines then reporting = false end
        end)
    end
end

local function Report()
    local list = Stats(RANGES[rangeIndex].hours)
    if #list == 0 then
        Say("nothing to report for " .. RANGES[rangeIndex].label:lower() .. ".")
        return
    end
    local lines = { "Biggus bank report, " .. RANGES[rangeIndex].label:lower() .. ":" }
    local saint, goblin = list[1], list[#list]
    if saint.net > 0 then
        table.insert(lines, "{star} Patron Saint of the Vault: " .. ShortName(saint.name) .. " (+" .. Money(saint.net) .. ")")
    end
    if goblin.net < 0 then
        table.insert(lines, "{skull} Chief Goblin Officer: " .. ShortName(goblin.name) .. " (" .. Money(goblin.net) .. ")")
    end
    local repairer = Best(list, "repairs")
    if repairer then
        table.insert(lines, "{cross} Sponsored by Repair Bills: " .. ShortName(repairer.name) .. " (" .. repairer.repairs .. " repairs)")
    end
    local panda = Best(list, "junkIn")
    if panda then
        table.insert(lines, "{circle} Trash Panda: " .. ShortName(panda.name) .. " (" .. panda.junkIn .. " grey items deposited)")
    end
    local goal, pct = GoalText(Guild())
    if goal then
        table.insert(lines, "{diamond} " .. goal .. " - " .. GoalQuip(pct))
    end
    SendLines(lines)
end

---------------------------------------------------------------------------------------------------
-- The window

local win, rows = nil, {}
local MAX_COLUMNS = 7

-- The window shows one view at a time: the bank, or dungeon runs (Dungeons.lua).
local VIEWS = {
    bank = {
        title = "who feeds the vault, and who raids it",
        empty = "Nothing yet. Visit the guild bank and the snitch will start taking notes.",
        foot = "Net counts items at what a vendor would pay for them.",
        columns = {
            { title = "#", width = 22, justify = "RIGHT" },
            { title = "Name", width = 120 },
            { title = "Gold in", width = 70, justify = "RIGHT" },
            { title = "Gold out", width = 70, justify = "RIGHT" },
            { title = "Items in/out", width = 74, justify = "RIGHT" },
            { title = "Net", width = 78, justify = "RIGHT" },
            { title = "Title", width = 160 },
        },
        rows = function()
            local list, out = Stats(RANGES[rangeIndex].hours), {}
            for i, p in ipairs(list) do
                out[i] = {
                    i .. ".",
                    ShortName(p.name),
                    p.goldIn > 0 and Money(p.goldIn) or "-",
                    p.goldOut > 0 and Money(p.goldOut) or "-",
                    p.itemsIn .. " / " .. p.itemsOut,
                    Colored(p.net),
                    Title(p, list),
                }
            end
            return out
        end,
        report = Report,
    },
    dungeons = {
        title = "who runs dungeons with whom",
        empty = "No runs yet. Enter a dungeon with a guild member and it's logged.",
        foot = "A run counts when at least two guild members are in the group.",
        columns = function() return B.Dungeons.Columns end,
        rows = function() return B.Dungeons.Rows(RANGES[rangeIndex].hours) end,
        info = function() return B.Dungeons.Info() end,
        highlight = function() return B.Dungeons.Highlight(RANGES[rangeIndex].hours) end,
        report = function() B.Dungeons.Report(RANGES[rangeIndex].hours, RANGES[rangeIndex].label) end,
    },
    loot = {
        title = "loot envy: who gets the good stuff",
        empty = "No loot yet. Rare and epic drops in runs with guild members show up here.",
        foot = "Rare (blue) and better items looted in runs with guild members.",
        columns = function() return B.Dungeons.LootColumns end,
        rows = function() return B.Dungeons.LootRows(RANGES[rangeIndex].hours) end,
        info = function() return B.Dungeons.Info() end,
        highlight = function() return B.Dungeons.LootHighlight(RANGES[rangeIndex].hours) end,
        report = function() B.Dungeons.LootReport(RANGES[rangeIndex].hours, RANGES[rangeIndex].label) end,
    },
    wanted = {
        title = "Most Wanted: enemy players who killed a guildie",
        empty = "Nobody yet. When a guildie with Biggus is killed by an enemy player, the killer lands here.",
        foot = "From the death recaps of guildies with Biggus. Battlegrounds and arenas don't count.",
        columns = function() return B.Wanted.Columns end,
        rows = function() return B.Wanted.Rows(RANGES[rangeIndex].hours) end,
        info = function() return B.Wanted.Info() end,
        highlight = function() return B.Wanted.Highlight(RANGES[rangeIndex].hours) end,
        report = function() B.Wanted.Report(RANGES[rangeIndex].hours, RANGES[rangeIndex].label) end,
    },
}
local VIEW_ORDER = { "bank", "dungeons", "loot", "wanted" }
local VIEW_LABELS = { bank = "Bank", dungeons = "Dungeons", loot = "Loot", wanted = "Most Wanted" }
local viewName = "bank"

local function Columns(view)
    return type(view.columns) == "function" and view.columns() or view.columns
end

local function MakeRow(parent, x, y, header)
    local row = { x = x, y = y }
    for i = 1, MAX_COLUMNS do
        local fs = parent:CreateFontString(nil, "OVERLAY", header and "GameFontNormalSmall" or "GameFontHighlightSmall")
        fs:SetWordWrap(false)
        row[i] = fs
    end
    return row
end

-- places a row's cells for the view's columns; cells it has no column for are hidden
local function Layout(row, columns)
    local x = row.x
    for i, fs in ipairs(row) do
        local col = columns[i]
        fs:ClearAllPoints()
        if col then
            fs:SetPoint("TOPLEFT", x, row.y)
            fs:SetWidth(col.width)
            fs:SetJustifyH(col.justify or "LEFT")
            fs:Show()
            x = x + col.width + 6
        else
            fs:Hide()
        end
    end
end

local Refresh

local function BuildWindow()
    win = CreateFrame("Frame", "BiggusFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(690, 480)
    win:SetClampedToScreen(true)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BiggusFrame") -- Escape closes it

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.title:SetPoint("TOP", 0, -5)

    -- a solid background: some UI skins make the template's own see-through
    local background = win:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetPoint("TOPLEFT", 4, -24)
    background:SetPoint("BOTTOMRIGHT", -4, 4)
    background:SetColorTexture(0.06, 0.06, 0.08, 0.97)

    -- one tab per view; the one you're on is lit
    win.tabs = {}
    for i, name in ipairs(VIEW_ORDER) do
        local tab = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        tab:SetSize(86, 22)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 88, -28)
        tab:SetText(VIEW_LABELS[name])
        tab:SetScript("OnClick", function()
            viewName = name
            Refresh()
        end)
        win.tabs[name] = tab
    end

    win.info = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.info:SetPoint("TOPLEFT", 14, -58)
    win.info:SetWidth(660)
    win.info:SetJustifyH("LEFT")
    win.info:SetWordWrap(false)

    local range = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    range:SetSize(110, 22)
    range:SetPoint("TOPRIGHT", -100, -28)
    range:SetScript("OnClick", function()
        rangeIndex = rangeIndex % #RANGES + 1
        Refresh()
    end)
    win.range = range

    local report = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    report:SetSize(80, 22)
    report:SetPoint("TOPRIGHT", -14, -28)
    report:SetText("Report")
    report:SetScript("OnClick", function() VIEWS[viewName].report() end)
    report:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Post the highlights to guild chat")
        GameTooltip:Show()
    end)
    report:SetScript("OnLeave", GameTooltip_Hide)

    local bar = CreateFrame("StatusBar", nil, win)
    bar:SetPoint("TOPLEFT", 14, -74)
    bar:SetPoint("TOPRIGHT", -14, -74)
    bar:SetHeight(18)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.5)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    win.bar = bar

    -- in the dungeons view, a line in the bar's place
    win.highlight = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.highlight:SetPoint("TOP", 0, -76)

    win.header = MakeRow(win, 14, -102, true)

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -120)
    scroll:SetPoint("BOTTOMRIGHT", -32, 30)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(640, 1)
    scroll:SetScrollChild(content)
    win.content = content

    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("CENTER", 0, -10)

    local settings = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    settings:SetSize(80, 20)
    settings:SetPoint("BOTTOMRIGHT", -12, 7)
    settings:SetText("Settings")
    settings:SetScript("OnClick", function() B.OpenSettings() end)

    win.foot = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.foot:SetPoint("BOTTOMLEFT", 14, 10)

    win:SetScript("OnShow", function() Refresh() end)
    win:Hide() -- new frames start shown; Toggle shows it
end

local function RefreshBank()
    local g = Guild()
    if not g then
        win.info:SetText("You're not in a guild.")
    elseif g.lastRead then
        win.info:SetText(#g.log .. " transactions logged · bank last read " .. Ago(time() - g.lastRead))
    else
        win.info:SetText("The bank hasn't been read yet.")
    end

    local goal, pct = GoalText(g)
    if goal then
        win.bar:SetValue(math.min(1, pct / 100))
        if pct >= 100 then win.bar:SetStatusBarColor(0.2, 0.9, 0.2) else win.bar:SetStatusBarColor(1, 0.82, 0) end
        win.bar.text:SetText(goal .. " - " .. GoalQuip(pct))
    else
        win.bar:SetValue(0)
        if g and g.bankMoney and not g.goal then
            win.bar.text:SetText("Every bank tab is bought. Set a goal: /biggus goal 5000 New tabard")
        else
            win.bar.text:SetText("Savings goal: visit the guild bank to count the gold")
        end
    end
end

function Refresh()
    if not win or not win:IsShown() then return end
    local view = VIEWS[viewName]
    local bank = viewName == "bank"
    win.title:SetText("|cffffd700Biggus|r - " .. view.title)
    for name, tab in pairs(win.tabs) do
        local active = name == viewName
        if active then tab:LockHighlight() else tab:UnlockHighlight() end
        local label = tab:GetFontString()
        if label then
            if active then label:SetTextColor(1, 1, 1) else label:SetTextColor(1, 0.82, 0) end
        end
    end
    win.range:SetText(RANGES[rangeIndex].label)
    win.empty:SetText(view.empty)
    win.foot:SetText(view.foot)
    win.bar:SetShown(bank)
    win.highlight:SetShown(not bank)
    if bank then
        RefreshBank()
    else
        win.info:SetText(view.info())
        win.highlight:SetText(view.highlight())
    end

    local columns = Columns(view)
    Layout(win.header, columns)
    for i, fs in ipairs(win.header) do fs:SetText(columns[i] and columns[i].title or "") end

    local data = view.rows()
    win.empty:SetShown(#data == 0)
    for i, cells in ipairs(data) do
        local row = rows[i]
        if not row then
            row = MakeRow(win.content, 0, -(i - 1) * 18)
            rows[i] = row
        end
        Layout(row, columns)
        for c, fs in ipairs(row) do fs:SetText(cells[c] ~= nil and tostring(cells[c]) or "") end
    end
    for i = #data + 1, #rows do
        for _, fs in ipairs(rows[i]) do fs:Hide() end
    end
    win.content:SetHeight(math.max(1, #data * 18))
end

-- for Dungeons.lua
B.Say, B.ShortName, B.Guild, B.SendLines = Say, ShortName, Guild, SendLines
B.Refresh = function() Refresh() end

-- opens the window on a view, or closes it when it's already showing that view
local function Toggle(view)
    if not win then BuildWindow() end
    if win:IsShown() and viewName == view then
        win:Hide()
    else
        viewName = view
        win:Show()
        Refresh()
    end
end
B.Toggle = Toggle

-- for tooltips: a guild member's bank stats (all time) and title; computed at most every 10 seconds
function B.BankFor(name)
    if not bankCache or GetTime() - bankCacheAt > 10 then
        bankCache, bankCacheAt = Stats(nil), GetTime()
    end
    local short = ShortName(name)
    for _, p in ipairs(bankCache) do
        if ShortName(p.name) == short then return p, Title(p, bankCache) end
    end
end

-- the savings goal as one line, or nil
function B.GoalLine()
    return (GoalText(Guild()))
end

function B.Colored(copper)
    return Colored(copper)
end

B.Ago = Ago

---------------------------------------------------------------------------------------------------
-- Events

local newSinceOpen, readPending, announcePending = {}, false, false

local function Announce()
    announcePending = false
    if #newSinceOpen == 0 then return end
    local biggest
    for _, e in ipairs(newSinceOpen) do
        if e.kind == "money" and e.type ~= "deposit" and e.money >= BIG_WITHDRAWAL
            and (not biggest or e.money > biggest.money) then
            biggest = e
        end
    end
    if not B.Opt("chatBank") then
        newSinceOpen = {}
        return
    end
    Say("noted " .. #newSinceOpen .. " new transactions. " .. QUIPS[math.random(#QUIPS)])
    if biggest then
        local _, target = GoalProgress(Guild())
        local setback = target and (" That's " .. math.floor(biggest.money / target * 100) .. "% of the savings goal.") or ""
        Say(ShortName(biggest.who) .. " took " .. Money(biggest.money) .. " out of the bank. Bold." .. setback)
    end
    newSinceOpen = {}
end

local function ReadMoney()
    local g = Guild()
    if not g or not GetGuildBankMoney then return end
    local before = table.concat({ g.bankMoney or "", g.tabCost or "", g.tabsOwned or "" }, "|")
    g.bankMoney = GetGuildBankMoney() or 0
    if GetGuildBankTabCost then g.tabCost = GetGuildBankTabCost() or 0 end
    if GetNumGuildBankTabs then g.tabsOwned = GetNumGuildBankTabs() end
    g.moneySeen, g.moneyU = B.Now(), B.Now()
    if table.concat({ g.bankMoney, g.tabCost or "", g.tabsOwned or "" }, "|") ~= before then
        B.Sync.Broadcast(MoneyMsg(g))
    end
    Refresh()
end

local function ReadSoon()
    if readPending then return end
    readPending = true
    C_Timer.After(1, function()
        readPending = false
        local g = Guild()
        local found = ReadLogs()
        for _, e in ipairs(Merge(found)) do
            table.insert(newSinceOpen, e)
            if g then B.Sync.Broadcast(BankMsg(g, e), e.kind == "item") end
        end
        Verify(found)
        Refresh()
        if not announcePending then
            announcePending = true
            C_Timer.After(3, Announce)
        end
    end)
end

local function OnBankOpened()
    if not Supported() or not IsInGuild() then return end
    QueryAll()
    -- the bank's gold has arrived by then
    C_Timer.After(2, function()
        ReadMoney()
        local goal, pct = GoalText(Guild())
        if goal and B.Opt("chatBank") then Say(goal .. ". " .. GoalQuip(pct)) end
    end)
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "GUILDBANKLOG_UPDATE", "GUILDBANKFRAME_OPENED",
                         "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "GUILDBANK_UPDATE_MONEY",
                         "GUILDBANK_UPDATE_TABS" }) do
    pcall(frame.RegisterEvent, frame, event) -- some of these don't exist in every client
end

frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        BiggusDB = BiggusDB or {}
    elseif event == "GUILDBANKFRAME_OPENED" then
        OnBankOpened()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if Enum and Enum.PlayerInteractionType and arg == Enum.PlayerInteractionType.GuildBanker then
            OnBankOpened()
        end
    elseif event == "GUILDBANKLOG_UPDATE" then
        ReadSoon()
    elseif event == "GUILDBANK_UPDATE_MONEY" or event == "GUILDBANK_UPDATE_TABS" then
        ReadMoney()
    end
end)

---------------------------------------------------------------------------------------------------
-- /biggus

SLASH_BIGGUS1 = "/biggus"
SLASH_BIGGUS2 = "/snitch"
SlashCmdList.BIGGUS = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "goal" then
        local g = Guild()
        if not g then
            Say("you're not in a guild.")
            return
        end
        local gold, name = rest:match("^(%d+)%s*(.*)$")
        local leader = (B.Sync.MyRank() or 99) <= GOAL_RANK
        local shared = leader and " Shared with the guild's Biggus users."
            or " Only on your copy: other copies take the goal from the guild master and officers only."
        if gold and tonumber(gold) * 10000 <= MAX_COPPER then
            g.goal = { copper = tonumber(gold) * 10000, name = B.Text(name, 40) or "Savings goal" }
            Say("now saving for " .. g.goal.name .. ": " .. Money(g.goal.copper) .. "." .. shared)
        else
            g.goal = nil
            Say("back to saving for the next bank tab." .. shared)
        end
        g.goalAt, g.goalU, g.goalSrc = B.Now(), B.Now(), nil
        if leader then B.Sync.Broadcast(GoalMsg(g)) end
        Refresh()
    elseif cmd == "sync" then
        B.Sync.Command(rest:lower())
    elseif cmd == "block" or cmd == "unblock" or cmd == "forget" then
        B.Sync.Trust(cmd, rest)
    elseif cmd == "report" then
        local which = VIEWS[rest:lower()] or VIEWS.bank
        which.report()
    elseif cmd == "dungeons" or cmd == "loot" or cmd == "wanted" then
        Toggle(cmd)
    elseif cmd == "deathcheck" then
        B.Wanted.DeathCheck()
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        B.OpenSettings()
    elseif cmd == "reset" then
        local g = Guild()
        if g then
            wipe(g.log)
            g.lastRead = nil
            Say("bank history wiped. Everyone's innocent again.")
            Refresh()
        end
    elseif cmd == "help" then
        Say("/biggus - bank leaderboard · /biggus dungeons - runs and deaths · /biggus loot - loot envy · "
            .. "/biggus wanted - enemy players who killed guildies · /biggus deathcheck - what your last death "
            .. "recap gave · /biggus report (or report dungeons / loot / wanted) - post to guild chat · /biggus goal 5000 Name - "
            .. "set a savings goal (/biggus goal alone: back to the next bank tab) · /biggus settings · "
            .. "/biggus sync - is sharing working? (/biggus sync now: say hello to everyone again) · "
            .. "/biggus block Name / unblock Name - ignore a player's messages · /biggus forget Name - "
            .. "drop everything that player reported · "
            .. "/biggus reset - forget the bank history")
    else
        if not Supported() then
            Say("this game client has no guild bank log for addons to read.")
        end
        Toggle("bank")
    end
end
