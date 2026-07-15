import 'package:cockpit/app/cockpit/domain/contracts/url_opener.dart';
import 'package:url_launcher/url_launcher.dart';

/// Open external URLs through the operating system's registered handler.
///
/// Uses `url_launcher` in external-application mode and maps URI or launcher
/// failures to `false`.
class UrlOpenerImpl implements UrlOpener {
  const UrlOpenerImpl();

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
