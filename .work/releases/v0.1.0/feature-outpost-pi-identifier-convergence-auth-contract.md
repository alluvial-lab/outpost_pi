---
id: feature-outpost-pi-identifier-convergence-auth-contract
kind: story
stage: done
tags: [rebrand, security, testing, pi-extension, app, relay, protocol]
parent: feature-outpost-pi-identifier-convergence
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
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

## Implementation notes

Path taken: schema-metadata SSOT + codegen generation + shared-vector contract test (the design's primary path, not the fallback).

- The canonical `authDomainPrefix: "outpost-pi-relay-auth-v1\n"` lives in `protocol/schema/relay-control.schema.json` under `x-outpost-pi`.
- The codegen (`tools/protocol-codegen/src/index.ts` + `bin/protocol-codegen.mjs`) emits `RELAY_AUTH_DOMAIN_PREFIX` into the generated TS module (`pi-extension/src/protocol/generated/protocol.generated.ts`) and the generated Rust module (`relay/src/protocol/generated/control.rs`).
- TS consumer (`pi-extension/src/transport/relay_client.ts`) imports the generated constant instead of hand-coding the literal; a `relayAuthSigningBytes()` helper builds the signed bytes.
- Rust consumer (`relay/src/auth/challenge.rs`) references the generated constant.
- Dart (`app/lib/data/transport/ws_transport.dart`) stays local (no codegen path) with a `relayAuthSigningBytes()` helper, covered by the shared-vector test.
- Shared byte-vector fixture: `protocol/fixtures/relay/auth-domain-vector.json`; per-component tests load it and assert each client signs over the identical bytes: `app/test/data/transport/ws_transport_auth_contract_test.dart`, `pi-extension/src/transport/relay_client.test.ts`, `relay/src/auth/auth_test.rs` (new `relay_auth_signs_the_shared_cross_component_byte_vector` test).
- `protocol/scripts/check-fixtures.ts` extended to validate the vector fixture family.

Files changed: `protocol/schema/relay-control.schema.json`, `protocol/fixtures/relay/auth-domain-vector.json`, `protocol/scripts/check-fixtures.ts`, `tools/protocol-codegen/src/index.ts`, `tools/protocol-codegen/bin/protocol-codegen.mjs`, `tools/protocol-codegen/src/index.test.ts`, `pi-extension/src/protocol/generated/protocol.generated.ts`, `pi-extension/src/transport/relay_client.ts`, `pi-extension/src/transport/relay_client.test.ts`, `relay/src/protocol/generated/control.rs`, `relay/src/auth/challenge.rs`, `relay/src/auth/auth_test.rs`, `app/lib/data/transport/ws_transport.dart`, `app/test/data/transport/ws_transport_auth_contract_test.dart`.

Note: `relay-control.schema.json` and `index.test.ts` also carry the protocol-schema story's title/description rename (shared-file interleave); both verified green together.

Verification (run by orchestrator on the combined tree): extension typecheck + tests (838 passed, 3 skipped); relay fmt/clippy/test (all green); app analyze (clean) + tests (698 passed); protocol `check` + `generate:rust:check` (clean).

Discrepancies from design: none — the primary generation path was feasible.
Adjacent issues parked: none.


## Review (2026-07-15)

**Verdict**: Approve - story verified by implement; fast-lane advance

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane: green build+test verification recorded by implement. Orchestrator re-verified the combined tree (extension 838 passed/3 skipped; relay all green; app analyze clean + 698 passed; protocol check + generate:rust:check clean; site lint+build clean).
