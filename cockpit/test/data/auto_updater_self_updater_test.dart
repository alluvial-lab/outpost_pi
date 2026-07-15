import 'package:auto_updater/auto_updater.dart';
import 'package:cockpit/app/cockpit/data/update/auto_updater_self_updater.dart';
import 'package:cockpit/app/cockpit/data/update/noop_self_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // dispose() removes the singleton `autoUpdater` listener (touching the
  // platform channel via EventChannel); the test binding handles this safely.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoUpdaterSelfUpdater maps native events → SelfUpdateState', () {
    late AutoUpdaterSelfUpdater updater;

    setUp(() {
      updater = AutoUpdaterSelfUpdater(
        feedUrl: 'https://example.test/appcast.xml',
      );
    });
    tearDown(() => updater.dispose());

    test('isSupported is true', () {
      expect(updater.isSupported, isTrue);
    });

    test('checking-for-update → phase checking', () {
      updater.onUpdaterCheckingForUpdate(null);
      expect(updater.state.phase, SelfUpdatePhase.checking);
    });

    test('update-available → downloading with version', () {
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      expect(updater.state.phase, SelfUpdatePhase.downloading);
      expect(updater.state.version, '1.6.0');
      expect(updater.state.hasPendingUpdate, isTrue);
      expect(updater.state.isReadyToInstall, isFalse);
    });

    test('update-downloaded → ready to install', () {
      updater.onUpdaterUpdateDownloaded(
        const AppcastItem(displayVersionString: '1.6.0', versionString: '9'),
      );
      expect(updater.state.phase, SelfUpdatePhase.downloaded);
      expect(updater.state.isReadyToInstall, isTrue);
      expect(updater.state.version, '1.6.0');
    });

    test(
      'version falls back to versionString when displayVersionString is null',
      () {
        updater.onUpdaterUpdateDownloaded(
          const AppcastItem(versionString: '9'),
        );
        expect(updater.state.version, '9');
      },
    );

    test('update-not-available → idle (nothing pending)', () {
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      updater.onUpdaterUpdateNotAvailable(null);
      expect(updater.state.phase, SelfUpdatePhase.idle);
      expect(updater.state.hasPendingUpdate, isFalse);
    });

    test('error carries the message', () {
      updater.onUpdaterError(UpdaterError('boom'));
      expect(updater.state.phase, SelfUpdatePhase.error);
      expect(updater.state.message, 'boom');
    });

    test('changes emits transitions in order', () {
      expectLater(
        updater.changes.map((s) => s.phase),
        emitsInOrder([
          SelfUpdatePhase.checking,
          SelfUpdatePhase.downloading,
          SelfUpdatePhase.downloaded,
        ]),
      );
      updater.onUpdaterCheckingForUpdate(null);
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      updater.onUpdaterUpdateDownloaded(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
    });
  });

  group('NoopSelfUpdater (Linux)', () {
    test('unsupported and inert', () async {
      const updater = NoopSelfUpdater();
      expect(updater.isSupported, isFalse);
      expect(updater.state.phase, SelfUpdatePhase.idle);
      // Methods are no-ops and do not throw.
      await updater.initialize();
      await updater.checkForUpdates();
      await updater.applyDownloadedUpdate();
      expect(updater.state.isReadyToInstall, isFalse);
    });
  });
}
