import 'dart:typed_data';

import 'package:app/data/update/update_checker_impl.dart';
import 'package:app/domain/entities/update_info.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    return ResponseBody.fromString(body, statusCode);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, responseType: ResponseType.plain),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  test('default checker returns null without issuing HTTP', () async {
    final adapter = _FakeAdapter(statusCode: 200, body: 'unexpected');
    final result = await UpdateCheckerImpl(
      dio: _dioWith(adapter),
    ).fetchLatest();

    expect(result, isNull);
    expect(adapter.requestCount, 0);
  });

  group('explicit manifest URL', () {
    test('fetches and parses a valid manifest', () async {
      final adapter = _FakeAdapter(
        statusCode: 200,
        body: '''
          {
            "version": "1.2.0",
            "date": "2026-06-12",
            "notes": "Release notes",
            "artifacts": [
              {
                "platform": "android",
                "arch": "universal",
                "format": "apk",
                "url": "https://example.test/app.apk",
                "sha256": "abc",
                "size": 42
              }
            ]
          }
        ''',
      );
      final checker = UpdateCheckerImpl(
        manifestUrl: 'https://example.test/latest.json',
        dio: _dioWith(adapter),
      );

      final result = await checker.fetchLatest();

      expect(result, isA<UpdateInfo>());
      expect(result!.version, '1.2.0');
      expect(result.artifacts.single.url, 'https://example.test/app.apk');
      expect(adapter.requestCount, 1);
    });

    test('returns null for a 404 response', () async {
      final adapter = _FakeAdapter(statusCode: 404, body: 'not found');
      final checker = UpdateCheckerImpl(
        manifestUrl: 'https://example.test/latest.json',
        dio: _dioWith(adapter),
      );

      expect(await checker.fetchLatest(), isNull);
      expect(adapter.requestCount, 1);
    });

    test('returns null for invalid JSON', () async {
      final adapter = _FakeAdapter(statusCode: 200, body: '{not json');
      final checker = UpdateCheckerImpl(
        manifestUrl: 'https://example.test/latest.json',
        dio: _dioWith(adapter),
      );

      expect(await checker.fetchLatest(), isNull);
      expect(adapter.requestCount, 1);
    });
  });
}
