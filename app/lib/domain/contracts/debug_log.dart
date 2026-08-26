import 'package:app/domain/contracts/service.dart';

/// Closed set of wire failure codes admissible into diagnostics.
///
/// Protocol values mirror `knownErrorCode` in
/// `defs/app-pi-common.schema.json`, which is not generated into Dart. Unknown
/// wire values project to [kUnrecognizedFailureCode] rather than entering a
/// diagnostic surface as arbitrary text.
const Set<String> kAdmissibleFailureCodes = {
  // Protocol `knownErrorCode`.
  'tool_approval_required',
  'invalid_message',
  'unsupported_type',
  'too_large',
  'rate_limited',
  'timeout',
  'internal_error',
  'session_mismatch',
  'delivery_pending',
  // App-local codes.
  'send_error',
  'send_timeout',
  'outbox_error',
  'cancelled',
};

/// Fixed diagnostic category for an unrecognized wire failure code.
const String kUnrecognizedFailureCode = 'unrecognized';

/// Admit a failure code into diagnostics only when it belongs to the closed set.
String admitFailureCode(String wireCode) =>
    kAdmissibleFailureCodes.contains(wireCode)
    ? wireCode
    : kUnrecognizedFailureCode;

/// Payload-like keys that must never appear in a persisted or exported
/// diagnostic line. The registry test deny-list and the file-backed log's
/// load/export filters both consume this single set: legacy lines written
/// before a key became forbidden are dropped at every egress boundary rather
/// than scrubbed (content-free by construction).
const Set<String> kForbiddenDiagnosticKeys = {
  'body', 'image', 'data', 'args', 'result', 'prompt', 'message', 'ct',
  'detail', 'err',
  // payload-like aliases:
  'content', 'payload', 'preview', 'summary', 'fullText', 'bodyText', 'raw',
  'toolOutput', 'imageBytes',
};

/// Per-variant tag for a [DebugEvent]. The enum IS the capture surface — a
/// new capture site adds a variant + a tag, not a free-form string.
///
/// Privacy invariant: no variant carries message bodies, previews, image data,
/// tool args/results, server-originated error text, or arbitrary error text.
/// Failure diagnostics admit only closed code sets or fixed categories.
/// Enforced by the registry test (see `story-app-debug-log-adapter`
/// acceptance).
enum DebugTag {
  wsIn,
  peerFrame,
  msgSend,
  msgEcho,
  msgFailed,
  sendQueue,
  route,
  sessionGate,
  sessionSync,
  connStatus,
  // The duplicate-connection-takeover proof: fires on BOTH branches of
  // `connection_manager.dart` `_onChannelLost` (the `identical(cur, ch)`
  // check). `stale=true` = replaced channel's onDone safely ignored;
  // `stale=false` = current channel lost → retry started.
  connChannelLost,
  connHydrate,
  roomSnapshot,
  workingConv,
  replayDedup,
  lifecycleFailure,
  layoutMode,
}

/// Name owner-local async operations without accepting free-form site labels.
enum LifecycleOperation {
  channelClose,
  roomCachePersist,
  legacyRoomPersist,
  retryConnect,
  transcriptWrite,
  runtimeWrite,
  sessionRebind,
  meshPublish,
}

/// Typed diagnostic event. Each variant owns its allowed fields and its scrub.
///
/// Every variant serializes through [toJson]; the registry test asserts no
/// forbidden keys (`body`, `preview`, `image`, `data`, `args`, `result`,
/// `prompt`, `message`, `ct`) and that all string values are capped
/// ([kMaxFieldValueChars]). Field values are primitives only
/// (String/int/bool/null) — never nested objects or untrusted blobs.
sealed class DebugEvent {
  final DebugTag tag;
  final DateTime ts;
  const DebugEvent({required this.tag, required this.ts});

  /// Canonical serializer. Implementations MUST clamp string fields to
  /// [kMaxFieldValueChars] and MUST NOT emit forbidden keys.
  Map<String, Object?> toJson();
}

/// `ws-in` frame demux (transport inbound). No payload — lengths/kinds only.
final class WsInEvent extends DebugEvent {
  final int? bytes;
  final int? count;
  final String? kind; // envelope / control / malformed / dropped
  final String? stage;
  final String? senderRoom;
  final String? controlType;
  final String? error;

  const WsInEvent({
    required super.ts,
    this.bytes,
    this.count,
    this.kind,
    this.stage,
    this.senderRoom,
    this.controlType,
    this.error,
  }) : super(tag: DebugTag.wsIn);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    if (bytes != null) 'bytes': bytes,
    if (count != null) 'count': count,
    if (kind != null) 'kind': _cap(kind!),
    if (stage != null) 'stage': _cap(stage!),
    if (senderRoom != null) 'senderRoom': _cap(senderRoom!),
    if (controlType != null) 'controlType': _cap(controlType!),
    if (error != null) 'error': _cap(error!),
  };
}

/// Peer-channel inner frame drop. No payload — lengths/kinds/reasons only.
final class PeerFrameEvent extends DebugEvent {
  final String kind; // unsupported_type / malformed
  final int bytes;
  final String? error;

  const PeerFrameEvent({
    required super.ts,
    required this.kind,
    required this.bytes,
    this.error,
  }) : super(tag: DebugTag.peerFrame);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'kind': _cap(kind),
    'bytes': bytes,
    if (error != null) 'error': _cap(error!),
  };
}

/// Record outbound user-message correlation metadata without its content.
final class MsgSendEvent extends DebugEvent {
  final String id;
  final bool? blocked;

  const MsgSendEvent({required super.ts, required this.id, this.blocked})
    : super(tag: DebugTag.msgSend);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'id': _cap(id),
    if (blocked != null) 'blocked': blocked,
  };
}

/// Describe the held-send lifecycle without recording message content.
enum SendQueuePhase { held, visibleFail, resend }

/// Describe the outcome of a held-send retry.
enum SendQueueOutcome { sent, failed }

/// Record held, visible-failure, and reconnect-resend transitions by id.
final class SendQueueEvent extends DebugEvent {
  final String id;
  final SendQueuePhase phase;
  final SendQueueOutcome? outcome;
  final String? code;

  const SendQueueEvent({
    required super.ts,
    required this.id,
    required this.phase,
    this.outcome,
    this.code,
  }) : super(tag: DebugTag.sendQueue);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'id': _cap(id),
    'phase': _sendQueuePhaseName(phase),
    if (outcome != null) 'outcome': outcome!.name,
    if (code != null) 'code': admitFailureCode(code!),
  };
}

/// Record session-route entry and the post-hydrate projection state.
enum RoutePhase { entry, projectionReady, projectionEmpty }

/// Record content-free route/projection milestones for blank-chat triage.
final class RouteEvent extends DebugEvent {
  final String room;
  final String? sessionIdTail;
  final RoutePhase phase;
  final int? messageCount;

  const RouteEvent({
    required super.ts,
    required this.room,
    required this.phase,
    this.sessionIdTail,
    this.messageCount,
  }) : super(tag: DebugTag.route);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'room': _cap(room),
    'phase': _routePhaseName(phase),
    if (sessionIdTail != null) 'sessionIdTail': _cap(sessionIdTail!),
    if (messageCount != null) 'messageCount': messageCount,
  };
}

/// Echo of a sent user message (confirms delivery + disarms the send timeout).
final class MsgEchoEvent extends DebugEvent {
  final String id;

  const MsgEchoEvent({required super.ts, required this.id})
    : super(tag: DebugTag.msgEcho);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'id': _cap(id),
  };
}

/// Send-failure surfacing (20s no-echo timeout or cancel). [code] is
/// normalized through [admitFailureCode] at construction so the capture
/// surface is closed-code by construction, not by caller discipline.
final class MsgFailedEvent extends DebugEvent {
  final String id;
  final String? code;

  MsgFailedEvent({required super.ts, required this.id, String? code})
    : code = code == null ? null : admitFailureCode(code),
      super(tag: DebugTag.msgFailed);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'id': _cap(id),
    if (code != null) 'code': _cap(code!),
  };
}

/// Session-gate rejection (`missing_session_id` / `session_mismatch` /
/// `active_session_unknown`).
final class SessionGateEvent extends DebugEvent {
  final String messageType;
  final String reason;
  final String? sessionIdTail;

  const SessionGateEvent({
    required super.ts,
    required this.messageType,
    required this.reason,
    this.sessionIdTail,
  }) : super(tag: DebugTag.sessionGate);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'messageType': _cap(messageType),
    'reason': _cap(reason),
    if (sessionIdTail != null) 'sessionIdTail': _cap(sessionIdTail!),
  };
}

/// `session_sync` request failure.
final class SessionSyncEvent extends DebugEvent {
  const SessionSyncEvent({required super.ts})
    : super(tag: DebugTag.sessionSync);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
  };
}

/// ConnectionManager status transition. `StatusOffline` is not emitted today
/// (left out until/unless the state machine adds it).
final class ConnStatusEvent extends DebugEvent {
  final String status; // connecting / online / retrying
  final int? attempt;
  final int? delayMs;
  final String? peerTail;
  final String? room;

  const ConnStatusEvent({
    required super.ts,
    required this.status,
    this.attempt,
    this.delayMs,
    this.peerTail,
    this.room,
  }) : super(tag: DebugTag.connStatus);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'status': _cap(status),
    if (attempt != null) 'attempt': attempt,
    if (delayMs != null) 'delayMs': delayMs,
    if (peerTail != null) 'peerTail': _cap(peerTail!),
    if (room != null) 'room': _cap(room!),
  };
}

/// Channel-lost transition — the duplicate-connection-takeover proof.
/// `stale=true` (replaced channel's onDone safely ignored) vs `stale=false`
/// (current channel lost → retry started).
enum ReconnectCause {
  unknown,
  channelError,
  channelDone,
  pingSendFailure,
  simulated,
}

/// Channel-lost transition with a closed cause attribution.
final class ConnChannelLostEvent extends DebugEvent {
  final String? peerTail;
  final String? room;
  final bool stale;
  final ReconnectCause cause;

  const ConnChannelLostEvent({
    required super.ts,
    this.peerTail,
    this.room,
    required this.stale,
    this.cause = ReconnectCause.unknown,
  }) : super(tag: DebugTag.connChannelLost);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'stale': stale,
    'cause': cause.name,
    if (peerTail != null) 'peerTail': _cap(peerTail!),
    if (room != null) 'room': _cap(room!),
  };
}

/// Resume hydration (`_replaySubscriptions`).
final class ConnHydrateEvent extends DebugEvent {
  final String action;
  final String? room;
  final int? snapshotCount;

  const ConnHydrateEvent({
    required super.ts,
    required this.action,
    this.room,
    this.snapshotCount,
  }) : super(tag: DebugTag.connHydrate);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'action': _cap(action),
    if (room != null) 'room': _cap(room!),
    if (snapshotCount != null) 'snapshotCount': snapshotCount,
  };
}

/// Room snapshot / announcement adoption.
final class RoomSnapshotEvent extends DebugEvent {
  final String room;
  final int? presenceCount;
  final bool? working;

  const RoomSnapshotEvent({
    required super.ts,
    required this.room,
    this.presenceCount,
    this.working,
  }) : super(tag: DebugTag.roomSnapshot);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'room': _cap(room),
    if (presenceCount != null) 'presenceCount': presenceCount,
    if (working != null) 'working': working,
  };
}

/// `working` state convergence (must converge false after success/error/abort/
/// reconnect/shutdown).
final class WorkingConvEvent extends DebugEvent {
  final String room;
  final bool working;
  final String? reason;

  const WorkingConvEvent({
    required super.ts,
    required this.room,
    required this.working,
    this.reason,
  }) : super(tag: DebugTag.workingConv);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'room': _cap(room),
    'working': working,
    if (reason != null) 'reason': _cap(reason!),
  };
}

/// Replay/backfill dedup (the duplication-bug surface).
final class ReplayDedupEvent extends DebugEvent {
  final String sessionId;

  /// Privacy-safe event-id digest; the wire key retains its legacy name.
  final String? eventIdTail;
  final bool dropped;

  const ReplayDedupEvent({
    required super.ts,
    required this.sessionId,
    this.eventIdTail,
    required this.dropped,
  }) : super(tag: DebugTag.replayDedup);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'sessionId': _cap(sessionId),
    if (eventIdTail != null) 'eventIdTail': _cap(eventIdTail!),
    'dropped': dropped,
  };
}

/// Record a privacy-safe failure at an owner-local async lifecycle boundary.
final class LifecycleFailureEvent extends DebugEvent {
  const LifecycleFailureEvent({
    required super.ts,
    required this.operation,
    required this.reason,
    this.peerTail,
    this.room,
    this.sessionIdTail,
    this.retryScheduled = false,
  }) : super(tag: DebugTag.lifecycleFailure);

  final LifecycleOperation operation;
  final String reason;
  final String? peerTail;
  final String? room;
  final String? sessionIdTail;
  final bool retryScheduled;

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'operation': operation.name,
    'reason': _cap(reason),
    if (peerTail != null) 'peerTail': _cap(peerTail!),
    if (room != null) 'room': _cap(room!),
    if (sessionIdTail != null) 'sessionIdTail': _cap(sessionIdTail!),
    'retryScheduled': retryScheduled,
  };
}

/// Clamp a string field to the adapter's per-field cap. Defined here (domain)
/// so the registry test can reference the constant without importing data.
const int kMaxFieldValueChars = 256;

String _cap(String s) =>
    s.length <= kMaxFieldValueChars ? s : s.substring(0, kMaxFieldValueChars);

String _sendQueuePhaseName(SendQueuePhase phase) => switch (phase) {
  SendQueuePhase.held => 'held',
  SendQueuePhase.visibleFail => 'visible-fail',
  SendQueuePhase.resend => 'resend',
};

String _routePhaseName(RoutePhase phase) => switch (phase) {
  RoutePhase.entry => 'entry',
  RoutePhase.projectionReady => 'projection-ready',
  RoutePhase.projectionEmpty => 'projection-empty',
};

/// Persistent, privacy-scrubbed debug ring log for retroactive diagnosis of
/// intermittent mobile-session bugs.
///
/// Extends [Service] so `addService<DebugLog>` (the disposing DI path) wires
/// `dispose()` → flush on app teardown.
///
/// **Lifecycle.** [log] is an early no-op when debug mode is OFF (checked via
/// the injected `_debugEnabled` callback, which reads `Preferences` — no I/O
/// in the hot path). [export] and [clear] work while OFF (read/wipe whatever
/// is on disk); only NEW capture is gated.
///
/// **Privacy.** Field values are primitives only (String/int/bool/null). The
/// adapter serializes whatever each variant's [DebugEvent.toJson] emits; the
/// per-variant scrub (no body/image/args/result) is enforced by the registry
/// test. Callers pass already-scrubbed fields.
///
/// **Cross-side correlation.** The owner-message id joins the app's
/// `MsgSendEvent.id` / `MsgEchoEvent.id` with the extension's `app
/// user_message id` (`audit.jsonl`) for app↔extension tracing. Sealed owner
/// frames keep that id inside `outer.ct`, so the relay cannot join it; the
/// relay's `env_id_tail` is a separate correlation key for cross-PC
/// `pi_envelope` traffic only.
abstract interface class DebugLog implements Service {
  /// Appends a structured line. Early no-op when debug mode is OFF.
  void log(DebugEvent event);

  /// Force-flush, then read the file (source of truth) line-by-line. Returns
  /// null when empty. Works while debug logging is OFF (reads on-disk state).
  Future<String?> export();

  /// Wipe ring + file. Does NOT clear `Preferences.debugLogging` (the toggle
  /// state is separate from the captured data).
  Future<void> clear();
}

/// Layout-mode transition (two-pane gate). Fired when the shell's two-pane
/// verdict flips, with the metrics that produced it — catches transient
/// misreported window sizes (e.g. Fold display switches) as the field cause
/// of phantom half-screen layouts on phone-class displays.
final class LayoutModeEvent extends DebugEvent {
  const LayoutModeEvent({
    required super.ts,
    required this.twoPane,
    required this.widthDp,
    required this.heightDp,
    required this.shortestSideDp,
    required this.devicePixelRatio,
    this.trigger,
  }) : super(tag: DebugTag.layoutMode);

  final bool twoPane;
  final int widthDp;
  final int heightDp;
  final int shortestSideDp;
  final double devicePixelRatio;
  final String? trigger; // builder / resume / zero-state flip

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'twoPane': twoPane,
    'widthDp': widthDp,
    'heightDp': heightDp,
    'shortestSideDp': shortestSideDp,
    'dpr': devicePixelRatio,
    if (trigger != null) 'trigger': _cap(trigger!),
  };
}

/// Add an awaited teardown boundary to a composition-owned [DebugLog].
abstract interface class DrainableDebugLog implements DebugLog {
  /// Stop new admissions and await the final coalesced file-write drain.
  ///
  /// Completes only after any active/trailing snapshot and temporary-file
  /// cleanup have settled. Safe to call repeatedly.
  Future<void> close();
}
