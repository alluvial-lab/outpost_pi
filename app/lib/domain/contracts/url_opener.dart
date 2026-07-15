/// Open an external URL in the system browser or download handler.
///
/// This domain contract is implemented with `url_launcher` in `data/update/`.
abstract class UrlOpener {
  /// Open [url], returning whether the platform accepted the request.
  Future<bool> open(String url);
}
