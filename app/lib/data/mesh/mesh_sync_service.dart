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
/// (plan/24); the local storage is a hydrated cache. Mutations:
///   1. write through to local storage immediately (UI responsiveness)
///   2. publish in background; on conflict/failure, the next
///      [pullAndApply] reconciles.
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
    final hash = await MeshClient.ownerPkHash(pk);
    if (!_isPullCurrent(mutationRevision, allowPendingMutation, pk)) {
      return false;
    }
    final result = await _client.fetch(
      hash,
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
  ) {
    final currentOwnerPk = _ownerBridge.currentOwnerPk;
    return !_disposed &&
        mutationRevision == _mutationRevision &&
        (allowPendingMutation || !_mutationPending) &&
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
    return _replaceLocalCacheWith(
      blob,
      expectedOwnerPk: expectedOwnerPk,
      mutationRevision: mutationRevision,
      allowPendingMutation: allowPendingMutation,
    );
  }

  /// Overwrite local peers + nicknames with what the relay says.
  /// Implements the "relay is source of truth" contract from plan/24:
  /// any peer in the local cache but absent from `blob.members` is
  /// removed; renamed nicknames propagate; relay_url updates.
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
    final existing = {for (final p in peers) p.remoteEpk: p};
    final keep = <String>{};
    for (final m in blob.members) {
      if (!current()) return false;
      keep.add(m.remoteEpk);
      final prev = existing[m.remoteEpk];
      final next = PeerRecord(
        remoteEpk: m.remoteEpk,
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
    for (final p in existing.values) {
      if (!current()) return false;
      if (!keep.contains(p.remoteEpk)) {
        await _storage.deletePeerSilent(p.remoteEpk);
        if (!current()) return false;
        await _storage.deleteRooms(p.remoteEpk);
        if (!current()) return false;
      }
    }
    return current();
  }

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
  /// [pullAndApply] tick will reconcile (LWW from plan/24 § Q5).
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
    final nextVersion = _lastVersion + 1;
    final blob = MeshBlob(
      version: nextVersion,
      issuedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      ownerPk: pk,
      members: members,
    );
    final keyPair = await _ownerBridge.requireKeyPair();
    if (_disposed) return const MeshPublishFailure('disposed');
    final envelope = await blob.signWith(keyPair);
    if (_disposed) return const MeshPublishFailure('disposed');
    final hash = await MeshClient.ownerPkHash(pk);
    if (_disposed) return const MeshPublishFailure('disposed');
    final result = await _client.publish(hash, envelope);
    if (_disposed) return const MeshPublishFailure('disposed');
    switch (result) {
      case MeshPublishOk(version: final v, updatedAt: final u):
        _lastVersion = v;
        lastUpdatedAt = u;
        notifyListeners();
        return result;
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

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
