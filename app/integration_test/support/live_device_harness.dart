import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/debug/debug_log_impl.dart';
import 'package:app/data/images/image_picker_service.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/data/voice/speech_service.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/onboarding/widgets/pair_step.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';

const livePiHostUrl = String.fromEnvironment('E2E_PI_HOST_URL');
const liveRelayUrl = String.fromEnvironment('E2E_RELAY_URL');

/// Own the real app-side services used by live device regression scenarios.
///
/// Pairing, secure owner-channel transport, Hive transcript projection, and the
/// production chat widgets remain real. The harness only supplies process-safe
/// ownership and bounded probes around those production boundaries.
final class LiveDeviceHarness {
  LiveDeviceHarness._({
    required this.storage,
    required this.preferences,
    required _SecureOwnerIdentityStore ownerStore,
    required this.ownerBridge,
    required this.debugLog,
    required this.connection,
    required this.sync,
    required this.readRepository,
    required this.actions,
    required this.pairingViewModel,
    required this.host,
  }) : _ownerStore = ownerStore;

  final PairingStorage storage;
  final Preferences preferences;
  final _SecureOwnerIdentityStore _ownerStore;
  final OwnerIdentityBridge ownerBridge;
  final DebugLogImpl debugLog;
  final ConnectionManager connection;
  final SyncService sync;
  final SessionReadRepository readRepository;
  final ActionsRepository actions;
  final PairingViewModel pairingViewModel;
  final LiveHostClient host;

  GoRouter? _chatRouter;
  IActionsRepository? _routeActions;
  SpeechService? _speech;
  PeerRecord? _peer;

  PeerRecord get peer =>
      _peer ?? (throw StateError('live harness is not paired'));

  /// Build production app services, optionally restoring the persisted pair.
  static Future<LiveDeviceHarness> create({required bool restorePair}) async {
    expect(livePiHostUrl, isNotEmpty, reason: 'runner must inject pi-host URL');
    expect(liveRelayUrl, isNotEmpty, reason: 'runner must inject relay URL');

    await LocalBoxes.init();
    const secureStorage = FlutterSecureStorage();
    final storage = PairingStorage(secureStorage);
    final preferences = Preferences(secureStorage);
    await preferences.load();
    if (preferences.relayUrl != liveRelayUrl) {
      await preferences.setRelayUrl(liveRelayUrl);
    }
    await preferences.setDebugLogging(true);

    final ownerStore = _SecureOwnerIdentityStore(secureStorage);
    final ownerBridge = OwnerIdentityBridge(ownerStore, storage);
    final ownerResult = await ownerBridge.boot();
    if (ownerResult is! IdentityReady) {
      throw StateError('live owner identity did not become ready');
    }
    final debugLog = DebugLogImpl(debugEnabled: () => preferences.debugLogging);

    Future<IChannel> reconnect(PeerRecord peer, CancelToken cancel) async {
      final current = await storage.loadPeer(peer.remoteEpk);
      if (current?.channel == null) {
        throw StateError('live reconnect lost owner-channel state');
      }
      final transport = await WsTransport.connect(
        relayUrl: liveRelayUrl,
        peerPubkey: current!.remoteEpk,
        ed25519Key: await ownerBridge.requireKeyPair(),
        deviceId: 'live-oddities-device',
        activeRoom: current.roomId ?? 'main',
        debugLog: debugLog,
      ).timeout(const Duration(seconds: 15));
      if (cancel.isCancelled) {
        await transport.close();
        throw StateError('live reconnect was cancelled');
      }
      return SecurePeerChannel(
        transport: transport,
        storage: storage,
        peer: current,
        debugLog: debugLog,
      );
    }

    final connection = ConnectionManager(
      factory: reconnect,
      storage: storage,
      debugLog: debugLog,
      emitDebounce: Duration.zero,
    );
    final sync = SyncService(connection, LocalBoxes(), debugLog: debugLog);
    final readRepository = SessionReadRepository(LocalBoxes());
    final actions = ActionsRepository(connection);
    final pairingViewModel = PairingViewModel(
      storage,
      (qr, ownerKey) => WsTransport.connect(
        relayUrl: liveRelayUrl,
        peerPubkey: qr.epk,
        ed25519Key: ownerKey,
        deviceId: 'live-oddities-device',
        activeRoom: qr.roomId ?? 'main',
        debugLog: debugLog,
      ).timeout(const Duration(seconds: 15)),
      connection,
      preferences,
      ownerBridge,
      debugLog: debugLog,
    );
    final harness = LiveDeviceHarness._(
      storage: storage,
      preferences: preferences,
      ownerStore: ownerStore,
      ownerBridge: ownerBridge,
      debugLog: debugLog,
      connection: connection,
      sync: sync,
      readRepository: readRepository,
      actions: actions,
      pairingViewModel: pairingViewModel,
      host: LiveHostClient(Uri.parse(livePiHostUrl)),
    );

    if (restorePair) {
      final selected = preferences.selectedPeerEpk;
      final peers = await storage.listPeers();
      final peer = selected == null
          ? peers.firstOrNull
          : peers
                .where((candidate) => candidate.remoteEpk == selected)
                .firstOrNull;
      if (peer == null) {
        throw StateError('live run has no persisted pair to restore');
      }
      harness._peer = peer;
      connection.subscribeToPeers(<String>[peer.remoteEpk]);
      await connection.boot(preferredEpk: peer.remoteEpk);
      await harness.waitOnlineAndLive();
    }
    return harness;
  }

  /// Pair through the production scanner widget and native QR decoder.
  Future<PeerRecord> pair(WidgetTester tester) async {
    return pairFromUri(tester, await issuePairCode(tester));
  }

  /// Issue a fresh production pair code and return its scanner URI.
  Future<String> issuePairCode(WidgetTester tester) async {
    await host.delete('/pair-code');
    await host.post('/command', <String, Object>{'args': 'pair'});
    final pairCode = await eventually<Map<String, dynamic>>(tester, () async {
      final value = await host.tryGet('/pair-code');
      return value?['uri'] is String ? value : null;
    }, description: 'production pair-code publication');
    return pairCode['uri'] as String;
  }

  /// Drive one QR URI through the native decoder and await visible pair state.
  Future<PeerRecord> pairFromUri(WidgetTester tester, String pairUri) async {
    final qr = QrPairPayload.tryParse(pairUri);
    expect(qr, isNotNull);
    expect(qr!.relayUrl, isNull);
    final qrFile = await _writeQrPng(pairUri);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          home: ChangeNotifierProvider<PairingViewModel>.value(
            value: pairingViewModel,
            child: Scaffold(
              body: SizedBox(
                height: 800,
                child: PairStep(onPaired: () {}, onBack: () {}, onSkip: () {}),
              ),
            ),
          ),
        ),
      );
      final scanner = await _findStartedScanner(tester);
      final capture = await scanner.controller!.analyzeImage(
        qrFile.path,
        formats: const [BarcodeFormat.qrCode],
      );
      expect(capture?.barcodes.single.rawValue, pairUri);
      scanner.onDetect!(capture!);

      final paired = await eventually<PeerRecord>(
        tester,
        () async => switch (pairingViewModel.state) {
          PairingPaired(:final peer) => peer,
          PairingError(:final message) => throw TestFailure(message),
          _ => null,
        },
        description: 'visible paired state',
        timeout: const Duration(seconds: 40),
      );
      _peer = paired;
      await preferences.setSelectedRoom(
        epk: paired.remoteEpk,
        roomId: paired.roomId,
      );
      connection.subscribeToPeers(<String>[paired.remoteEpk]);
      await waitOnlineAndLive(tester: tester);
      return paired;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      if (await qrFile.exists()) await qrFile.delete();
    }
  }

  /// Scan one valid QR while the relay is unavailable and retain the error UI.
  Future<String> pairFailureFromUri(WidgetTester tester, String pairUri) async {
    final qrFile = await _writeQrPng(pairUri);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          home: ChangeNotifierProvider<PairingViewModel>.value(
            value: pairingViewModel,
            child: Scaffold(
              body: SizedBox(
                height: 800,
                child: PairStep(onPaired: () {}, onBack: () {}, onSkip: () {}),
              ),
            ),
          ),
        ),
      );
      final scanner = await _findStartedScanner(tester);
      final capture = await scanner.controller!.analyzeImage(
        qrFile.path,
        formats: const [BarcodeFormat.qrCode],
      );
      expect(capture?.barcodes.single.rawValue, pairUri);
      scanner.onDetect!(capture!);
      return eventually<String>(
        tester,
        () async => switch (pairingViewModel.state) {
          PairingError(:final message) => message,
          PairingPaired() => throw TestFailure(
            'pairing unexpectedly succeeded while relay was unavailable',
          ),
          _ => null,
        },
        description: 'visible bounded pairing failure',
        timeout: const Duration(seconds: 25),
      );
    } finally {
      if (await qrFile.exists()) await qrFile.delete();
    }
  }

  /// Retry the PairStep error state through its production ViewModel action.
  ///
  /// The failed attempt already proved the native QR boundary. The retry feeds
  /// the freshly issued URI to the same action without restarting the stopped
  /// scanner's platform stream, which Android's scanner plugin cannot safely
  /// re-subscribe within one instrumentation activity.
  Future<PeerRecord> retryPairFromUri(
    WidgetTester tester,
    String pairUri,
  ) async {
    pairingViewModel.retry();
    await pairingViewModel.onQrScanned(pairUri);
    final paired = await eventually<PeerRecord>(
      tester,
      () async => switch (pairingViewModel.state) {
        PairingPaired(:final peer) => peer,
        PairingError(:final message) => throw TestFailure(message),
        _ => null,
      },
      description: 'visible paired state after retry',
      timeout: const Duration(seconds: 40),
    );
    _peer = paired;
    await preferences.setSelectedRoom(
      epk: paired.remoteEpk,
      roomId: paired.roomId,
    );
    connection.subscribeToPeers(<String>[paired.remoteEpk]);
    await waitOnlineAndLive(tester: tester);
    return paired;
  }

  /// Mount a fresh production chat route bound to the persisted selection.
  Future<void> mountChat(WidgetTester tester) async {
    await unmountChat(tester);
    final routeActions = _StaticActionsRepository();
    final speech = SpeechToTextService();
    _routeActions = routeActions;
    _speech = speech;
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, _) => MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => ChatViewModel(
                  readRepository,
                  sync,
                  connection,
                  preferences,
                  storage,
                ),
              ),
              ChangeNotifierProvider(
                create: (_) => VoiceInputViewModel(speech),
              ),
              ChangeNotifierProvider(
                create: (_) =>
                    AttachmentViewModel(ImagePickerService(), routeActions),
              ),
            ],
            child: const ChatPage(showBack: false, initialOnline: true),
          ),
        ),
      ],
    );
    _chatRouter = router;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Preferences>.value(value: preferences),
          ChangeNotifierProvider<SessionSelection>.value(
            value: SessionSelection(),
          ),
        ],
        child: MaterialApp.router(
          theme: buildDarkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
  }

  /// Tear down only the route-owned UI while retaining live app services.
  Future<void> unmountChat(WidgetTester tester) async {
    if (_chatRouter == null) return;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    _chatRouter?.dispose();
    _chatRouter = null;
    _routeActions?.dispose();
    _routeActions = null;
    _speech?.dispose();
    _speech = null;
  }

  /// Stage an assistant reply, submit through the composer, and release it.
  Future<void> sendAndResolve(
    WidgetTester tester, {
    required String prompt,
    required String reply,
  }) async {
    await host.post('/turn-control/defer-next', <String, Object>{
      'reply': reply,
    });
    await eventually<TextField>(tester, () async {
      final visibleFields = find.byType(TextField).hitTestable();
      if (visibleFields.evaluate().isEmpty) return null;
      final field = tester.widget<TextField>(visibleFields.first);
      return field.enabled == true ? field : null;
    }, description: 'enabled production chat composer');
    await tester.enterText(find.byType(TextField).hitTestable().first, prompt);
    await tester.pump();
    await eventually<bool>(
      tester,
      () async =>
          find.byIcon(LucideIcons.send600).evaluate().isNotEmpty ? true : null,
      description: 'composer send affordance',
    );
    final sendButton = find.ancestor(
      of: find.byIcon(LucideIcons.send600).first,
      matching: find.byType(GestureDetector),
    );
    await tester.tap(sendButton.first);
    await eventually<Map<String, dynamic>>(tester, () async {
      final value = await host.tryGet('/turn-control');
      return value?['phase'] == 'pending' ? value : null;
    }, description: 'staged Pi turn pending');
    await eventually<bool>(
      tester,
      () async => find.text(prompt).evaluate().isNotEmpty ? true : null,
      description: 'rendered user bubble',
    );
    expect(
      find.text('working…').evaluate().isNotEmpty ||
          find.text('streaming…').evaluate().isNotEmpty,
      isTrue,
    );
    await host.post('/turn-control/resolve', const <String, Object>{});
    await eventually<bool>(
      tester,
      () async => find.text(reply).evaluate().isNotEmpty ? true : null,
      description: 'assistant reply bubble',
    );
    await eventually<bool>(
      tester,
      () async =>
          find.text('working…').evaluate().isEmpty &&
              find.text('streaming…').evaluate().isEmpty
          ? true
          : null,
      description: 'rendered working convergence',
    );
  }

  /// Wait until the owner channel and selected room are both authoritative.
  Future<void> waitOnlineAndLive({WidgetTester? tester}) async {
    final selected = peer;
    final room = selected.roomId ?? 'main';
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      if (connection.status is StatusOnline &&
          connection.isRoomLive(selected.remoteEpk, room) &&
          connection.activeSessionId?.isNotEmpty == true) {
        return;
      }
      if (tester == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } else {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    final rooms = connection.roomsFor(selected.remoteEpk);
    throw TimeoutException(
      'timed out waiting for online live room '
      '(status=${connection.status.runtimeType}, selected=$room, '
      'active=${connection.activeRoomId}, session=${connection.activeSessionId}, '
      'rooms=${rooms.map((value) => value.roomId).join(',')})',
    );
  }

  /// Read the disposable transcript projection for the active canonical session.
  Future<List<MessageRecord>> transcriptRows() async {
    final sessionId = connection.activeSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('active session identity is unavailable');
    }
    return transcriptRowsFor(sessionId);
  }

  /// Read one retained session projection without changing the active route.
  Future<List<MessageRecord>> transcriptRowsFor(String sessionId) {
    return readRepository.readMessages(
      RemoteSessionRef(
        peerEpk: peer.remoteEpk,
        roomId: peer.roomId ?? 'main',
        sessionId: sessionId,
      ),
    );
  }

  /// Exercise A→B→A switching with faults and verify projection isolation.
  Future<LiveSessionShapeResult> exerciseMultiSessionShape(
    WidgetTester tester,
  ) async {
    await waitOnlineAndLive(tester: tester);
    final room = connection.activeRoomId;
    final selected = preferences.selectedRoomRaw;
    final sessionA = connection.activeSessionId!;
    const promptA = 'state-shape session A prompt';
    const replyA = 'state-shape session A reply';
    const promptB = 'state-shape session B prompt';
    const replyB = 'state-shape session B reply';
    await sendAndResolve(tester, prompt: promptA, reply: replyA);

    requestLiveFault('net_fault bandwidth 64');
    await tester.pump(const Duration(seconds: 1));
    try {
      await actions.newSession();
    } finally {
      requestLiveFault('net_clear');
    }
    final sessionB = await _waitForDifferentSession(tester, sessionA);
    await unmountChat(tester);
    await mountChat(tester);
    await eventually<bool>(
      tester,
      () async => find.text(promptA).evaluate().isEmpty ? true : null,
      description: 'session B excludes session A projection',
    );
    await sendAndResolve(tester, prompt: promptB, reply: replyB);

    requestLiveFault('net_fault down');
    await eventually<bool>(
      tester,
      () async => connection.status is! StatusOnline ? true : null,
      description: 'A resume fault takes the owner channel offline',
      timeout: const Duration(seconds: 45),
    );
    await host.post('/session/switch', <String, Object>{'sessionId': sessionA});
    await connection.disconnect();
    requestLiveFault('net_clear');
    await connection.connectTo(peer);
    await waitOnlineAndLive(tester: tester);
    await eventually<bool>(
      tester,
      () async => connection.activeSessionId == sessionA ? true : null,
      description: 'session A identity after faulted resume',
    );
    await unmountChat(tester);
    await mountChat(tester);
    await eventually<bool>(
      tester,
      () async => find.text(replyA).evaluate().isNotEmpty ? true : null,
      description: 'session A projection after A→B→A',
    );

    final rowsA = await transcriptRowsFor(sessionA);
    final rowsB = await transcriptRowsFor(sessionB);
    expect(
      rowsA.map((row) => row.text),
      containsAll(<String>[promptA, replyA]),
    );
    expect(rowsA.any((row) => row.text == promptB), isFalse);
    expect(
      rowsB.map((row) => row.text),
      containsAll(<String>[promptB, replyB]),
    );
    expect(rowsB.any((row) => row.text == promptA), isFalse);
    expect(find.text(promptB), findsNothing);
    expect(connection.activeRoomId, room);
    expect(preferences.selectedRoomRaw, selected);
    expect(connection.isRoomWorking(peer.remoteEpk, room), isFalse);
    return LiveSessionShapeResult(sessionA: sessionA, sessionB: sessionB);
  }

  /// Exercise local unpair→re-pair while preserving identity and transcript.
  Future<void> exerciseRePairShape(WidgetTester tester) async {
    const beforePrompt = 'state-shape before re-pair';
    const beforeReply = 'state-shape before re-pair reply';
    const afterPrompt = 'state-shape after re-pair';
    const afterReply = 'state-shape after re-pair reply';
    await sendAndResolve(tester, prompt: beforePrompt, reply: beforeReply);
    final oldPeer = peer;
    final oldSession = connection.activeSessionId!;
    final oldRows = await transcriptRowsFor(oldSession);
    final oldIds = oldRows.map((row) => row.id).toList(growable: false);
    final oldOwner = Uint8List.fromList(ownerBridge.currentOwnerPk!);
    final oldChannel = oldPeer.channel!;

    await unmountChat(tester);
    await connection.disconnect();
    connection.subscribeToPeers(const <String>[]);
    await storage.deletePeer(oldPeer.remoteEpk);
    await preferences.setSelectedPeerEpk(null);
    pairingViewModel.retry();
    final repaired = await pairFromUri(tester, await issuePairCode(tester));

    expect(listEquals(ownerBridge.currentOwnerPk, oldOwner), isTrue);
    expect(repaired.remoteEpk, oldPeer.remoteEpk);
    expect(repaired.roomId, oldPeer.roomId);
    expect(connection.activeSessionId, oldSession);
    expect(repaired.channel, isNot(oldChannel));
    expect(repaired.channel!.sendKey, isNot(oldChannel.sendKey));
    await mountChat(tester);
    await eventually<bool>(
      tester,
      () async => find.text(beforeReply).evaluate().isNotEmpty ? true : null,
      description: 'pre-repair transcript after fresh owner channel',
    );
    expect(
      (await transcriptRowsFor(oldSession)).map((row) => row.id),
      containsAllInOrder(oldIds),
    );
    await sendAndResolve(tester, prompt: afterPrompt, reply: afterReply);
    final texts = (await transcriptRows()).map((row) => row.text);
    expect(
      texts,
      containsAll(<String>[beforePrompt, beforeReply, afterPrompt, afterReply]),
    );
  }

  /// Force capture-ring rotation, reconnect replay, and bounded convergence.
  Future<void> exerciseLongUptimeShape(
    WidgetTester tester, {
    int ringEvents = 5500,
    bool requireRotation = true,
  }) async {
    expect(ringEvents, greaterThan(1));
    const stage =
        'bounded-long-uptime-capture-rotation-probe-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
    debugLog.log(
      WsInEvent(
        ts: DateTime.now(),
        count: -1,
        kind: 'state-shape',
        stage: stage,
      ),
    );
    for (var index = 0; index < ringEvents; index++) {
      debugLog.log(
        WsInEvent(
          ts: DateTime.now(),
          count: index,
          kind: 'state-shape',
          stage: stage,
        ),
      );
    }
    final exported = await debugLog.export();
    expect(exported, isNotNull);
    expect(utf8.encode(exported!).length, lessThanOrEqualTo(1 << 20));
    final rotated = await captureEvents();
    if (requireRotation) {
      expect(
        rotated.any((row) => row['tag'] == 'wsIn' && row['count'] == -1),
        isFalse,
        reason: 'oldest capture row must rotate out of the bounded ring',
      );
    }
    expect(
      rotated.any(
        (row) => row['tag'] == 'wsIn' && row['count'] == ringEvents - 1,
      ),
      isTrue,
    );

    final before = await transcriptRows();
    final beforeIds = before.map((row) => row.id).toList(growable: false);
    final replayBaseline = rotated.length;
    await connection.disconnect();
    await connection.connectTo(peer);
    await waitOnlineAndLive(tester: tester);
    await eventually<bool>(tester, () async {
      final ids = (await transcriptRows()).map((row) => row.id).toList();
      return listEquals(ids, beforeIds) ? true : null;
    }, description: 'stable transcript after long-uptime replay');
    final replay = (await captureEvents())
        .skip(replayBaseline)
        .where((row) => row['tag'] == 'replayDedup');
    expect(replay, isNotEmpty);
    final afterIds = (await transcriptRows()).map((row) => row.id).toList();
    expect(afterIds.toSet().length, afterIds.length);
    expect(
      connection.isRoomWorking(peer.remoteEpk, connection.activeRoomId),
      isFalse,
    );
  }

  Future<String> _waitForDifferentSession(
    WidgetTester tester,
    String previous,
  ) async {
    return eventually<String>(
      tester,
      () async {
        final current = connection.activeSessionId;
        return current != null && current != previous ? current : null;
      },
      description: 'fresh canonical session identity',
      timeout: const Duration(seconds: 45),
    );
  }

  /// Wait until one submitted prompt is both rendered and durably projected.
  ///
  /// Requiring both boundaries prevents identity-window regressions from
  /// passing on a transient widget or on a row that never reached the route.
  Future<void> waitForSubmissionVisibility(
    WidgetTester tester,
    String prompt, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    expect(
      await submissionIsVisible(tester, prompt, timeout: timeout),
      isTrue,
      reason: 'submission must render and have a transcript-DB row',
    );
  }

  /// Evaluate the bubble + transcript-DB predicate without hiding a timeout.
  Future<bool> submissionIsVisible(
    WidgetTester tester,
    String prompt, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (find.text(prompt).evaluate().isNotEmpty &&
            (await transcriptRows()).any((row) => row.text == prompt)) {
          return true;
        }
      } on StateError {
        // The identity-window predicate is false until a canonical ref exists.
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// Export and decode the content-free app capture ring.
  Future<List<Map<String, dynamic>>> captureEvents() async {
    final text = await debugLog.export();
    if (text == null) return const [];
    return [
      for (final line in const LineSplitter().convert(text))
        (jsonDecode(line) as Map).cast<String, dynamic>(),
    ];
  }

  /// Release every process-owned test service without deleting durable state.
  Future<void> close(WidgetTester tester) async {
    await unmountChat(tester);
    pairingViewModel.dispose();
    actions.dispose();
    sync.dispose();
    readRepository.dispose();
    await connection.disconnect();
    connection.dispose();
    ownerBridge.dispose();
    await _ownerStore.dispose();
    debugLog.dispose();
  }
}

/// Session identities observed during the deterministic A→B→A shape.
final class LiveSessionShapeResult {
  const LiveSessionShapeResult({
    required this.sessionA,
    required this.sessionB,
  });

  final String sessionA;
  final String sessionB;
}

/// Minimal bounded HTTP client for the pi-host test-support adapter.
final class LiveHostClient {
  const LiveHostClient(this.baseUri);

  final Uri baseUri;

  Future<Map<String, dynamic>?> tryGet(String path) async {
    try {
      return await _json('GET', path);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> get(String path) => _json('GET', path);

  Future<Map<String, dynamic>> post(String path, Map<String, Object> body) =>
      _json('POST', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _json('DELETE', path);

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

/// Poll one observable boundary while pumping device frames.
Future<T> eventually<T>(
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

/// Ask the shell runner to apply one live fault at the device boundary.
void requestLiveFault(String command) {
  debugPrintSynchronously('OUTPOST_LIVE_FAULT_REQUEST $command');
}

/// Probe the app-facing relay boundary without consulting transport internals.
Future<bool> liveRelayHealthReachable({
  Duration timeout = const Duration(milliseconds: 750),
}) async {
  final uri = Uri.parse(liveRelayUrl).resolve('/health');
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

final class _StaticActionsRepository extends IActionsRepository {
  final StreamController<ActiveRoomMeta> _meta =
      StreamController<ActiveRoomMeta>.broadcast();

  @override
  ActiveRoomMeta get activeRoomMeta => const ActiveRoomMeta();

  @override
  Stream<ActiveRoomMeta> get activeRoomMetaStream => _meta.stream;

  @override
  Future<ModelsCatalogue> listModels({bool forceRefresh = false}) async =>
      const ModelsCatalogue(models: []);

  @override
  Future<void> compact() => throw const ActionFailure('not exercised');

  @override
  Future<void> newSession() => throw const ActionFailure('not exercised');

  @override
  Future<void> setModel(String provider, String modelId) =>
      throw const ActionFailure('not exercised');

  @override
  Future<void> setThinking(ThinkingLevel level) =>
      throw const ActionFailure('not exercised');

  @override
  void dispose() {
    _meta.close();
    super.dispose();
  }
}

final class _SecureOwnerIdentityStore implements OwnerIdentityStore {
  _SecureOwnerIdentityStore(this._storage);

  static const _key = 'e2e.live.owner_identity';
  final FlutterSecureStorage _storage;
  final StreamController<OwnerIdentity> _updates =
      StreamController<OwnerIdentity>.broadcast();

  @override
  Future<OwnerIdentity?> load() async {
    final encoded = await _storage.read(key: _key);
    return encoded == null
        ? null
        : OwnerIdentity.fromBlob(Uint8List.fromList(base64Decode(encoded)));
  }

  @override
  Future<void> save(OwnerIdentity identity) async {
    await _storage.write(key: _key, value: base64Encode(identity.toBlob()));
    _updates.add(identity);
  }

  @override
  Stream<OwnerIdentity> watch() => _updates.stream;

  @override
  Future<void> delete() => _storage.delete(key: _key);

  @override
  Future<bool> isSyncAvailable() async => true;

  Future<void> dispose() => _updates.close();
}

Future<MobileScanner> _findStartedScanner(WidgetTester tester) async {
  return eventually<MobileScanner>(
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
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
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
