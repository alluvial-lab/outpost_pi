---
id: feature-retire-legacy-piext-composition-seams
kind: feature
stage: drafting
tags: [pi-extension, refactor, cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-16
---

# Retire transitional Pi-extension composition/test seams after module extraction

## Brief

The `epic-bold-split-pi-extension-index-*` arc extracted the monolithic
`src/index.ts` into composition-root modules (relay-transport, owner-multiplexer,
cli-daemon-pairing, sdk-session-projection). Several transitional compatibility
seams were left in place to keep the build green during the split; they are now
the canonical wiring and the legacy surfaces are redundant. This feature removes
or neutralizes the transitional shims:

- Migrate legacy index test aliases to the named harness
  (`gate-cruft-index-legacy-test-aliases`)
- Retire or neutralize the legacy index ports adapter after module extraction
  (`gate-cruft-legacy-index-ports-adapter`)
- Retire the temporary relay owner-channel bridge
  (`gate-cruft-relay-owner-channel-bridge`)
- Remove the unused standalone CLI command-surface dependency
  (`gate-cruft-standalone-cli-unused-command-surface`)

## Simplification opportunity

This is the cleanup that closes the module-extraction arc: delete compatibility
adapters, dead test aliases, and the temporary owner-channel bridge once the
split modules are the sole runtime wiring. Pure structural removal — no
observable behavior change to the public surface.

## Source

Promoted from backlog by `scope` (2026-07-15). Cluster of 4 `gate-cruft-*`
findings from the v0.6.0 release `gate-cruft` pass.
