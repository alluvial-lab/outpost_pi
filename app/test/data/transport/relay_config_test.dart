import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore implements FlutterSecureStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _m[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _m.remove(key);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('relay_config — isValidRelayUrl', () {
    test('accepts http:// and https:// with non-empty host', () {
      expect(isValidRelayUrl('http://localhost'), isTrue);
      expect(isValidRelayUrl('http://127.0.0.1:8080'), isTrue);
      expect(isValidRelayUrl('https://relay.example.com'), isTrue);
      expect(isValidRelayUrl('https://selfhosted.example'), isTrue);
    });

    test('rejects ws:// and wss:// — those are conversions only', () {
      expect(isValidRelayUrl('ws://localhost'), isFalse);
      expect(isValidRelayUrl('wss://relay.example.com'), isFalse);
    });

    test('rejects empty, unsupported schemes, missing host', () {
      expect(isValidRelayUrl(''), isFalse);
      expect(isValidRelayUrl('ftp://example.com'), isFalse);
      expect(isValidRelayUrl('foo'), isFalse);
      expect(isValidRelayUrl('https://'), isFalse, reason: 'no host segment');
      expect(isValidRelayUrl('http://'), isFalse, reason: 'no host segment');
    });
  });

  group('relay_config — relayUrlValidationMessage', () {
    test('returns null for valid http(s) URLs', () {
      expect(relayUrlValidationMessage('https://relay.example.com'), isNull);
      expect(relayUrlValidationMessage('http://localhost:3000'), isNull);
    });

    test('returns ws-specific hint for ws:// and wss://', () {
      final ws = relayUrlValidationMessage('ws://localhost');
      expect(ws, kRelayUrlInvalidScheme);
      expect(ws, contains('http://'));
      expect(ws, contains('ws://'));

      final wss = relayUrlValidationMessage('wss://relay.example.com');
      expect(wss, kRelayUrlInvalidScheme);
    });

    test('returns generic message for empty / malformed input', () {
      expect(relayUrlValidationMessage(''), kRelayUrlInvalidGeneric);
      expect(relayUrlValidationMessage('foo'), kRelayUrlInvalidGeneric);
      expect(relayUrlValidationMessage('ftp://x.com'), kRelayUrlInvalidGeneric);
      expect(relayUrlValidationMessage('https://'), kRelayUrlInvalidGeneric);
    });
  });

  group('relay_config — orderedRelayUrls', () {
    test('keeps the configured endpoint first and removes wire duplicates', () {
      expect(
        orderedRelayUrls('https://tailnet.example', [
          'http://lan.example',
          'wss://tailnet.example',
          'http://lan.example',
        ]),
        ['https://tailnet.example', 'http://lan.example'],
      );
    });

    test('ignores blank alternates without changing the primary', () {
      expect(orderedRelayUrls('http://primary', [' ', '']), ['http://primary']);
    });
  });

  group('relay_config — toWsRelayUrl', () {
    test('translates http(s) to ws(s)', () {
      expect(
        toWsRelayUrl('https://relay.example.com'),
        'wss://relay.example.com',
      );
      expect(toWsRelayUrl('http://localhost:8080'), 'ws://localhost:8080');
    });

    test('passes ws(s) through unchanged (legacy QR / PeerRecord)', () {
      expect(
        toWsRelayUrl('wss://relay.example.com'),
        'wss://relay.example.com',
      );
      expect(toWsRelayUrl('ws://localhost'), 'ws://localhost');
    });
  });

  group('relay_config — resolveRelayUrl', () {
    test('returns ConfiguredRelay when a stored URL is present', () async {
      final p = Preferences(_FakeStore());
      await p.setRelayUrl('https://custom.example.com');

      final resolution = resolveRelayUrl(p);
      expect(resolution, isA<ConfiguredRelay>());
      expect((resolution as ConfiguredRelay).url, 'https://custom.example.com');
      expect(resolution.source, RelaySource.preferences);
    });

    test('returns UnconfiguredRelay when no stored URL is present', () {
      final resolution = resolveRelayUrl(Preferences(_FakeStore()));
      expect(resolution, isA<UnconfiguredRelay>());
      expect(resolution.source, RelaySource.unconfigured);
    });

    test('uses a shared actionable message for unconfigured failures', () {
      expect(
        const RelayNotConfiguredException().toString(),
        kRelayNotConfiguredMessage,
      );
    });
  });
}
