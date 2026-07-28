---
id: gate-security-secure-transcript-key-loss-recovery-ux
kind: story
stage: drafting
tags: [app, security]
parent: feature-secure-transcript-key-loss-recovery-ux
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-19
updated: 2026-07-28
---

# No recovery path after secure-storage key loss (fail-closed bricks startup)

## Source

Parked from the `standard`-weight cross-model review of
`feature-secure-transcript-storage` (2026-07-19). Lower-risk finding — consistent
with the accepted fail-closed design, not a blocker.

## Finding

`app/lib/main.dart:46`: startup intentionally fails before `runApp` when the
secure-storage-backed Hive key is missing/malformed/unreadable, leaving users no
in-app option to explicitly discard unreadable local ciphertext and recover.
Backup/restore loss or secure-store corruption can permanently brick startup
until app data is cleared.

## Risk rationale (why parked, not fixed this cycle)

This is consistent with the feature's accepted fail-closed design (key loss =
startup error, not silent plaintext fallback). The feature's scope was
collision-safe + encrypted storage + safe migration, not recovery UX. Bricking
on key loss is the security-correct posture (no silent decryption bypass); the
gap is the UX (no in-app recovery/discard flow), which is a separate design
surface.

## Recommended direction

Design an explicit in-app recovery flow (e.g. a "local data unreadable — discard
local transcripts and re-pair?" affordance) that lets an operator intentionally
discard unreadable ciphertext to unbrick startup, distinct from a silent
decryption bypass. Consider whether re-pairing re-hydrates from the extension's
`audit.jsonl`/session history.
