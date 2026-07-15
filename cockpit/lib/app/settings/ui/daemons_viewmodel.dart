import 'package:cockpit/app/settings/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:cockpit/app/settings/domain/exceptions/daemon_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

/// Describe the daemon list's load lifecycle.
enum DaemonsLoad { idle, loading, ready, error }

/// Manage the **Daemon Agents** tab's supervised, long-running agents.
///
/// Loads on demand and reloads after actions so state converges with the
/// supervisor. An `online` value of `false` indicates an unreachable supervisor.
class DaemonsViewModel extends ChangeNotifier {
  DaemonsViewModel(this._supervisor);

  final DaemonSupervisor _supervisor;

  DaemonsLoad load = DaemonsLoad.idle;
  bool online = false;
  List<DaemonInfo> daemons = const <DaemonInfo>[];
  String? error; // Failure while listing daemons.
  String?
  actionError; // Failure from the latest start/stop/restart/remove/create.

  final Set<String> _busy = <String>{}; // IDs with an action in progress.
  bool busyAll = false; // Whether a fleet-wide action is in progress.

  bool _disposed = false;

  bool isBusy(String id) => _busy.contains(id);
  bool get anyBusy => busyAll || _busy.isNotEmpty;

  /// Poll only while idle to reflect state changes made outside the UI.
  Future<void> refreshQuiet() async {
    if (anyBusy || load == DaemonsLoad.loading) return;
    await reload();
  }

  /// Check supervisor reachability and load daemons when the tab opens.
  Future<void> reload() async {
    load = DaemonsLoad.loading;
    error = null;
    _notify();

    online = await _supervisor.isOnline();
    if (!online) {
      daemons = const <DaemonInfo>[];
      load = DaemonsLoad.ready;
      _notify();
      return;
    }

    final result = await _supervisor.list();
    result.fold(
      (list) {
        daemons = list;
        load = DaemonsLoad.ready;
      },
      (e) {
        error = e.message;
        load = DaemonsLoad.error;
      },
    );
    _notify();
  }

  /// Start one daemon, ignoring duplicate work for the same [id].
  ///
  /// Exposes per-daemon busy or failure state and reloads after completion.
  Future<void> start(String id) => _action(id, () => _supervisor.start(id));

  /// Stop one daemon, ignoring duplicate work for the same [id].
  ///
  /// Exposes per-daemon busy or failure state and reloads after completion.
  Future<void> stop(String id) => _action(id, () => _supervisor.stop(id));

  /// Restart one daemon, ignoring duplicate work for the same [id].
  ///
  /// Exposes per-daemon busy or failure state and reloads after completion.
  Future<void> restart(String id) => _action(id, () => _supervisor.restart(id));

  /// Unregister one daemon, ignoring duplicate work for the same [id].
  ///
  /// Exposes per-daemon busy or failure state and reloads after completion.
  Future<void> remove(String id) =>
      _action(id, () => _supervisor.unregister(id));

  /// Start every daemon as one fleet-wide busy operation.
  ///
  /// Records typed failures and reloads the daemon snapshot afterward.
  Future<void> startAll() => _globalAction(_supervisor.startAll);

  /// Stop every daemon as one fleet-wide busy operation.
  ///
  /// Records typed failures and reloads the daemon snapshot afterward.
  Future<void> stopAll() => _globalAction(_supervisor.stopAll);

  /// Restart every daemon as one fleet-wide busy operation.
  ///
  /// Records typed failures and reloads the daemon snapshot afterward.
  Future<void> restartAll() => _globalAction(_supervisor.restartAll);

  /// Restart the **supervisor process** to reload its code.
  ///
  /// Waits for the supervisor to return online before reloading the list.
  Future<void> restartSupervisor() async {
    if (busyAll) return;
    busyAll = true;
    actionError = null;
    _notify();
    final result = await _supervisor.restartSupervisor();
    result.fold((_) {}, (e) => actionError = e.message);
    // Wait up to about 12 seconds for the supervisor to rebind the UDS.
    for (var i = 0; i < 12; i++) {
      if (await _supervisor.isOnline()) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    busyAll = false;
    _notify();
    await reload();
  }

  /// Rename an agent and restart its daemon to apply the new `agent_name`.
  ///
  /// Returns whether the name was saved, even if the subsequent restart fails.
  Future<bool> rename(DaemonInfo daemon, String name) async {
    if (_busy.contains(daemon.id)) return false;
    _busy.add(daemon.id);
    actionError = null;
    _notify();
    final result = await _supervisor.setAgentName(daemon.cwd, name);
    final ok = result.fold((_) => true, (e) {
      actionError = e.message;
      return false;
    });
    if (ok) {
      // Restart so the live process adopts the new name.
      final restart = await _supervisor.restart(daemon.id);
      restart.fold(
        (_) {},
        (e) => actionError = 'Name saved, but failed to restart: ${e.message}',
      );
    }
    _busy.remove(daemon.id);
    _notify();
    await reload();
    return ok;
  }

  /// Create and register a daemon for [cwd], reporting whether it succeeded.
  Future<bool> create(String cwd, {String? name}) async {
    actionError = null;
    _notify();
    final result = await _supervisor.create(cwd, name: name);
    final ok = result.fold((_) => true, (e) {
      actionError = e.message;
      return false;
    });
    if (ok) await reload();
    return ok;
  }

  Future<void> _action(
    String id,
    Future<Result<void, DaemonError>> Function() op,
  ) async {
    if (_busy.contains(id)) return;
    _busy.add(id);
    actionError = null;
    _notify();
    final result = await op();
    result.fold((_) {}, (e) => actionError = e.message);
    _busy.remove(id);
    _notify();
    await reload();
  }

  Future<void> _globalAction(
    Future<Result<void, DaemonError>> Function() op,
  ) async {
    if (busyAll) return;
    busyAll = true;
    actionError = null;
    _notify();
    final result = await op();
    result.fold((_) {}, (e) => actionError = e.message);
    busyAll = false;
    _notify();
    await reload();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
