/// Search a folder for files used by `@` autocomplete in the agent input.
///
/// This domain contract is implemented in `data/` with a filesystem walk and
/// cache.
abstract class FileSearcher {
  /// Return **file paths relative to [root]** that match [query].
  ///
  /// An empty query returns the first paths. Results are ordered by relevance
  /// and limited to [limit].
  Future<List<String>> search(String root, String query, {int limit});
}
