---
id: gate-tests-pairing-qr-rpc-mode-no-seam-untested
kind: story
stage: done
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: tests
created: 2026-07-24
updated: 2026-08-11
---

# showPairQr in non-TUI mode without the seam is untested

Priority: Medium (parked per gate_finding_routing).
`gate-security-pairing-token-in-model-context` made QR display TUI-only with
`OUTPOST_PI_PAIR_CODE_FILE` as the sole headless exception. Tests cover TUI
mode and RPC mode with the seam enabled, but not RPC/non-TUI mode without
it: assert a token-free warning, no token issuance, no `ui.custom`, no
`sendPiMessage`, and no file output. Location:
`pi-extension/src/extension/command_surface/pairing_coordinator.test.ts`.
Affinity: same file as the bound
`gate-tests-pairing-token-context-regression-representation-blind` item.

## Implementation notes

- Added the RPC/non-TUI/no-seam regression: it asserts warning-only behavior,
  no token issuance, no custom UI, and no model-context message.
- Changed `pi-extension/src/extension/command_surface/pairing_coordinator.test.ts`.
- Verified with `vitest run src/extension/command_surface/pairing_coordinator.test.ts`
  (4 tests) and `tsc --noEmit`.
