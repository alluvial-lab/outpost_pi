import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/core/domain/contracts/state_store.dart';

/// Persist opaque workspace layout documents through a named state store.
final class JsonWorkspaceLayoutStore implements WorkspaceLayoutStore {
  JsonWorkspaceLayoutStore(this._store);

  /// Named state document containing encoded project layouts.
  static const String storeName = 'layouts';

  final StateStore _store;

  @override
  Future<Map<String, dynamic>?> load(String projectId) async {
    final raw = _store.get(projectId);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(String projectId, Map<String, dynamic> document) =>
      _store.put(projectId, jsonEncode(document));

  @override
  Future<void> remove(String projectId) => _store.delete(projectId);
}
