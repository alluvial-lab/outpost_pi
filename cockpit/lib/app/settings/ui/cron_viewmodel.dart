import 'package:cockpit/app/settings/domain/contracts/cron_gateway.dart';
import 'package:cockpit/app/settings/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:cockpit/app/settings/domain/exceptions/daemon_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

/// Describe the schedule list's load lifecycle.
enum CronLoad { idle, loading, ready, error }

/// Manage the **Schedules** tab's cron jobs and daemon lookup list.
///
/// Uses the daemon UDS control plane, loads on demand, and reloads after each
/// mutation so displayed state converges with the supervisor.
class CronViewModel extends ChangeNotifier {
  CronViewModel(this._cron, this._supervisor);

  final CronGateway _cron;
  final DaemonSupervisor _supervisor;

  CronLoad load = CronLoad.idle;
  bool online = false;
  List<CronJob> jobs = const <CronJob>[];
  List<DaemonInfo> daemons = const <DaemonInfo>[];
  String? error; // Failure while listing jobs.
  String? actionError; // Failure from the most recent action.

  final Set<String> _busy = <String>{};

  bool _disposed = false;

  bool isBusy(String id) => _busy.contains(id);
  bool get anyBusy => _busy.isNotEmpty;
  bool get hasDaemons => daemons.isNotEmpty;

  /// Poll for updates only while idle, without flashing the first-load spinner.
  Future<void> refreshQuiet() async {
    if (anyBusy || load == CronLoad.loading) return;
    await reload();
  }

  /// Resolve a job's target daemon name, falling back to its ID.
  String daemonName(String daemonId) {
    for (final d in daemons) {
      if (d.id == daemonId) return d.name.isEmpty ? d.id : d.name;
    }
    return daemonId;
  }

  /// Reload supervisor reachability, daemons, and scheduled jobs.
  ///
  /// An offline supervisor produces a ready empty snapshot; cron-list failures
  /// publish [CronLoad.error]. Notifications after disposal are suppressed.
  Future<void> reload() async {
    load = CronLoad.loading;
    error = null;
    _notify();

    online = await _supervisor.isOnline();
    if (!online) {
      jobs = const <CronJob>[];
      daemons = const <DaemonInfo>[];
      load = CronLoad.ready;
      _notify();
      return;
    }

    final daemonsResult = await _supervisor.list();
    daemonsResult.fold((d) => daemons = d, (_) {});

    final jobsResult = await _cron.listCron();
    jobsResult.fold(
      (j) {
        jobs = j;
        load = CronLoad.ready;
      },
      (e) {
        error = e.message;
        load = CronLoad.error;
      },
    );
    _notify();
  }

  /// Set whether [job] is enabled, exposing per-job busy and failure state.
  ///
  /// Reloads the schedule snapshot after the gateway returns.
  Future<void> setEnabled(CronJob job, bool enabled) =>
      _action(job.id, () => _cron.setCronEnabled(job.id, enabled));

  /// Remove [job], exposing per-job busy and failure state.
  ///
  /// Reloads the schedule snapshot after the gateway returns.
  Future<void> remove(CronJob job) =>
      _action(job.id, () => _cron.removeCron(job.id));

  /// Run [job] immediately, exposing per-job busy and failure state.
  ///
  /// Normalizes the gateway result and reloads the schedule snapshot afterward.
  Future<void> run(CronJob job) => _action(job.id, () async {
    final r = await _cron.runCron(job.id);
    return r.fold(
      (_) => const Success<void, DaemonError>(null),
      (e) => Failure<void, DaemonError>(e),
    );
  });

  /// Create a job and return whether the dialog may close.
  ///
  /// Successful creation reloads the schedule snapshot.
  Future<bool> create({
    required String daemonId,
    required String schedule,
    required String prompt,
    String? tz,
    bool skipIfBusy = true,
    bool wake = false,
    bool catchup = false,
  }) async {
    actionError = null;
    _notify();
    final result = await _cron.addCron(
      daemonId: daemonId,
      schedule: schedule,
      prompt: prompt,
      tz: tz,
      skipIfBusy: skipIfBusy,
      wake: wake,
      catchup: catchup,
    );
    final ok = result.fold((_) => true, (e) {
      actionError = e.message;
      return false;
    });
    if (ok) await reload();
    return ok;
  }

  /// Fetch `cron.jsonl`, returning `null` and setting [actionError] on failure.
  Future<List<CronLogEntry>?> fetchLog({String? jobId}) async {
    final result = await _cron.cronLog(jobId: jobId, tail: 50);
    return result.fold((list) => list, (e) {
      actionError = e.message;
      _notify();
      return null;
    });
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
