import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/entities/update_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateInfo.fromJson', () {
    test('parses a valid manifest with artifacts', () {
      final json = jsonDecode('''
      {
        "version": "1.2.0",
        "date": "2026-06-12",
        "notes": "summary",
        "artifacts": [
          { "platform": "macos", "arch": "universal", "format": "dmg",
            "url": "https://x/a.dmg", "sha256": "abc", "size": 123 },
          { "platform": "linux", "arch": "arm64", "format": "deb",
            "url": "https://x/a.deb", "sha256": "def", "size": 456 }
        ]
      }
      ''');
      final info = UpdateInfo.fromJson(json);
      expect(info.version, '1.2.0');
      expect(info.date, '2026-06-12');
      expect(info.notes, 'summary');
      expect(info.artifacts, hasLength(2));
      expect(info.artifacts.first.platform, 'macos');
      expect(info.artifacts.first.url, 'https://x/a.dmg');
      expect(info.artifacts[1].size, 456);
    });

    test('uses defaults when optional fields are absent', () {
      final info = UpdateInfo.fromJson(
        jsonDecode('{"version":"1.0.0","artifacts":[]}'),
      );
      expect(info.date, '');
      expect(info.notes, '');
      expect(info.artifacts, isEmpty);
    });

    test('throws for the wrong schema when version is absent', () {
      expect(
        () => UpdateInfo.fromJson(jsonDecode('{"artifacts":[]}')),
        throwsFormatException,
      );
    });

    test(
      'throws when the manifest is not an object or artifacts is not a list',
      () {
        expect(
          () => UpdateInfo.fromJson(jsonDecode('[]')),
          throwsFormatException,
        );
        expect(
          () => UpdateInfo.fromJson(jsonDecode('{"version":"1.0.0"}')),
          throwsFormatException,
        );
      },
    );

    test('throws when an artifact lacks url, platform, or format', () {
      expect(
        () => UpdateInfo.fromJson(
          jsonDecode('{"version":"1.0.0","artifacts":[{"platform":"macos"}]}'),
        ),
        throwsFormatException,
      );
    });
  });

  group('artifactFor', () {
    final info = UpdateInfo.fromJson(
      jsonDecode('''
    {
      "version": "1.2.0",
      "artifacts": [
        { "platform": "macos", "arch": "universal", "format": "dmg", "url": "mac.dmg" },
        { "platform": "linux", "arch": "x64",   "format": "deb", "url": "x64.deb" },
        { "platform": "linux", "arch": "arm64", "format": "deb", "url": "arm.deb" }
      ]
    }
    '''),
    );

    test('matches platform and format while preferring the requested arch', () {
      expect(
        info.artifactFor(platform: 'linux', format: 'deb', arch: 'arm64')?.url,
        'arm.deb',
      );
      expect(
        info.artifactFor(platform: 'linux', format: 'deb', arch: 'x64')?.url,
        'x64.deb',
      );
    });

    test('falls back to the first format match for universal macOS', () {
      expect(
        info
            .artifactFor(platform: 'macos', format: 'dmg', arch: 'universal')
            ?.url,
        'mac.dmg',
      );
    });

    test('returns null when no artifact matches', () {
      expect(
        info.artifactFor(platform: 'windows', format: 'exe', arch: 'x64'),
        isNull,
      );
    });
  });
}
