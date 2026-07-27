import 'dart:async';

import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:flutter/foundation.dart';

import 'mesh_blob.dart';
import 'mesh_client.dart';
import 'mesh_envelope.dart';

/// Orchestrates publish + pull-and-apply of the Owner's mesh blob
/// against the relay's `/mesh` endpoint. Sits between the
/// [PairingStorage] (local cache) and the [MeshClient] (network).
///
/// Single source of truth for the Owner's membership is the relay
/// (plan/24); the local storage is a hydrated cache — except device-local
/// owner-channel keys, which blob authority can never destroy (see
/// [_replaceLocalCacheWith]). Mutations:
///   1. write through to local storage immediately (UI responsiveness)
///   2. publish in background; on conflict/failure, the next
///      [pullOnDemand] reconciles.
///
/// Reads: [pullOnDemand] runs at boot, WS reconnect, deep links;
/// [startPolling] keeps the cache fresh while the app is in foreground.
class MeshSyncService extends ChangeNotifier {
  final MeshClient _client;
  final OwnerIdentityBridge _ownerBridge;
  final PairingStorage _storage;
  final DebugLog? _debugLog;
  final Duration _mutationRetryDelay;

  /// Last version we observed locally — used as the `since` query
  /// parameter on subsequent fetches so the relay can short-circuit
  /// to 304. Reset to 0 when the Owner key changes (sync drift).
  int _lastVersion = 0;

  // Watermark state is owner-bound and only replaced through _watermarkTail.
  // Network round-trips remain outside the queue so conflict rebase can pull
  // without deadlocking the publication that initiated it.
  _WatermarkContext? _watermarkContext;
  Future<void> _watermarkTail = Future<void>.value();

  /// True while any direct or mutation-owned publication is in flight.
  bool _publishing = false;

  int _mutationRevision = 0;
  bool _mutationPending = false;
  PeerMutationKind? _pendingMutationKind;
  bool _mutationDrainRunning = false;
  Timer? _mutationRetryTimer;
  Timer? _pollTimer;
  bool _disposed = false;

  /// Last observed [updatedAt] from the relay. Surfaced so the UI can
  /// render "last synced ... ago" if it wants to.
  int? lastUpdatedAt;

  MeshSyncService(
    this._client,
    this._ownerBridge,
    this._storage, {
    DebugLog? debugLog,
    Duration mutationRetryDelay = const Duration(seconds: 5),
  }) : _debugLog = debugLog,
       _mutationRetryDelay = mutationRetryDelay;

  /// Return the verified relay version used as the next conditional-fetch watermark.
  int get lastVersion => _lastVersion;

  /// Load an immutable rollback-floor snapshot for one Owner operation.
  ///
  /// The secure-storage read may overlap other reads, but committing its result
  /// is serialized and revalidates Owner/lifecycle state. A late Owner-A read
  /// therefore cannot replace Owner B's active context.
  Future<_WatermarkContext?> _loadWatermarkContext(
    Uint8List ownerPk, {
    required bool Function() isCurrent,
  }) async {
    final ownerPkHash = await MeshClient.ownerPkHash(ownerPk);
    if (!isCurrent()) return null;
    final loaded = await _storage.loadMeshHighWatermark(ownerPkHash);
    if (!isCurrent()) return null;
    final snapshot = _watermarkContext;
    if (snapshot != null &&
        snapshot.ownerPkHash == ownerPkHash &&
        snapshot.highWatermark >= loaded) {
      return snapshot;
    }
    return _serializeWatermark(() async {
      if (!isCurrent()) return null;
      final active = _watermarkContext;
      final mark = active != null && active.ownerPkHash == ownerPkHash
          ? (active.highWatermark > loaded ? active.highWatermark : loaded)
          : loaded;
      final context = _WatermarkContext(ownerPkHash, mark);
      _watermarkContext = context;
      return context;
    });
  }

  _WatermarkContext _latestContext(_WatermarkContext operationContext) {
    final active = _watermarkContext;
    if (active == null || active.ownerPkHash != operationContext.ownerPkHash) {
      return operationContext;
    }
    return active.highWatermark > operationContext.highWatermark
        ? active
        : operationContext;
  }

  Future<T> _serializeWatermark<T>(Future<T> Function() operation) {
    final result = _watermarkTail.then((_) => operation());
    _watermarkTail = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }

  void _diagnoseRollbackRejection() {
    _debugLog?.log(
      LifecycleFailureEvent(
        ts: DateTime.now().toUtc(),
        operation: LifecycleOperation.meshPublish,
        reason: 'mesh_rollback_rejected',
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Pull
  // -------------------------------------------------------------------------

  /// One-shot fetch + apply. Called from boot, WS reconnection, deep
  /// links. Returns `true` if the local cache now reflects a
  /// successfully-verified relay version (including 304 "we're up to
  /// date" and 404 "relay never had data"); `false` on failure.
  Future<bool> pullOnDemand() {
    if (_disposed) return Future.value(false);
    if (_mutationPending) {
      _startMutationPublishDrain();
      return Future.value(false);
    }
    return _pullOnDemand(allowPendingMutation: false);
  }

  Future<bool> _pullOnDemand({
    required bool allowPendingMutation,
    int? expectedMutationRevision,
  }) async {
    final mutationRevision = expectedMutationRevision ?? _mutationRevision;
    final pk = _ownerBridge.currentOwnerPk;
    if (pk == null ||
        !_isPullCurrent(mutationRevision, allowPendingMutation, pk)) {
      return false;
    }
    late final _WatermarkContext watermarkContext;
    try {
      final loaded = await _loadWatermarkContext(
        pk,
        isCurrent: () =>
            _isPullCurrent(mutationRevision, allowPendingMutation, pk),
      );
      if (loaded == null) return false;
      watermarkContext = loaded;
    } on Object {
      return false;
    }
    if (!_isPullCurrent(mutationRevision, allowPendingMutation, pk)) {
      return false;
    }
    final result = await _client.fetch(
      watermarkContext.ownerPkHash,
      since: _lastVersion > 0 ? _lastVersion : null,
    );
    if (!_isPullCurrent(mutationRevision, allowPendingMutation, pk)) {
      return false;
    }
    switch (result) {
      case MeshFetchOk(
        envelope: final env,
        version: final v,
        updatedAt: final u,
      ):
        final applied = await _applyVerified(
          env,
          expectedOwnerPk: pk,
          operationContext: watermarkContext,
          mutationRevision: mutationRevision,
          allowPendingMutation: allowPendingMutation,
        );
        if (applied &&
            _isPullCurrent(mutationRevision, allowPendingMutation, pk)) {
          _lastVersion = v;
          lastUpdatedAt = u;
          notifyListeners();
          return true;
        }
        return false;
      case MeshFetchNotModified():
        return _isPullCurrent(mutationRevision, allowPendingMutation, pk);
      case MeshFetchNotFound():
        return _isPullCurrent(mutationRevision, allowPendingMutation, pk);
      case MeshFetchFailure():
        return false;
    }
  }

  bool _isPullCurrent(
    int mutationRevision,
    bool allowPendingMutation,
    Uint8List expectedOwnerPk,
  ) =>
      mutationRevision == _mutationRevision &&
      (allowPendingMutation || !_mutationPending) &&
      _isOwnerCurrent(expectedOwnerPk);

  bool _isOwnerCurrent(Uint8List expectedOwnerPk) {
    final currentOwnerPk = _ownerBridge.currentOwnerPk;
    return !_disposed &&
        currentOwnerPk != null &&
        _bytesEqual(currentOwnerPk, expectedOwnerPk);
  }

  /// Verify the envelope, parse, and overwrite the local storage with
  /// the relay's view. Returns `false` when verification fails or the
  /// embedded owner_pk doesn't match the one we expected — those are
  /// silent drops (we do not touch the cache).
  Future<bool> _applyVerified(
    MeshEnvelope env, {
    required Uint8List expectedOwnerPk,
    required _WatermarkContext operationContext,
    required int mutationRevision,
    required bool allowPendingMutation,
  }) async {
    final ok = await MeshBlob.verifyEnvelope(env);
    if (!ok ||
        !_isPullCurrent(
          mutationRevision,
          allowPendingMutation,
          expectedOwnerPk,
        )) {
      return false;
    }
    final blob = MeshBlob.fromCanonicalBytes(env.blob);
    if (!_bytesEqual(blob.ownerPk, expectedOwnerPk) ||
        !_isPullCurrent(
          mutationRevision,
          allowPendingMutation,
          expectedOwnerPk,
        )) {
      return false;
    }
    try {
      return await _serializeWatermark(() async {
        bool current() => _isPullCurrent(
          mutationRevision,
          allowPendingMutation,
          expectedOwnerPk,
        );
        if (!current()) return false;
        var context = _latestContext(operationContext);
        if (blob.version < context.highWatermark) {
          _diagnoseRollbackRejection();
          return false;
        }
        if (blob.version > context.highWatermark) {
          if (!current()) return false;
          await _storage.saveMeshHighWatermark(
            context.ownerPkHash,
            blob.version,
          );
          if (!current()) return false;
          context = _WatermarkContext(context.ownerPkHash, blob.version);
          _watermarkContext = context;
        }
        if (!current()) return false;
        return _replaceLocalCacheWith(
          blob,
          expectedOwnerPk: expectedOwnerPk,
          mutationRevision: mutationRevision,
          allowPendingMutation: allowPendingMutation,
        );
      });
    } on Object {
      return false;
    }
  }

  /// Overwrite local peers + nicknames with what the relay says.
  /// Implements the "relay is source of truth" contract from plan/24 with
  /// two qualifications added after the 2026-07-26/27 pairing-bricking
  /// incident (story-mesh-reconciliation-deletes-pairing-channel):
  ///
  ///   1. **Canonical epk matching.** PairingStorage keys records by the
  ///      QR/pair_ok string (base64url) while blob members are published
  ///      base64 standard (see [_publishOnce]). Raw string equality across
  ///      that boundary misses same-key records: the keep-set check used to
  ///      delete the channel-bearing local record and hydrate a channel-less
  ///      duplicate under the standard spelling, bricking the pairing on the
  ///      next cold-start pull. All membership matching here is by canonical
  ///      (standard-b64) form; a matched local record keeps its stored
  ///      spelling, and a genuinely new member hydrates under the
  ///      storage-canonical (base64url) spelling so a later pairing
  ///      overwrites it instead of duplicating it.
  ///   2. **Blob absence is not revocation authority for paired records.**
  ///      The blob is a last-writer-wins register that can lag this device's
  ///      latest pairing, and owner-channel keys are device-local and
  ///      unrecoverable without re-pair. A channel-bearing record absent
  ///      from the blob is kept whole; if the peer was genuinely revoked
  ///      elsewhere it becomes a harmless ghost (the Pi self-revoked, so
  ///      the channel is dead) that the user revokes locally. Channel-less
  ///      (metadata-only hydrated) records absent from the blob are still
  ///      removed, so revocation and roster hygiene propagate for records
  ///      this device never paired.
  ///
  /// Uses the **silent** variants of save/delete so the mutation hook
  /// (which republishes) does not fire. Otherwise every pull would
  /// loop into a publish, and any tiny diff (timestamp precision,
  /// reordering) would round-trip back to the relay. Worse: a race
  /// between the apply-phase intermediate states and a concurrent
  /// `publish()` could observe an empty PairingStorage and ship
  /// members=[] — the bug reproduced by the user, where pi-extension
  /// self-revoked after the app silently published v2 empty.
  Future<bool> _replaceLocalCacheWith(
    MeshBlob blob, {
    required Uint8List expectedOwnerPk,
    required int mutationRevision,
    required bool allowPendingMutation,
  }) async {
    bool current() =>
        _isPullCurrent(mutationRevision, allowPendingMutation, expectedOwnerPk);

    final peers = await _storage.listPeers();
    if (!current()) return false;
    // Canonical-epk survivor map. Incident debris and pre-fix hydrations can
    // leave one member stored under two spellings; collapse each canonical
    // key to a single surviving record (see [_preferSurvivor]).
    final survivors = <String, PeerRecord>{};
    final shadowed = Set<PeerRecord>.identity();
    for (final p in peers) {
      final key = toStandardB64(p.remoteEpk);
      final prev = survivors[key];
      if (prev == null) {
        survivors[key] = p;
      } else {
        final (keepRecord, dropRecord) = _preferSurvivor(prev, p);
        survivors[key] = keepRecord;
        shadowed.add(dropRecord);
      }
    }

    final keep = <String>{};
    for (final m in blob.members) {
      if (!current()) return false;
      final key = toStandardB64(m.remoteEpk);
      keep.add(key);
      final prev = survivors[key];
      final next = PeerRecord(
        remoteEpk: prev?.remoteEpk ?? toAppEpk(m.remoteEpk),
        sessionName: prev?.sessionName ?? m.nickname ?? 'outpost_pi',
        relayUrl: m.relayUrl,
        pairedAt: m.pairedAt,
        nickname: m.nickname,
        roomId: prev?.roomId,
        harness: prev?.harness,
        // Owner-channel keys are device-local secret state. Mesh membership
        // updates may change labels/relay metadata but must never carry them
        // onto a newly hydrated peer or replace an existing channel.
        channel: prev?.channel,
      );
      if (prev == null || !_peerEqualsForMesh(prev, next)) {
        await _storage.saveMeshPeerMetadata(next);
        if (!current()) return false;
      }
    }
    for (final p in peers) {
      if (!current()) return false;
      if (shadowed.contains(p)) {
        // Same-key duplicate under a second spelling. Only metadata-only
        // shadows are droppable; a channel-bearing duplicate should not
        // exist (pairing writes one record per spelling) and is kept
        // defensively rather than destroying unrecoverable keys.
        if (p.channel == null) {
          await _storage.deletePeerSilent(p.remoteEpk);
          if (!current()) return false;
          await _storage.deleteRooms(p.remoteEpk);
          if (!current()) return false;
        }
        continue;
      }
      if (!keep.contains(toStandardB64(p.remoteEpk))) {
        if (p.channel != null) {
          // Blob absence is not revocation authority for a paired record —
          // see the method doc. Kept whole, rooms included.
          debugPrint(
            'MeshSyncService: kept channel-bearing peer '
            '${_epkTail(p.remoteEpk)} absent from mesh blob v${blob.version}',
          );
          continue;
        }
        await _storage.deletePeerSilent(p.remoteEpk);
        if (!current()) return false;
        await _storage.deleteRooms(p.remoteEpk);
        if (!current()) return false;
      }
    }
    return current();
  }

  /// Pick the surviving record for one canonical epk stored under two
  /// spellings. A channel-bearing record always wins: owner-channel keys
  /// are device-local and unrecoverable, while metadata-only hydrations are
  /// replaceable. Ties prefer the storage-canonical (base64url) spelling so
  /// the survivor matches what the pairing flow writes.
  (PeerRecord, PeerRecord) _preferSurvivor(PeerRecord a, PeerRecord b) {
    final aHasChannel = a.channel != null;
    final bHasChannel = b.channel != null;
    if (aHasChannel != bHasChannel) return aHasChannel ? (a, b) : (b, a);
    final aCanonical = a.remoteEpk == toAppEpk(a.remoteEpk);
    final bCanonical = b.remoteEpk == toAppEpk(b.remoteEpk);
    if (aCanonical != bCanonical) return aCanonical ? (a, b) : (b, a);
    return (a, b);
  }

  static String _epkTail(String epk) =>
      epk.length <= 8 ? epk : epk.substring(epk.length - 8);

  Future<bool> _restoreProtectedLocalSnapshot(
    List<PeerRecord> protectedPeers, {
    required Uint8List expectedOwnerPk,
    required int mutationRevision,
  }) async {
    bool current() => _isPullCurrent(mutationRevision, true, expectedOwnerPk);

    final currentPeers = await _storage.listPeers();
    if (!current()) return false;
    final existing = {for (final peer in currentPeers) peer.remoteEpk: peer};
    final protectedByEpk = {
      for (final peer in protectedPeers) peer.remoteEpk: peer,
    };
    for (final peer in protectedPeers) {
      if (!current()) return false;
      final stored = existing[peer.remoteEpk];
      if (stored == null || stored != peer) {
        final restored = await _storage.restorePeerSnapshotSilent(
          peer,
          stillCurrent: current,
        );
        if (!restored || !current()) return false;
      }
    }
    for (final peer in currentPeers) {
      if (!current()) return false;
      if (!protectedByEpk.containsKey(peer.remoteEpk)) {
        await _storage.deletePeerSilent(peer.remoteEpk);
        if (!current()) return false;
        await _storage.deleteRooms(peer.remoteEpk);
        if (!current()) return false;
      }
    }
    return current();
  }

  /// Compare the mesh-controlled fields only — `sessionName` and
  /// `roomId` stay client-local and don't trigger a re-save when the
  /// relay version arrives unchanged.
  bool _peerEqualsForMesh(PeerRecord a, PeerRecord b) =>
      a.remoteEpk == b.remoteEpk &&
      a.relayUrl == b.relayUrl &&
      a.pairedAt == b.pairedAt &&
      a.nickname == b.nickname;

  // -------------------------------------------------------------------------
  // Publish
  // -------------------------------------------------------------------------

  /// Snapshot the current local peer list, bump version, sign, POST.
  /// Conflict (409) → re-fetch then publish again with the higher
  /// version. Network failure leaves the cache as-is — the next
  /// [pullOnDemand] tick will reconcile (LWW from plan/24 § Q5).
  ///
  /// [allowEmpty] opts out of the empty-on-existing safety net (see
  /// [_publishOnce]). Used by the revoke-last-peer flow, which is the
  /// only legitimate caller of "publish members=[] on top of a
  /// non-zero version watermark" — every other caller leaves the
  /// default `false` so the safety net still protects against races.
  Future<MeshPublishResult> publish({bool allowEmpty = false}) async {
    if (_disposed) return const MeshPublishFailure('disposed');
    if (_publishing) {
      return const MeshPublishFailure('already in flight');
    }
    final pk = _ownerBridge.currentOwnerPk;
    if (pk == null) {
      return const MeshPublishFailure('owner pk not loaded');
    }
    _publishing = true;
    try {
      return await _publishOnce(
        pk,
        refetchOnConflict: true,
        allowEmpty: allowEmpty,
      );
    } finally {
      _publishing = false;
      _startMutationPublishDrain();
    }
  }

  Future<MeshPublishResult> _publishOnce(
    Uint8List pk, {
    required bool refetchOnConflict,
    required bool allowEmpty,
  }) async {
    late final _WatermarkContext watermarkContext;
    try {
      final loaded = await _loadWatermarkContext(
        pk,
        isCurrent: () => _isOwnerCurrent(pk),
      );
      if (loaded == null) {
        return const MeshPublishFailure('owner changed');
      }
      watermarkContext = loaded;
    } on Object {
      return const MeshPublishFailure('watermark_unavailable');
    }
    if (!_isOwnerCurrent(pk)) {
      return const MeshPublishFailure('owner changed');
    }
    final peers = await _storage.listPeers();
    if (_disposed) return const MeshPublishFailure('disposed');
    // Safety net (plan/24-fix-app-publish-race): never overwrite a
    // non-empty membership with members=[] UNLESS the caller opted in
    // via [allowEmpty]. The only legitimate "empty on top of non-zero
    // version" path is the user revoking their last paired peer
    // (SettingsViewModel.revoke); every other caller passes
    // `allowEmpty:false` so we still refuse races (transient
    // PairingStorage state, apply mid-flight, mistaken Owner-key
    // reset) that would self-revoke pi-extension on every Pi the user
    // owns.
    if (peers.isEmpty && _lastVersion > 0 && !allowEmpty) {
      return const MeshPublishFailure('refused empty-on-existing');
    }
    // Encoding gotcha: `PairingStorage.PeerRecord.remoteEpk` is whatever
    // the QR / pair_ok handed us — historically base64url (no padding).
    // The Pi-extension's self-revoke check compares `my_pubkey` (which
    // it formats as base64 STANDARD, matching `owner_pk` in the blob)
    // against the strings in `members[].remote_epk`. Mixing encodings
    // looks like "I'm not listed" → self-revoke. Normalise on the way
    // out so the blob is uniformly base64 standard, end-to-end.
    final members = peers
        .map(
          (p) => MeshMember(
            remoteEpk: toStandardB64(p.remoteEpk),
            relayUrl: p.relayUrl,
            pairedAt: p.pairedAt,
            nickname: p.nickname,
          ),
        )
        .toList(growable: false);
    final preparation = await _serializeWatermark(() async {
      if (!_isOwnerCurrent(pk)) return null;
      final context = _latestContext(watermarkContext);
      _watermarkContext = context;
      final floor = _lastVersion > context.highWatermark
          ? _lastVersion
          : context.highWatermark;
      return _PublishPreparation(context, floor + 1);
    });
    if (preparation == null || !_isOwnerCurrent(pk)) {
      return const MeshPublishFailure('owner changed');
    }
    final blob = MeshBlob(
      version: preparation.nextVersion,
      issuedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      ownerPk: pk,
      members: members,
    );
    final keyPair = await _ownerBridge.requireKeyPair();
    if (_disposed) return const MeshPublishFailure('disposed');
    final envelope = await blob.signWith(keyPair);
    if (_disposed) return const MeshPublishFailure('disposed');
    if (!_isOwnerCurrent(pk)) {
      return const MeshPublishFailure('owner changed');
    }
    final result = await _client.publish(
      preparation.context.ownerPkHash,
      envelope,
    );
    if (!_isOwnerCurrent(pk)) {
      return const MeshPublishFailure('owner changed');
    }
    switch (result) {
      case MeshPublishOk(version: final v, updatedAt: final u):
        try {
          final committed = await _serializeWatermark(() async {
            if (!_isOwnerCurrent(pk)) return false;
            var context = _latestContext(preparation.context);
            if (v > context.highWatermark) {
              await _storage.saveMeshHighWatermark(context.ownerPkHash, v);
              if (!_isOwnerCurrent(pk)) return false;
              context = _WatermarkContext(context.ownerPkHash, v);
              _watermarkContext = context;
            }
            if (!_isOwnerCurrent(pk)) return false;
            if (v > _lastVersion) _lastVersion = v;
            lastUpdatedAt = u;
            notifyListeners();
            return true;
          });
          return committed ? result : const MeshPublishFailure('owner changed');
        } on Object {
          return const MeshPublishFailure('watermark_unavailable');
        }
      case MeshPublishConflict():
        if (!refetchOnConflict) return result;
        final rebaseRevision = _mutationRevision;
        final protectedLocalSnapshot = await _storage.listPeers();
        if (!_isPullCurrent(rebaseRevision, true, pk)) return result;
        final pulled = await _pullOnDemand(
          allowPendingMutation: true,
          expectedMutationRevision: rebaseRevision,
        );
        if (!pulled || !_isPullCurrent(rebaseRevision, true, pk)) {
          return result;
        }
        final restored = await _restoreProtectedLocalSnapshot(
          protectedLocalSnapshot,
          expectedOwnerPk: pk,
          mutationRevision: rebaseRevision,
        );
        if (!restored || !_isPullCurrent(rebaseRevision, true, pk)) {
          return result;
        }
        return _publishOnce(
          pk,
          refetchOnConflict: false,
          allowEmpty: allowEmpty,
        );
      case MeshPublishBadRequest():
        return result;
      case MeshPublishForbidden():
      case MeshPublishTooLarge():
      case MeshPublishFailure():
        return result;
    }
  }

  /// Queue publication after a committed local peer mutation.
  ///
  /// The callback is deliberately synchronous so [PairingStorage] never owns a
  /// network future. This service owns result inspection, coalescing, retry,
  /// diagnostics, and disposal for the asynchronous publication drain.
  void publishAfterPeerMutation(PeerMutationKind kind) {
    if (_disposed) return;
    _mutationRevision += 1;
    _mutationPending = true;
    _pendingMutationKind = kind;
    _mutationRetryTimer?.cancel();
    _mutationRetryTimer = null;
    _startMutationPublishDrain();
  }

  void _startMutationPublishDrain() {
    if (_disposed ||
        !_mutationPending ||
        _publishing ||
        _mutationDrainRunning ||
        _mutationRetryTimer != null) {
      return;
    }
    _mutationDrainRunning = true;
    unawaited(_drainPendingMutationPublish());
  }

  Future<void> _drainPendingMutationPublish() async {
    try {
      while (!_disposed && _mutationPending) {
        final revision = _mutationRevision;
        final kind = _pendingMutationKind!;
        _publishing = true;
        MeshPublishResult result;
        try {
          final pk = _ownerBridge.currentOwnerPk;
          result = pk == null
              ? const MeshPublishFailure('owner pk not loaded')
              : await _publishOnce(
                  pk,
                  refetchOnConflict: true,
                  allowEmpty: kind == PeerMutationKind.delete,
                );
        } catch (_) {
          if (_disposed) return;
          _diagnoseMutationPublish(
            reason: 'unexpected publish exception',
            retryScheduled: true,
          );
          _scheduleMutationPublishRetry();
          return;
        } finally {
          _publishing = false;
        }
        if (_disposed) return;

        switch (result) {
          case MeshPublishOk():
            if (revision == _mutationRevision) {
              _mutationPending = false;
              _pendingMutationKind = null;
            }
            continue;
          case MeshPublishFailure():
            _diagnoseMutationPublish(
              reason: 'transient publish failure',
              retryScheduled: true,
            );
            _scheduleMutationPublishRetry();
            return;
          case MeshPublishConflict():
            _diagnoseMutationPublish(
              reason: 'conflict after rebase',
              retryScheduled: true,
            );
            _scheduleMutationPublishRetry();
            return;
          case MeshPublishBadRequest():
            _stopMutationPublishAfterPermanentFailure('bad request');
            return;
          case MeshPublishForbidden():
            _stopMutationPublishAfterPermanentFailure('forbidden');
            return;
          case MeshPublishTooLarge():
            _stopMutationPublishAfterPermanentFailure('too large');
            return;
        }
      }
    } finally {
      _mutationDrainRunning = false;
      if (!_disposed && _mutationPending && _mutationRetryTimer == null) {
        _startMutationPublishDrain();
      }
    }
  }

  void _stopMutationPublishAfterPermanentFailure(String reason) {
    _diagnoseMutationPublish(reason: reason, retryScheduled: false);
    _mutationPending = false;
    _pendingMutationKind = null;
    _mutationRetryTimer?.cancel();
    _mutationRetryTimer = null;
  }

  void _scheduleMutationPublishRetry() {
    if (_disposed || !_mutationPending || _mutationRetryTimer != null) return;
    _mutationRetryTimer = Timer(_mutationRetryDelay, () {
      _mutationRetryTimer = null;
      _startMutationPublishDrain();
    });
  }

  void _diagnoseMutationPublish({
    required String reason,
    required bool retryScheduled,
  }) {
    _debugLog?.log(
      LifecycleFailureEvent(
        ts: DateTime.now().toUtc(),
        operation: LifecycleOperation.meshPublish,
        reason: reason,
        retryScheduled: retryScheduled,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Polling
  // -------------------------------------------------------------------------

  /// Begin periodic [pullOnDemand] every [interval] (default 60s, the
  /// Q1 value from plan/24). Idempotent — calling twice cancels the
  /// previous timer first.
  ///
  /// The host (typically the router or a top-level lifecycle observer)
  /// is responsible for stopping the polling when the app goes
  /// background and restarting it on resume.
  void startPolling({Duration interval = const Duration(seconds: 60)}) {
    stopPolling();
    _pollTimer = Timer.periodic(interval, (_) {
      // ignore: unawaited_futures
      pullOnDemand();
    });
  }

  /// Stop foreground polling and release its timer; safe to call repeatedly.
  void stopPolling() {
    if (_pollTimer != null) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// Reset the version watermark — used by the Owner-key-replaced
  /// path (sync drift in plan/23) so the next fetch is unconditional.
  void resetVersionWatermark() {
    _lastVersion = 0;
    lastUpdatedAt = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _mutationRevision += 1;
    _mutationPending = false;
    _pendingMutationKind = null;
    _mutationRetryTimer?.cancel();
    _mutationRetryTimer = null;
    stopPolling();
    super.dispose();
  }
}

final class _WatermarkContext {
  const _WatermarkContext(this.ownerPkHash, this.highWatermark);

  final String ownerPkHash;
  final int highWatermark;
}

final class _PublishPreparation {
  const _PublishPreparation(this.context, this.nextVersion);

  final _WatermarkContext context;
  final int nextVersion;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
