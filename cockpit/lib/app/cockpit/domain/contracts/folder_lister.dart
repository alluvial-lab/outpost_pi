/// List a directory's subfolders for selecting which project folder an agent
/// will work in.
///
/// This domain contract is implemented with `dart:io` in `data/`.
abstract class FolderLister {
  /// Return the sorted names of [root]'s immediate, non-hidden subfolders.
  Future<List<String>> subfolders(String root);
}
