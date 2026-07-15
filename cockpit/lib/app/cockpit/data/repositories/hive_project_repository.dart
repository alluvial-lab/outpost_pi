import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:hive/hive.dart';

/// Persist projects in Hive as one primitive-only `Map` per project id.
///
/// Avoids TypeAdapters and generated codecs so legacy primitive maps remain
/// directly readable.
class HiveProjectRepository implements ProjectRepository {
  HiveProjectRepository(this._box);

  /// Use the box opened during bootstrap (`config/`), keyed by `project.id`.
  final Box<dynamic> _box;

  static const String boxName = 'projects';

  /// Reserve a non-Map key for the last selected workspace.
  ///
  /// It cannot collide with absolute-path project ids, and `all()` ignores it
  /// through `whereType<Map>`.
  static const String _lastSelectedKey = '__last_selected__';

  @override
  Future<List<Project>> all() async {
    final projects = _box.values
        .whereType<Map<dynamic, dynamic>>()
        .map(_fromMap)
        .whereType<Project>()
        .toList();
    // Preserve the user's manual drag-and-drop order. Use `createdAt` to break
    // ties and as the fallback for legacy records whose order is always zero.
    projects.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return projects;
  }

  @override
  Future<void> save(Project project) => _box.put(project.id, _toMap(project));

  @override
  Future<void> remove(String id) => _box.delete(id);

  @override
  Future<String?> loadLastSelected() async {
    final v = _box.get(_lastSelectedKey);
    return v is String ? v : null;
  }

  @override
  Future<void> saveLastSelected(String? id) async {
    if (id == null) {
      await _box.delete(_lastSelectedKey);
    } else {
      await _box.put(_lastSelectedKey, id);
    }
  }

  Map<String, dynamic> _toMap(Project p) => <String, dynamic>{
    'id': p.id,
    'name': p.name,
    'path': p.path,
    'color': p.colorValue,
    'createdAt': p.createdAt.millisecondsSinceEpoch,
    'order': p.order,
    'image': p.imagePath,
  };

  Project? _fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'];
    final path = map['path'];
    if (id is! String || path is! String) return null;
    return Project(
      id: id,
      name: map['name'] as String? ?? path,
      path: path,
      colorValue: (map['color'] as num?)?.toInt() ?? 0xFF2F6FF0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
      // Legacy records omit this field; zero falls back to `createdAt` order.
      order: (map['order'] as num?)?.toInt() ?? 0,
      imagePath: map['image'] as String?,
    );
  }
}
