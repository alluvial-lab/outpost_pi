import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Categorize scrubbed file-backed debug-log failures.
enum _DebugLogFailure { load, log, export, clear, dispose, flush }

final class _DebugLine {
  const _DebugLine(this.encoded, this.byteLength);

  final String encoded;
  final int byteLength;
}

/// File-backed [DebugLog].
///
/// A bounded in-memory ring (capped at [_maxBytes]) written to a jsonl file in
/// `getApplicationDocumentsDirectory()`, so it survives reboot and logcat
/// buffer rollover. During asynchronous warm loading, new admissions wait in a
/// bounded side queue and merge after file rows to preserve chronology. Each
/// line matches the extension's `audit.jsonl` shape so a single message id greps
/// across all three sides.
///
/// **Snapshot-write model.** The file is an atomic snapshot of the capped
/// in-memory ring — every flush overwrites the file with the current capped
/// `_ring` (NOT append-only). This keeps the on-disk retention bounded by the
/// same cap as the in-memory ring; evicted lines never persist on disk. The
/// in-memory `_ring` is the source of truth after warm loading; the bounded
/// pre-load admission queue exists only to preserve file-before-live order.
///
/// **Flush policy.** Critical events (the [kImmediateFlushTags] set — the
/// crash-reconnect tail events) flush immediately; routine events debounce
/// [_flushInterval]. One dirty-latched flush drain serializes writes and
/// coalesces overlapping requests: events admitted after a snapshot begins are
/// covered by one trailing snapshot instead of one queued write per event.
/// Because [Service.dispose] returns `void`, the final flush is fire-and-forget.
/// Critical events START a flush immediately on `log()` and usually survive
/// normal teardown, but crash/process-kill durability is best-effort until a
/// caller awaits a flush.
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
  static int _nextWriterId = 0;
  static final Set<String> _activeTempPaths = <String>{};

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

  /// FIFO of encoded jsonl lines and their retained byte ownership. The queue
  /// makes oldest-line eviction constant-time; [_retainedBytes] avoids a full
  /// UTF-8 recount on every admission.
  final Queue<_DebugLine> _ring = Queue<_DebugLine>();
  final Queue<_DebugLine> _pendingAdmissions = Queue<_DebugLine>();
  final int _writerId = _nextWriterId++;
  int _retainedBytes = 0;
  int _pendingAdmissionBytes = 0;
  bool _loaded = false;

  Timer? _flushTimer;
  bool _disposed = false;
  bool _flushDirty = false;
  String? _filePath;

  /// Active clear barrier. A flush requested while the file is being wiped
  /// waits here, then snapshots events admitted after the clear linearized.
  Future<void>? _clearFuture;

  /// Shared load future: concurrent callers (log/export/clear) await the SAME
  /// load, so a critical `log()` during the first load can't race a half-set
  /// `_filePath` (review Important — _ensureLoaded reentrancy).
  Future<void>? _loadFuture;

  /// The active coalesced flush drain. It remains active through any trailing
  /// snapshot requested while an earlier snapshot write is in flight.
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

  /// Test barrier invoked after each snapshot is captured but before its write.
  /// Tests use explicit started/release completers to exercise interleavings.
  @visibleForTesting
  Future<void> Function()? beforeSnapshotWriteForTesting;

  /// Test barrier invoked after export's force-flush and before its file read.
  @visibleForTesting
  Future<void> Function()? beforeExportReadForTesting;

  /// Test barrier invoked after the temp snapshot is durable but before commit.
  @visibleForTesting
  Future<void> Function()? beforeSnapshotCommitForTesting;

  int _snapshotWriteCount = 0;

  /// Test seam: number of completed snapshot writes by this logger instance.
  @visibleForTesting
  int get snapshotWriteCountForTesting => _snapshotWriteCount;

  Future<void> _ensureLoaded() {
    // Concurrent callers share the same load future; _filePath is set only
    // after resolution, so a concurrent log()/flush() sees a consistent state.
    if (_loaded) return Future<void>.value();
    if (_loadFuture != null) return _loadFuture!;
    _loadFuture = _doLoad().catchError((Object _) {
      _safeLog(_DebugLogFailure.load);
      // Keep pre-load admissions buffered so a later call can retry without
      // reversing their chronology against rows from the file.
      _loadFuture = null;
    });
    return _loadFuture!;
  }

  Future<void> _doLoad() async {
    final dir = await getApplicationDocumentsDirectory();
    _filePath = '${dir.path}/outpost_pi_debug.jsonl';
    final file = File(_filePath!);
    final loadedLines = <String>[];
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
        loadedLines.add(line);
      }
    }

    // File rows precede events admitted while the asynchronous load was in
    // flight. Apply both sequences only after the file has been read so the
    // first live event cannot become older than warm rows.
    for (final line in loadedLines) {
      _append(line);
    }
    while (_pendingAdmissions.isNotEmpty) {
      final line = _pendingAdmissions.removeFirst();
      _pendingAdmissionBytes -= line.byteLength;
      _append(line.encoded);
    }
    _loaded = true;
    await _sweepStaleTemps(_filePath!);
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
      if (_loaded) {
        _append(line); // cap-on-append: never overshoot between flushes
      } else {
        _appendPending(line);
        // log() is synchronous, so buffer this admission while the shared load
        // future establishes the file chronology. Steady-state logs take the
        // branch above and never await or enqueue behind I/O.
        unawaited(_ensureLoaded());
      }
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
      final readBarrier = beforeExportReadForTesting;
      if (readBarrier != null) await readBarrier();
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
      // Acquire the clear boundary only when neither a prior clear nor a flush
      // drain is active. Re-check after every await because a log callback may
      // have started a new drain before this continuation resumed.
      while (true) {
        final activeClear = _clearFuture;
        if (activeClear != null) {
          await activeClear.catchError((Object _, StackTrace _) {});
          continue;
        }
        final activeFlush = _flushFuture;
        if (activeFlush != null) {
          await activeFlush.catchError((Object _, StackTrace _) {});
          continue;
        }
        break;
      }

      final clearCompleter = Completer<void>();
      _clearFuture = clearCompleter.future;
      try {
        _ring.clear();
        _retainedBytes = 0;
        _pendingAdmissions.clear();
        _pendingAdmissionBytes = 0;
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            await file.writeAsString('');
          }
        }
      } finally {
        if (identical(_clearFuture, clearCompleter.future)) {
          _clearFuture = null;
        }
        clearCompleter.complete();
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

  /// Start or join the coalesced flush drain.
  ///
  /// Every request marks the ring dirty. If a snapshot is already being
  /// written, the active drain observes that dirty bit and writes one trailing
  /// snapshot containing all events admitted during the in-flight write.
  Future<void> _flushNow() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushDirty = true;

    final active = _flushFuture;
    if (active != null) return active;

    final completer = Completer<void>();
    _flushFuture = completer.future;
    unawaited(_drainFlushes(completer));
    return completer.future;
  }

  Future<void> _drainFlushes(Completer<void> completer) async {
    try {
      await _ensureLoaded();
      while (_flushDirty) {
        // A post-clear event must not race the empty-file write. Waiting before
        // clearing dirty lets every event admitted during the wait join the next
        // snapshot rather than forcing a redundant trailing write.
        final activeClear = _clearFuture;
        if (activeClear != null) {
          await activeClear.catchError((Object _, StackTrace _) {});
          continue;
        }

        _flushDirty = false;
        final path = _filePath;
        if (path == null || _ring.isEmpty) continue;

        final snapshot = '${_ring.map((line) => line.encoded).join('\n')}\n';
        try {
          final barrier = beforeSnapshotWriteForTesting;
          if (barrier != null) await barrier();
          await _writeSnapshotAtomically(path, snapshot);
          _snapshotWriteCount += 1;
        } catch (_) {
          _safeLog(_DebugLogFailure.flush);
        }
      }
    } catch (_) {
      _flushDirty = false;
      _safeLog(_DebugLogFailure.flush);
    } finally {
      // The loop-exit check and future release share one async continuation,
      // leaving no gap where a new dirty request can join a drain that has
      // already decided to stop.
      if (identical(_flushFuture, completer.future)) {
        _flushFuture = null;
      }
      completer.complete();
    }
  }

  /// Replace the exported file without exposing its truncate/write window.
  Future<void> _writeSnapshotAtomically(String path, String snapshot) async {
    final tempPath = '$path.tmp.$_writerId';
    final tempFile = File(tempPath);
    _activeTempPaths.add(tempPath);
    try {
      await tempFile.writeAsString(snapshot, flush: true);
      final commitBarrier = beforeSnapshotCommitForTesting;
      if (commitBarrier != null) await commitBarrier();
      await tempFile.rename(path);
    } finally {
      _activeTempPaths.remove(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Remove crash-orphaned sibling snapshots without touching an active write.
  Future<void> _sweepStaleTemps(String path) async {
    final prefix = '$path.tmp.';
    try {
      await for (final entry in Directory(File(path).parent.path).list()) {
        if (entry is! File || !entry.path.startsWith(prefix)) continue;
        if (_activeTempPaths.contains(entry.path)) continue;
        try {
          await entry.delete();
        } catch (_) {
          // Cleanup is best-effort; a permissions race must not break loading.
        }
      }
    } catch (_) {
      // The canonical load path remains usable even if directory cleanup fails.
    }
  }

  /// Buffer one line until warm loading has established file-before-live order.
  void _appendPending(String encoded) {
    final line = _DebugLine(encoded, utf8.encode(encoded).length + 1);
    _pendingAdmissions.addLast(line);
    _pendingAdmissionBytes += line.byteLength;
    while (_pendingAdmissionBytes > _maxBytes &&
        _pendingAdmissions.isNotEmpty) {
      _pendingAdmissionBytes -= _pendingAdmissions.removeFirst().byteLength;
    }
  }

  /// Admit one encoded line and evict oldest entries until the byte cap holds.
  void _append(String encoded) {
    final line = _DebugLine(encoded, utf8.encode(encoded).length + 1);
    _ring.addLast(line);
    _retainedBytes += line.byteLength;
    _truncate();
  }

  void _truncate() {
    while (_retainedBytes > _maxBytes && _ring.isNotEmpty) {
      _retainedBytes -= _ring.removeFirst().byteLength;
    }
  }

  /// Emit a fixed failure category without exception details or stack traces.
  void _safeLog(_DebugLogFailure failure) {
    debugPrint('[debug-log] ${failure.name} failed');
  }
}
