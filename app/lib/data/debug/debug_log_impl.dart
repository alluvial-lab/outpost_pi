import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Categorize scrubbed file-backed debug-log failures.
enum _DebugLogFailure { load, log, export, clear, dispose, flush }

/// File-backed [DebugLog].
///
/// A bounded in-memory ring (capped at [_maxBytes]) written to a jsonl file in
/// `getApplicationDocumentsDirectory()`, so it survives reboot and logcat
/// buffer rollover. Each line matches the extension's `audit.jsonl` shape so a
/// single message id greps across all three sides.
///
/// **Snapshot-write model.** The file is an atomic snapshot of the capped
/// in-memory ring — every flush overwrites the file with the current capped
/// `_ring` (NOT append-only). This keeps the on-disk retention bounded by the
/// same cap as the in-memory ring; evicted lines never persist on disk. The
/// in-memory `_ring` IS the source of truth for pending state — no separate
/// `_pending` list that could diverge.
///
/// **Flush policy.** Critical events (the [kImmediateFlushTags] set — the
/// crash-reconnect tail events) flush immediately; routine events debounce
/// [_flushInterval]. Flushes are serialized via a [_flushFuture] chain so
/// batches write in call order. Because [Service.dispose] returns `void`, the
/// final flush is fire-and-forget. Critical events START a flush immediately
/// on `log()` and usually survive normal teardown, but crash/process-kill
/// durability is best-effort until a caller awaits a flush.
///
/// **Cap-on-append.** Truncation happens in [log] immediately after encoding,
/// not only on flush — the in-memory ring never overshoots between flushes.
/// Byte accounting is UTF-8 ([utf8.encode]) to match what's written to disk.
///
/// **Export-from-file.** [export] force-flushes, then reads the FILE as the
/// source of truth (line-by-line, skipping unparseable lines), so it recovers
/// on-disk state even if the in-memory ring diverged. Works while debug
/// logging is OFF (reads whatever is on disk).
///
/// **Never throws.** [log]/[export]/[clear]/[dispose] catch `Object,
/// StackTrace` around the entire public body (including the `_debugEnabled()`
/// callback and `jsonEncode`); the flush timer callback catches internally;
/// failures emit a scrubbed `debugPrint('[debug-log] …')` and never rethrow.
/// The logger must not break the app even on platform/quota/permission failure.
class DebugLogImpl implements DebugLog {
  /// Ring buffer capacity. 1 MiB covers ~48h of the expanded capture surface
  /// (state-transition lines, NOT per-token streaming) with headroom.
  static const int _defaultMaxBytes = 1 << 20; // 1 MiB

  /// Worst-case unflushed tail on a crash for ROUTINE events. Critical events
  /// bypass this and flush immediately (see [kImmediateFlushTags]).
  static const Duration _flushInterval = Duration(seconds: 2);

  /// Critical events that flush immediately — the crash-reconnect tail.
  /// Expanded per review v2 #2 to match the capture surface.
  static const Set<DebugTag> kImmediateFlushTags = {
    DebugTag.msgSend,
    DebugTag.msgFailed,
    DebugTag.sendQueue,
    DebugTag.route,
    DebugTag.sessionGate,
    DebugTag.sessionSync,
    DebugTag.connStatus,
    DebugTag.connChannelLost,
    DebugTag.connHydrate,
    DebugTag.workingConv,
    DebugTag.roomSnapshot,
  };

  /// Ring of jsonl lines (each already-encoded string). The single source of
  /// truth for both in-memory state and pending flushes — no separate `_pending`
  /// list, so the ring and the disk snapshot can't diverge.
  final List<String> _ring = [];

  Timer? _flushTimer;
  bool _disposed = false;
  String? _filePath;

  /// Shared load future: concurrent callers (log/export/clear) await the SAME
  /// load, so a critical `log()` during the first load can't race a half-set
  /// `_filePath` (review Important — _ensureLoaded reentrancy).
  Future<void>? _loadFuture;

  /// Serialized flushes: each flush awaits the previous, so batches write in
  /// call order and never reorder (review Important — concurrent flushes).
  Future<void>? _flushFuture;

  /// Returns whether debug logging is enabled. Injected (reads `Preferences`)
  /// so the hot path does no I/O. When false, [log] is a no-op.
  final bool Function() _debugEnabled;

  DebugLogImpl({bool Function()? debugEnabled})
    : _debugEnabled = debugEnabled ?? (() => false),
      _maxBytesOverride = null;

  /// Test seam: override the byte cap to exercise truncation cheaply.
  @visibleForTesting
  DebugLogImpl.withMaxBytesForTest({
    required bool Function() debugEnabled,
    required int maxBytes,
  }) : _debugEnabled = debugEnabled,
       _maxBytesOverride = maxBytes;

  int get _maxBytes => _maxBytesOverride ?? _defaultMaxBytes;
  final int? _maxBytesOverride;

  /// Test seam: the in-flight flush future (or null if no flush is pending).
  /// Lets tests prove `clear()` awaits an in-flight flush before wiping.
  @visibleForTesting
  Future<void>? get pendingFlush => _flushFuture;

  /// Test seam: delay injected before each snapshot write, so tests can
  /// deterministically hold a flush in-flight (proving clear() awaits it).
  /// Null in production.
  @visibleForTesting
  Duration? flushDelayForTesting;

  Future<void> _ensureLoaded() {
    // Concurrent callers share the same load future; _filePath is set only
    // after resolution, so a concurrent log()/flush() sees a consistent state.
    if (_loadFuture != null) return _loadFuture!;
    _loadFuture = _doLoad().catchError((Object _) {
      _safeLog(_DebugLogFailure.load);
      // Allow a retry on a later call if this load failed.
      _loadFuture = null;
    });
    return _loadFuture!;
  }

  Future<void> _doLoad() async {
    final dir = await getApplicationDocumentsDirectory();
    _filePath = '${dir.path}/outpost_pi_debug.jsonl';
    final file = File(_filePath!);
    if (await file.exists()) {
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.isEmpty) continue;
        // Skip unparseable lines (corrupt tail from a crash) — never throw.
        // Skip legacy lines carrying forbidden keys (written before a key
        // became forbidden): drop at the egress boundary, never scrub.
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map &&
              decoded.keys.any(kForbiddenDiagnosticKeys.contains)) {
            continue;
          }
        } catch (_) {
          continue;
        }
        _ring.add(line);
      }
      _truncate();
    }
  }

  @override
  void log(DebugEvent event) {
    // Wrap the whole public body — a throwing _debugEnabled() callback or an
    // unexpected internal fault must never escape to the caller (review
    // Important — log() can throw if the callback throws).
    try {
      if (_disposed) return;
      if (!_debugEnabled()) return; // no-op when debug logging is OFF
      final line = jsonEncode(event.toJson());
      _ring.add(line);
      _truncate(); // cap-on-append: never overshoot between flushes
      if (kImmediateFlushTags.contains(event.tag)) {
        // Critical event: flush now so a crash doesn't lose the diagnostic tail.
        // ignore: discarded_futures
        _scheduleFlushNow();
      } else {
        _scheduleDebouncedFlush();
      }
    } catch (_) {
      _safeLog(_DebugLogFailure.log);
    }
  }

  @override
  Future<String?> export() async {
    try {
      await _ensureLoaded();
      await _flushNow(); // force-flush so the file is current
      final path = _filePath;
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      // Read the FILE as source of truth, line-by-line, skipping corrupt lines
      // (review F2 — export-from-file). Recovers on-disk state even if the
      // in-memory ring diverged.
      final lines = <String>[];
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map &&
              decoded.keys.any(kForbiddenDiagnosticKeys.contains)) {
            continue;
          }
        } catch (_) {
          continue;
        }
        lines.add(line);
      }
      if (lines.isEmpty) return null;
      return lines.join('\n');
    } catch (_) {
      _safeLog(_DebugLogFailure.export);
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      // Cancel the debounced timer so a pending routine flush doesn't fire
      // after we wipe. (Critical events already triggered immediate flushes
      // that may be in flight — those are serialized below.)
      _flushTimer?.cancel();
      _flushTimer = null;
      await _ensureLoaded();
      final path = _filePath;
      // Serialize against any in-flight flush: a stale snapshot write captured
      // before clear() must complete (or be superseded) before we wipe, or it
      // could resurrect the cleared logs by writing the old snapshot AFTER
      // clear() emptied the file (review v2 Blocker).
      final prev = _flushFuture;
      if (prev != null) {
        await prev.catchError((Object _, StackTrace _) {});
      }
      _ring.clear();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.writeAsString('');
        }
      }
    } catch (_) {
      _safeLog(_DebugLogFailure.clear);
    }
  }

  @override
  void dispose() {
    try {
      _disposed = true;
      _flushTimer?.cancel();
      _flushTimer = null;
      // Best-effort final flush. `Service.dispose()` returns `void`, so the
      // flush is fire-and-forget — the OS gives the process a moment to finish
      // on normal teardown. Critical events already flushed immediately on
      // `log()`; routine events logged right before teardown may not finish.
      // ignore: discarded_futures
      _flushNow();
    } catch (_) {
      _safeLog(_DebugLogFailure.dispose);
    }
  }

  void _scheduleDebouncedFlush() {
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(_flushInterval, () {
      // ignore: discarded_futures
      _flushNow();
    });
  }

  void _scheduleFlushNow() {
    // ignore: discarded_futures
    _flushNow();
  }

  /// Serialize flushes: each awaits the previous so batches write in call
  /// order and never reorder. Writes the capped `_ring` as an atomic snapshot
  /// (overwrite), not append — so on-disk retention is bounded by [_maxBytes].
  Future<void> _flushNow() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _ensureLoaded();
    final path = _filePath;
    if (path == null) return;
    // Chain onto any in-flight flush so writes are ordered.
    final prev = _flushFuture ?? Future<void>.value();
    final thisFlush = prev.then((_) async {
      try {
        final file = File(path);
        // Snapshot the capped ring. If the ring is empty, leave any existing
        // file (a clear() already wiped it); only write if there's content.
        if (_ring.isEmpty) return;
        final snapshot = '${_ring.join('\n')}\n';
        // Test seam: hold the flush in-flight so tests can prove clear()
        // awaits it. No-op in production.
        final delay = flushDelayForTesting;
        if (delay != null) await Future<void>.delayed(delay);
        await file.writeAsString(snapshot, flush: true);
      } catch (_) {
        _safeLog(_DebugLogFailure.flush);
      }
    });
    _flushFuture = thisFlush;
    try {
      await thisFlush;
    } finally {
      // Clear our future only if no later caller chained onto it.
      if (identical(_flushFuture, thisFlush)) {
        _flushFuture = null;
      }
    }
  }

  /// Truncate oldest lines until under [_maxBytes], using UTF-8 byte length to
  /// match what's written to disk (review Nit — byte accounting).
  void _truncate() {
    var size = _ring.fold<int>(
      0,
      (sum, line) => sum + utf8.encode(line).length + 1,
    );
    while (size > _maxBytes && _ring.isNotEmpty) {
      final removed = _ring.removeAt(0);
      size -= utf8.encode(removed).length + 1;
    }
  }

  /// Emit a fixed failure category without exception details or stack traces.
  void _safeLog(_DebugLogFailure failure) {
    debugPrint('[debug-log] ${failure.name} failed');
  }
}
