---
id: idea-pair-code-clipboard-copy
created: 2026-07-30
updated: 2026-07-30
tags: [pi-extension, app, ux]
---

# Pair-code dialog should offer a clipboard-copy action

## Observed (2026-07-30)

Re-pairing via the paste path failed because the `outpostpi://` URI was corrupted
in manual copy-paste: the terminal font rendered `0` (zero) and `O` (capital oh)
ambiguously, and the copied bytes ended up with both swapped in opposite
directions (`epk` `uj0Hdg8=` → `ujoHdg8=`; `room` `83MK6OkhBrcQ` →
`83MK60khBrcQ`). The app sent `pair_request` to a non-existent peer/room, the
relay dropped it ("dest not found"), and the app timed out after 30s.

The `PairingCodeDialog` (`pi-extension/src/extension/command_surface/pairing_coordinator.ts`)
only renders the URI as wrapped text — there is no clipboard-copy action, so the
operator must visually transcribe the URI, which is exactly when base64url
confusables (`0`/`O`, `l`/`1`/`I`) bite.

## Why it matters

The file seam (`OUTPOST_PI_PAIR_CODE_FILE`) works but requires a pi restart with
the env var set — too heavy for routine re-pairing. A clipboard-copy action in the
dialog would make the paste path reliable without a restart.

## Recommended direction

- Add a clipboard-copy action (keybinding or on-screen button) to
  `PairingCodeDialog` that copies the exact `qrUri` string to the system clipboard.
- The pi TUI has access to a clipboard mechanism (or can shell out to
  `pbcopy`/`xclip`/`wl-copy`); wire it as a port so the dialog stays testable.
- Failing a clipboard port, consider a "print to a temp file" action accessible
  mid-session (not just via the startup env var).

## Provenance

Diagnosed during the 2026-07-30 pairing incident chain
(`.work/session-notes/2026-07-30-drain-and-pairing-incident.md`). The narrow-terminal
URI-display fix (`8603635`) and the paste-tolerance fix (`5ff8f2e`) shipped, but
neither eliminates the visual-transcription step.
