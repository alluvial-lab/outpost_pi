import 'dart:convert';

import 'package:app/domain/contracts/update_checker.dart';
import 'package:app/domain/entities/update_info.dart';
import 'package:dio/dio.dart';

/// Fetch the app's `latest.json` manifest over HTTP.
///
/// Uses a short timeout and returns `null` for every transport, status, JSON,
/// or schema failure so the update notice remains silent while offline. The
/// manifest shares Cockpit's `android`/`apk` schema; [UpdateInfo.fromJson]
/// owns parsing and validation.
class UpdateCheckerImpl implements UpdateChecker {
  UpdateCheckerImpl({
    this.manifestUrl,
    Duration timeout = const Duration(seconds: 5),
    Dio? dio,
  }) : _timeout = timeout,
       _dio = dio;

  final String? manifestUrl;
  final Duration _timeout;
  final Dio? _dio;

  static Dio _defaultDio(Duration timeout) {
    return Dio(
      BaseOptions(
        connectTimeout: timeout,
        sendTimeout: timeout,
        receiveTimeout: timeout,
        // Handle non-2xx status codes below instead of letting Dio throw.
        validateStatus: (_) => true,
        // Decode manually so empty or non-JSON 4xx/5xx bodies stay harmless.
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<UpdateInfo?> fetchLatest() async {
    final manifestUrl = this.manifestUrl;
    if (manifestUrl == null) return null;

    try {
      final dio = _dio ?? _defaultDio(_timeout);
      final response = await dio.getUri<Object?>(Uri.parse(manifestUrl));
      if (response.statusCode != 200) return null;
      final data = response.data;
      final body = data is String ? data : null;
      if (body == null || body.isEmpty) return null;
      return UpdateInfo.fromJson(jsonDecode(body));
    } catch (_) {
      // Network, status, JSON, and schema failures are intentionally silent.
      return null;
    }
  }
}
