---
id: gate-cruft-qr-terminal-rotation-dead-path
kind: story
stage: review
tags: [cleanup, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-24
updated: 2026-07-28
---

# Unreachable legacy QR terminal rotation path remains in the extension

## Source
gate-cruft scan for v0.3.0 (2026-07-24). Medium confidence → parked per
gate_finding_routing.

## Confidence
Medium (pattern-matched)

## Category
dead function

## Location
`pi-extension/src/pairing/qr.ts:140`

## Evidence
```ts
export function displayQR(uri: string): void {
  const qrcode = renderQRAscii(uri);
  process.stderr.write(`\n📱 Scan to pair:\n\n${qrcode}\n`);
}

export function startQRRotation(
  longtermEdPk: Uint8Array,
  sessionName: string,
  roomId?: string,
): () => void {
```
Repository callers use `renderQRAscii` through `PairingCoordinator`;
`displayQR` is only called by `startQRRotation`, and `startQRRotation` has no
callers. The direct-run branch in `index.ts:2919` invokes
`runStandaloneOutpostPiCli`, not this rotation path.

## Removal
Remove `displayQR` and `startQRRotation`, update the stale "standalone CLI
mode" comment, and remove test mocks for `displayQR` that no longer serve a
production dependency.

## Implementation notes

- Removed unreachable terminal-writing and rotating-QR exports, plus the stale
  `displayQR` mock.
- Changed `pi-extension/src/pairing/qr.ts` and
  `pi-extension/src/extension.test.ts`.
- Verified with `vitest run src/extension.test.ts` (200 tests) and
  `tsc --noEmit`.
