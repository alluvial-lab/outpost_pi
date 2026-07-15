import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/entities/session_info.dart';

/// Read saved Pi sessions from `~/.pi/agent/sessions/<encoded-cwd>/`.
///
/// Uses the same directory encoding as Pi's core session manager: remove the
/// leading separator, replace `/`, `\`, and `:` with `-`, then wrap the result
/// in `--…--` (for example, `/Users/jacob/app` becomes
/// `--Users-jacob-app--`, and `R:\code\orbe` becomes `--R-code-orbe--`). Each
/// `.jsonl` file is one session.
class SessionHistoryImpl implements SessionHistory {
  const SessionHistoryImpl();

  @override
  Future<List<SessionInfo>> sessionsFor(
    String cwd, {
    bool withTitle = false,
  }) async {
    final dir = Directory('${_sessionsRoot()}/${_encode(cwd)}');
    final sessions = <SessionInfo>[];
    try {
      if (!await dir.exists()) return const <SessionInfo>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
        final stat = await entity.stat();
        sessions.add(
          SessionInfo(
            path: entity.path,
            id: _idOf(entity.path),
            modifiedAt: stat.modified,
            title: withTitle ? await _titleOf(entity) : null,
          ),
        );
      }
    } catch (_) {
      // Treat invalid or unreadable paths as no sessions instead of crashing.
      return const <SessionInfo>[];
    }
    sessions.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return sessions;
  }

  /// Derive a title from the first user message because Pi stores no session name.
  ///
  /// Reads the `.jsonl` stream line by line and stops at the first `role:user`
  /// message.
  Future<String?> _titleOf(File file) async {
    try {
      final lines = file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.isEmpty || !line.contains('"user"')) continue;
        final Object? obj = jsonDecode(line);
        if (obj is! Map || obj['type'] != 'message') continue;
        final msg = obj['message'];
        if (msg is! Map || msg['role'] != 'user') continue;
        final text = _textOf(
          msg['content'],
        ).trim().replaceAll(RegExp(r'\s+'), ' ');
        if (text.isEmpty) continue;
        return text.length > 100 ? '${text.substring(0, 100)}…' : text;
      }
    } catch (_) {
      // An unreadable or corrupt file has no title.
    }
    return null;
  }

  /// Extract text from message `content`, whether a string or a list of parts.
  String _textOf(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final parts = <String>[];
      for (final p in content) {
        if (p is String) {
          parts.add(p);
        } else if (p is Map && p['type'] == 'text' && p['text'] is String) {
          parts.add(p['text'] as String);
        }
      }
      return parts.join(' ');
    }
    return '';
  }

  String _sessionsRoot() {
    // Windows uses USERPROFILE instead of HOME.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final agentDir =
        Platform.environment['PI_CODING_AGENT_DIR'] ?? '$home/.pi/agent';
    return '$agentDir/sessions';
  }

  /// Encode the working directory as Pi's session folder name.
  ///
  /// Mirrors `core/session-manager.js`:
  /// `--${cwd.replace(/^[/\\]/,'').replace(/[/\\:]/g,'-')}--`. Without this,
  /// raw `:` and `\` characters in Windows paths such as `R:\code` would produce
  /// an invalid directory name.
  String _encode(String cwd) {
    final stripped = cwd.replaceFirst(RegExp(r'^[/\\]'), '');
    final slug = stripped.replaceAll(RegExp(r'[/\\:]'), '-');
    return '--$slug--';
  }

  /// Extract the UUID suffix from `<timestamp>_<uuid>.jsonl`.
  ///
  /// Accepts both `/` and `\` as path separators for Windows compatibility.
  String _idOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last.replaceAll('.jsonl', '');
    final underscore = name.lastIndexOf('_');
    return underscore == -1 ? name : name.substring(underscore + 1);
  }
}
