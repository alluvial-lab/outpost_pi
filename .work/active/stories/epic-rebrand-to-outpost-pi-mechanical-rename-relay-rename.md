---
id: epic-rebrand-to-outpost-pi-mechanical-rename-relay-rename
kind: story
stage: done
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
- [ ] `cargo fmt --check` (in `relay/`) clean — blocked by 45 pre-existing formatting diffs in relay source/tests; this story did not modify those files.
- [x] `cargo clippy -- -D warnings` (in `relay/`) clean
- [x] `cargo test` (in `relay/`) green
- [x] Verification grep clean (only excluded auth literal remains, renamed by wire-stable Unit 3)

## Implementation notes
- Renamed the relay Cargo package and Docker image/tag references to `outpost-pi-relay`; preserved the `relay` library and binary targets so existing Rust imports and the Docker entrypoint remain stable.
- Added the `Outpost-Pi WebSocket relay` Cargo description and renamed relay README, Docker volume examples, deployment script image, and relay guidance title.
- Left `RELAY_AUTH_DOMAIN_PREFIX = b"remote-pi-relay-auth-v1\\n"` unchanged as required. The verification grep reports only that excluded literal.
- `cargo clippy -- -D warnings` passed. `cargo test` passed (121 unit, 3 integration, 13 mesh, 9 forwarding, 10 presence, 2 protocol parity, and 20 rooms tests); it emitted two existing `unused_mut` warnings in test code. `cargo fmt --check` remains blocked by 45 pre-existing source/test formatting diffs.
