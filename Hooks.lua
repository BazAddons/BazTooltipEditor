-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazTooltipEditor: Hooks
--
-- Captures every line added to a tooltip alongside attribution. The
-- captures live in a per-tooltip "working" buffer keyed by frame, so
-- a re-fired tooltip (item info loading async, comparison tooltip
-- mirror, etc.) accumulates into a fresh buffer each time
-- OnTooltipCleared fires.
--
-- This file is *capture-only* in v001. The inspector reads from the
-- working buffer to render its panel; no rules engine yet, no tooltip
-- mutation. That keeps the prototype safe (we are touching no secure
-- state, only observing) while the attribution accuracy is validated.
---------------------------------------------------------------------------

local addon = BazCore:GetAddon("BazTooltipEditor")
if not addon then return end

local Hooks       = addon.Hooks
local Attribution = addon.Attribution

---------------------------------------------------------------------------
-- Per-tooltip working buffers
---------------------------------------------------------------------------

-- Indexed by tooltip frame. Each entry: { lines = { {kind, text, sig,
-- addonName}, ... }, type = <Enum.TooltipDataType or nil>, lastUpdated }
local working = {}

-- Public so the inspector can read the most recent capture.
addon.WorkingTooltips = working

local function ensure(tip)
    local w = working[tip]
    if not w then
        w = { lines = {}, type = nil }
        working[tip] = w
    end
    return w
end

local function recordLine(tip, kind, payload, color)
    local w = ensure(tip)
    local text
    if kind == "double" then
        text = (payload.left or "") .. " | " .. (payload.right or "")
    elseif kind == "texture" then
        text = "[texture]"
    else
        text = payload or ""
    end
    local sig = Attribution:Signature(text or "")
    w.lines[#w.lines + 1] = {
        kind  = kind,
        text  = text,
        sig   = sig,
        addon = Attribution:LookupOrAttribute(sig),
        color = color,  -- {r, g, b} or nil for default
    }
end

---------------------------------------------------------------------------
-- Frame list
--
-- We hook the standard tooltip frames. ItemRefTooltip handles chat
-- link clicks; EmbeddedItemTooltip is the one inside QuestLog and
-- recipe tooltips; ShoppingTooltip1/2/3 are item comparisons.
-- Hooking each frame's AddLine is necessary because secure post-hooks
-- on a method-table-level function would still need the `self` to
-- decide which working buffer to write to, and going per-frame is
-- clearer.
---------------------------------------------------------------------------

local TOOLTIP_FRAMES = {
    GameTooltip,
    ItemRefTooltip,
    EmbeddedItemTooltip,
    ShoppingTooltip1,
    ShoppingTooltip2,
    ShoppingTooltip3,
}

local function HookFrame(tip)
    if not tip then return end
    if tip._bttHooked then return end
    tip._bttHooked = true

    hooksecurefunc(tip, "AddLine", function(self, text, r, g, b)
        local color = (r and g and b) and { r, g, b } or nil
        recordLine(self, "text", text, color)
    end)
    hooksecurefunc(tip, "AddDoubleLine", function(self, left, right, lr, lg, lb)
        local color = (lr and lg and lb) and { lr, lg, lb } or nil
        recordLine(self, "double", { left = left, right = right }, color)
    end)
    if tip.AddTexture then
        hooksecurefunc(tip, "AddTexture", function(self)
            recordLine(self, "texture")
        end)
    end

    -- OnTooltipCleared empties the working buffer. The next AddLine
    -- after a clear starts a fresh capture.
    tip:HookScript("OnTooltipCleared", function(self)
        local w = working[self]
        if w then
            wipe(w.lines)
            w.type     = nil
            w._scanned = false
        end
    end)
end

---------------------------------------------------------------------------
-- Post-call delta scan
--
-- The AddLine / AddDoubleLine hooks miss any addon that mutates the
-- tooltip's existing FontStrings directly (Zygor's price-data block is
-- the obvious case in the wild - it grabs `_G[tooltipName.."TextLeft"..i]`
-- and calls SetText on each one). After the TooltipDataProcessor's
-- post-call has fired (i.e. all addons have had their chance to
-- inject), walk the actual visible lines and surface anything our
-- captures don't account for as "(direct mutation)" entries.
---------------------------------------------------------------------------

-- Recursively walk a frame's child frames and their regions, returning
-- every visible FontString that contains text. Used to find tooltip
-- additions that live in child frames Blizzard's NumLines API doesn't
-- count (Zygor's gold-data block being the canonical example).
local function CollectChildFontStrings(frame, out, depth)
    depth = depth or 0
    if depth > 4 then return end  -- safety: tooltips don't nest deeper
    if not frame.GetChildren then return end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetObjectType
               and region:GetObjectType() == "FontString"
               and region:IsShown()
               and region.GetText then
                local text = region:GetText()
                if text and text ~= "" then
                    out[#out + 1] = region
                end
            end
        end
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        if child.IsShown and child:IsShown() then
            CollectChildFontStrings(child, out, depth + 1)
        end
    end
end

local function ScanUnattributed(tip)
    local w = working[tip]
    if not w or w._scanned then return end
    w._scanned = true

    local tipName = tip.GetName and tip:GetName()
    if not tipName then return end

    -- Multiset keyed by signature (whitespace-normalised, colour-code
    -- and number-stripped). Using raw text here lost duplicates to
    -- minor differences between the AddLine arg and what GetText()
    -- reads back later. For double-lines we index *both* the flattened
    -- "left | right" form and the LEFT-only form, since the scanner
    -- only walks TextLeftN FontStrings - the visible left half should
    -- match against the double-line's left text.
    local captured = {}
    local function add(sig)
        if sig == "" then return end
        captured[sig] = (captured[sig] or 0) + 1
    end
    for _, line in ipairs(w.lines) do
        add(line.sig or "")
        if line.kind == "double" then
            -- The full flattened sig was already added above. Also
            -- index the left-only signature so a TextLeftN-only walker
            -- matches even though the right column is in TextRightN.
            local left = (line.text or ""):match("^(.-)%s*|%s*")
            if left then add(Attribution:Signature(left)) end
        end
    end

    -- Pass 1: tooltip's own TextLeft FontStrings (the standard line
    -- sequence Blizzard's NumLines counts).
    local numLines = tip.NumLines and tip:NumLines() or 0
    for i = 1, numLines do
        local fs = _G[tipName .. "TextLeft" .. i]
        if fs and fs.GetText and fs:IsShown() then
            local visible = fs:GetText()
            if visible and visible ~= "" then
                local sig = Attribution:Signature(visible)
                local count = captured[sig]
                if count and count > 0 then
                    captured[sig] = count - 1
                else
                    local r, g, b = fs:GetTextColor()
                    w.lines[#w.lines + 1] = {
                        kind  = "text",
                        text  = visible,
                        sig   = sig,
                        addon = "(direct mutation)",
                        color = (r and g and b) and { r, g, b } or nil,
                    }
                    captured[sig] = -1  -- mark seen so the child-frame
                                        -- pass doesn't double-add it
                end
            end
        end
    end

    -- Pass 2: FontStrings inside child frames. Catches addons that
    -- attach their own panel onto the tooltip (Zygor-style overlays).
    local extras = {}
    CollectChildFontStrings(tip, extras)
    for _, fs in ipairs(extras) do
        local visible = fs:GetText()
        if visible and visible ~= "" then
            local sig = Attribution:Signature(visible)
            local count = captured[sig]
            if not count or count <= 0 then
                if count == nil then
                    -- Brand-new line that the standard scan didn't see.
                    local r, g, b = fs:GetTextColor()
                    w.lines[#w.lines + 1] = {
                        kind  = "text",
                        text  = visible,
                        sig   = sig,
                        addon = "(direct mutation)",
                        color = (r and g and b) and { r, g, b } or nil,
                    }
                    captured[sig] = -1
                end
                -- count <= 0 means we already accounted for it; skip.
            else
                captured[sig] = count - 1
            end
        end
    end
end

-- Public so the inspector and slash commands can force a re-scan.
addon.ScanUnattributed = ScanUnattributed

---------------------------------------------------------------------------
-- Tooltip data type registration
--
-- TooltipDataProcessor.AddTooltipPostCall runs *after* Blizzard's base
-- tooltip is built and most addons have injected. We use it to tag
-- the working buffer with its tooltip type (Item / Spell / Unit / etc.)
-- so the inspector can group rules by type later. Capture itself is
-- already done via the AddLine hooks above; the post-call here is just
-- for the type tag.
---------------------------------------------------------------------------

local function TagType(tip, dataType)
    local w = ensure(tip)
    w.type = dataType
end

local function RegisterPostCalls()
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then return end
    if not Enum or not Enum.TooltipDataType then return end

    for _, dataType in pairs(Enum.TooltipDataType) do
        if type(dataType) == "number" then
            TooltipDataProcessor.AddTooltipPostCall(dataType, function(tooltip)
                TagType(tooltip, dataType)
                ScanUnattributed(tooltip)
                if addon.Inspector and addon.Inspector.OnTooltipReady then
                    addon.Inspector:OnTooltipReady(tooltip)
                end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function Hooks:Install()
    for _, tip in ipairs(TOOLTIP_FRAMES) do
        HookFrame(tip)
    end
    RegisterPostCalls()
end

BazCore:QueueForLogin(function()
    Hooks:Install()
end, "BazTooltipEditor:hooks")
