---
source_handle: outpost-pi-pairing-command-handler
fetched: 2026-08-26
source_path: pi-extension/src/extension/command_surface/pairing_coordinator.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi pairing command context and mode gate

Paraphrased summary: Pairing uses base UI/cwd/mode capabilities, but QR issuance/display is rejected outside TUI unless the private pair-code-file seam is configured.

## Key passages

- Lines 17-18 define `PairingUiContext` from base `ExtensionContext` UI/cwd plus optional mode.
- Lines 216-220 reject non-TUI pairing when `OUTPOST_PI_PAIR_CODE_FILE` is absent.
- Lines 262-272 publish through the pair-code file when configured and return before display in non-TUI mode.
- Lines 272-280 restrict QR custom rendering to TUI and reacquire live UI after async work.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Relevant method: `PairingCoordinator.showPairQr`
