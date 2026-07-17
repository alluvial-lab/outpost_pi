---
id: story-refresh-current-protocol-security-docs
kind: story
stage: done
tags: [docs, protocol, security, app, pi-extension]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-16
---

# Refresh current protocol and pairing-security documentation

## Review origin

Important, explicitly non-blocking follow-up from the deep review of `feature-outpost-pi-identifier-convergence`. The feature named the `PROTOCOL.md` trust-model correction as out of scope, but no separate story tracked it.

## Problem

`PROTOCOL.md` still describes an ephemeral App-key and an Owner-signed inner `pair_request` that the extension verifies. The current schema's `pair_request` contains only `id`, `token`, and `device_name`; the app authenticates its relay WebSocket with the persisted Owner key and sends the token request over that authenticated transport. The identities, pairing sequence, and protection claims therefore overstate a signature step that is not present in the inner message.

The protocol package also retains completed-step prose: `protocol/README.md` says runtime consumers have not switched to generated contracts, and `protocol/schema/outpost-pi.schema.json` says later stories will fill the family schemas. Generated TS/Dart/Rust consumers and populated family schemas are already current reality.

## Scope

- Rewrite the identities, pairing sequence, and trust-model assertions in `PROTOCOL.md` to match the current authenticated-transport plus single-use-token flow.
- Preserve the accurate Owner-key role in relay authentication and signed mesh membership; do not weaken or invent security guarantees.
- Rewrite stale Step-1/future-adoption prose in `protocol/README.md` and `protocol/schema/outpost-pi.schema.json` as current-state descriptions.
- Keep history in git rather than migration/progress prose.

## Acceptance criteria

- [ ] `PROTOCOL.md` matches the current `pair_request` schema and app/extension pairing implementation.
- [ ] The protection model no longer claims an inner Owner signature the wire does not carry.
- [ ] `protocol/README.md` and the umbrella schema describe current generated-contract adoption without “Step 1” or “later stories” progress language.
- [ ] `corepack pnpm --dir protocol check` and generated-contract drift checks pass.
