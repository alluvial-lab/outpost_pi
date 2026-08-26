import 'package:cockpit/app/cockpit/domain/entities/project.dart';

/// Persist projects and their saved folders.
///
/// Concrete persistence is supplied by the feature's `data/` adapter.
abstract class ProjectRepository {
  /// Return all saved projects from oldest to newest by creation time.
  Future<List<Project>> all();

  /// Create or update [project].
  Future<void> save(Project project);

  /// Remove the project identified by [id].
  Future<void> remove(String id);

  /// Return the last selected workspace ID for the next startup selection.
  ///
  /// Returns `null` when no selection has ever been saved.
  Future<String?> loadLastSelected();

  /// Persist the last selected workspace [id], or clear it when `null`.
  Future<void> saveLastSelected(String? id);
}
