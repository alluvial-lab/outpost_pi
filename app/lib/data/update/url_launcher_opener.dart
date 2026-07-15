import 'package:app/domain/contracts/url_opener.dart';
import 'package:url_launcher/url_launcher.dart';

/// Open external URLs through `url_launcher` for direct `OutpostPi.apk` downloads.
///
/// This is best-effort: invalid URLs, unsupported handlers, and platform
/// failures return `false` so the update UI can retain its fallback.
class UrlLauncherOpener implements UrlOpener {
  const UrlLauncherOpener();

  @override
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
