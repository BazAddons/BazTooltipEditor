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

local function recordLine(tip, kind, ...)
    local w = ensure(tip)
    local text
    if kind == "double" then
        local left, right = ...
        text = (left or "") .. " | " .. (right or "")
    elseif kind == "texture" then
        text = "[texture]"
    else
        text = (...)
    end
    local sig = Attribution:Signature(text or "")
    w.lines[#w.lines + 1] = {
        kind  = kind,
        text  = text,
        sig   = sig,
        addon = Attribution:LookupOrAttribute(sig),
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

    hooksecurefunc(tip, "AddLine", function(self, text)
        recordLine(self, "text", text)
    end)
    hooksecurefunc(tip, "AddDoubleLine", function(self, left, right)
        recordLine(self, "double", left, right)
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
            w.type = nil
        end
    end)
end

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
