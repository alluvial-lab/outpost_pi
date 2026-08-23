import 'dart:io';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/home/home_page.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/update/viewmodels/update_banner_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../../golden/fold_matrix_capture.dart';
import '../../golden/fold_matrix_fixtures.dart';

void main() {
  http.Client? originalFontClient;
  late MockClient fixtureFontClient;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    final fontCacheDirectory = Directory(
      '${Directory.current.path}/.dart_tool/home_a11y_fonts',
    )..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async {
          return fontCacheDirectory.path;
        });
    await loadFoldGoldenFonts();
    originalFontClient = GoogleFonts.config.httpClient;
    fixtureFontClient = MockClient((request) async {
      final hash = request.url.pathSegments.last.replaceFirst('.ttf', '');
      final filename = switch (hash) {
        'd9e28ce88420fcbccb074f652afc16c1d496f7aca31311964c6a30bbdd71e4a0' =>
          'SpaceMono-Regular.ttf',
        '9bc9f9da68e4f847e99faab84b9202aa74430a0955675dcf949b79a65257c368' =>
          'SpaceMono-Bold.ttf',
        _ => throw StateError('Unexpected font request: $request'),
      };
      return http.Response.bytes(
        File('test/fixtures/fonts/$filename').readAsBytesSync(),
        200,
      );
    });
    GoogleFonts.config.httpClient = fixtureFontClient;
    await GoogleFonts.pendingFonts(<TextStyle>[
      GoogleFonts.spaceMono(),
      GoogleFonts.spaceMono(fontWeight: FontWeight.w700),
    ]);
  });

  tearDownAll(() async {
    await GoogleFonts.pendingFonts();
    GoogleFonts.config.httpClient = originalFontClient;
    fixtureFontClient.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  testWidgets('compact Home relay status keeps the 12sp floor', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(234, 842);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = FoldPairingStorage();
    final preferences = Preferences(FoldMemorySecureStorage());
    final connection = ConnectionManager(
      factory: (_, _) async => FoldChannel(),
      storage: storage,
    );
    final home = FoldHomeViewModel(storage, preferences, connection);
    final update = UpdateBannerViewModel(
      const FoldUpdateChecker(),
      const FoldDismissedUpdateStore(),
      const FoldUrlOpener(),
      currentVersion: '0.6.0',
      enabled: false,
    );
    final shell = ShellLayout();

    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    home.emit(
      const HomeList(
        peers: [foldPeerA],
        roomsByPeer: {
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA': foldRoomsA,
        },
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeViewModel>.value(value: home),
          ChangeNotifierProvider<UpdateBannerViewModel>.value(value: update),
          ChangeNotifierProvider<ShellLayout>.value(value: shell),
        ],
        child: MaterialApp(theme: buildDarkTheme(), home: const HomePage()),
      ),
    );
    await tester.pump();

    final relayStatus = tester.widget<Text>(
      find.byKey(const Key('home-relay-status-label')),
    );
    expect(relayStatus.style?.fontSize, greaterThanOrEqualTo(12));

    await tester.pumpWidget(const SizedBox.shrink());
    home.dispose();
    update.dispose();
    connection.dispose();
    preferences.dispose();
    storage.dispose();
    shell.dispose();
  });
}
