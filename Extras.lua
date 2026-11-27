-- Biggus extras: the minimap button, the lines on guild members' tooltips, and the settings window.

local ADDON, B = ...

local OPTIONS = {
    { key = "chatBank", label = "Comment in chat when the guild bank log is read" },
    { key = "chatRuns", label = "Say when a dungeon run with guild members is logged" },
    { key = "chatDeaths", label = "Make fun of deaths in dungeon runs" },
    { key = "chatLoot", label = "Announce blue and epic drops and roll wins in guild runs" },
    { key = "wanted", label = "Track Most Wanted and Avengers (enemy players who killed guildies)" },
    { key = "chatWanted", label = "Announce ganks and revenge, and warn when I target someone Most Wanted" },
    { key = "share", label = "Share bank, runs, deaths, loot, kills and revenge with guild members who have Biggus" },
    { key = "minimap", label = "Show the minimap button" },
    { key = "tooltip", label = "Show Biggus info on tooltips (guild members, and Most Wanted enemies)" },
}

---------------------------------------------------------------------------------------------------
-- Minimap button: left-click opens Biggus, right-click the settings, drag moves it around the map

local button

local function PlaceButton()
    local angle = math.rad(BiggusDB.minimapAngle or 200)
    local radius = Minimap:GetWidth() / 2 + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local atan2 = math.atan2 or math.atan
    BiggusDB.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
    PlaceButton()
end

local function MakeButton()
    button = CreateFrame("Button", "BiggusMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then B.OpenSettings() else B.Toggle("bank") end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffd700Biggus|r")
        local goal = B.GoalLine()
        if goal then GameTooltip:AddLine(goal, 1, 1, 1) end
        GameTooltip:AddLine("Left-click: open · Right-click: settings · Drag: move", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    PlaceButton()
end

local function UpdateMinimapButton()
    if B.Opt("minimap") then
        if not button then MakeButton() end
        button:Show()
    elseif button then
        button:Hide()
    end
end

---------------------------------------------------------------------------------------------------
-- Tooltips: a guild member's Biggus titles and numbers

local function AddLines(tooltip)
    if not B.Opt("tooltip") then return end
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    local name = B.UnitName(unit) -- the full "First Last" name: UnitName gives only the first part on Forever
    if not name then return end
    if not UnitIsInMyGuild(unit) then
        -- an enemy-faction player: on the Most Wanted list?
        local faction, mine = UnitFactionGroup(unit), UnitFactionGroup("player")
        if not faction or faction == mine or faction == "Neutral" then return end
        local p, place, title, victims = B.Wanted.For(name)
        if not p then return end
        tooltip:AddLine("|cffff4444Biggus Most Wanted #" .. place .. "|r - " .. title)
        tooltip:AddLine("Killed " .. victims .. " (" .. p.kills .. (p.kills == 1 and " kill" or " kills")
            .. "), last in " .. (p.lastZone or p.zone or "?") .. " " .. B.Ago(B.Now() - p.last), 1, 0.6, 0.6, true)
        local paid, lastBy = B.Wanted.PaidBack(name)
        if paid > 0 then
            tooltip:AddLine("Paid back by guildies " .. paid .. (paid == 1 and " time" or " times")
                .. (lastBy and (" (last: " .. B.ShortName(lastBy) .. ")") or ""), 0.4, 1, 0.4)
        end
        tooltip:Show()
        return
    end
    local bank, bankTitle = B.BankFor(name)
    local runs, runTitle, lootTitle, withYou = B.Dungeons.For(name)
    if not bank and not runs then return end
    tooltip:AddLine("|cffffd700Biggus|r")
    if bank then
        tooltip:AddLine("Bank: " .. bankTitle .. " (" .. B.Colored(bank.net) .. ")", 1, 1, 1)
    end
    if runs then
        local together = (withYou > 0 and not UnitIsUnit(unit, "player")) and (", " .. withYou .. " with you") or ""
        tooltip:AddLine("Dungeons: " .. runTitle .. " (" .. runs.runs .. " runs" .. together .. ", "
            .. runs.deaths .. " deaths)", 1, 1, 1)
        if runs.drops > 0 or runs.rollWins > 0 then
            tooltip:AddLine("Loot: " .. lootTitle .. " (" .. runs.epics .. " epics, " .. runs.rares .. " blues, rolls won "
                .. runs.needWins .. " Need / " .. runs.greedWins .. " Greed)", 1, 1, 1)
        end
    end
    tooltip:Show() -- resize to fit the new lines
end

local function HookTooltips()
    local function OnUnit(tooltip)
        if tooltip == GameTooltip then pcall(AddLines, tooltip) end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", OnUnit)
    end
end

---------------------------------------------------------------------------------------------------
-- Settings window

local settings

local function MakeSettings()
    settings = CreateFrame("Frame", "BiggusSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    settings:SetSize(470, 400) -- the height is set once the rows are laid out
    settings:SetFrameStrata("FULLSCREEN_DIALOG") -- above the main window
    settings:SetClampedToScreen(true)

    -- a solid background: some UI skins make the template's own see-through
    local background = settings:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetPoint("TOPLEFT", 4, -24)
    background:SetPoint("BOTTOMRIGHT", -4, 4)
    background:SetColorTexture(0.06, 0.06, 0.08, 0.97)
    settings:SetMovable(true)
    settings:EnableMouse(true)
    settings:RegisterForDrag("LeftButton")
    settings:SetScript("OnDragStart", settings.StartMoving)
    settings:SetScript("OnDragStop", settings.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BiggusSettingsFrame") -- Escape closes it

    local title = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("|cffffd700Biggus|r settings")

    -- each label wraps inside the window, and each row is as tall as its label
    local WIDTH, LEFT, BOX, GAP = 470, 16, 26, 4
    local labelWidth = WIDTH - LEFT - BOX - GAP - 18
    settings.boxes = {}
    local rows = {}
    for _, option in ipairs(OPTIONS) do
        local box = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
        box:SetSize(BOX, BOX)
        local label = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetWidth(labelWidth)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        if label.SetWordWrap then label:SetWordWrap(true) end
        label:SetText(option.label)
        label:SetPoint("LEFT", box, "RIGHT", GAP, 0)
        box:SetScript("OnClick", function(self)
            B.SetOpt(option.key, self:GetChecked() and true or false)
            if option.key == "minimap" then UpdateMinimapButton() end
        end)
        settings.boxes[option.key] = box
        table.insert(rows, { box = box, label = label })
    end

    -- rows one under the other, each as tall as its (wrapped) label; again on every show, since a
    -- label's height can read 0 before the window was first drawn
    local function Layout()
        local y = -34
        for _, row in ipairs(rows) do
            local textHeight = math.ceil(row.label:GetStringHeight() or 0)
            local rowHeight = math.max(BOX, textHeight + 6)
            row.label:SetHeight(math.max(textHeight, 14))
            row.box:ClearAllPoints()
            row.box:SetPoint("TOPLEFT", LEFT, y - (rowHeight - BOX) / 2)
            y = y - rowHeight - 4
        end
        settings:SetSize(WIDTH, -y + 12)
    end
    Layout()

    settings:SetScript("OnShow", function()
        Layout()
        for key, box in pairs(settings.boxes) do box:SetChecked(B.Opt(key)) end
    end)
    settings:Hide()
end

function B.OpenSettings()
    if not settings then MakeSettings() end
    if settings:IsShown() then
        settings:Hide()
        return
    end
    -- beside the main window when it's open, so they don't cover each other
    settings:ClearAllPoints()
    local main = _G.BiggusFrame
    if main and main:IsShown() then
        settings:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
    else
        settings:SetPoint("CENTER")
    end
    settings:Show()
end

---------------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    UpdateMinimapButton()
    HookTooltips()
end)
