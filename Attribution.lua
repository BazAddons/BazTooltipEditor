-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazTooltipEditor: Attribution
--
-- Identifies which addon added a given tooltip line by walking the Lua
-- stack at hook-call time via BazCore:GetAddonFromStack(). Skips our
-- own and BazCore frames so the third-party addon is what surfaces.
--
-- Also produces a stable signature for a line's text so identical
-- lines (e.g. "Damage: 5,432" and "Damage: 7,108") collapse to one
-- cache entry. This keeps the persisted attribution table small and
-- lets the inspector show "this kind of line was added by X" rather
-- than caching every literal value separately.
---------------------------------------------------------------------------

local addon = BazCore:GetAddon("BazTooltipEditor")
if not addon then return end

local Attribution = addon.Attribution

-- Frames in these addons are noise on the stack walk - they're
-- BazTooltipEditor's own hook plumbing or the suite framework. The
-- *interesting* frame is whichever addon called AddLine.
local SKIP_ADDONS = {
    BazTooltipEditor = true,
    BazCore          = true,
}

-- "Wrapper layer" addons that don't generate tooltip content themselves
-- but appear on the stack because they replaced (rather than
-- hooksecurefunc'd) one of the tooltip APIs. When the walker encounters
-- one of these, it keeps going - the deeper frame is the real source.
-- Empty for now; populate as wrapping addons are confirmed in the wild.
-- (BlizzMove is NOT a wrapper - it legitimately re-emits the sell-price
-- line via TooltipDataProcessor.AddLinePreCall, so attributing that
-- line to it is correct.)
local WRAPPER_ADDONS = {}

---------------------------------------------------------------------------
-- Line text > stable signature
--
-- Strips colour codes, normalises whitespace, and replaces digit runs
-- with a placeholder. Two lines from the same addon with different
-- numeric values collapse to one signature.
---------------------------------------------------------------------------

function Attribution:Signature(text)
    if type(text) ~= "string" or text == "" then return "" end
    local t = text
    t = t:gsub("|c%x%x%x%x%x%x%x%x", "")
    t = t:gsub("|r", "")
    t = t:gsub("|H[^|]*|h", "")
    t = t:gsub("|h", "")
    t = t:gsub("%d[%d,%.]*", "#")
    t = t:gsub("%s+", " ")
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    return t:lower()
end

---------------------------------------------------------------------------
-- Identify the addon currently calling AddLine / AddDoubleLine etc.
--
-- The hook chain looks like:
--   Foo addon's tooltip hook
--   GameTooltip:AddLine(...)         <- secure post-hook fires here
--   our hooksecurefunc closure       <- this function is called from here
--   Attribution:Identify
--
-- BazCore:GetAddonFromStack(level=3, skip) starts at the closure's
-- caller (the addon that called AddLine) and walks up until it finds
-- a frame outside our skip-list.
---------------------------------------------------------------------------

-- Collapse Blizzard's many internal addon paths (Blizzard_SharedXML,
-- Blizzard_TooltipDataProcessor, Blizzard_PlayerInteractionFrameTemplates,
-- etc.) to a single "Blizzard" credit. The user wants to know "is this
-- a third-party addon or shipped with the game" - which Blizzard module
-- the line happens to live in is noise.
local function NormalizeAddonName(name)
    if not name then return nil end
    if name:find("^Blizzard_") then return "Blizzard" end
    if name == "FrameXML" then return "Blizzard" end
    return name
end

function Attribution:Identify()
    -- Walk the whole stack looking for the first "real content" addon -
    -- skip our own frames AND any registered wrapper-layer addons so a
    -- chain like `Blizzard > BlizzMove (wrapper) > our hook` resolves
    -- to Blizzard rather than BlizzMove.
    local stack = debugstack(3)
    if stack and stack ~= "" then
        for line in stack:gmatch("[^\n]+") do
            local n = line:match("Interface[\\/]AddOns[\\/]([^\\/]+)[\\/]")
            if n and not SKIP_ADDONS[n] and not WRAPPER_ADDONS[n] then
                return NormalizeAddonName(n) or "Blizzard"
            end
        end
    end
    return "Blizzard"
end

---------------------------------------------------------------------------
-- Cache lookup with persistence
--
-- The first time we see a (signature, addon) pair we store it in the
-- saved variable so subsequent sessions can attribute the line without
-- having to walk the stack again. The cache is keyed by signature
-- alone; if two addons happen to produce identical signature text the
-- cache will retain whichever was first seen, which is acceptable for
-- a v1 prototype - the inspector can always force a refresh.
---------------------------------------------------------------------------

function Attribution:LookupOrAttribute(signature)
    if signature == "" then return "Blizzard" end
    local cache = addon:GetSetting("attribution") or {}
    if cache[signature] then return cache[signature] end
    local name = self:Identify()
    cache[signature] = name
    addon:SetSetting("attribution", cache)
    return name
end
