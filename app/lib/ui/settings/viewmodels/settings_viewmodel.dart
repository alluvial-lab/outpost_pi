import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/settings/states/settings_state.dart';

/// Settings is config-only (nickname + revoke). The peer switcher moved
/// to Home; the connection itself is shared and owned by
/// [ConnectionManager] from app boot (plan 12). Revoke side-effect:
/// re-subscribe the relay's presence push so the removed epk is dropped.
class SettingsViewModel extends ViewModel<SettingsState> {
  final PairingStorage _storage;
  final Preferences _prefs;
  final ConnectionManager _conn;
  final DebugLog? _debugLog;
  bool _disposed = false;

  SettingsViewModel(this._storage, this._prefs, this._conn, [this._debugLog])
    : super(const SettingsLoading()) {
    _load();
  }

  Future<void> _load() async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    if (peers.isEmpty) {
      emit(const SettingsNoPeer());
      return;
    }
    emit(SettingsList(peers: peers));
  }

  /// Set or clear the local nickname for the peer at [epk].
  Future<void> setNickname(String epk, String? nickname) async {
    final s = state;
    if (s is! SettingsList) return;
    PeerRecord? target;
    for (final p in s.peers) {
      if (p.remoteEpk == epk) {
        target = p;
        break;
      }
    }
    if (target == null) return;
    final trimmed = nickname?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final updated = target.copyWith(nickname: normalized);
    await _storage.savePeer(updated);
    await _load();
  }

  /// Current relay configuration. The explicit unconfigured branch keeps
  /// legacy completed-onboarding installs recoverable in Settings.
  RelayResolution get relayResolution => resolveRelayUrl(_prefs);

  /// Display label derived from the canonical resolution rather than a UI-only
  /// null check.
  String get effectiveRelayLabel => switch (relayResolution) {
    ConfiguredRelay(:final url) => url,
    UnconfiguredRelay() => 'Not configured',
  };

  bool get isDebugLogging => _prefs.debugLogging;

  Future<void> setDebugLogging(bool value) async {
    await _prefs.setDebugLogging(value);
    if (_disposed) return;
    notifyListeners();
  }

  /// Returns jsonl content to be shared by the UI, or null when no log exists.
  /// Export intentionally works even while capture is disabled.
  Future<String?> exportDebugLog() => _debugLog?.export() ?? Future.value();

  /// Wipes the debug ring/file without changing [isDebugLogging]. Clear
  /// intentionally works even while capture is disabled.
  Future<void> clearDebugLog() => _debugLog?.clear() ?? Future.value();

  /// User-set relay URL. A missing value intentionally keeps the editor blank
  /// so users can recover legacy installations by supplying their own relay.
  String get relayUrlOverride => _prefs.relayUrl ?? '';

  Future<String?> saveRelayUrl(String? value) async {
    final trimmed = value?.trim() ?? '';
    final reason = relayUrlValidationMessage(trimmed);
    if (reason != null) return reason;
    await _prefs.setRelayUrl(trimmed);

    await _conn.disconnect();
    _conn.boot(preferredEpk: _prefs.selectedPeerEpk);
    return null;
  }

  /// Revoke pairing locally. Drops the peer from the relay's presence
  /// subscription too so we stop receiving updates about a peer that no
  /// longer exists on this device. Clears the selected pointer when it
  /// matches. If this was the LAST peer, also resets
  /// `onboardingCompleted=false` so the next boot lands on /onboarding
  /// (matches user expectation of "revoke = start fresh").
  Future<void> revoke(String epk) async {
    final wasActive = _conn.activePeer?.remoteEpk == epk;
    if (_prefs.selectedPeerEpk == epk) {
      await _prefs.setSelectedPeerEpk(null);
    }
    // The normal delete emits typed mutation intent. MeshSyncService owns the
    // asynchronous publication and may therefore publish members=[] safely
    // when this was the final peer; Settings owns no network future.
    await _storage.deletePeer(epk);
    final remaining = await _storage.listPeers();
    _conn.subscribeToPeers(remaining.map((p) => p.remoteEpk).toList());
    // If the revoked peer was the one currently driving the connection,
    // tear it down so we don't keep talking to a peer the user just
    // removed. If others remain, fall back to one of them; otherwise
    // disconnect cleanly.
    if (wasActive) {
      await _conn.disconnect();
      if (remaining.isNotEmpty) {
        final fallback = remaining.first;
        await _prefs.setSelectedPeerEpk(fallback.remoteEpk);
        // ignore: unawaited_futures
        _conn.boot(preferredEpk: fallback.remoteEpk);
      }
    }
    if (remaining.isEmpty) {
      await _prefs.setOnboardingCompleted(false);
    }
    await _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
