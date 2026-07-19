import 'dart:convert';
import 'dart:io';

/// Control the service-level proxy used only for the app→relay path.
final class ToxiproxyClient {
  ToxiproxyClient(this.baseUri);

  final Uri baseUri;

  Future<void> setAppRelayEnabled(bool enabled) async {
    final client = HttpClient();
    try {
      final request = await client.patchUrl(
        baseUri.resolve('/proxies/app-relay'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, Object>{'enabled': enabled}));
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'toxiproxy update failed (${response.statusCode})',
        );
      }
    } finally {
      client.close(force: true);
    }
  }
}
