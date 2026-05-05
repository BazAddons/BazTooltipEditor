# BazTooltipEditor Changelog

## 006 — Inspect entry also lives in BazBars's shift+right-click menu

The "Inspect this tooltip" entry now registers against both the
`bag-item` (BazBags) and `bar-slot` (BazBars 054+) scopes, so the
inspector is one click away from any tooltip-bearing frame in the
suite.

## 005 — "Inspect this tooltip" context-menu entry

Registers an "Inspect this tooltip" entry into BazCore's shared
`bag-item` context menu (BazCore 116+). Now when you shift+right-click
a bag slot, the BazBags category menu appears with a BazTooltipEditor
section below it offering one-click capture of the current tooltip
into the inspector — no more flicking back to chat to type
`/btt capture`.

The same entry will register against more scopes (bar-slot, unit,
quest pin, etc.) as BazCore exposes them.

## 004 — Double-line right halves no longer mis-flagged + taller panel

- Indexing both halves of every captured `AddDoubleLine`. v003 only
  registered the left text in the delta-scan multiset, so the right
  half ("Cloth" against a "Feet | Cloth" double-line, "Speed 2.60"
  against "84-141 Damage | Speed 2.60", etc.) was treated as a brand-
  new direct-mutation entry. Both halves are indexed now.
- Inspector panel is taller (360 px → 600 px) so a typical equipped-
 item tooltip fits without scrolling.

## 003 — Fewer false direct-mutation entries

- **Signature-based delta-scan comparison.** v002 compared raw `AddLine`
  text to FontString `:GetText()` output, but tiny differences (escaped
  colour codes, internal Blizzard reformatting) caused captured lines
  to appear as `(direct mutation)` duplicates. Comparison now uses the
  same whitespace-/colour-/digit-normalised signature the attribution
  cache uses, so cosmetic differences collapse.
- **Double-line left-text indexing.** Captured `AddDoubleLine` entries
  now also register their left half alone, so the scanner walking
  `TextLeftN` FontStrings matches "Feet" against the captured "Feet |
  Cloth" double-line instead of treating it as a new line.
- **Recursive child-frame scan.** Some addons (Zygor's gold-data
  overlay being the canonical case) attach their own panel onto the
  tooltip rather than touching its `TextLeftN` FontStrings. The post-
  call delta scan now walks `tip:GetChildren()` and their regions
  recursively, surfacing FontStrings inside child frames as
  `(direct mutation)` entries.

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
