-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazTooltipEditor: Core
--
-- v001 prototype: inspector-only. Hover any tooltip-bearing thing
-- (item, spell, unit, etc.) and the inspector panel shows every line
-- of the resulting tooltip with attribution to the addon that added it.
-- Rules engine (hide / reorder) lands in v2 once the inspector has
-- proven its attribution accuracy.
---------------------------------------------------------------------------

local ADDON_NAME = "BazTooltipEditor"

BazTooltipEditor = BazTooltipEditor or {}

local addon
addon = BazCore:RegisterAddon(ADDON_NAME, {
    title = "BazTooltipEditor",
    savedVariable = "BazTooltipEditorDB",
    profiles = true,
    defaults = {
        enabled       = true,
        inspectorOpen = false,
        attribution   = {},  -- cached signature -> addonName, persisted
    },

    slash = { "/btt", "/baztooltip" },
    commands = {
        inspect = {
            desc = "Toggle the tooltip inspector panel",
            handler = function()
                if addon.Inspector and addon.Inspector.Toggle then
                    addon.Inspector:Toggle()
                end
            end,
        },
        capture = {
            desc = "Snapshot the currently visible tooltip and freeze",
            handler = function()
                if addon.Inspector and addon.Inspector.Capture then
                    addon.Inspector:Capture()
                end
            end,
        },
        reset = {
            desc = "Clear cached attribution data",
            handler = function()
                addon:SetSetting("attribution", {})
                addon:Print("Attribution cache cleared.")
            end,
        },
    },

    minimap = {
        label = "BazTooltipEditor",
        onClick = function()
            if addon.Inspector and addon.Inspector.Toggle then
                addon.Inspector:Toggle()
            end
        end,
    },
})

-- Module-shared namespace. Each file attaches its public surface here.
addon.Hooks       = {}
addon.Attribution = {}
addon.Inspector   = {}
