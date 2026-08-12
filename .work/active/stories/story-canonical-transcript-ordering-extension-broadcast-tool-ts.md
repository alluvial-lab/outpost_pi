---
id: story-canonical-transcript-ordering-extension-broadcast-tool-ts
kind: story
stage: done
tags: [pi-extension, bug]
parent: feature-canonical-transcript-ordering
depends_on: []
release_binding: v0.4.0
gate_origin: null
created: 2026-08-03
updated: 2026-08-11
---

# Extension broadcasts canonical server ts on live tool frames

Unit 1 of `feature-canonical-transcript-ordering`. The extension already
computes `Date.now()` for the history/transcript event log
(`pi-extension/src/index.ts:1349,1373,1381`) — it just omits `ts` from the
**live** `tool_request`/`tool_result` owner-channel broadcast
(`:1356-1361,:1387-1388`). Thread the same `ts` into both live broadcasts.

## Change

- `pi-extension/src/index.ts` `tool_execution_start` / `tool_execution_end`
  handlers: include `ts` (the epoch-ms value already computed for
  `_appendTranscriptEvent`) in the `_owners.broadcast({...})` payload for both
  `tool_request` (request variant) and `tool_result` (`result`/`error`
  variants).
- Shared protocol schema source (codegen input under the protocol root's
  `schema/` dir, consumed by `tools/protocol-codegen`): add OPTIONAL `ts`
  (integer, epoch ms) to the `tool_request` and `tool_result` message
  definitions. Optional = backward-compatible (old app ignores; old extension
  → app falls back). Regenerate:
  `corepack pnpm generate:protocol` (extension →
  `src/protocol/generated/protocol.generated.ts`) and the app's protocol
  regenerate step (→ `app/lib/protocol/generated/protocol.g.dart`).

## Acceptance

- [ ] Live `tool_request` and `tool_result` broadcasts carry `ts` equal
  (±tolerance) to the history `_appendTranscriptEvent` `ts` for the same call.
- [ ] Generated TS + Dart wire types include the optional `ts`; the decoder
  treats it as optional (no break for frames without it).
- [ ] `corepack pnpm check:protocol` passes; existing extension tool tests
  updated and green (`corepack pnpm test`).
- [ ] Optional-field backward compat asserted (a `tool_request` without `ts`
  still decodes).

## Ordering

`depends_on: []` — parallel entry point. Unblocks
`story-canonical-transcript-ordering-app-consume-tool-ts`.

## Implementation discovery

The requested all-language regeneration path is not currently capable of
projecting this schema change, so the story returned to `stage: drafting`
without source edits:

- `protocol/scripts/list-types.ts` emits only a type catalog with schema refs.
  The Dart target's catalog normalizer creates every variant with `fields: []`;
  piping that output into `protocol-codegen --target dart` produces empty
  `ToolRequest`/`ToolResult` classes and a 1,607-line destructive diff against
  the 1,547-line committed app projection. The production Dart DTO still comes
  from the separately maintained
  `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`, whose update is
  outside this story's allowed write scope and is not derived by `list-types.ts`.
- The Rust generator intentionally maps `appPiClient` and `appPiServer` to no
  module (`rustModuleForFamily` returns `null`). Consequently
  `relay/src/protocol/generated/` contains no live `ToolRequest` or
  `ToolResult` projection, and regenerating Rust cannot produce the required
  optional `ts` field or the mandated relay generated-file diff.

Observed Dart probe command (output directed only to `/tmp`):

```bash
cd protocol
node --import tsx scripts/list-types.ts > /tmp/outpost-pi-list-types.json
node ../tools/protocol-codegen/bin/protocol-codegen.mjs \
  --target dart \
  --schema /tmp/outpost-pi-list-types.json \
  --out /tmp/outpost-pi-from-list-types.g.dart
```

The design needs either (a) schema-derived Dart field IR plus a Rust app-Pi
projection, or (b) corrected scope/acceptance that explicitly updates the Dart
IR fixture and recognizes that Rust has no app-Pi DTO artifact.

The orchestrator resolved those two blockers: the Dart IR fixture is now in
scope and Rust is intentionally excluded. The implementation and both
regenerations now complete in the working tree, but the mandatory full
extension suite exposes a separate pre-existing async teardown race outside
this story's allowed change:

- `corepack pnpm check:protocol`, `corepack pnpm typecheck`, the generated Dart
  analyzer check, and the focused `tool visibility` tests all pass (8/8).
- `corepack pnpm test` fails after all 55 files and all 963 runnable tests pass
  because Vitest catches an unhandled `ENOENT` from
  `src/session/leader_election.ts:99`: the existing `hot-reload lifecycle
  fence: startup sweeps identities for dead PIDs` test invokes the async
  `session_start` handler without awaiting its leader-election socket startup,
  then removes its temporary `OUTPOST_PI_HOME`; the later listen callback tries
  to `chmod` the deleted socket path. The failure reproduces both in the full
  suite and when running `src/extension.test.ts` alone.

### Resolved by the orchestrator (2026-08-03)

The suite blocker is **pre-existing and unrelated**, confirmed by reproducing
the identical `ENOENT` on `HEAD` with this item's changes stashed (all 962
tests pass; the nonzero exit is the same unhandled hot-reload teardown error).
Per test-integrity, a pre-existing flake is parked, not folded into an item:
see `backlog/backlog-extension-hot-reload-restart-sweep-enoent-race.md`. This
item's own scope is verified green and advances to `done`.

## Implementation notes

- Schema: added optional `ts` (integer, min 0) to the LIVE `toolRequest` and
  `toolResult` in `protocol/schema/app-pi-server.schema.json` (mirrors the
  existing optional-`ts` pattern on `userInput`/`agentMessage`/`compaction`).
- Extension: `tool_execution_start`/`tool_execution_end` now broadcast the same
  `Date.now()` value used for the history `_appendTranscriptEvent` on the
  owner-channel `tool_request`/`tool_result` frames (`pi-extension/src/index.ts`).
  The agent-network mesh tool path (Pi↔Pi, not app-facing) is intentionally
  unchanged.
- TS regen: `corepack pnpm generate:protocol` (from `pi-extension/`).
- Dart regen (the fixture is the dart source-of-truth, maintained in lockstep
  with the schema): edit the LIVE `tool_request`/`tool_result` members in
  `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json` to add optional
  `ts`, then:
  `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json --out app/lib/protocol/generated/protocol.g.dart`
- Rust: no change — app↔pi messages are excluded from the Rust codegen by design.

## Verification

- `corepack pnpm check:protocol` ✅
- `corepack pnpm typecheck` ✅
- Focused tool-visibility tests 8/8 ✅
- Generated Dart `flutter analyze` ✅
- Full extension suite: all 962 tests pass; the single nonzero-exit error is
  the pre-existing hot-reload restart-sweep `ENOENT` race (parked above), not
  this item.
