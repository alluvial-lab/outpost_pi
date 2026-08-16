import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:outpost_pi_identity/outpost_pi_identity.dart';

/// Outcome of a `bridge.boot()` call. The router uses this to decide
/// between "show sync-required gate" and "boot normally".
sealed class OwnerIdentityBootResult {
  const OwnerIdentityBootResult();
}

/// Platform key-sync surface is off — caller must surface the
/// platform-specific config instructions and *not* generate a local
/// identity (would silently diverge with sync later).
final class SyncUnavailableResult extends OwnerIdentityBootResult {
  const SyncUnavailableResult();
}

/// Either loaded from sync or freshly generated. Carries the
/// 32-byte public key so callers can stash it before challenge-response
/// time; the private key stays on-disk to avoid keeping it in heap.
final class IdentityReady extends OwnerIdentityBootResult {
  final OwnerIdentity identity;

  /// True when this run generated the keypair instead of loading it.
  /// Surfaced for telemetry / "fresh install" UX decisions.
  final bool generated;
  const IdentityReady(this.identity, {required this.generated});
}

/// A previously-started Owner replacement must finish cleanup before its
/// identity can become active.
final class OwnerTransitionPending extends OwnerIdentityBootResult {
  const OwnerTransitionPending(this.identity);

  final OwnerIdentity identity;
}

/// Bridge between the `outpost_pi_identity` plugin and the rest of the
/// app. Responsibilities:
///
/// - Boot-time decision: sync available? identity present?
/// - `currentIdentity` getter for callers that need the Owner-sk for
///   relay challenge-response (production transport factory).
/// - Watch-on-sync hook: when the platform delivers a different Owner key,
///   durably gate access until the router removes local state tied to the
///   previous Owner.
class OwnerIdentityBridge extends ChangeNotifier {
  final OwnerIdentityStore _store;
  final PairingStorage _pairing;
  final Ed25519 _ed25519 = Ed25519();

  OwnerIdentity? _current;
  StreamSubscription<OwnerIdentity>? _watchSub;
  Future<void> _watchTail = Future<void>.value();
  bool _transitionPending = false;
  bool _disposed = false;

  OwnerIdentityBridge(this._store, this._pairing);

  /// Return the bootstrapped owner identity, or null before the router gate runs.
  OwnerIdentity? get currentIdentity => _transitionPending ? null : _current;

  /// Public key of the currently-loaded Owner identity (or null when
  /// the bridge hasn't booted yet). Surfaces this for the router's
  /// guard logic.
  Uint8List? get currentOwnerPk =>
      _transitionPending ? null : _current?.ownerPk;

  /// Whether a replacement Owner is blocked until old local state is removed.
  bool get isTransitionPending => _transitionPending;

  /// Load (or generate) the Owner identity.
  ///
  /// The real load/save path is the capability check. A separate availability
  /// preflight can be a false negative on entitlement-less iOS builds, while a
  /// [SyncUnavailable] from storage remains gateable. Platform failures still
  /// propagate so they cannot silently replace the durable Owner key. The
  /// candidate is compared to the durable owner-of-local-state fingerprint
  /// before it is assigned to [_current].
  Future<OwnerIdentityBootResult> boot() async {
    final transitionPending = await _pairing.hasPendingOwnerTransition();
    try {
      final loaded = await _store.load();
      if (loaded != null) {
        return _acceptBootCandidate(
          loaded,
          generated: false,
          transitionPending: transitionPending,
        );
      }
    } on SyncUnavailable {
      return const SyncUnavailableResult();
    }

    if (transitionPending) {
      _current = null;
      _transitionPending = true;
      throw StateError('Owner transition is pending identity restoration');
    }

    final generated = await _generateIdentity();
    // A restored identity can arrive after the first null read. Re-read before
    // saving so a concurrent restoration wins over a local first-run key.
    OwnerIdentity? restored;
    try {
      restored = await _store.load();
    } on SyncUnavailable {
      return const SyncUnavailableResult();
    }
    if (restored != null) {
      return _acceptBootCandidate(
        restored,
        generated: false,
        transitionPending: false,
      );
    }
    try {
      await _store.save(generated);
    } on SyncUnavailable {
      return const SyncUnavailableResult();
    }
    return _acceptBootCandidate(
      generated,
      generated: true,
      transitionPending: false,
    );
  }

  /// Commit [identity] only after the router has completed every cleanup step.
  ///
  /// The durable marker is deleted before its replacement fingerprint is
  /// recorded, so a failed deletion leaves access gated and boot-convergent.
  Future<void> completePendingTransition(OwnerIdentity identity) async {
    final fingerprint = await _ownerFingerprint(identity.ownerPk);
    await _pairing.completeOwnerTransition(fingerprint);
    _transitionPending = false;
    _current = identity;
    notifyListeners();
  }

  Future<OwnerIdentityBootResult> _acceptBootCandidate(
    OwnerIdentity candidate, {
    required bool generated,
    required bool transitionPending,
  }) async {
    if (transitionPending || await _pairing.hasPendingOwnerTransition()) {
      _current = null;
      _transitionPending = true;
      return OwnerTransitionPending(candidate);
    }

    final candidateFingerprint = await _ownerFingerprint(candidate.ownerPk);
    final storedFingerprint = await _pairing.loadOwnerStateFingerprint();
    final ownerFingerprint =
        storedFingerprint ??
        await _pairing.initializeOwnerStateFingerprint(candidateFingerprint);
    if (ownerFingerprint != candidateFingerprint) {
      await _pairing.beginOwnerTransition();
      _current = null;
      _transitionPending = true;
      return OwnerTransitionPending(candidate);
    }

    _transitionPending = false;
    _current = candidate;
    return IdentityReady(candidate, generated: generated);
  }

  Future<String> _ownerFingerprint(Uint8List ownerPk) async {
    final digest = await Sha256().hash(ownerPk);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  Future<OwnerIdentity> _generateIdentity() async {
    final kp = await _ed25519.newKeyPair();
    final pub = await kp.extractPublicKey();
    final priv = await kp.extractPrivateKeyBytes();
    return OwnerIdentity(
      ownerPk: Uint8List.fromList(pub.bytes),
      ownerSk: Uint8List.fromList(priv),
    );
  }

  /// Rehydrate a `SimpleKeyPair` from the cached Owner identity. Used
  /// at challenge-response time — callers must have already gone
  /// through [boot] (otherwise [currentIdentity] would still be null
  /// and this throws `StateError`).
  Future<SimpleKeyPair> requireKeyPair() async {
    final id = currentIdentity;
    if (id == null) {
      throw StateError(
        'OwnerIdentityBridge.requireKeyPair() called before boot() — '
        'router should have gated this path on IdentityReady.',
      );
    }
    return _ed25519.newKeyPairFromSeed(id.ownerSk);
  }

  /// Subscribe to platform sync events. When the incoming Owner-pk differs
  /// from [_current], the bridge persists a transition gate, then calls
  /// [onTransition]. The router must wipe pairing, disconnect, wipe
  /// transcripts, and finally call [completePendingTransition].
  ///
  /// Same-pk events are dropped — re-saves of identical content (echo
  /// from our own write) shouldn't reset state.
  ///
  /// Initial-emit race: both the iOS plugin (`KeychainSyncStore`
  /// onListen → emitIfChanged) and the Android plugin (initial
  /// `store.load()` on subscribe) push the current blob to the event
  /// channel as soon as we `.listen()`. If we subscribed before
  /// [boot] populated `_current`, that initial emit would look like
  /// a "different owner_pk" (because current is null) and trigger a
  /// spurious `wipeAll`. That cleared the freshly-paired peer set,
  /// and a downstream `_maybeAdoptLegacyRoom` (driven by an incoming
  /// `room_announced`) would then re-publish v=N+1 with members=[],
  /// causing the pi-extension to self-revoke ~60s later.
  ///
  /// Defence: when `_current` is null at observation time, treat the
  /// event as the platform's initial-snapshot and *adopt without
  /// wiping*. The host should also order calls so `startWatching`
  /// runs after `boot()` whenever possible, but this guard makes the
  /// bridge correct even when the order is reversed (e.g. router
  /// boot is fire-and-forget).
  void startWatching({
    required Future<void> Function(OwnerIdentity incoming) onTransition,
  }) {
    _watchSub?.cancel();
    _watchSub = _store.watch().listen((incoming) {
      _watchTail = _watchTail
          .then((_) => _handleIncoming(incoming, onTransition))
          .catchError((Object _) {});
    }, onError: (Object _) {});
  }

  Future<void> _handleIncoming(
    OwnerIdentity incoming,
    Future<void> Function(OwnerIdentity incoming) onTransition,
  ) async {
    if (_disposed || _transitionPending) return;
    final current = _current;
    if (current == null) {
      _current = incoming;
      return;
    }
    if (_bytesEqual(current.ownerPk, incoming.ownerPk)) return;

    // The durable marker is the first transition side effect. Do not publish
    // [incoming] until the router has removed every old-Owner capability.
    await _pairing.beginOwnerTransition();
    _transitionPending = true;
    notifyListeners();
    await onTransition(incoming);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _watchSub?.cancel();
    _watchSub = null;
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
