---
id: feature-repair-current-state-docs
kind: feature
stage: drafting
tags: [docs, pi-extension, relay, cockpit, prose]
parent: null
depends_on: []
release_binding: null
gate_origin: docs
created: 2026-07-15
updated: 2026-07-16
---

# Repair current-state module, protocol, and operator guidance docs

## Brief

Six documentation gate findings describe foundation/README/CLAUDE.md claims
that have drifted from current code after the bold-refactor module extraction
and the 1 MiB → 4 MiB relay limit change. Per the rolling-foundation principle,
docs carry truth, not history — these are stale assertions a future agent will
read as authoritative. This feature rewrites each in place:

- `gate-docs-composition-root-session-hooks` — `src/index.ts` no longer registers `session_start`/`session_shutdown` directly (moved to composition root)
- `gate-docs-peer-join-broadcast-location` — `peer_joined/peer_left` broadcast comment points to the wrong module (now `session/broker.ts`)
- `gate-docs-readme-stale-boilerplate` — Cockpit README is still generic Flutter starter text
- `gate-docs-relay-claudemd-logging-guidance` — `relay/CLAUDE.md` logging guidance references `info_span!` for handlers (handlers now use `info!`/`warn!`/`error!` directly)
- `gate-docs-relay-ct-limit-1mib-stale` — relay message-size decision table still says 1 MiB (implementation defaults to 4 MiB)
- `gate-cruft-protocol-facade-stale-schema-ir-comment` — protocol facade claims relay-control frames are absent from the schema IR, but `manifest.json` declares the `relayControl` family

## Simplification opportunity

Rewrite each stale assertion to current state; remove the drift. No code
change. No "previously" prose — git is the audit trail.

## Source

Promoted from backlog by `scope` (2026-07-15). 5 `gate-docs-*` + 1
`gate-cruft-protocol-facade-*` findings from the v0.6.0 release `gate-docs`
and `gate-cruft` passes.
