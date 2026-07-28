---
id: feature-secure-transcript-key-loss-recovery-ux
kind: feature
stage: drafting
tags: [app, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-28
updated: 2026-07-28
---

# Secure-transcript key-loss recovery UX

## Brief
Parked from the `standard`-weight cross-model review of
`feature-secure-transcript-storage` (2026-07-19). `app/lib/main.dart:46`
intentionally fails before `runApp` when the secure-storage-backed Hive key is
missing/malformed/unreadable (the accepted fail-closed design — key loss =
startup error, not a silent plaintext fallback). The gap is the UX: there is
no in-app recovery/discard flow, so backup/restore loss or secure-store
corruption permanently bricks startup until app data is cleared.

This is a design-bearing feature: the recovery surface is a new in-app
affordance, distinct from a silent decryption bypass, and needs a design pass
to define the operator-facing flow and whether re-pairing re-hydrates from the
extension's `audit.jsonl`/session history.

## Simplification opportunity
None — this adds a missing recovery path; it does not remove code. The
fail-closed startup guard is retained as the security boundary.

## Design notes
Route through `feature-design`. The design pass should: (1) design an explicit
in-app recovery flow ("local data unreadable — discard local transcripts and
re-pair?" affordance) that lets an operator intentionally discard unreadable
ciphertext to unbrick startup; (2) confirm the security boundary — the
discard is an explicit operator action, never a silent decryption bypass;
(3) decide whether re-pairing re-hydrates from the extension's
`audit.jsonl`/session history or starts clean. Coordinate with the
`feature-secure-transcript-storage` release (already shipped) — this is the
deferred UX follow-up.

## Children
- `gate-security-secure-transcript-key-loss-recovery-ux` (the finding body
  is the design input; this feature wraps it for a design pass)
