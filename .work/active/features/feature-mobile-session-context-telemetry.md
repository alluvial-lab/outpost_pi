---
id: backlog-mobile-session-context-telemetry
created: 2026-09-07
updated: 2026-09-07
tags: [pi-extension, app, ux, protocol]
---

# Mobile parity for TUI footer telemetry: git branch, ctx %, max ctx

Operator ask (2026-09-07): the pi TUI footer shows `git branch`, `ctx
▰▰▰▰▱ 92% · max 1m` — surface the same on mobile.

## Shape (rides the additive-room-meta rails proven by `background`)

- **Fields**: `branch` (string), `ctx_percent` (0-100), `ctx_max` (token
  count or humanized "1m" — decide at design; raw number + app-side
  formatting is cleaner). Schema: additive optional fields on
  `roomMeta`/`roomMetaPatch`/`helloRoomMeta` + codegen + relay
  merge/broadcast — the exact recipe from the `background` field
  (d13b85fec), now well-trodden.
- **Extension sources**: branch — read git for the session cwd
  (shell-out or SDK surface; the TUI already derives it — check whether
  the SDK exposes it to extensions before shelling). ctx usage/max —
  the session knows (TUI renders it); find the extension-visible
  surface (session header / usage events / sessionManager) — THIS is
  the one real investigation point. Publish cadence: on change
  (compaction shifts max; percent crosses thresholds) — transition/
  threshold-gated, not per-message, to keep meta traffic bounded
  (mirror the background field's edge-only discipline).
- **App render**: chat header line (compact: `main · 92% of 1m`) and/or
  the session tile subtitle when idle; a ctx-pressure state (e.g. >85%)
  could tint like reconnecting-amber — operator call at design.
- **Sequencing note**: single-schema-touch batching — if other telemetry
  fields are wanted later, land them in one schema pass, not N.

## Candidate lane

Feature, small — one investigation point (SDK ctx-usage surface), then
a proven recipe. Pairs naturally with the fleet-update button as the
next workstation-tie-cutting batch.
