---
id: story-pair-code-clipboard-copy
kind: story
stage: done
tags: [pi-extension, app, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-30
updated: 2026-08-27
---

# Pair-code dialog should offer a clipboard-copy action

## Brief

Re-pairing via the paste path requires visually transcribing the
`outpostpi://` URI out of the TUI pair dialog — exactly when base64url
confusables (`0`/`O`, `l`/`1`/`I`) bite. A clipboard-copy action in the
dialog makes the paste path reliable and deletes the manual-transcription
step (the whole confusable failure class) without a pi restart.

## Observed (2026-07-30)

Re-pairing via the paste path failed because the `outpostpi://` URI was
corrupted in manual copy-paste: the terminal font rendered `0` (zero) and
`O` (capital oh) ambiguously, and the copied bytes ended up with both
swapped in opposite directions (`epk` `uj0Hdg8=` → `ujoHdg8=`; `room`
`83MK6OkhBrcQ` → `83MK60khBrcQ`). The app sent `pair_request` to a
non-existent peer/room, the relay dropped it ("dest not found"), and the
app timed out after 30s.

The `PairingCodeDialog`
(`pi-extension/src/extension/command_surface/pairing_coordinator.ts`)
only renders the URI as wrapped text — no clipboard-copy action exists.

## Why it matters

The file seam (`OUTPOST_PI_PAIR_CODE_FILE`) works but requires a pi
restart with the env var set — too heavy for routine re-pairing. A
clipboard-copy action in the dialog makes the paste path reliable without
a restart.

## Work

- Add a clipboard-copy action (keybinding or on-screen button) to
  `PairingCodeDialog` that copies the exact `qrUri` string to the system
  clipboard.
- Wire it as a port so the dialog stays testable. Grounding note
  (2026-08-27): the extension SDK surface exposes no clipboard write API
  (checked `dist/extensions/index.d.ts`) — the port's adapter needs OSC 52
  escape output or a platform-tool shell-out (`pbcopy`/`xclip`/`wl-copy`),
  per the original recommendation. The pi TUI's own `/copy` proves the
  terminal-side mechanism works; reuse the same approach if reachable.
- Failing a clipboard port, consider a "print to a temp file" action
  accessible mid-session (not just via the startup env var).

## Simplification opportunity

Clipboard copy replaces manual transcription entirely — if it lands, the
wrap-for-TUI display concern shrinks to pure display (no need to optimize
the rendering for copyability). Skip the temp-file fallback if the
clipboard port works; do not build both.

## Verification

`corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
from `pi-extension/`; unit-test the port (injected fake clipboard) and the
dialog keybinding wiring.

## Provenance

Diagnosed during the 2026-07-30 pairing incident chain
(`.work/session-notes/2026-07-30-drain-and-pairing-incident.md`). The
narrow-terminal URI-display fix (`8652dcf`) and the paste-tolerance fix
(`0761c91`) shipped, but neither eliminates the visual-transcription
step.

## Implementation notes

- Added the injected `ClipboardPort` and `Osc52Clipboard` adapter in
  `pi-extension/src/extension/command_surface/clipboard.ts`. OSC 52 was chosen
  as the smallest dependency-free strategy: it works through modern local and
  SSH terminals without shelling out to platform-specific clipboard tools.
- Updated `PairingCodeDialog` to show a visible `c` copy hint, copy the exact
  URI through the injected port, refresh the TUI while copying, and show
  success or failure feedback. `PairingCoordinatorDeps.clipboard` keeps the
  port injectable while defaulting production to the OSC 52 adapter.
- Added `clipboard.test.ts` covering exact UTF-8 OSC 52 output and injected
  fake clipboard/keybinding behavior.
- Verification passed from `pi-extension/`: `corepack pnpm typecheck`,
  `corepack pnpm test` (62 files, 1108 passed, 3 skipped), and
  `corepack pnpm build`.
