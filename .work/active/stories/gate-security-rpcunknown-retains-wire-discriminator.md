---
id: gate-security-rpcunknown-retains-wire-discriminator
kind: story
stage: done
tags: [cockpit, security]
parent: feature-diagnostic-privacy-hardening
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-19
updated: 2026-07-23
---

# RpcUnknown retains arbitrary wire discriminator text

## Source

Parked from the `standard`-weight cross-model review of
`feature-redact-secrets-from-diagnostic-surfaces` (2026-07-19). Lower-risk
finding — not a present diagnostic exposure.

## Finding

`cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart` (lines ~79, 162,
234, 276) retains arbitrary `type`/`customType`/`method`/nested event types in
`RpcUnknown.type`, despite the redaction feature's documentation saying raw wire
content is not retained. `AgentSession` currently ignores these events, so this
is NOT a present diagnostic exposure — no log/transcript surface consumes
`RpcUnknown.type` today.

## Risk rationale (why parked, not fixed this cycle)

No present consumer logs or displays `RpcUnknown.type`; the redaction feature's
scope was the three named diagnostic surfaces (outbound previews, raw RPC logs,
raw stderr). Replacing arbitrary values with fixed unknown categories is a
defensive hardening of a non-exposed surface. A future consumer that logs or
displays the supposedly safe category would create the exposure.

## Recommended direction

When adopting: replace arbitrary `RpcUnknown.type`/`customType`/`method` with
fixed unknown categories (e.g. `unknown_event`, `unknown_method`) at the mapper
boundary, preserving the routing fact without the raw discriminator string.

## Implementation notes

- Replaced the four arbitrary wire discriminator projections with the fixed
  `<unknown-frame>`, `<unknown-custom-message>`, `<unknown-ui-request>`, and
  `<unknown-message-update>` categories.
- Added a mapper canary covering secret-shaped top-level type, custom type, UI
  method, and message-update type values.
- Verification: `flutter test` passed (259 tests). `flutter analyze` reports
  one pre-existing unrelated info in
  `lib/app/cockpit/data/rpc/pi_rpc_process.dart:470`
  (`unnecessary_underscores`); no analyzer findings touch this checkpoint.
