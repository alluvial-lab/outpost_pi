---
id: feature-owner-identity-transition
kind: feature
stage: done
tags: [security, app, pi-extension]
parent: null
depends_on: [feature-owner-message-e2e-authentication]
release_binding: null
gate_origin: security
created: 2026-07-23
updated: 2026-07-23
---

# Owner-identity transition boundary

## Brief

Two findings define the same security boundary — what happens when the owner
key changes (rotation, reset, or device replacement):

1. `app-owner-key-version-rollback-hardening` — after owner-key changes,
   older valid signed blobs may be reaccepted (no durable version watermark).
2. `gate-security-owner-reset-retains-transcripts` — owner-key replacement
   leaves the previous owner's transcripts readable (no namespace/wipe).

The design pass should decide as one contract: a durable mesh-version/owner
watermark (reject blobs signed before the latest transition), transcript
namespacing or wipe on owner change, and the recovery UX when a legitimate
owner loses key access. Deciding them separately risks two half-policies that
contradict at the boundary.

Depends on `feature-owner-message-e2e-authentication`: that feature's
per-pairing/session key derivation determines what owner rotation must
invalidate, so sequencing avoids re-deciding rotation semantics twice. The
two features together form the v0.3.0 owner-channel security arc.

## Simplification opportunity

A single owner-transition event with well-defined invalidation semantics
(keys, transcripts, cached memberships) replaces per-surface ad-hoc reset
handling.

## Origin

Groom 2026-07-23, cluster F7 — promoted per advisor-review recommendation
that it pairs with the owner-channel E2E authentication feature.

## Design decisions

- **Transcript policy on confirmed owner-key replacement**: **WIPE** —
  operator-confirmed 2026-07-23 (Option A). Delete every transcript-bearing
  box (sessions index, all event logs, all message projections, runtime
  snapshots) so zero previous-owner residue remains on-device. Namespacing by
  owner-pk hash rejected: it forces `LocalBoxes.init` reordering after owner
  boot, a migration of every existing install's encrypted boxes, runtime
  re-init of a static facade — and still leaves ciphertext residue.
- **Data-loss policy (explicit)**: a genuine owner-key transition destroys the
  previous identity's LOCAL transcripts irrecoverably. Pi-side session history
  is unaffected; the new identity re-pairs and syncs fresh. Same-owner device
  replacement (platform sync restores the SAME key) is not a transition and
  loses nothing. A→B→A churn loses A's local transcripts — accepted.
- **Recovery UX**: no new UI. Owner-key loss recovery remains the existing
  re-pair flow; channel keys are already wiped by `PairingStorage.wipeAll`
  (`_kChannelsService:` prefix) on transition.
- **Transcript key NOT rotated**: the app-global AES key stays; the ciphertext
  it protected is deleted, so rotation adds re-provisioning complexity with no
  gain against this finding's adversary (app-level projection by the
  replacement owner). Metadata box (`key_verifier_v3`, migration state) kept.
- **Mesh rollback finding CONFIRMED, not low-confidence**: grounding shows
  `_lastVersion` is in-memory only (cold start ⇒ `since=null` full fetch) and
  `_applyVerified` performs NO version-monotonicity check — an untrusted relay
  can serve any historical validly-signed blob (rollback reintroducing a
  revoked peer). The relay is untrusted by design; signed blobs exist for
  exactly this. A durable per-owner highest-version watermark is adopted.
- **Watermark scoped per owner-pk hash, never wiped**: stored under a distinct
  secure-storage prefix that `wipeAll` does not touch, so owner-key change
  starts the NEW identity at 0 automatically while a RETURNING identity
  (A→B→A) keeps its high-water mark. Wiping watermarks on transition would
  re-open the rollback window.
- **Fail-closed watermark**: if the durable watermark cannot be read, pulls do
  not apply and publishes fail — consistent with the project's fail-closed
  posture; a storage failure must not silently reopen the rollback window.
- **No wire/protocol/relay/extension change**: blob shape, schema, relay
  endpoints, and pairing are untouched. Not a paired wire change; ships with
  v0.3.0 without cutover ordering.

## Architectural choice

### Options considered (transcripts)

1. **Namespace key + boxes by owner-pk hash** — non-destructive; rejected per
   the operator decision above (complexity + residue).
2. **Wipe on confirmed transition (chosen)** — one facade API that closes and
   deletes all transcript-bearing boxes and reopens fresh common boxes, called
   from the existing router `onReset` path (already disconnects and reboots
   the router generation on transition).
3. **Rotate key only** — leaves orphaned ciphertext boxes readable via derived
   names; does not meet the finding.

### Options considered (mesh watermark)

1. **Rely on relay 409 conflict self-healing (status quo)** — publish conflicts
   rebase correctly, but the APPLY path remains rollback-exposed on every cold
   start; rejected.
2. **Durable per-owner high-water mark (chosen)** — persist
   `mesh_high_watermark_v1:<ownerPkHash>` in FlutterSecureStorage; enforce
   monotonicity on apply and floor the publish version; in-memory
   `_lastVersion` stays as the session fetch hint.
3. **Persist `_lastVersion` as-is per owner** — conflates fetch hint with
   security invariant; a regressed write would lower protection. A
   highest-ever mark can only move forward.

## Implementation Units

### Unit 1: Durable per-owner mesh version watermark (trickiest — fail-closed + monotonicity)

**Files**:
- `app/lib/pairing/storage.dart`
- `app/lib/data/mesh/mesh_sync_service.dart`
- `app/test/data/mesh/mesh_sync_service_test.dart` (existing home)
- `app/test/pairing/storage_test.dart` (existing home, if present)

**Story**: `app-owner-key-version-rollback-hardening`

```dart
// PairingStorage — distinct prefix; wipeAll must NOT match it.
const _kMeshWatermarkService = 'dev.outpostpi.meshwatermark';

/// Highest relay mesh version ever verified for [ownerPkHash]; 0 when none.
/// Throws on storage failure (fail-closed: callers must not proceed on a
/// guess).
Future<int> loadMeshHighWatermark(String ownerPkHash);

/// Persist a new high-water mark. Callers only ever move it forward.
Future<void> saveMeshHighWatermark(String ownerPkHash, int version);
```

**Implementation Notes**:
- `MeshSyncService` gains an `_highWatermark` (int, starts 0) + `_watermarkLoaded`
  guard, loaded lazily once per owner hash inside the pk-known paths
  (`_pullOnDemand`, `_publishOnce`) before fetch/publish. Load failure ⇒ pull
  returns false / publish returns `MeshPublishFailure('watermark_unavailable')`.
- Apply path (`_applyVerified`, after signature + owner-pk verification):
  reject `blob.version < _highWatermark` (return false + a fixed-category
  diagnostic, e.g. lifecycleFailure reason `mesh_rollback_rejected`).
  `blob.version == _highWatermark` is an idempotent re-apply — allowed.
- On successful apply: if `v > _highWatermark`, set + persist.
- Publish: `nextVersion = max(_lastVersion, _highWatermark) + 1`; on
  `MeshPublishOk` set + persist. This also removes the cold-start
  publish-at-v1 conflict round-trip.
- `resetVersionWatermark()` keeps clearing only the in-memory `_lastVersion`
  (session fetch hint). The durable mark is per-owner and survives transitions.
- First boot after upgrade has mark 0: one unavoidable acceptance window of
  the relay's current version — recorded in Risks.

**Acceptance Criteria**:
- [ ] Rollback canary: relay serves a validly-signed blob with version LOWER
  than the persisted mark → not applied, local cache unchanged, fixed
  diagnostic emitted.
- [ ] Monotonic forward motion: apply/publish at v=N persists N; a later cold
  start (fresh service, same storage) still rejects v<N.
- [ ] Owner scoping: a different owner hash sees mark 0; `wipeAll()` does not
  delete watermark entries.
- [ ] Fail-closed: storage read failure ⇒ no apply, no publish.
- [ ] Revoke-last-peer (`allowEmpty`) publish still succeeds and advances the
  mark.

---

### Unit 2: Wipe transcripts on confirmed owner-key replacement

**Files**:
- `app/lib/data/local/boxes.dart`
- `app/lib/routing/app_router.dart` (hook into the existing `onReset`)
- `app/test/data/local/boxes_test.dart` (existing home, if present — else new)
- wiring regression in the existing owner-reset test home (search
  `app/test/` for `startWatching` / `resetVersionWatermark` coverage)

**Story**: `gate-security-owner-reset-retains-transcripts`

```dart
/// Wipe every transcript-bearing box for a CONFIRMED owner-key replacement:
/// the sessions index, all `transcript_events_v3_*` event logs, all
/// `msgs_v3_*` projections, and the volatile runtime box. Keeps the
/// app-global key and the security-metadata box (verifier, migration state).
/// Reopens fresh common boxes so the subsequent router reboot boots onto
/// empty storage. The previous identity's ciphertext leaves the device.
static Future<void> wipeTranscriptsForOwnerTransition()
```

**Implementation Notes**:
- Enumerate deletion set TWO ways: (a) derive `eventsName`/`messagesName`
  from every `SessionIndexRecord` in the sessions index; (b) backstop-scan
  `Directory(Hive.homePath)` for `transcript_events_v3_*.hive` /
  `msgs_v3_*.hive` files so orphan boxes (no index record) are also caught.
- Close any open box before `Hive.deleteBoxFromDisk(name)`; close + clear +
  reopen `_kSessionsIndex` and `_kRuntime` via `_openCommon()`.
- Call site: `app_router.dart` `onReset`, AFTER `conn.disconnect()` (old
  generation can no longer write) and BEFORE `boot.load(...)`, adjacent to
  `meshSync.resetVersionWatermark()`. Late zombie writes are already dropped
  by lifecycle-generation guards; a write racing a closed box throws inside
  the old generation and is discarded.
- No key rotation, no metadata wipe (decision above).

**Acceptance Criteria**:
- [ ] Replacement-owner regression: seed index + event + projection rows under
  identity A, run the transition path, boot identity B paired to the SAME
  peer/room/session tuple — derived box names are identical but storage is
  EMPTY; no A row can be projected.
- [ ] Orphan backstop: an events box with no index record is also deleted.
- [ ] The key verifier, provisioning flag, and migration metadata survive;
  storage remains fully usable for B (write + read round-trip).
- [ ] Same-owner re-watch (identical pk) triggers no wipe (bridge already
  drops same-pk events — wiring test must prove the wipe is not reachable
  from that path).

## Implementation Order

1. `app-owner-key-version-rollback-hardening` — self-contained watermark
   (storage + mesh service).
2. `gate-security-owner-reset-retains-transcripts` — lifecycle-sensitive wipe
   (facade + router wiring).

Both child stories stay `depends_on: []` — different files, no ordering
constraint; one feature worker carries them sequentially. No new stories.

## Simplification

- No namespace/migration machinery: deletion replaces a whole box-renaming
  subsystem.
- No key rotation: deletes the ciphertext instead of re-keying.
- Watermark reuses `PairingStorage`'s existing secure-storage ownership rather
  than a new store class.

## Testing

- **Mesh rollback canary** (Unit 1): the security core of this feature —
  proves an untrusted relay cannot roll membership back.
- **Replacement-owner regression** (Unit 2): proves the finding's exact attack
  (same tuple ⇒ same box names ⇒ empty storage) is closed.
- **Fail-closed + scoping tests** (Unit 1): storage failure and per-owner
  isolation.
- **Orphan backstop + metadata survival** (Unit 2).
- No UI tests; no wire/schema tests (unchanged).

## Risks

- **First-boot-after-upgrade window**: existing installs start with mark 0 and
  accept the relay's current version once. Unavoidable without prior durable
  state; bounded because the relay's CURRENT row is the honest-majority state
  and every subsequent apply is monotonic.
- **Wipe races a zombie old-generation write**: mitigated by disconnect-first
  ordering + lifecycle-generation guards; worst case is a closed-box throw in
  a discarded generation.
- **Directory-scan backstop is platform-dependent** (Hive file layout):
  mitigated by also deriving names from the index; a missed orphan is
  ciphertext without an index entry — unreadable through app paths anyway.
- **A→B→A churn destroys A's local transcripts**: accepted in the data-loss
  policy (operator-confirmed); the bridge's same-pk drop + initial-emit guard
  keep spurious transitions from reaching the wipe.

## Implementation

- **`app-owner-key-version-rollback-hardening`**: persisted an owner-hash
  scoped mesh high-water mark outside `wipeAll`; mesh pull rejects lower valid
  versions fail-closed and publish is floored above both in-memory and durable
  marks. Added rollback cold-start, owner-scoping, unavailable-store,
  fresh-publish-floor, and last-peer-revoke coverage.
- **`gate-security-owner-reset-retains-transcripts`**: added the transcript
  wipe facade and inserted it after old-generation disconnect and before the
  router's replacement-owner boot. It derives indexed boxes, deletes orphaned
  event/projection boxes discovered in the Hive home directory, preserves key
  and security metadata, then reopens empty common boxes. Added same-tuple,
  orphan, metadata, router-ordering, and same-owner no-reset coverage.
- **Integrated verification**: `flutter analyze` passed. `flutter test` ran
  825 passing tests; its only six failures are the documented e2e
  pairing-endpoint environment limitation, unrelated to this feature.

## Review (standard, cross-model, 2026-07-23) — adjudicated, closed

One balanced fresh-context cross-model pass (`openai-codex/gpt-5.6-sol` vs host
`umans/umans-glm-5.2`). Verdict REQUEST CHANGES with 3 proposed blockers
(0 important, 0 nits) — all in the async/lifecycle defect class. All three
receiver-confirmed against code and fixed in `f9c416d`:

1. **Watermark race** — ACCEPTED, fixed. Overlapping pulls could apply v6
   after v7 advanced the floor; a late A pull during A→B transition could
   clobber B's shared watermark context; the durable max-update was a
   non-atomic read-then-write. Fix: immutable owner-bound `_WatermarkContext`
   carried per operation, a narrow `_watermarkTail` serialization chain around
   context commit / floor check / advance / cache-replace / publish version
   preparation (network stays outside the chain — conflict rebase cannot
   deadlock), currency revalidation after each serialized section, and durable
   max updates routed through `PairingStorage`'s mutation queue. Tests:
   deterministic overlapping v6/v7, A→B load-race, concurrent durable max.
2. **Wipe failure → retry skips wipe** — ACCEPTED, fixed. The wipe is now
   self-latching (`owner_transition_wipe_pending` metadata flag set before any
   deletion, cleared only on full success) and boot-convergent:
   `LocalBoxes.init`/router retry resume a pending wipe idempotently before
   initialization completes — the data-loss boundary is fail-closed by
   construction, not caller discipline. Tests: failure before common-clear,
   failure mid-delete, router retry convergence.
3. **Wipe not exclusive with transcript writer** — ACCEPTED, fixed. Facade
   transition gate: closes first, drains tracked in-flight opens, then
   enumerates/deletes; opens re-check the gate after awaiting Hive so a racing
   open throws before returning a writable box. Test: gated append-vs-wipe
   race regression.

### Verification (post-fix, orchestrator)

`flutter analyze` clean; full `flutter test` 832 passed (+7 corrective tests),
only the 6 known pairing-endpoint e2e environment failures.

Foundation note: `PROTOCOL.md:471` / `docs/DECISIONS.md:106` assert
anti-rollback protection; the pass-1 race left them untrue, and these fixes
restore alignment — no doc change needed.

Closure: `standard` weight — one independent pass, all receiver-confirmed
blockers fixed and verified, no second pass. Advanced `review → done`.
