import 'package:cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/domain/entities/project.dart';
import 'package:hive/hive.dart';

/// Persiste projetos numa Box do Hive, um `Map` por id (sem TypeAdapters —
/// só tipos primitivos, então não precisa de code-gen).
class HiveProjectRepository implements ProjectRepository {
  HiveProjectRepository(this._box);

  /// Box aberta no bootstrap (`config/`). Guarda `Map` por `project.id`.
  final Box<dynamic> _box;

  static const String boxName = 'projects';

  @override
  Future<List<Project>> all() async {
    final projects = _box.values
        .whereType<Map<dynamic, dynamic>>()
        .map(_fromMap)
        .whereType<Project>()
        .toList();
    projects.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return projects;
  }

  @override
  Future<void> save(Project project) => _box.put(project.id, _toMap(project));

  @override
  Future<void> remove(String id) => _box.delete(id);

  Map<String, dynamic> _toMap(Project p) => <String, dynamic>{
    'id': p.id,
    'name': p.name,
    'path': p.path,
    'color': p.colorValue,
    'createdAt': p.createdAt.millisecondsSinceEpoch,
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
    );
  }
}
