-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazTooltipEditor: Settings
--
-- v001 prototype: minimal landing page that explains the addon and
-- documents the slash commands. The real per-addon rule editor lands
-- in v2 once the inspector has surfaced which addons we need to
-- handle.
---------------------------------------------------------------------------

local addon = BazCore:GetAddon("BazTooltipEditor")
if not addon then return end

local function BuildLanding()
    return BazCore:CreateLandingPage("BazTooltipEditor", {
        subtitle = "See which addon is adding what to your tooltips",

        description =
            "Open the inspector with /btt inspect, then hover anything " ..
            "in the world or your bags. Every line of the resulting " ..
            "tooltip shows up in the panel with the name of the addon " ..
            "that added it - so you can see exactly who is responsible " ..
            "for the noise on your tooltips before deciding what to do " ..
            "about it.\n\n" ..
            "v1 is read-only inspection. Hide and reorder rules will " ..
            "arrive once attribution accuracy has been validated " ..
            "against the addons people commonly run.",

        features =
            "INSPECTOR PANEL\n" ..
            "* Floating draggable window that mirrors the most recent tooltip\n" ..
            "* Each line tagged with its source addon, colour-coded for quick scanning\n" ..
            "* Live mode follows whatever tooltip you mouse over; Freeze locks the current snapshot for study\n" ..
            "* Renders text lines, double-lines (left+right), and texture lines\n\n" ..
            "ATTRIBUTION CACHE\n" ..
            "* First sighting of a line walks the Lua stack to find the addon\n" ..
            "* Subsequent sightings reuse the cached attribution for speed\n" ..
            "* Cache persists across reloads; clear it from the inspector panel or via /btt reset\n",

        commands = {
            { "/btt",         "Open this settings page" },
            { "/btt inspect", "Toggle the inspector panel" },
            { "/btt reset",   "Clear the cached attribution data" },
        },
    })
end

BazCore:QueueForLogin(function()
    if not BazCore.RegisterOptionsTable then return end
    BazCore:RegisterOptionsTable("BazTooltipEditor", BuildLanding)
    if BazCore.AddToSettings then
        BazCore:AddToSettings("BazTooltipEditor", "BazTooltipEditor")
    end
end, "BazTooltipEditor:options")
