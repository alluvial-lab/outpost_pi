import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';

/// Hold a read-only file-viewer tab for text, Markdown, or images.
///
/// The ViewModel reads and classifies [view] before creating this session;
/// unsupported binary and video content never reaches it.
class FileViewerSession extends PaneItem {
  FileViewerSession({
    required this.id,
    required this.projectId,
    required this.path,
    required this.view,
    this.isPreview = false,
  });

  @override
  final String id;
  @override
  final String projectId;

  /// Track the absolute path as the file is renamed or moved.
  ///
  /// [retarget] mutates this value; the ViewModel then reloads the content and
  /// reattaches its file watcher.
  String path;

  // Derive the title and working directory from the path so renames propagate.
  @override
  String get title => path.split('/').where((p) => p.isNotEmpty).last;
  @override
  String get workingDirectory =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : path;

  /// Retarget the tab after its file is renamed or moved.
  ///
  /// This only changes the path and notifies the UI; the ViewModel reloads the
  /// content and reattaches the watcher.
  void retarget(String newPath) {
    if (newPath == path) return;
    path = newPath;
    notifyListeners();
  }

  /// Hold the current classified content.
  ///
  /// The ViewModel replaces it when the file watcher detects a disk change,
  /// then notifies listeners to rebuild the tab.
  FileView view;

  /// Indicate that the editor contains unsaved changes.
  ///
  /// This drives the tab marker and the close-without-saving dialog.
  /// `FileViewer` updates it through [setDirty].
  bool dirty = false;

  void setDirty(bool value) {
    if (value == dirty) return;
    dirty = value;
    if (value && isPreview) {
      isPreview = false;
    }
    notifyListeners();
  }

  /// Save the current editor buffer to disk.
  ///
  /// `FileViewer` registers this callback while mounted and clears it on
  /// unmount. It is `null` when no editor is active and returns `true` after a
  /// successful save.
  Future<bool> Function()? saveDraft;

  /// Indicate a VS Code-style preview tab.
  ///
  /// Opening another file may replace a preview; double-clicking pins it as a
  /// normal tab.
  bool isPreview;

  /// Pin this preview so later file selections cannot replace it.
  void pin() {
    if (!isPreview) return;
    isPreview = false;
    notifyListeners();
  }
}
