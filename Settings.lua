-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazTooltipEditor: Settings
--
-- v001 prototype: minimal options page that explains the addon and
-- exposes the Toggle Inspector / Clear Cache actions. The real
-- per-addon rule editor lands in v2 once the inspector has surfaced
-- which addons we need to handle.
---------------------------------------------------------------------------

local addon = BazCore:GetAddon("BazTooltipEditor")
if not addon then return end

local function BuildOptions()
    return {
        type = "page",
        name = "BazTooltipEditor",
        blocks = {
            { type = "h1", text = "BazTooltipEditor" },
            { type = "lead", text = "Inspect the lines other addons inject into tooltips, see who's adding what, and (in a future update) reorder or hide them." },

            { type = "h2", text = "Inspector" },
            { type = "paragraph", text = "Open the inspector panel and hover anything in the world or your bags. Each line of the resulting tooltip is shown with the name of the addon that contributed it." },
            { type = "paragraph", text = "Slash command: |cff00ff00/btt inspect|r" },

            { type = "h2", text = "Attribution cache" },
            { type = "paragraph", text = "Once an addon has been seen adding a particular line, that attribution is remembered across reloads so the inspector stays fast. Clearing the cache forces a re-scan the next time you open a tooltip." },
            { type = "paragraph", text = "Slash command: |cff00ff00/btt reset|r" },

            { type = "note", style = "info", text = "v1 prototype: read-only inspection. Hide / reorder rules will arrive once attribution accuracy has been validated against the addons people commonly run." },
        },
    }
end

BazCore:QueueForLogin(function()
    if not BazCore.RegisterOptionsTable then return end
    BazCore:RegisterOptionsTable("BazTooltipEditor", BuildOptions)
end, "BazTooltipEditor:options")
