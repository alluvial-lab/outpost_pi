---
id: epic-rebrand-to-outpost-pi-mechanical-rename-relay-rename
kind: story
stage: implementing
tags: [rebrand, relay]
parent: epic-rebrand-to-outpost-pi-mechanical-rename
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# relay mechanical rename

## Scope
Unit 5 of the mechanical-rename feature. ~12 occurrences across 6 files.
Small. Rename log prefixes, Cargo metadata, README prose.

## Exclusion list (DO NOT TOUCH — owned by wire-stable feature)
- `RELAY_AUTH_DOMAIN_PREFIX` / `remote-pi-relay-auth-v1` (Unit 3),
  generated protocol files (`relay/src/protocol/generated/`).

## Acceptance Criteria
- [ ] `cargo fmt --check` (in `relay/`) clean
- [ ] `cargo clippy -- -D warnings` (in `relay/`) clean
- [ ] `cargo test` (in `relay/`) green
- [ ] Verification grep clean (only excluded auth literal remains, renamed by wire-stable Unit 3)
