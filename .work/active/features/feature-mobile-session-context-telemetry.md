---
id: feature-mobile-session-context-telemetry
kind: feature
stage: drafting
tags: [pi-extension, app, ux, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Mobile parity for TUI footer telemetry: git branch, ctx %, max ctx

## Brief

The pi TUI footer shows `git branch`, `ctx ▰▰▰▰▱ 92% · max 1m` — surface the
same on mobile (operator ask, 2026-09-07). Additive optional fields on
`roomMeta`/`roomMetaPatch`/`helloRoomMeta` (`branch`, `ctx_percent`,
`ctx_max`), riding the exact additive-room-meta rails proven by the
`background` field (d13b85fec): schema + codegen + relay merge/broadcast +
extension publish + app render.

One real investigation point: the extension-visible SDK surface for context
usage/max (the TUI renders it, so the session knows it — find the surface:
session header, usage events, sessionManager). Everything else is a
well-trodden recipe.

## Strategic decisions

- None at scope time — the framing is fully pinned by the proven
  `background`-field recipe; remaining choices (ctx_max raw vs humanized,
  publish thresholds, render placement) are feature-design calls.

## Simplification opportunity

- **Single-schema-touch batching**: if other telemetry fields are wanted
  later, land them in this one schema pass, not N passes (sequencing note
  from the park — resist scope creep the other way too: only fields the
  operator actually asked for).
- **SDK surface before subprocess**: check whether the SDK exposes the git
  branch to extensions before shelling out — a shell-out per publish is a new
  process lifecycle to own; prefer an SDK surface if one exists.
- **Raw numbers, app-side formatting**: `ctx_max` as a raw token count; the
  app humanizes ("1m") — keeps the extension dumb and the render flexible.

## Design input (shaped at park, 2026-09-07)

### Shape (rides the additive-room-meta rails proven by `background`)

- **Fields**: `branch` (string), `ctx_percent` (0-100), `ctx_max` (raw token
  count). Schema: additive optional fields on `roomMeta`/`roomMetaPatch`/
  `helloRoomMeta` + codegen + relay merge/broadcast — the exact recipe from
  the `background` field (d13b85fec), now well-trodden.
- **Extension sources**: branch — read git for the session cwd (SDK surface
  or shell-out; the TUI already derives it). ctx usage/max — find the
  extension-visible surface (session header / usage events / sessionManager)
  — THIS is the one real investigation point. Publish cadence: on change
  (compaction shifts max; percent crosses thresholds) — transition/
  threshold-gated, not per-message, to keep meta traffic bounded (mirror the
  background field's edge-only discipline).
- **App render**: chat header line (compact: `main · 92% of 1m`) and/or the
  session tile subtitle when idle; a ctx-pressure state (e.g. >85%) could
  tint like reconnecting-amber — operator call at design.
