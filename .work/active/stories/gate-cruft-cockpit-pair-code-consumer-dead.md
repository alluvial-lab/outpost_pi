---
id: gate-cruft-cockpit-pair-code-consumer-dead
kind: story
stage: done
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

## Implementation notes

- Cockpit now creates a private temporary directory for each pairing attempt,
  passes its seam-file path to the ephemeral Pi process, and polls the atomic
  JSON payload into `PairCodeReady`.
- Only the token-free `outpost-pi:paired` RPC custom event remains consumed;
  the stale pair-code RPC mapping was removed.
- Cleanup cancels polling/timeouts, disposes the process, and deletes the
  Cockpit-owned seam directory. Targeted tests cover code discovery, boot
  timeout, and cleanup deletion.
- Verification: `flutter test test/core/data/relay/pairing_gateway_impl_test.dart`
  (3 passing).

## Review

Bounded inline review (orchestrator, 2026-07-24): three commit groups
inspected. Cockpit now retrieves the pair code via a private 0700-dir seam
file passed through OUTPOST_PI_PAIR_CODE_FILE (polling + boot-timeout +
cleanup deletion; token-free `outpost-pi:paired` consumer retained). Seam
hardened: exclusive-create 0600 temp, fsync, symlink/pre-existing-target
rejection, atomic rename — the parked low security item closed in-commit.
Producer-less `outpost-pi:pair-code` variant dropped from the cockpit-control
schema + fixture + regenerated output. Orchestrator-verified: cockpit analyze
clean + 264 tests green, extension typecheck green (worker: 931 tests,
protocol check green). Approved -> done.
