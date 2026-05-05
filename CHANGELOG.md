# BazTooltipEditor Changelog

## 002 — Catches direct-mutation lines, captures colours, /btt capture

- **Direct-mutation detection.** Some addons (Zygor's gold-data block
  is the obvious example) skip `AddLine` and write straight to the
  tooltip's existing FontStrings via `_G[name.."TextLeft"..i]:SetText`.
  After the tooltip data processor's post-call fires, the inspector
  now walks the actual visible lines and surfaces anything its hooks
  didn't capture as `(direct mutation)` entries — so Zygor's block
  shows up instead of disappearing.
- **Colour capture.** Lines now carry the `r,g,b` Blizzard / addons
  pass to `AddLine` / `AddDoubleLine`, and the inspector renders each
  line in its actual colour. "Crafting Reagent" shows up cyan, quest
  prerequisites show red, etc.
- **`Blizzard_*` collapse.** `Blizzard_SharedXML`,
  `Blizzard_TooltipDataProcessor`, etc. all collapse to a single
  "Blizzard" credit. The inspector tells you whether a line is from
  the game itself or a third-party addon — *which* internal Blizzard
  module it lives in is noise.
- **Wrapper-skip mechanism.** Empty list for now, but the scaffolding
  is in place: addons confirmed to be wrappers (i.e. they replace a
  tooltip API rather than `hooksecurefunc`'ing it) can be added so the
  walker steps past them and credits the real source. BlizzMove was
  initially suspected here but turns out to legitimately re-emit the
  Sell Price line via `TooltipDataProcessor.AddLinePreCall`, so the
  attribution to it was correct — the list stays empty pending real
  candidates.
- **`/btt capture`** — snapshot the currently-visible `GameTooltip`,
  open the inspector, and freeze on it. Avoids a modifier-click
  shortcut while we figure out how a unified BazCore-owned shift+
  right-click menu should work.

## 001 — Inspector prototype

First release. Adds a floating inspector panel that captures every
line of the most recent tooltip and shows which addon contributed
each one. Read-only for now — the goal of v1 is to validate that
attribution is accurate before wiring in the rules engine that will
hide and reorder lines in v2.

Open with `/btt` or `/btt inspect`. Hover anything. Click **Freeze**
to lock the current snapshot, **Refresh** to re-render against the
latest tooltip, **Clear cache** if a line was mis-attributed.

Requires BazCore 115+ (`GetAddonFromStack`).
