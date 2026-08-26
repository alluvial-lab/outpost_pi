import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/core/domain/contracts/state_store.dart';

/// Persist project records through the shared state-store boundary.
final class JsonProjectRepository implements ProjectRepository {
  JsonProjectRepository(this._store);

  /// Named state document containing projects and the last selection.
  static const String storeName = 'projects';

  static const String _lastSelectedKey = '__last_selected__';

  final StateStore _store;

  @override
  Future<List<Project>> all() async {
    final projects = _store.values
        .whereType<Map<dynamic, dynamic>>()
        .map(_fromMap)
        .whereType<Project>()
        .toList();
    projects.sort((Project a, Project b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return projects;
  }

  @override
  Future<void> save(Project project) => _store.put(project.id, _toMap(project));

  @override
  Future<void> remove(String id) => _store.delete(id);

  @override
  Future<String?> loadLastSelected() async {
    final value = _store.get(_lastSelectedKey);
    return value is String ? value : null;
  }

  @override
  Future<void> saveLastSelected(String? id) => id == null
      ? _store.delete(_lastSelectedKey)
      : _store.put(_lastSelectedKey, id);

  Map<String, Object?> _toMap(Project project) => <String, Object?>{
    'id': project.id,
    'name': project.name,
    'path': project.path,
    'color': project.colorValue,
    'createdAt': project.createdAt.millisecondsSinceEpoch,
    'order': project.order,
    'image': project.imagePath,
  };

  Project? _fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'];
    final path = map['path'];
    if (id is! String || path is! String) return null;
    try {
      return Project(
        id: id,
        name: map['name'] is String ? map['name'] as String : path,
        path: path,
        colorValue: map['color'] is num
            ? (map['color'] as num).toInt()
            : 0xFF2F6FF0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['createdAt'] is num ? (map['createdAt'] as num).toInt() : 0,
        ),
        order: map['order'] is num ? (map['order'] as num).toInt() : 0,
        imagePath: map['image'] is String ? map['image'] as String : null,
      );
    } on ArgumentError {
      return null;
    }
  }
}
