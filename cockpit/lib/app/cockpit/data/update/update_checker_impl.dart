import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/update_checker.dart';
import 'package:cockpit/app/cockpit/domain/entities/update_info.dart';

/// Fetch `latest.json` over `dart:io` HTTP without another dependency.
///
/// Uses a short timeout and returns `null` instead of throwing on any failure,
/// keeping update notifications silent while offline or unavailable.
class UpdateCheckerImpl implements UpdateChecker {
  const UpdateCheckerImpl({
    this.manifestUrl,
    this.timeout = const Duration(seconds: 5),
  });

  final String? manifestUrl;
  final Duration timeout;

  @override
  Future<UpdateInfo?> fetchLatest() async {
    final manifestUrl = this.manifestUrl;
    if (manifestUrl == null) return null;

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse(manifestUrl))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return UpdateInfo.fromJson(jsonDecode(body));
    } catch (_) {
      // Treat network, HTTP, JSON, and schema failures as a silent miss.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
