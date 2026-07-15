import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Build the Windows supervisor named-pipe path.
///
/// Mirrors `pi-extension/src/session/ipc.ts`:
/// `\\.\pipe\outpost-pi-supervisor-<user>`, with the username sanitized by
/// replacing `[^A-Za-z0-9_.-]` with `_`.
String supervisorPipeName() {
  final raw = Platform.environment['USERNAME'] ?? 'user';
  final user = raw.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return r'\\.\pipe\outpost-pi-supervisor-' + (user.isEmpty ? 'user' : user);
}

/// Perform one complete transaction over a Windows named pipe.
///
/// Connects, writes [requestLine] (which must end in `\n`), reads one reply
/// line, and closes the pipe. Returns the line without `\n`, or `null` when the
/// supervisor is offline, an operation fails, or the deadline expires.
///
/// Blocking FFI calls run in [Isolate.run] to keep the UI responsive. Only
/// sendable strings cross the isolate boundary.
Future<String?> winPipeTransact(
  String pipeName,
  String requestLine, {
  Duration timeout = const Duration(seconds: 6),
}) {
  final deadlineMs = timeout.inMilliseconds;
  return Isolate.run(() => _transactSync(pipeName, requestLine, deadlineMs));
}

/// Run the synchronous, blocking Win32 transaction inside the isolate.
String? _transactSync(String pipeName, String requestLine, int deadlineMs) {
  final namePtr = pipeName.toNativeUtf16();
  var handle = INVALID_HANDLE_VALUE;
  final sw = Stopwatch()..start();
  try {
    // Open the pipe, retrying ERROR_PIPE_BUSY until the deadline. win32 5.x
    // does not expose WaitNamedPipe, so use a short manual backoff.
    while (true) {
      handle = CreateFile(
        namePtr,
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        0,
      );
      if (handle != INVALID_HANDLE_VALUE) break;
      final err = GetLastError();
      if (err != ERROR_PIPE_BUSY || sw.elapsedMilliseconds >= deadlineMs) {
        return null; // Offline, missing, or inaccessible.
      }
      sleep(const Duration(milliseconds: 50));
    }

    if (!_writeAll(handle, utf8.encode(requestLine))) return null;
    return _readLine(handle, sw, deadlineMs);
  } finally {
    if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
    calloc.free(namePtr);
  }
}

bool _writeAll(int handle, List<int> bytes) {
  final len = bytes.length;
  final buf = calloc<Uint8>(len);
  final written = calloc<Uint32>();
  try {
    buf.asTypedList(len).setAll(0, bytes);
    var off = 0;
    while (off < len) {
      final ok = WriteFile(
        handle,
        (buf + off).cast(),
        len - off,
        written,
        nullptr,
      );
      if (ok == 0 || written.value == 0) return false;
      off += written.value;
    }
    return true;
  } finally {
    calloc.free(buf);
    calloc.free(written);
  }
}

/// Accumulate pipe bytes through the first `\n`.
///
/// Returns the first line without `\n`, or `null` if the pipe closes first or
/// the deadline expires.
String? _readLine(int handle, Stopwatch sw, int deadlineMs) {
  const chunk = 4096;
  final buf = calloc<Uint8>(chunk);
  final read = calloc<Uint32>();
  final acc = <int>[];
  try {
    while (sw.elapsedMilliseconds < deadlineMs) {
      final ok = ReadFile(handle, buf, chunk, read, nullptr);
      if (ok == 0) return null; // Broken pipe or end of stream.
      final n = read.value;
      if (n == 0) return null;
      final bytes = buf.asTypedList(n);
      for (var i = 0; i < n; i++) {
        if (bytes[i] == 0x0A) {
          return utf8.decode(acc, allowMalformed: true);
        }
        acc.add(bytes[i]);
      }
    }
    return null;
  } finally {
    calloc.free(buf);
    calloc.free(read);
  }
}
