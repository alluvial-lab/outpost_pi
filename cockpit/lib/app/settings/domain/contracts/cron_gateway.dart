import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:cockpit/app/settings/domain/exceptions/daemon_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Control recurring daemon prompts through the supervisor's cron boundary.
///
/// Uses the daemon control-plane UDS (`~/.pi/remote/supervisor.sock`) and
/// `cron_*` operations. The server validates the cron expression, minimum
/// 60-second interval, and supervisor availability, returning failures as
/// [DaemonError].
abstract class CronGateway {
  /// List the cron jobs registered with the supervisor.
  ///
  /// Returns the current jobs on success or a typed supervisor failure.
  Future<Result<List<CronJob>, DaemonError>> listCron();

  /// Register a recurring prompt for a daemon.
  ///
  /// The supervisor validates the schedule and returns validation or control
  /// failures as [DaemonError].
  Future<Result<void, DaemonError>> addCron({
    required String daemonId,
    required String schedule,
    required String prompt,
    String? tz,
    bool skipIfBusy = true,
    bool wake = false,
    bool catchup = false,
  });

  /// Remove a supervisor cron job by its stable job identifier.
  ///
  /// Returns a typed failure when the supervisor rejects the mutation.
  Future<Result<void, DaemonError>> removeCron(String jobId);

  /// Enable or disable a supervisor cron job without replacing its schedule.
  ///
  /// Returns a typed failure when the target or mutation is invalid.
  Future<Result<void, DaemonError>> setCronEnabled(String jobId, bool enabled);

  /// Run a cron job immediately, ignoring its schedule.
  ///
  /// Returns the trigger `result` or a typed supervisor failure.
  Future<Result<String, DaemonError>> runCron(String jobId);

  /// Read `cron.jsonl` history, optionally filtered by job and tail length.
  Future<Result<List<CronLogEntry>, DaemonError>> cronLog({
    String? jobId,
    int? tail,
  });
}
