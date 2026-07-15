/// Open external URLs through the OS browser or download handler.
///
/// This domain contract is implemented with `url_launcher` in `data/`.
abstract class UrlOpener {
  /// Open [url], returning `true` on success and `false` otherwise.
  Future<bool> open(String url);
}
