<h1 align="center">BazTooltipEditor</h1>

<p align="center">
  <strong>See which addon is adding what to your tooltips.</strong>
</p>

<p align="center">
  <a href="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"><img src="https://img.shields.io/badge/License-GPL%20v2-green" alt="License"/></a>
  <a href="https://github.com/BazAddons/BazTooltipEditor/releases"><img src="https://img.shields.io/github/v/tag/BazAddons/BazTooltipEditor?label=Version&color=orange" alt="Version"/></a>
</p>

> **Requires [BazCore](https://www.curseforge.com/wow/addons/bazcore)**

## What it does

Open the inspector with `/btt`, then hover an item, spell, NPC, or quest. Every line of the resulting tooltip shows up in the panel with the name of the addon that added it. Useful for tracking down which addon is responsible for the noise on your tooltips before you decide what to do about it.

This is a v1 prototype — it inspects, it doesn't yet edit. Hide / reorder rules are next.

## Slash commands

| Command | Description |
|---------|-------------|
| `/btt` | Toggle the inspector panel |
| `/btt inspect` | Same as `/btt` |
| `/btt reset` | Clear the cached attribution data |

## How attribution works

When an addon calls `GameTooltip:AddLine(...)`, BazTooltipEditor walks the Lua stack at hook time and finds the first frame whose source path lives under `Interface\AddOns\<name>\`. That name is the credited addon. Results are cached by a normalised line signature so identical lines from the same addon share an entry.

The Lua stack-walk lives in BazCore (`BazCore:GetAddonFromStack`) so any other addon that needs caller attribution can use the same primitive.

## License

[GNU General Public License v2](LICENSE).
