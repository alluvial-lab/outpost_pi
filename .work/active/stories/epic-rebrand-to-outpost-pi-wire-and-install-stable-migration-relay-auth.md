---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-relay-auth
kind: story
stage: implementing
tags: [rebrand, relay, security]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on:
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-regen-generated
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# Relay auth constant rename + hard-cutover compatibility test

## Scope

Unit 3 of the wire-stable migration feature. Rename the relay's
`RELAY_AUTH_DOMAIN_PREFIX` constant and add the hard-cutover compatibility
test that pins the locked strategic decision (no dual-accept: old auth
string rejected, new accepted).

## Units implemented
- Unit 3 (relay auth)

## Changes
- `relay/src/auth/challenge.rs` line 107:
  `b"remote-pi-relay-auth-v1\n"` → `b"outpost-pi-relay-auth-v1\n"`
- Update the doc comment's cross-reference to the app's
  `relayAuthDomainPrefix` (the app file changes in Unit 6; the comment's
  file-path reference stays valid)
- Add a hard-cutover compatibility test: an auth attempt signed over the
  OLD `remote-pi-relay-auth-v1\n` prefix is rejected as `InvalidSig`; the
  same signature over the new prefix verifies. This is the single most
  important new test in the feature — it makes the strategic decision
  testable.

## Acceptance Criteria
- [ ] `cargo test` (in `relay/`) passes including the new cutover test
- [ ] `cargo clippy -- -D warnings` (in `relay/`) clean
- [ ] `cargo fmt --check` (in `relay/`) clean
