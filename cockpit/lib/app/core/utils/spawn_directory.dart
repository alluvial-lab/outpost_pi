import 'dart:io';

/// The directory selected for a process spawn and the directory requested by
/// the workspace.
final class SpawnDirectory {
  const SpawnDirectory({required this.path, required this.requested});

  /// The existing directory in which the process can start.
  final String path;

  /// The original workspace directory, before recovery.
  final String requested;

  /// Whether the requested non-empty directory was unavailable.
  bool get fellBack => requested.isNotEmpty && path != requested;
}

/// Resolve an existing directory for a shell or process spawn.
///
/// A persisted workspace can outlive its directory. Process creation fails
/// when its working directory is missing, so retain the closest existing
/// ancestor where possible and expose the fallback to the caller instead of
/// silently pretending the workspace still exists.
SpawnDirectory resolveSpawnDirectory(String wanted) {
  final requested = wanted.trim();
  if (requested.isEmpty) {
    return SpawnDirectory(path: _homeOrEmpty(), requested: requested);
  }
  if (Directory(requested).existsSync()) {
    return SpawnDirectory(path: requested, requested: requested);
  }

  var current = Directory(requested).parent;
  while (true) {
    if (current.existsSync()) {
      return SpawnDirectory(path: current.path, requested: requested);
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }

  return SpawnDirectory(path: _homeOrEmpty(), requested: requested);
}

String _homeOrEmpty() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return home.isNotEmpty && Directory(home).existsSync() ? home : '';
}
