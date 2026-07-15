---
id: feature-outpost-pi-identifier-convergence-auth-contract
kind: story
stage: review
tags: [rebrand, security, testing, pi-extension, app, relay, protocol]
parent: feature-outpost-pi-identifier-convergence
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Share the auth-domain contract and add a cross-component test

Implements Unit 4 of `feature-outpost-pi-identifier-convergence`.

## Scope

Establish the canonical `outpost-pi-relay-auth-v1\n` auth-domain prefix in one schema-level location. Derive the TS and Rust constants from the generated protocol module where the toolchain makes it trivial; the Dart constant stays local (no codegen path from TS schema) but is covered by the shared-vector test. Add a cross-component contract test asserting app/extension/relay all sign over the identical `outpost-pi-relay-auth-v1\n` prefix bytes.

Current duplication:
- `app/lib/data/transport/ws_transport.dart:34`
- `pi-extension/src/transport/relay_client.ts:14`
- `relay/src/auth/challenge.rs:125`

## Preserve

- `relay/src/auth/auth_test.rs:128` legacy `remote-pi-relay-auth-v1\n` literal (rejection test).

## Design note

If generating a byte constant from JSON Schema into all three languages proves impractical (schema codegen emits structs/unions, not byte constants), the acceptable fallback is: put the canonical string in a shared schema metadata field, document that consumers reference it, and rely on the cross-component test as the enforcement. Do not over-engineer a byte-constant generator. Record which path was taken in implementation notes.

## Verification

- Extension: `corepack pnpm typecheck && corepack pnpm test` (from `pi-extension/`)
- Relay: `cargo fmt --check && cargo clippy -- -D warnings && cargo test` (from `relay/`)
- App: `flutter analyze && flutter test` (from `app/`)
- The new cross-component test must fail if any one of the three constants drifts.
