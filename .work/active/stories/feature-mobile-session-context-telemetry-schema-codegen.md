---
id: feature-mobile-session-context-telemetry-schema-codegen
kind: story
stage: done
tags: [pi-extension, app, relay, protocol]
parent: feature-mobile-session-context-telemetry
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Wire contract: branch/ctx_percent/ctx_max additive room-meta + nullableIntegers codegen

Design element: Unit 1 of the feature body — read the feature's
"Implementation Units / Unit 1" for the full design (schema fields,
merge categories, codegen emitter sites with line anchors, relay merge
hand-edits mirroring d13b85fec's exact touched lines, SPEC.md doc line).

## Acceptance evidence

- Codegen suite green with updated goldens + `protocol/fixtures/relay/
  relay-control.jsonl` rows covering set / clear / preserve for `branch`,
  `ctx_percent`, `ctx_max`.
- Relay merge test proving the null-clear path (post-compaction stale
  percent must not survive) plus absent-preserve.
- `cargo fmt --check && cargo clippy -- -D warnings && cargo test` green;
  codegen vitest green; TS + Dart generated files committed from the run.
- SPEC.md room-meta contract line gains the three fields in the same
  commit set (code-first timing).

## Ordering constraints

None — this is the foundation story; the extension-sampler and app-render
stories depend on it.

## Implementation notes

- Added nullable `branch`, `ctx_percent`, and `ctx_max` to every room-meta
  projection, with `branch` in `nullableStrings` and the new `ctx_percent` /
  `ctx_max` `nullableIntegers` merge category. Generated TypeScript, Dart, and
  Rust outputs are refreshed from the schema; Rust integer projections use
  `u64` and preserve tri-state patch decoding with `Option<Option<u64>>`.
- Extended relay snapshot merge/is-empty and subscriber projection paths. The
  relay remains opaque to telemetry values; null clears are applied in the
  canonical room snapshot and absent patch fields preserve prior values.
- The generated `RoomMeta` expansion also requires the auth bootstrap literal
  to carry the new optional fields, so `relay/src/auth/challenge.rs` was
  updated as a necessary compile-time consumer of the generated contract.
- Fixture coverage includes telemetry set, explicit null-clear, and omitted
  (preserve) patch rows. `docs/SPEC.md` now states the room-meta contract.

## Verification evidence

- `cd protocol && node --import tsx scripts/check-fixtures.ts` — passed (all 5
  fixture families validated).
- `cd tools/protocol-codegen && ../../pi-extension/node_modules/.bin/vitest run
  src/index.vitest.test.ts` — passed (7 tests).
- `cd pi-extension && corepack pnpm generate:protocol && corepack pnpm
  check:protocol && corepack pnpm typecheck` — passed.
- Rust generation from `protocol/scripts/list-types.ts` — passed; generated
  outputs are current.
- `cd relay && cargo fmt --check && cargo clippy -- -D warnings && cargo test`
  — passed (171 unit tests plus all integration suites).
