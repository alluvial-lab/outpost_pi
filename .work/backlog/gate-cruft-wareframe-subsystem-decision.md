---
id: gate-cruft-wareframe-subsystem-decision
created: 2026-08-15
updated: 2026-08-15
tags: [app, cleanup, docs]
---

# Decide the fate of the orphaned wareframe design subsystem (decision required)

Post-hoc v0.5.0 cruft-gate finding, merged with the docs-gate duplicate.
Confidence: High that it is orphaned; **Decision required** on disposition.

## Location
`app/wareframe/` (5 tracked files, ~85 KB): `FLUTTER_GUIDE.md`,
`ios-frame.jsx`, `Outpost-Pi.html`, `screens.jsx`, `tweaks-panel.jsx` — the
retired black/cyan + Inter/JetBrains Mono design. No current tracked file
references the directory; the canonical design contract is now
`.mockups/design-system/tokens.css`.

## Risk
`FLUTTER_GUIDE.md:3-20` still *prescribes* the retired palette/fonts as the
implementation contract — an agent or future contributor loading it would
implement against obsolete tokens.

## Options
(a) Delete the subsystem (simplest; history retains it),
(b) move under a clearly-historical location/README,
(c) keep + banner-mark every file as retired.
Removal simplifies the design source surface; retention preserves old screen
rationale. Operator call.
