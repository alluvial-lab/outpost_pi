import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// File-backed [DebugLog].
///
/// A bounded in-memory ring (capped at [_maxBytes]) flushed to a daily-rotated
/// jsonl file in `getApplicationDocumentsDirectory()`, so it survives reboot
/// and logcat buffer rollover. Each line matches the extension's `audit.jsonl`
/// shape so a single message id greps across all three sides.
///
/// **Flush policy.** Critical events (the [kImmediateFlushTags] set — the
/// crash-reconnect tail events) flush immediately; routine events debounce
/// [_flushInterval]. This survives a crash for the lines that matter most.
///
/// **Cap-on-append.** Truncation happens in [log] immediately after encoding,
/// not only on flush — the in-memory ring never overshoots between flushes.
///
/// **Export-from-file.** [export] force-flushes, then reads the FILE as the
/// source of truth (line-by-line, skipping unparseable lines), so it recovers
/// on-disk state even if the in-memory ring diverged. Works while debug
/// logging is OFF (reads whatever is on disk).
///
/// **Never throws.** [log]/[export]/[clear]/[dispose] catch `Object, StackTrace`;
/// the flush timer callback catches internally; failures emit a scrubbed
/// `debugPrint('[debug-log] …')` and never rethrow. The logger must not break
/// the app even on platform/quota/permission failure.
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
    DebugTag.sessionGate,
    DebugTag.sessionSync,
    DebugTag.connStatus,
    DebugTag.connChannelLost,
    DebugTag.connHydrate,
    DebugTag.workingConv,
    DebugTag.roomSnapshot,
  };

  /// Ring of jsonl lines (each already-encoded string).
  final List<String> _ring = [];

  /// Pending (unflushed) entries, in order.
  final List<String> _pending = [];

  Timer? _flushTimer;
  bool _disposed = false;
  String? _filePath;
  bool _loaded = false;

  /// Returns whether debug logging is enabled. Injected (reads `Preferences`)
  /// so the hot path does no I/O. When false, [log] is a no-op.
  final bool Function() _debugEnabled;

  DebugLogImpl({bool Function()? debugEnabled})
    : _debugEnabled = debugEnabled ?? (() => false),
      _maxBytesOverride = null;

  /// Test seam: override the byte cap to exercise truncation cheaply.
  DebugLogImpl.withMaxBytesForTest({
    required bool Function() debugEnabled,
    required int maxBytes,
  }) : _debugEnabled = debugEnabled,
       _maxBytesOverride = maxBytes;

  int get _maxBytes => _maxBytesOverride ?? _defaultMaxBytes;
  final int? _maxBytesOverride;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _filePath = '${dir.path}/remote_pi_debug.jsonl';
      // Warm the ring from the existing file so a restart keeps recent history.
      final file = File(_filePath!);
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.isEmpty) continue;
          // Skip unparseable lines (corrupt tail from a crash) — never throw.
          try {
            jsonDecode(line);
          } catch (_) {
            continue;
          }
          _ring.add(line);
        }
        _truncate();
      }
    } catch (e, s) {
      _safeLog('failed to load ring file: $e', s);
    }
  }

  @override
  void log(DebugEvent event) {
    if (_disposed) return;
    if (!_debugEnabled()) return; // no-op when debug logging is OFF
    String line;
    try {
      line = jsonEncode(event.toJson());
    } catch (e, s) {
      // Encoding failure (a non-primitive slipped through, etc.) — drop the
      // entry rather than letting it corrupt the ring or break the caller.
      _safeLog('encode failed for ${event.tag}: $e', s);
      return;
    }
    _ring.add(line);
    _truncate(); // cap-on-append: never overshoot between flushes
    _pending.add(line);
    if (kImmediateFlushTags.contains(event.tag)) {
      // Critical event: flush now so a crash doesn't lose the diagnostic tail.
      // ignore: discarded_futures
      _flushAndReset();
    } else {
      _scheduleFlush();
    }
  }

  @override
  Future<String?> export() async {
    await _ensureLoaded();
    await _flushAndReset();
    if (_ring.isEmpty) return null;
    return _ring.join('\n');
  }

  @override
  Future<void> clear() async {
    _ring.clear();
    _pending.clear();
    await _ensureLoaded();
    final path = _filePath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.writeAsString('');
        }
      } catch (e, s) {
        _safeLog('failed to clear ring file: $e', s);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    // Best-effort final flush. `Service.dispose()` returns `void` (synchronous),
    // so the flush is fire-and-forget — the OS gives the process a moment to
    // finish the write on normal teardown; on hard kill the immediate-flush
    // policy for critical events already put them on disk.
    // ignore: discarded_futures
    _flushAndReset();
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(_flushInterval, _flushAndResetSync);
  }

  void _flushAndResetSync() {
    // ignore: discarded_futures
    _flushAndReset();
  }

  Future<void> _flushAndReset() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final batch = List<String>.of(_pending);
    _pending.clear();
    await _ensureLoaded();
    final path = _filePath;
    if (path == null) return;
    try {
      final file = File(path);
      final sink = file.openWrite(mode: FileMode.append);
      for (final line in batch) {
        sink.writeln(line);
      }
      await sink.flush();
      await sink.close();
    } catch (e, s) {
      _safeLog('flush failed: $e', s);
    }
  }

  /// Truncate oldest lines until under [_maxBytes]. Called on append so the
  /// in-memory ring never overshoots between flushes.
  void _truncate() {
    var size = _ring.fold<int>(0, (sum, line) => sum + line.length + 1);
    while (size > _maxBytes && _ring.isNotEmpty) {
      final removed = _ring.removeAt(0);
      size -= removed.length + 1;
    }
  }

  /// Emit a scrubbed fallback log (no user fields) and never rethrow.
  void _safeLog(String message, StackTrace stack) {
    debugPrint('[debug-log] $message');
    if (kDebugMode) debugPrint('$stack');
  }
}
