---
id: feature-secure-transcript-key-loss-recovery-ux
kind: feature
stage: implementing
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
- `gate-security-secure-transcript-key-loss-recovery-ux` (single cohesive
  storage/bootstrap/UI checkpoint; `depends_on: []`)

## Design decisions

- **Security boundary**: `LocalBoxes.init()` must still succeed before dependency setup, `SyncService` construction, or the normal app router can run. Only stable key-loss/ciphertext-unreadable `TranscriptStorageKeyException` codes may enter recovery UI; every other startup failure keeps the existing fail-closed behavior.
- **Recovery shape**: Use a blocking full-screen bootstrap recovery state, followed by the app's existing `AlertDialog` destructive confirmation pattern. A dialog alone cannot be shown at the current failure point because no `MaterialApp`/Navigator exists, and the existing `/boot` failure treatment is already a full-screen retry surface.
- **Explicitness**: Retry is non-destructive. Ciphertext deletion starts only after the operator taps `Discard local transcripts`, then confirms `Discard and continue`; cancel/back/dismiss never mutates storage. A persisted discard-intent latch may finish an already-confirmed deletion after a crash, but no key error may create that latch automatically.
- **Discard scope**: Delete only transcript-bearing v3 Hive data (`sessions_index_v3`, every `transcript_events_v3_*` and `msgs_v3_*` box) plus volatile `runtime`; delete/reset only the transcript key and its verifier/provisioning metadata. Retain Owner identity, peer/channel pairings, preferences, mesh watermark, and unrelated secure-storage entries. A full app reset is more irreversible and can alter remote mesh membership, so it is not part of this recovery.
- **Re-pairing and rehydration**: Do not force re-pairing when pairing credentials survived. Reconnect/re-pair uses the normal `session_sync` path, whose source is the Pi SDK's durable current-session history backfilled into the extension transcript projection; `audit.jsonl` is mesh-routing metadata and is not a transcript restore source. Replay is bounded (30 events by default), current-session-only, and cannot restore local-only/pending/older cached history, so the UI must promise permanent local deletion and only say that some current-session history *may* sync again.
- **Restart semantics**: After a confirmed discard, rerun the guarded storage bootstrap in-process, then set up dependencies exactly once and reveal `OutpostPiApp`. Do not require an OS-level restart and do not build a second production router.
- **UI alignment**: No mockup is required for this minor extension of established boot-error and destructive-confirmation compositions. Reuse theme tokens, the `/boot` error-page hierarchy, and the destructive `AlertDialog` pattern; no new navigation topology or shared visual primitive is introduced.
- **Dispatch/review**: Direct reads were sufficient: the startup, storage, pairing, and replay owners are explicit. No Explore agent was needed. Design-time advisory dispatch was skipped because this invocation forbids nested delegation other than unresolved read-only exploration.

## Architectural choice

### Option A — Bootstrap state machine with narrow, crash-resumable discard (chosen)

Run a small root bootstrap surface before the normal app. It attempts the existing guarded storage initialization, renders recovery only for recognized key-loss/ciphertext failures, and exposes retry plus an explicitly confirmed narrow discard. The discard is latched and restart-convergent; only a subsequent successful `LocalBoxes.init()` permits dependency setup and the real app. This optimizes for a visible recovery path without weakening the security boundary.

### Option B — Catch in `main()` and replace the root with a one-off recovery app

`main()` could catch the exception, call `runApp(RecoveryApp)`, and later call `runApp` again after deletion. It is smaller initially, but splits lifecycle ownership across two root apps, makes dependency setup/disposal harder to test, and invites recovery-specific bootstrap drift.

### Option C — Enter the normal router and offer a full local reset

The existing `/boot` screen could own the flow after dependencies are created, or the app could clear all local/secure state. That either opens services before transcript storage is proven safe or destroys unrelated Owner/pairing state and may affect mesh membership. It is too broad and violates the fail-closed boundary.

Option A is the least-irreversible sound design. It adds one guarded pre-app state machine, reuses the existing UI language, and makes an explicit prior confirmation the only authority for destructive convergence.

## Trickiest unit first

The discard primitive is the highest-risk unit. It must delete boxes that may be impossible to open, survive interruption across several Hive files and secure-storage deletion, and never turn a mere initialization exception into implicit data destruction. A plaintext, content-free `transcript_discard_pending_v3` latch is therefore written only by the confirmed action; `LocalBoxes.init()` may converge that latch before reading the missing key, but may never create it in response to a key error.

## Implementation Units

### Unit 1: Explicit, narrow, crash-resumable transcript discard

**Files**:
- `app/lib/data/local/transcript_storage_key.dart`
- `app/lib/data/local/boxes.dart`
- `app/test/data/local/transcript_storage_key_test.dart`
- `app/test/data/local/transcript_storage_recovery_test.dart`

**Story**: `gate-security-secure-transcript-key-loss-recovery-ux`

```dart
abstract interface class TranscriptKeyValueStore {
  Future<String?> read();
  Future<void> write(String encodedKey);
  Future<void> delete();
}

final class TranscriptStorageKeyException implements Exception {
  const TranscriptStorageKeyException(this.code);

  final String code;
  bool get canDiscardUnreadableTranscripts;
}

class LocalBoxes {
  static Future<void> discardUnreadableTranscripts({
    TranscriptKeyValueStore? keyStore,
  });

  @visibleForTesting
  static Future<void> Function(String boxName)?
      afterTranscriptRecoveryBoxDeleteForTesting;
}
```

**Implementation Notes**:
- Classify only `missing_provisioned_key`, `malformed_key`, `key_mismatch`, and `encrypted_box_unreadable` as discard-recoverable. `key_write_not_persisted`, `key_not_initialized`, migration failures, and unknown exceptions do not enter this flow.
- On confirmation, serialize with existing initialization/wipe ownership, close the transcript-open gate, and write `transcript_discard_pending_v3` to the plaintext security metadata box before closing/deleting anything.
- Inventory from the metadata box's Hive directory, not the encrypted index: the index may be the unreadable file. Delete exact common names and only the `transcript_events_v3_`/`msgs_v3_` prefixes; do not guess at legacy or unrelated boxes.
- Close any open target boxes, delete their files, clear/delete volatile `runtime`, delete the transcript secure-storage key, and remove `key_provisioned_v3` plus `key_verifier_v3`. Clear any transient migration copy-verification marker, but retain a completed `migration_version = 3`; if migration was incomplete and readable legacy sources remain, the normal migrator may safely retry under the new key.
- Clear `transcript_discard_pending_v3` last and reset in-memory cipher/initialization state. At the start of production init, converge a pre-existing pending latch before key load. This automatic continuation is authorized by the earlier confirmed action, not by the new startup error.
- Keep Owner-transition recovery markers intact. The later normal boot can converge them against the now-empty transcript namespace without skipping the separate Owner identity boundary.

**Acceptance Criteria**:
- [ ] A provisioned installation with a missing, malformed, mismatched, or unreadable transcript key still throws before any normal service starts and does not delete a file merely by detecting the error.
- [ ] Calling the discard API after confirmation removes the encrypted session index, all indexed and orphan v3 event/projection boxes, and runtime, while retaining pairing, Owner, preference, mesh, and unrelated Hive/secure-storage state.
- [ ] A crash after any per-box deletion leaves the intent latch set; the next `LocalBoxes.init()` completes the same narrow deletion, provisions one fresh key, and opens empty encrypted boxes.
- [ ] Cancel/retry paths never call key deletion or box deletion.
- [ ] Prefix inventory cannot delete legacy plaintext boxes or any non-transcript Hive box.

---

### Unit 2: Pre-app bootstrap security gate

**File**: `app/lib/main.dart`

**Test**: `app/test/main_bootstrap_test.dart`

**Story**: `gate-security-secure-transcript-key-loss-recovery-ux`

```dart
typedef AppBootstrapTask = Future<void> Function();

class OutpostPiBootstrap extends StatefulWidget {
  const OutpostPiBootstrap({
    super.key,
    required this.initializeStorage,
    required this.discardUnreadableTranscripts,
    required this.initializeDependencies,
    required this.appBuilder,
  });

  final AppBootstrapTask initializeStorage;
  final AppBootstrapTask discardUnreadableTranscripts;
  final AppBootstrapTask initializeDependencies;
  final WidgetBuilder appBuilder;
}
```

**Implementation Notes**:
- `main()` initializes Flutter bindings and immediately runs `OutpostPiBootstrap`; the bootstrap first awaits `LocalBoxes.init()`, then `setupDependencies()`, then renders `OutpostPiApp`.
- Catch only a `TranscriptStorageKeyException` whose `canDiscardUnreadableTranscripts` is true. Store it as a recovery-required phase and render the recovery page. Report/rethrow every other failure without rendering the normal app.
- `Retry` reruns initialization without mutation. Confirmed discard awaits `LocalBoxes.discardUnreadableTranscripts()`, then reruns the same initialization path. Use an operation generation/mounted check so stale retry/discard completions cannot reveal the app or call dependency setup twice.
- While loading or discarding, disable both actions. The normal dependency graph and eager `SyncService` construction remain downstream of successful encrypted box open.

**Acceptance Criteria**:
- [ ] A recoverable key error renders recovery while `setupDependencies`, `SyncService`, router construction, and `OutpostPiApp` remain unreachable.
- [ ] Retry can recover a transient secure-store read without deleting data; repeated failed retries remain on the blocking surface.
- [ ] A confirmed successful discard reruns storage initialization, initializes dependencies exactly once, and replaces the bootstrap surface with the normal app.
- [ ] Non-key, non-discardable, migration, and discard failures never fall through to the normal app.
- [ ] Disposing/replacing the bootstrap during an async operation prevents stale completion from mutating UI or starting services.

---

### Unit 3: Honest recovery surface and destructive confirmation

**File**: `app/lib/ui/storage_recovery/transcript_storage_recovery_page.dart`

**Test**: `app/test/ui/storage_recovery/transcript_storage_recovery_page_test.dart`

**Story**: `gate-security-secure-transcript-key-loss-recovery-ux`

```dart
class TranscriptStorageRecoveryPage extends StatefulWidget {
  const TranscriptStorageRecoveryPage({
    super.key,
    required this.onRetry,
    required this.onDiscard,
  });

  final Future<void> Function() onRetry;
  final Future<void> Function() onDiscard;
}
```

**Implementation Notes**:
- Mirror `_BootSplash`: centered error icon, short title/body, retry action, and theme-token typography/colors. This is a pre-DI root widget; it receives callbacks and never imports `LocalBoxes`, pairing storage, or the router.
- Copy must say: the local encryption key is unavailable; Outpost-Pi will not open the ciphertext without it; discard permanently removes transcripts stored on this device; some current Pi-session history may sync after reconnect, but older/local-only history may not return; pairing may be required only if those credentials were also lost.
- `Discard local transcripts` opens a themed `AlertDialog` with `Cancel` and error-colored `Discard and continue`. Use `barrierDismissible: false` so every exit is an explicit button choice.
- Await callbacks and guard `mounted` before changing busy/error state. A discard failure remains blocking and shows safe inline copy without raw exception codes, keys, paths, or transcript data.

**Acceptance Criteria**:
- [ ] The page never claims that `audit.jsonl`, re-pairing, or session sync is a backup or guarantees restoration.
- [ ] Retry is visually non-destructive and does not open the confirmation dialog.
- [ ] Tapping discard alone does nothing; cancel does nothing; only `Discard and continue` invokes `onDiscard` once.
- [ ] Actions are disabled while an operation is pending, double taps cannot start concurrent discards, and failures remain on the blocking page.
- [ ] No raw key error, file path, ciphertext, or transcript content is rendered or logged.

## Implementation Order

1. Extend the transcript key adapter and land the latched, narrowly scoped discard primitive with file-backed restart tests.
2. Introduce `OutpostPiBootstrap` so successful encrypted initialization remains the sole gate to dependency setup.
3. Add the recovery page/confirmation and wire retry/discard back into the same bootstrap path.
4. Run focused storage/bootstrap/widget tests, then `flutter analyze` and `flutter test --exclude-tags e2e` from `app/`.

The existing child story remains one checkpoint because the storage action, security gate, and UI confirmation form one inseparable acceptance boundary. Splitting them would add substrate overhead without creating safe independently shippable behavior.

## Simplification

- Reuse the existing `LocalBoxes` facade, plaintext security metadata box, boot-error hierarchy, theme tokens, and destructive `AlertDialog` vocabulary; do not create a second storage repository, router, or full-app reset service.
- Centralize recoverable key-error classification on `TranscriptStorageKeyException` so `main.dart`, copy, and tests do not hand-enumerate codes.
- Keep the live v3 accessors and cipher contract unchanged. Recovery deletes the unreadable generation and returns through the same `LocalBoxes.init()` path; there is no plaintext fallback, alternate reader, dual-write path, or permanent compatibility mode.
- No source or test removal is justified. Existing fail-closed key lifecycle and Owner-transition wipe tests remain evidence and gain recovery-specific cases.

## Testing

- **Storage interface/regression tests**: Use real temporary file-backed Hive boxes plus an in-memory key store to prove detection alone is non-destructive; explicit discard deletes only v3 transcript data; retained unrelated state survives; and an injected mid-delete crash converges from the persisted latch on restart. This protects the destructive boundary and scope.
- **Bootstrap widget tests**: Inject storage/dependency callbacks and a ready sentinel widget. Prove recoverable failure blocks the sentinel and dependency callback, retry is non-destructive, confirmed discard reaches ready only after a second successful guarded init, and repeated/stale completions cannot set ready twice. This is the no-silent-bypass test.
- **Recovery widget tests**: Drive retry, discard, cancel, confirmation, pending, and failure states. Assert honest loss/partial-replay copy and one destructive callback invocation.
- **Retain existing tests**: `transcript_storage_key_test.dart` continues to pin first-key provisioning and missing/malformed fail-closed behavior; owner-transition wipe and router boot-retry tests continue to prove their separate recovery boundary.
- No E2E protocol change is introduced. A manual smoke should simulate lost transcript key on a paired install, verify the recovery surface, cancel/relaunch without deletion, then confirm discard and observe either retained-pair reconnect plus bounded current-session sync or the existing pairing flow when credentials are absent.

## Risks

- **Silent bypass regression**: Moving `runApp` earlier could be mistaken for making storage optional. Mitigation: the bootstrap may render only loading/recovery; dependency setup and the real app remain structurally downstream of successful `LocalBoxes.init()`, with a test sentinel proving it.
- **Implicit destruction after restart**: A pending latch auto-converges. This is safe only because error detection never writes it; the confirmation handler writes it before deletion, and tests distinguish those paths.
- **Overbroad deletion**: Directory scans can become a full app-data wipe. Limit matching to exact common names and v3 transcript prefixes, and prove unrelated Hive/secure-storage entries survive.
- **Interrupted multi-file deletion**: Hive has no transaction across boxes and secure storage. The intent latch, gated opens, idempotent close/delete steps, and last-write latch clear are the fallback.
- **False restoration expectations**: The extension's mesh `audit.jsonl` is not transcript history. SDK-backed `session_history` is current-session and bounded (30 events by default), so older/local-only/pending content can be permanently lost. Copy and tests must preserve the word “may,” never “restore.”
- **Broader secure-store loss**: The same platform incident may also remove pair/channel credentials. The narrow recovery retains them when present and falls naturally into existing pairing UX when absent; it does not promise reconnection or mutate mesh membership.
- **Misclassified startup failures**: Treating migration or secure-store write failures as key loss could destroy salvageable data without solving startup. Only the four enumerated unreadable-key/ciphertext codes expose discard; all others remain fail-closed.

## Open questions

None block implementation. The two commissioning questions are resolved by the current contracts and least-irreversible default:

- **Rehydration**: normal reconnect/re-pair may replay only the Pi SDK-backed current-session `session_history`; mesh `audit.jsonl` cannot restore transcripts, and bounded replay is not a backup.
- **Discard scope**: delete only unreadable transcript-bearing v3 storage and its key metadata; do not offer or perform a full local identity/pairing reset in this feature.

If the operator later wants a separate “reset this device and mesh identity” affordance, it should be scoped as its own security-sensitive product flow rather than silently expanding this recovery action.
