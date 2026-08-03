---
id: story-canonical-transcript-ordering-extension-broadcast-tool-ts
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: feature-canonical-transcript-ordering
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
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
