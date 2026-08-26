---
id: feature-fresh-session-shutdown-and-recoverable-delivery-retry-contract
kind: story
stage: done
tags: [pi-extension, app]
parent: feature-fresh-session-shutdown-and-recoverable-delivery
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Define the recoverable owner-delivery wire signal

## Checkpoint

Add one schema-owned `delivery_retry` error code for a `user_message` that the
extension has fenced out before Pi SDK delivery. Its `in_reply_to` is the
original stable client message id. Keep `delivery_pending` distinct: it means
the current extension retained the message for local replay, while
`delivery_retry` means the sender remains responsible and must retry after a
fresh authoritative room/session signal.

The error union remains open, so this is additive on the wire; the complete
no-loss behavior nevertheless requires the app and extension portions of the
parent feature to deploy together. The relay remains opaque and unchanged.

## Files

- `protocol/schema/defs/app-pi-common.schema.json`
- `protocol/fixtures/app-pi/server-messages.jsonl`
- `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`
- generated projections:
  `pi-extension/src/protocol/generated/protocol.generated.ts` and
  `app/lib/protocol/generated/protocol.g.dart`
- protocol fixture/codegen tests under `pi-extension/src/protocol/` and
  `app/test/protocol_test.dart`
- current-truth contract prose in `PROTOCOL.md`, `docs/SPEC.md`,
  `docs/ARCHITECTURE.md`, and the paired-deploy list in `AGENTS.md`

## Acceptance evidence

- [x] The canonical schema and both generated endpoint projections name
      `delivery_retry`; no handwritten competing wire enum is added.
- [x] A fixture proves `{type:"error", code:"delivery_retry", in_reply_to:<id>,
      session_id:<old-session>}` decodes in TypeScript and Dart.
- [x] Contract prose distinguishes extension-local `delivery_pending` from
      sender-owned `delivery_retry` and states that retry reuses the original id.
- [x] `corepack pnpm --dir protocol check`, extension protocol generation/check,
      and focused Dart protocol tests pass.

## Ordering

Foundation checkpoint; no sibling dependency.

## Implementation notes

- Execution: inline host worker (`openai-codex/gpt-5.6-sol`, xhigh), required
  because this harness exposes no subagent adapter. Effective feature review
  weight remains `standard` from the caller/default.
- Dependency/order: completed first as the graph root. The drain and durable
  resend checkpoints became implementation-ready together; this single worker
  will take drain then resend for coherent cross-component ownership without
  changing their dependency relation.
- Added `delivery_retry` to the canonical schema and maintained Dart IR, then
  regenerated both committed endpoint projections. No generated file was
  hand-edited. The open `error.code` string remains forward-compatible.
- Added one canonical fixture and direct TS/Dart decode assertions, including
  explicit unknown-code compatibility coverage. Updated current-state protocol,
  specification, architecture, and paired-deploy documentation; the relay
  remains unchanged and the guarantee is explicitly at-least-once.
- Verification: `corepack pnpm --dir protocol check` passed (5 fixture
  families; 7 codegen tests); extension `check:protocol` and focused
  `src/protocol/codec.test.ts` passed (98 tests); Flutter focused
  `test/protocol_test.dart` passed (42 tests); `git diff --check` passed.
