/// Uma pasta que o usuário salvou como projeto (workspace). Persistido via Hive.
/// Agentes do Cockpit atuam em subpastas de [path].
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.path,
    required this.colorValue,
    required this.createdAt,
  });

  final String id;

  /// Nome de exibição (por padrão, o basename de [path]).
  final String name;

  /// Caminho absoluto da raiz do projeto.
  final String path;

  /// Cor do avatar (ARGB), atribuída na criação.
  final int colorValue;

  final DateTime createdAt;

  /// Inicial pro avatar da rail.
  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  Project copyWith({String? name, int? colorValue}) => Project(
    id: id,
    name: name ?? this.name,
    path: path,
    colorValue: colorValue ?? this.colorValue,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) => other is Project && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
