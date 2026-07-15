import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:hive/hive.dart';

/// Persist each project's layout document as one JSON String in a Hive box.
///
/// Encoding the document as text avoids Hive's nested
/// `Map<dynamic, dynamic>` values and always returns a clean
/// `Map<String, dynamic>` after decoding.
class HiveWorkspaceLayoutStore implements WorkspaceLayoutStore {
  HiveWorkspaceLayoutStore(this._box);

  final Box<dynamic> _box;

  static const String boxName = 'layouts';

  @override
  Future<Map<String, dynamic>?> load(String projectId) async {
    final raw = _box.get(projectId);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null; // Treat a corrupt document as missing.
    }
  }

  @override
  Future<void> save(String projectId, Map<String, dynamic> document) =>
      _box.put(projectId, jsonEncode(document));

  @override
  Future<void> remove(String projectId) => _box.delete(projectId);
}
