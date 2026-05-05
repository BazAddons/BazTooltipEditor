-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazTooltipEditor: Inspector
--
-- Floating panel that mirrors the most recently captured tooltip,
-- one row per line, with attribution labels showing which addon
-- contributed each line. The user freezes a snapshot by hovering
-- something with the inspector open; subsequent tooltip events keep
-- updating until they explicitly freeze (or close the inspector).
--
-- v001 prototype: read-only display. No "hide this line" button yet -
-- the goal is to validate that attribution is accurate before we wire
-- in the rules engine. Drag the title bar to reposition.
---------------------------------------------------------------------------

local addon = BazCore:GetAddon("BazTooltipEditor")
if not addon then return end

local Inspector = addon.Inspector

---------------------------------------------------------------------------
-- Tooltip-data-type names (display only)
---------------------------------------------------------------------------

local TYPE_LABEL = setmetatable({}, { __index = function() return "Unknown" end })
do
    if Enum and Enum.TooltipDataType then
        for name, value in pairs(Enum.TooltipDataType) do
            if type(value) == "number" then
                TYPE_LABEL[value] = name
            end
        end
    end
end

---------------------------------------------------------------------------
-- Panel construction
---------------------------------------------------------------------------

local PANEL_WIDTH  = 480
local PANEL_HEIGHT = 600
local ROW_HEIGHT   = 18

local function BuildPanel()
    local panel = BazCore:CreatePanel(UIParent, PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetFrameStrata("HIGH")
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:Hide()

    -- Title bar (also the drag handle)
    local title = CreateFrame("Frame", nil, panel)
    title:SetPoint("TOPLEFT", 4, -4)
    title:SetPoint("TOPRIGHT", -4, -4)
    title:SetHeight(24)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() panel:StartMoving() end)
    title:SetScript("OnDragStop",  function() panel:StopMovingOrSizing() end)

    title.text = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title.text:SetPoint("LEFT", title, "LEFT", 4, 0)
    title.text:SetText("BazTooltipEditor — Inspector")

    -- Frozen / live indicator
    title.status = title:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title.status:SetPoint("RIGHT", title, "RIGHT", -28, 0)
    title.status:SetTextColor(0.5, 1.0, 0.5)
    title.status:SetText("LIVE")

    -- Close button
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        Inspector:Hide()
    end)

    -- Subtitle (current tooltip type)
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -2)
    panel.subtitle:SetText("Hover anything to capture its tooltip.")
    panel.subtitle:SetTextColor(0.7, 0.7, 0.7)

    -- Toolbar: Freeze / Refresh / Clear cache
    local toolbar = CreateFrame("Frame", nil, panel)
    toolbar:SetPoint("TOPLEFT", panel.subtitle, "BOTTOMLEFT", -4, -6)
    toolbar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, 0)
    toolbar:SetHeight(22)

    local function MakeButton(label, anchorTo, anchorPoint, offsetX)
        local b = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
        b:SetSize(80, 20)
        b:SetText(label)
        if anchorTo then
            b:SetPoint("LEFT", anchorTo, anchorPoint or "RIGHT", offsetX or 4, 0)
        else
            b:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
        end
        return b
    end

    panel.btnFreeze = MakeButton("Freeze")
    panel.btnFreeze:SetScript("OnClick", function() Inspector:ToggleFreeze() end)

    panel.btnRefresh = MakeButton("Refresh", panel.btnFreeze)
    panel.btnRefresh:SetScript("OnClick", function() Inspector:Refresh() end)

    panel.btnClearCache = MakeButton("Clear cache", panel.btnRefresh)
    panel.btnClearCache:SetScript("OnClick", function()
        addon:SetSetting("attribution", {})
        addon:Print("Attribution cache cleared. Hover tooltips again to rebuild.")
    end)

    -- Scrollable line list
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 4, -6)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_WIDTH - 36, 1)
    scroll:SetScrollChild(content)

    panel.scroll  = scroll
    panel.content = content
    panel.title   = title
    panel.rows    = {}

    return panel
end

local panel  -- created lazily on first Show
local frozen = false
local lastSeenTooltip

---------------------------------------------------------------------------
-- Row rendering
---------------------------------------------------------------------------

local KIND_TAG = {
    text    = "T",
    double  = "D",
    texture = "I",
}

local function GetRow(content, i)
    local row = panel.rows[i]
    if not row then
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", content, "LEFT", 0, 0)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

        row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.kind:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.kind:SetWidth(14)
        row.kind:SetJustifyH("CENTER")
        row.kind:SetTextColor(0.6, 0.6, 0.6)

        row.addon = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.addon:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
        row.addon:SetWidth(110)
        row.addon:SetJustifyH("LEFT")
        row.addon:SetWordWrap(false)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.addon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        panel.rows[i] = row
    end
    return row
end

local function ColorForAddon(name)
    if name == "Blizzard" then return 0.85, 0.85, 0.85 end
    if name == "BazTooltipEditor" or name == "BazCore" then return 1.00, 0.82, 0.00 end
    -- Hash-based stable per-addon hue
    local hash = 0
    for i = 1, #name do hash = (hash + name:byte(i) * (i + 7)) % 360 end
    local h = hash / 360
    -- Simple HSV->RGB at S=0.55, V=0.95
    local s, v = 0.55, 0.95
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local r, g, b
    local sector = i % 6
    if     sector == 0 then r, g, b = v, t, p
    elseif sector == 1 then r, g, b = q, v, p
    elseif sector == 2 then r, g, b = p, v, t
    elseif sector == 3 then r, g, b = p, q, v
    elseif sector == 4 then r, g, b = t, p, v
    else                    r, g, b = v, p, q
    end
    return r, g, b
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

function Inspector:Render(tip)
    if not panel then return end
    local capture = addon.WorkingTooltips and addon.WorkingTooltips[tip]
    if not capture then return end

    local typeName = TYPE_LABEL[capture.type or -1]
    panel.subtitle:SetText(string.format("Type: |cffffd700%s|r   Lines: |cffffd700%d|r", typeName, #capture.lines))

    local y = 0
    for i, line in ipairs(capture.lines) do
        local row = GetRow(panel.content, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  panel.content, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0, -y)
        row.kind:SetText(KIND_TAG[line.kind] or "?")
        row.addon:SetText(line.addon or "?")
        row.addon:SetTextColor(ColorForAddon(line.addon or "Blizzard"))
        row.text:SetText(line.text or "")
        -- Apply the line's captured colour so the inspector reflects how
        -- the line will actually render in the tooltip (e.g. "Crafting
        -- Reagent" in cyan, quest-prereqs in red).
        if line.color then
            row.text:SetTextColor(line.color[1], line.color[2], line.color[3])
        else
            row.text:SetTextColor(1, 1, 1)
        end
        row:Show()
        y = y + ROW_HEIGHT
    end

    -- Hide unused rows
    for i = #capture.lines + 1, #panel.rows do
        panel.rows[i]:Hide()
    end

    panel.content:SetHeight(math.max(y, 1))
end

---------------------------------------------------------------------------
-- Hook entry point (called from Hooks.lua's TooltipDataProcessor post-call)
---------------------------------------------------------------------------

function Inspector:OnTooltipReady(tip)
    if not panel or not panel:IsShown() then return end
    if frozen then return end
    lastSeenTooltip = tip
    self:Render(tip)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Inspector:Show()
    panel = panel or BuildPanel()
    panel:Show()
    addon:SetSetting("inspectorOpen", true)
    if lastSeenTooltip then self:Render(lastSeenTooltip) end
end

function Inspector:Hide()
    if panel then panel:Hide() end
    addon:SetSetting("inspectorOpen", false)
end

function Inspector:Toggle()
    panel = panel or BuildPanel()
    if panel:IsShown() then self:Hide() else self:Show() end
end

function Inspector:ToggleFreeze()
    frozen = not frozen
    if not panel then return end
    if frozen then
        panel.title.status:SetText("FROZEN")
        panel.title.status:SetTextColor(1.0, 0.7, 0.0)
        panel.btnFreeze:SetText("Unfreeze")
    else
        panel.title.status:SetText("LIVE")
        panel.title.status:SetTextColor(0.5, 1.0, 0.5)
        panel.btnFreeze:SetText("Freeze")
        if lastSeenTooltip then self:Render(lastSeenTooltip) end
    end
end

function Inspector:Refresh()
    if lastSeenTooltip then self:Render(lastSeenTooltip) end
end

---------------------------------------------------------------------------
-- Capture: snapshot whatever's currently on GameTooltip and freeze.
-- Triggered by /btt capture and the future shift+right-click menu entry.
---------------------------------------------------------------------------

function Inspector:Capture()
    local tip = GameTooltip
    if not tip or not tip:IsShown() then
        addon:Print("No tooltip is currently visible. Hover something first, then run /btt capture.")
        return
    end
    -- Make sure the working buffer reflects whatever's on screen now,
    -- including any direct-mutation lines added by addons that bypassed
    -- AddLine (the post-call delta scan handles that path).
    if addon.ScanUnattributed then addon.ScanUnattributed(tip) end
    self:Show()
    lastSeenTooltip = tip
    if not frozen then self:ToggleFreeze() end
    self:Render(tip)
end

---------------------------------------------------------------------------
-- Restore inspector state on login
---------------------------------------------------------------------------

BazCore:QueueForLogin(function()
    if addon:GetSetting("inspectorOpen") then
        Inspector:Show()
    end
end, "BazTooltipEditor:inspector-restore")
