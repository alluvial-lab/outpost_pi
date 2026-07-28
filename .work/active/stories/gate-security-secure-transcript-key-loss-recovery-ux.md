---
id: gate-security-secure-transcript-key-loss-recovery-ux
kind: story
stage: implementing
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

## Checkpoint

Land the secure-transcript recovery boundary as one cohesive checkpoint:

1. A recoverable transcript key/cipher failure blocks normal bootstrap and exposes only retry plus an explicitly confirmed local-transcript discard.
2. The discard is narrow, latched before deletion, restart-convergent, and deletes only encrypted v3 transcript/index/projection data, volatile runtime, and transcript-key verifier/provisioning state.
3. The normal app, dependency graph, and eager `SyncService` remain unreachable until a fresh `LocalBoxes.init()` succeeds after retry or confirmed discard.
4. The recovery screen and confirmation use established boot-error/theme/dialog patterns and describe data loss honestly.

The feature body owns the complete signatures and file-level design. This story remains a single checkpoint because the delete primitive, bootstrap gate, and confirmation UI are not independently safe or shippable.

## Ordering

`depends_on: []`. This is the feature's only child. Implement storage discard first, then bootstrap integration, then UI wiring inside the same feature-owned delivery.

Cycle check: `.work/bin/work-view --blocking gate-security-secure-transcript-key-loss-recovery-ux` reported no blockers before the empty dependency list was retained.

## Acceptance evidence

- Detection alone is non-destructive: missing/malformed/mismatched key or unreadable ciphertext still fails before dependency setup, with every v3 file intact until confirmation.
- Retry performs no deletion and can recover a transient secure-store read.
- The destructive callback is invoked only after `Discard local transcripts` and `Discard and continue`; cancel/dismiss/back never invokes it.
- A confirmed discard removes `sessions_index_v3`, every `transcript_events_v3_*`/`msgs_v3_*` file (including orphans), runtime, and transcript-key verifier/provisioning state while retaining Owner identity, pair/channel records, preferences, mesh state, unrelated secure-storage keys, and unrelated Hive boxes.
- An injected crash after partial deletion leaves `transcript_discard_pending_v3`; the next storage init completes deletion, provisions one fresh key, opens empty encrypted storage, and clears the latch last.
- `setupDependencies`, `SyncService`, router construction, and the ready app sentinel remain blocked until guarded storage initialization succeeds; non-discardable exceptions never enter the recovery/ready path.
- UI copy states that local deletion is permanent, that some current Pi-session history may sync after reconnect, that older/local-only history may not return, and that pairing is required only if its separate credentials were also lost.
- Tests establish that `audit.jsonl` is never presented as a restoration source. The actual replay source remains the extension's bounded Pi SDK-backed `session_history` projection.

## Verification plan

From `app/`:

```bash
flutter test test/data/local/transcript_storage_key_test.dart \
  test/data/local/transcript_storage_recovery_test.dart \
  test/main_bootstrap_test.dart \
  test/ui/storage_recovery/transcript_storage_recovery_page_test.dart
flutter analyze
flutter test --exclude-tags e2e
```

Manual smoke: on a paired test install, remove/corrupt only the transcript key, confirm the blocking surface, cancel/relaunch to prove no deletion, then confirm discard and verify either retained-pair reconnect plus bounded current-session sync or the existing pairing flow when peer credentials are absent.
