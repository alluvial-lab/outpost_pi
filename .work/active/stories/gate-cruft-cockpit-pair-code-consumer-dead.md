---
id: gate-cruft-cockpit-pair-code-consumer-dead
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: cockpit-v0.3.0
gate_origin: cruft
created: 2026-07-24
updated: 2026-07-24
---

# Cockpit pairing gateway waits for the removed pair-code custom message

## Confidence
High (whole-repo grep + manual source trace, drain-delta re-scan 2026-07-24)

## Category
dead branch — **and a live feature break**

## Location
`cockpit/lib/app/core/data/relay/pairing_gateway_impl.dart:94`

## Evidence
The drain's `gate-security-pairing-token-in-model-context` removed the sole
extension `sendMessage` producer of `outpost-pi:pair-code` (QR now renders
TUI-only). Whole-repo grep finds no remaining producer; the new e2e asserts
the message's absence. Cockpit still waits for and parses it, so Cockpit's
pairing QR flow can only time out. Bound to cockpit-v0.3.0 (not repo
v0.3.0): the breaking change ships in the extension, but the fix belongs to
the paired cockpit release — cockpit 0.2.0's pairing display is broken
against extension 0.3.0 in the meantime. **Operator: re-route to repo
v0.3.0 if you want this blocking the repo tag.**

## Removal
Remove the obsolete `outpost-pi:pair-code` protocol variant and Cockpit
parsing/UI path, OR replace Cockpit pairing with a token-safe transport
(e.g. control-channel QR retrieval that never enters model context) before
retaining that UI. Decide per cockpit-v0.3.0 scope.
