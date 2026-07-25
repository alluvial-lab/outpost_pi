---
id: gate-docs-pi-extension-readme-tui-only-pair
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Pi-extension README still says the pairing QR is printed in the terminal

## Drift category
readme-staleness

## Location
- Doc: `pi-extension/README.md:227`
- Contradicting source: `pi-extension/src/extension/command_surface/pairing_coordinator.ts:134-137,176-200`

## Current doc text
> A QR code is printed in the terminal.

## Contradiction
Pairing QR rendering is now a TUI-only custom dialog. Non-TUI invocation
warns and does not display a QR; the only headless path is the E2E-only
`OUTPOST_PI_PAIR_CODE_FILE` seam.

## Required edit
State that `/outpost-pi pair` shows the QR/pairing URI in an interactive TUI
dialog only; describe non-TUI behavior and the E2E-only file seam if
operationally relevant.
