import 'package:cockpit/app/cockpit/domain/entities/session_info.dart';

/// List Pi's saved sessions for a folder.
///
/// The `data/` implementation reads
/// `~/.pi/agent/sessions/<cwd-codificado>/`.
abstract class SessionHistory {
  /// Return sessions for [cwd] from newest to oldest.
  ///
  /// When [withTitle] is `true`, also read the beginning of each `.jsonl` to
  /// derive its title from the first user message. This costs extra I/O, so hot
  /// capture and baseline paths leave it disabled.
  Future<List<SessionInfo>> sessionsFor(String cwd, {bool withTitle = false});
}
