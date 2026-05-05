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

function Attribution:Identify()
    local name = BazCore:GetAddonFromStack(3, SKIP_ADDONS)
    return name or "Blizzard"
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
