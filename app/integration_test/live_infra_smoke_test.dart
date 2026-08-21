@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/data/debug/debug_log_impl.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/onboarding/widgets/pair_step.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';

const _piHostUrl = String.fromEnvironment('E2E_PI_HOST_URL');
const _relayUrl = String.fromEnvironment('E2E_RELAY_URL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real device pairs through native QR decode and survives live faults',
    (tester) async {
      expect(_piHostUrl, isNotEmpty, reason: 'runner must inject pi-host URL');
      expect(_relayUrl, isNotEmpty, reason: 'runner must inject relay URL');

      const secureStorage = FlutterSecureStorage();
      await secureStorage.deleteAll();
      final pairingStorage = PairingStorage(secureStorage);
      final preferences = Preferences(secureStorage);
      await preferences.load();
      // Canonical pair QRs intentionally omit relay configuration. The device
      // lane injects the adb-reversed localhost URL through the same persisted
      // Preferences boundary used by Settings; no production URL seam exists.
      await preferences.setRelayUrl(_relayUrl);
      await preferences.setDebugLogging(true);

      final ownerStore = InMemoryOwnerIdentityStore();
      final ownerBridge = OwnerIdentityBridge(ownerStore, pairingStorage);
      expect(await ownerBridge.boot(), isA<IdentityReady>());
      final debugLog = DebugLogImpl(
        debugEnabled: () => preferences.debugLogging,
      );
      const deviceId = 'live-infra-smoke-device';

      late final ConnectionManager connection;
      Future<IChannel> reconnect(PeerRecord peer, CancelToken cancel) async {
        final current = await pairingStorage.loadPeer(peer.remoteEpk);
        if (current?.channel == null) {
          throw StateError('live reconnect lost owner-channel state');
        }
        final transport = await WsTransport.connect(
          relayUrl: _relayUrl,
          peerPubkey: current!.remoteEpk,
          ed25519Key: await ownerBridge.requireKeyPair(),
          deviceId: deviceId,
          activeRoom: current.roomId ?? 'main',
          debugLog: debugLog,
        ).timeout(const Duration(seconds: 15));
        if (cancel.isCancelled) {
          await transport.close();
          throw StateError('live reconnect was cancelled');
        }
        return SecurePeerChannel(
          transport: transport,
          storage: pairingStorage,
          peer: current,
          debugLog: debugLog,
        );
      }

      connection = ConnectionManager(
        factory: reconnect,
        storage: pairingStorage,
        debugLog: debugLog,
        emitDebounce: Duration.zero,
      );
      final pairingViewModel = PairingViewModel(
        pairingStorage,
        (QrPairPayload qr, SimpleKeyPair ownerKey) => WsTransport.connect(
          relayUrl: _relayUrl,
          peerPubkey: qr.epk,
          ed25519Key: ownerKey,
          deviceId: deviceId,
          activeRoom: qr.roomId ?? 'main',
          debugLog: debugLog,
        ),
        connection,
        preferences,
        ownerBridge,
        debugLog: debugLog,
      );
      final lifecycle = _LifecycleProbe();
      WidgetsBinding.instance.addObserver(lifecycle);

      addTearDown(() async {
        WidgetsBinding.instance.removeObserver(lifecycle);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        pairingViewModel.dispose();
        await connection.disconnect();
        connection.dispose();
        ownerBridge.dispose();
        await ownerStore.dispose();
        debugLog.dispose();
        await secureStorage.deleteAll();
      });

      final host = _HostClient(Uri.parse(_piHostUrl));
      await host.post('/command', <String, Object>{'args': 'pair'});
      final pairCode = await _eventually<Map<String, dynamic>>(
        tester,
        () async {
          final value = await host.tryGet('/pair-code');
          return value?['uri'] is String ? value : null;
        },
        description: 'production pair-code publication',
      );
      final pairUri = pairCode['uri'] as String;
      final qr = QrPairPayload.tryParse(pairUri);
      expect(qr, isNotNull);
      expect(
        qr!.relayUrl,
        isNull,
        reason: 'canonical QR is not the relay configuration vector',
      );
      expect(preferences.relayUrl, _relayUrl);

      final qrFile = await _writeQrPng(pairUri);
      addTearDown(() async {
        if (await qrFile.exists()) await qrFile.delete();
      });
      var pairedCallbackCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          home: ChangeNotifierProvider<PairingViewModel>.value(
            value: pairingViewModel,
            child: Scaffold(
              body: SizedBox(
                height: 800,
                child: PairStep(
                  onPaired: () => pairedCallbackCount++,
                  onBack: () {},
                  onSkip: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final scanner = await _findStartedScanner(tester);
      final controller = scanner.controller!;
      final capture = await controller.analyzeImage(
        qrFile.path,
        formats: const [BarcodeFormat.qrCode],
      );
      expect(capture?.barcodes.single.rawValue, pairUri);
      scanner.onDetect!(capture!);

      final paired = await _eventually<PeerRecord>(
        tester,
        () async => switch (pairingViewModel.state) {
          PairingPaired(:final peer) => peer,
          PairingError(:final message) => throw TestFailure(message),
          _ => null,
        },
        description: 'app PairingPaired state',
        timeout: const Duration(seconds: 40),
      );
      connection.subscribeToPeers(<String>[paired.remoteEpk]);
      await _eventually<bool>(
        tester,
        () async => connection.status is StatusOnline ? true : null,
        description: 'online app owner channel',
      );
      final pairedHost = await _eventually<Map<String, dynamic>>(
        tester,
        () async {
          final value = await host.tryGet('/status');
          return value?['state'] == 'paired' ? value : null;
        },
        description: 'pi-host paired peer',
      );
      expect(pairedCallbackCount, 1);

      _requestFault('net_fault down');
      await _eventually<bool>(
        tester,
        () async => connection.status is! StatusOnline ? true : null,
        description: 'app observes app-relay proxy down',
      );
      // Quiesce the retry timer while the harness restores the proxy. The
      // explicit reconnect below is the same entry point used by app resume.
      await connection.disconnect();
      _requestFault('net_clear');
      var consecutiveHealthyProbes = 0;
      await _eventually<bool>(tester, () async {
        if (await _relayHealthReachable(
          timeout: const Duration(milliseconds: 150),
        )) {
          consecutiveHealthyProbes++;
        } else {
          consecutiveHealthyProbes = 0;
        }
        return consecutiveHealthyProbes >= 5 ? true : null;
      }, description: 'stable app-relay proxy restoration');
      await connection.connectTo(paired);
      await _waitOnlineAndLive(tester, connection, paired);

      _requestFault('relay_pause');
      await _eventually<bool>(
        tester,
        () async => await _relayHealthReachable() ? null : true,
        description: 'paused relay is unreachable from device',
      );
      _requestFault('relay_resume');
      await _eventually<bool>(
        tester,
        () async => await _relayHealthReachable() ? true : null,
        description: 'resumed relay is reachable from device',
      );
      await _waitOnlineAndLive(tester, connection, paired);

      _requestFault('pi_restart');
      final generation = pairedHost['generation'] as String;
      await _eventually<Map<String, dynamic>>(
        tester,
        () async {
          final value = await host.tryGet('/status');
          return value != null &&
                  value['generation'] != generation &&
                  value['relayConnected'] == true
              ? value
              : null;
        },
        description: 'preserving pi-host restart generation',
        timeout: const Duration(seconds: 45),
      );
      await _eventually<bool>(
        tester,
        () async => connection.status is StatusOnline ? true : null,
        description: 'app owner channel remains online after pi restart',
      );

      _requestFault('app_background');
      await _eventually<bool>(
        tester,
        () async =>
            lifecycle.lastState != AppLifecycleState.resumed ? true : null,
        description: 'app background lifecycle transition',
      );
      _requestFault('app_foreground');
      await _eventually<bool>(
        tester,
        () async =>
            lifecycle.lastState == AppLifecycleState.resumed ? true : null,
        description: 'app foreground lifecycle transition',
      );
      await _eventually<bool>(
        tester,
        () async => connection.status is StatusOnline ? true : null,
        description: 'online app after foreground resume',
      );

      final docs = await getApplicationDocumentsDirectory();
      final airplaneAck = File('${docs.path}/.outpost_live_airplane');
      _requestFault('app_airplane on');
      await _eventually<bool>(
        tester,
        () async => await _fileEquals(airplaneAck, 'on') ? true : null,
        description: 'airplane mode enabled by adb helper',
      );
      _requestFault('app_airplane off');
      await _eventually<bool>(
        tester,
        () async => await _fileEquals(airplaneAck, 'off') ? true : null,
        description: 'airplane mode disabled by adb helper',
      );
      await _eventually<bool>(
        tester,
        () async => connection.status is StatusOnline ? true : null,
        description: 'online app after airplane toggle',
      );

      expect(
        await debugLog.export(),
        isNotNull,
        reason: 'capture ring must contain live connection events',
      );

      // Platform-view semantics ownership must end inside the test body;
      // addTearDown runs after WidgetTester leak verification.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

void _requestFault(String command) {
  debugPrintSynchronously('OUTPOST_LIVE_FAULT_REQUEST $command');
}

Future<void> _waitOnlineAndLive(
  WidgetTester tester,
  ConnectionManager connection,
  PeerRecord peer,
) async {
  await _eventually<bool>(
    tester,
    () async {
      final room = peer.roomId ?? 'main';
      return connection.status is StatusOnline &&
              connection.isRoomLive(peer.remoteEpk, room)
          ? true
          : null;
    },
    description: 'online app state with live paired room',
    timeout: const Duration(seconds: 45),
  );
}

Future<bool> _relayHealthReachable({
  Duration timeout = const Duration(seconds: 1),
}) async {
  final uri = Uri.parse(_relayUrl).resolve('/health');
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>().timeout(timeout);
    return response.statusCode == HttpStatus.ok;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<bool> _fileEquals(File file, String expected) async {
  try {
    return (await file.readAsString()).trim() == expected;
  } catch (_) {
    return false;
  }
}

Future<T> _eventually<T>(
  WidgetTester tester,
  Future<T?> Function() probe, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final value = await probe();
      if (value != null) return value;
    } on TestFailure {
      rethrow;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TimeoutException(
    'timed out waiting for $description'
    '${lastError == null ? '' : ' (last=${lastError.runtimeType})'}',
    timeout,
  );
}

Future<MobileScanner> _findStartedScanner(WidgetTester tester) async {
  return _eventually<MobileScanner>(
    tester,
    () async {
      final finder = find.byType(MobileScanner);
      if (finder.evaluate().isEmpty) return null;
      final scanner = tester.widget<MobileScanner>(finder);
      return scanner.controller?.value.isRunning ?? false ? scanner : null;
    },
    description: 'native MobileScanner startup',
    timeout: const Duration(seconds: 60),
  );
}

Future<File> _writeQrPng(String content) async {
  final qrCode = QrCode.fromData(
    data: content,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qrImage = QrImage(qrCode);
  const quietZone = 4;
  const modulePixels = 10;
  final size = (qrImage.moduleCount + quietZone * 2) * modulePixels;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  final foreground = Paint()..color = Colors.black;
  for (var row = 0; row < qrImage.moduleCount; row++) {
    for (var column = 0; column < qrImage.moduleCount; column++) {
      if (!qrImage.isDark(row, column)) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          (column + quietZone) * modulePixels.toDouble(),
          (row + quietZone) * modulePixels.toDouble(),
          modulePixels.toDouble(),
          modulePixels.toDouble(),
        ),
        foreground,
      );
    }
  }
  final image = await recorder.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) throw StateError('QR rasterization returned no PNG');
  final file = File(
    '${Directory.systemTemp.path}/outpost_live_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
  return file;
}

final class _LifecycleProbe with WidgetsBindingObserver {
  AppLifecycleState? lastState = WidgetsBinding.instance.lifecycleState;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    lastState = state;
  }
}

final class _HostClient {
  const _HostClient(this.baseUri);

  final Uri baseUri;

  Future<Map<String, dynamic>?> tryGet(String path) async {
    try {
      return await _json('GET', path);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> post(String path, Map<String, Object> body) =>
      _json('POST', path, body: body);

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, Object>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client
          .openUrl(method, baseUri.resolve(path))
          .timeout(const Duration(seconds: 2));
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('$method $path returned ${response.statusCode}');
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}
