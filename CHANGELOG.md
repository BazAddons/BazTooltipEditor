# BazTooltipEditor Changelog

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
