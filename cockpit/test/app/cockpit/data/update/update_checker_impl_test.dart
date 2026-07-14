import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/update/update_checker_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/update_info.dart';
import 'package:flutter_test/flutter_test.dart';

Future<HttpServer> _startManifestServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/latest.json':
          response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'version': '1.2.0',
                'date': '2026-06-12',
                'notes': 'Release notes',
                'artifacts': [
                  {
                    'platform': 'macos',
                    'arch': 'universal',
                    'format': 'dmg',
                    'url': 'https://example.test/app.dmg',
                    'sha256': 'abc',
                    'size': 42,
                  },
                ],
              }),
            );
        case '/missing.json':
          response.statusCode = HttpStatus.notFound;
          response.write('not found');
        case '/invalid.json':
          response
            ..statusCode = HttpStatus.ok
            ..write('{not json');
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    }),
  );
  return server;
}

String _url(HttpServer server, String path) =>
    'http://${server.address.address}:${server.port}$path';

void main() {
  test(
    'default checker returns null without creating an HTTP client',
    () async {
      var createClientCalls = 0;
      final result = await HttpOverrides.runZoned(
        () => const UpdateCheckerImpl().fetchLatest(),
        createHttpClient: (_) {
          createClientCalls++;
          throw StateError('default checker must not create an HTTP client');
        },
      );

      expect(result, isNull);
      expect(createClientCalls, 0);
    },
  );

  group('explicit manifest URL', () {
    late HttpServer server;

    setUpAll(() async {
      server = await _startManifestServer();
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    test('fetches and parses a valid manifest', () async {
      final result = await UpdateCheckerImpl(
        manifestUrl: _url(server, '/latest.json'),
      ).fetchLatest();

      expect(result, isA<UpdateInfo>());
      expect(result!.version, '1.2.0');
      expect(result.artifacts.single.url, 'https://example.test/app.dmg');
    });

    test('returns null for a 404 response', () async {
      final result = await UpdateCheckerImpl(
        manifestUrl: _url(server, '/missing.json'),
      ).fetchLatest();

      expect(result, isNull);
    });

    test('returns null for invalid JSON', () async {
      final result = await UpdateCheckerImpl(
        manifestUrl: _url(server, '/invalid.json'),
      ).fetchLatest();

      expect(result, isNull);
    });
  });
}
