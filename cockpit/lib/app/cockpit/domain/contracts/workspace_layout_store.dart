/// Persist a project's multiplexer layout, including its pane tree and tab
/// descriptors, as an **opaque JSON document** keyed by `projectId`.
///
/// The document's *shape* belongs to `ui/`, which knows `PaneNode` and the
/// sessions. This contract only transports a versioned blob that `data/` stores
/// and returns. It therefore uses `Map<String, dynamic>` instead of a domain
/// type: the store persists content without interpreting it.
abstract class WorkspaceLayoutStore {
  /// Return the project's saved document, or `null` if none was ever saved.
  Future<Map<String, dynamic>?> load(String projectId);

  /// Save, overwriting, the project's [document].
  Future<void> save(String projectId, Map<String, dynamic> document);

  /// Remove the project's document when its project is deleted.
  Future<void> remove(String projectId);
}
