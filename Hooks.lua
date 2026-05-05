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

local function ScanUnattributed(tip)
    local w = working[tip]
    if not w or w._scanned then return end
    w._scanned = true

    local tipName = tip.GetName and tip:GetName()
    if not tipName then return end

    local numLines = tip.NumLines and tip:NumLines() or 0
    if numLines == 0 then return end

    -- Multiset of texts we already captured via AddLine / AddDoubleLine.
    -- Double-lines flatten to "left | right" the same way recordLine
    -- builds them, so the visible left+right pair won't match - we only
    -- check single text lines here. Direct-mutation addons almost
    -- always touch left FontStrings, not the rarely-used double-line
    -- right column.
    local captured = {}
    for _, line in ipairs(w.lines) do
        if line.kind == "text" then
            local t = line.text or ""
            captured[t] = (captured[t] or 0) + 1
        end
    end

    for i = 1, numLines do
        local fs = _G[tipName .. "TextLeft" .. i]
        if fs and fs.GetText then
            local visible = fs:GetText()
            if visible and visible ~= "" then
                local count = captured[visible]
                if count and count > 0 then
                    captured[visible] = count - 1
                else
                    -- This visible line was never seen by AddLine; an
                    -- addon set the FontString directly.
                    local r, g, b = fs:GetTextColor()
                    w.lines[#w.lines + 1] = {
                        kind  = "text",
                        text  = visible,
                        sig   = Attribution:Signature(visible),
                        addon = "(direct mutation)",
                        color = (r and g and b) and { r, g, b } or nil,
                    }
                end
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
