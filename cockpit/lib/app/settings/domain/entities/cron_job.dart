/// Describe a cron delivery or skip recorded in the supervisor log.
enum CronResult {
  delivered,
  deliverFailed,
  wokeAndDelivered,
  skippedBusy,
  skippedDown,
  skippedDisabled,
  unknown,
}

/// Decode a supervisor cron result without rejecting forward-compatible input.
///
/// Unknown or absent wire values map to [CronResult.unknown].
CronResult cronResultFromWire(String? raw) => switch (raw) {
  'delivered' => CronResult.delivered,
  'deliver_failed' => CronResult.deliverFailed,
  'woke_and_delivered' => CronResult.wokeAndDelivered,
  'skipped_busy' => CronResult.skippedBusy,
  'skipped_down' => CronResult.skippedDown,
  'skipped_disabled' => CronResult.skippedDisabled,
  _ => CronResult.unknown,
};

/// Represent a recurring prompt scheduled for a daemon.
///
/// Mirrors the supervisor's `CronJobView` from `control_protocol.ts`, including
/// its calculated `nextRun`.
class CronJob {
  const CronJob({
    required this.id,
    required this.daemonId,
    required this.schedule,
    required this.prompt,
    required this.enabled,
    required this.skipIfBusy,
    required this.wake,
    required this.catchup,
    this.tz,
    this.createdAt,
    this.lastRun,
    this.lastStatus,
    this.nextRun,
  });

  final String id; // "j_<rand>"
  final String daemonId; // Eight-hex-character target daemon ID.
  final String schedule; // Cron expression.
  final String prompt;
  final bool enabled;
  final bool skipIfBusy;
  final bool wake;
  final bool catchup;
  final String? tz;
  final String? createdAt; // ISO timestamp.
  final String? lastRun; // ISO timestamp.
  final String? lastStatus; // Latest CronResult as its raw wire value.
  final String? nextRun; // ISO timestamp or null.

  @override
  bool operator ==(Object other) =>
      other is CronJob &&
      other.id == id &&
      other.daemonId == daemonId &&
      other.schedule == schedule &&
      other.prompt == prompt &&
      other.enabled == enabled &&
      other.skipIfBusy == skipIfBusy &&
      other.wake == wake &&
      other.catchup == catchup &&
      other.tz == tz &&
      other.lastRun == lastRun &&
      other.lastStatus == lastStatus &&
      other.nextRun == nextRun;

  @override
  int get hashCode => Object.hash(
    id,
    daemonId,
    schedule,
    prompt,
    enabled,
    skipIfBusy,
    wake,
    catchup,
    tz,
    lastRun,
    lastStatus,
    nextRun,
  );
}

/// Represent one `cron.jsonl` entry for every trigger and skip.
class CronLogEntry {
  const CronLogEntry({
    required this.tsMs,
    required this.jobId,
    required this.daemonId,
    required this.schedule,
    required this.fired,
    required this.result,
    required this.promptPreview,
  });

  final int tsMs; // epoch ms
  final String jobId;
  final String daemonId;
  final String schedule;
  final bool fired;
  final CronResult result;
  final String promptPreview;
}
