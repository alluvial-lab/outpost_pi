import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
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

Future<({Preferences prefs, OnboardingViewModel vm})> _setup() async {
  final prefs = Preferences(_FakeStore());
  final vm = OnboardingViewModel(prefs);
  return (prefs: prefs, vm: vm);
}

void main() {
  group('OnboardingViewModel', () {
    test('initial state is welcome with no relay configured', () async {
      final s = await _setup();
      final state = s.vm.state;
      expect(state, isA<OnboardingInProgress>());
      final p = state as OnboardingInProgress;
      expect(p.step, OnboardingStep.welcome);
      expect(p.customRelayUrl, isEmpty);
      expect(p.customRelayError, isNull);
      expect(s.prefs.relayUrl, isNull);
    });

    test('next() advances welcome → relay', () async {
      final s = await _setup();
      await s.vm.next();
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.relay);
    });

    test(
      'empty relay URL shows the shared validation error and cannot reach pairing',
      () async {
        final s = await _setup();
        await s.vm.next(); // → relay
        await s.vm.next(); // empty → validation error

        final state = s.vm.state as OnboardingInProgress;
        expect(state.step, OnboardingStep.relay);
        expect(state.customRelayError, kRelayUrlInvalidGeneric);
        expect(s.prefs.relayUrl, isNull);
      },
    );

    test('invalid relay URL emits error and stays on the relay step', () async {
      final s = await _setup();
      await s.vm.next(); // → relay
      s.vm.setCustomRelayUrl('not-a-url');
      await s.vm.next();

      final state = s.vm.state as OnboardingInProgress;
      expect(state.step, OnboardingStep.relay);
      expect(state.customRelayError, kRelayUrlInvalidGeneric);
      expect(s.prefs.relayUrl, isNull);
    });

    test(
      'valid relay URL is persisted before advancing to the pair step',
      () async {
        final s = await _setup();
        await s.vm.next(); // → relay
        s.vm.setCustomRelayUrl(' https://my-relay.example ');
        await s.vm.next();

        expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.pair);
        expect(s.prefs.relayUrl, 'https://my-relay.example');
      },
    );

    test('back() walks pair → relay → welcome and stops there', () async {
      final s = await _setup();
      await s.vm.next();
      s.vm.setCustomRelayUrl('https://my-relay.example');
      await s.vm.next();
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.pair);
      s.vm.back();
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.relay);
      s.vm.back();
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.welcome);
      s.vm.back(); // no-op
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.welcome);
    });

    test('setCustomRelayUrl validates on-the-fly: invalid → error, empty → '
        'no error, valid → clear error', () async {
      final s = await _setup();
      await s.vm.next();

      s.vm.setCustomRelayUrl('ftp://nope');
      expect((s.vm.state as OnboardingInProgress).customRelayError, isNotNull);

      s.vm.setCustomRelayUrl('');
      expect((s.vm.state as OnboardingInProgress).customRelayError, isNull);

      s.vm.setCustomRelayUrl('https://localhost');
      expect((s.vm.state as OnboardingInProgress).customRelayError, isNull);
    });

    test('setCustomRelayUrl flags ws:// and wss:// with the scheme-specific '
        'hint about internal conversion', () async {
      final s = await _setup();
      await s.vm.next();

      s.vm.setCustomRelayUrl('ws://localhost');
      final err1 = (s.vm.state as OnboardingInProgress).customRelayError;
      expect(err1, isNotNull);
      expect(err1, contains('ws://'));
      expect(err1, contains('http://'));

      s.vm.setCustomRelayUrl('wss://relay.example');
      final err2 = (s.vm.state as OnboardingInProgress).customRelayError;
      expect(err2, isNotNull);
      expect(err2, contains('ws://'));
    });

    test(
      'completePairing flips onboardingCompleted and emits complete',
      () async {
        final s = await _setup();
        expect(s.prefs.onboardingCompleted, isFalse);
        await s.vm.completePairing();
        expect(s.prefs.onboardingCompleted, isTrue);
        expect(s.vm.state, isA<OnboardingComplete>());
      },
    );
  });
}
