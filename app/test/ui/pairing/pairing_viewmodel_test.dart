// Tests for PairingViewModel: scan → pair_request → paired.
// Uses in-memory transport so no real WS is needed.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/secure_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/pair_request_flow.dart' show PeerTransport;
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';
import 'package:cryptography/cryptography.dart';

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------

class _Q {
  final _buf = <Uint8List>[];
  final _wait = <Completer<Uint8List>>[];
  void add(Uint8List d) {
    if (_wait.isNotEmpty) {
      _wait.removeAt(0).complete(d);
    } else {
      _buf.add(d);
    }
  }

  Future<Uint8List> next() {
    if (_buf.isNotEmpty) return Future.value(_buf.removeAt(0));
    final c = Completer<Uint8List>();
    _wait.add(c);
    return c.future;
  }
}

class _MemTransport implements PeerTransport {
  final _Q _s;
  final _Q _r;
  int closeCalls = 0;
  _MemTransport({required _Q send, required _Q recv}) : _s = send, _r = recv;
  @override
  Future<void> send(Uint8List d) async => _s.add(d);
  @override
  Future<Uint8List> receive() => _r.next();
  @override
  Future<void> close() async => closeCalls++;
}

class _HangingTransport implements PeerTransport {
  final _reply = Completer<Uint8List>();
  int closeCalls = 0;

  @override
  Future<void> send(Uint8List data) async {}

  @override
  Future<Uint8List> receive() => _reply.future;

  @override
  Future<void> close() async {
    closeCalls++;
    if (!_reply.isCompleted) {
      _reply.complete(Uint8List(0));
    }
  }
}

/// In-memory fake of FlutterSecureStorage so Preferences can be
/// constructed in tests without touching the platform channel.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];
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
      _store.remove(key);
    } else {
      _store[key] = value;
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
  }) async {
    _store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Synchronous Preferences subclass for tests. Pre-set relay URL to
/// `ws://localhost` so it matches `_qrUri` (which still embeds the
/// legacy `r=ws://localhost`); avoids tripping the relay-mismatch
/// guard in `pair_request_flow.performPairing`. Pass `null` to force
/// a different URL and exercise the mismatch path.
class _PrefsForTest extends Preferences {
  final String? _relay;
  _PrefsForTest({String? relay = 'ws://localhost'})
    : _relay = relay,
      super(_FakeSecureStorage());
  @override
  String? get relayUrl => _relay;
}

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> _saved = [];
  bool _transitionPending = false;
  String? _ownerFingerprint;

  @override
  Future<List<PeerRecord>> listPeers() async => _saved;

  @override
  Future<void> savePairedPeer(PeerRecord r) async => _saved.add(r);

  @override
  Future<bool> savePairedPeerIfCurrent(
    PeerRecord r, {
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) return false;
    _saved.add(r);
    return true;
  }

  @override
  Future<void> savePeer(PeerRecord r) async => _saved.add(r);

  // Owner-transition marker (W4b): kept in-memory so boot() stays hermetic.
  @override
  Future<bool> hasPendingOwnerTransition() async => _transitionPending;

  @override
  Future<String?> loadOwnerStateFingerprint() async => _ownerFingerprint;

  @override
  Future<String> initializeOwnerStateFingerprint(String fingerprint) async =>
      _ownerFingerprint ??= fingerprint;

  @override
  Future<void> beginOwnerTransition() async => _transitionPending = true;

  @override
  Future<void> completeOwnerTransition(String fingerprint) async =>
      _transitionPending = false;
}

class _DeferredPairingStorage extends _FakeStorage {
  final saveStarted = Completer<void>();
  final releaseSave = Completer<void>();

  @override
  Future<bool> savePairedPeerIfCurrent(
    PeerRecord r, {
    required bool Function() stillCurrent,
  }) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await releaseSave.future;
    if (!stillCurrent()) return false;
    _saved.add(r);
    return true;
  }
}

/// Helper: build a fully-booted [OwnerIdentityBridge] backed by an
/// in-memory plugin store, seeded with a freshly-generated identity.
/// Mirrors what `dependencies.dart` + the router's _BootState do before
/// PairingViewModel runs in production.
Future<OwnerIdentityBridge> _bootedBridge(PairingStorage storage) async {
  final store = InMemoryOwnerIdentityStore();
  final bridge = OwnerIdentityBridge(store, storage);
  await bridge.boot();
  return bridge;
}

late SimpleKeyPair _piSigningKey;
late String _qrUri;

/// A pairing transport factory that runs a fake "Pi" responder which replies
/// with the given inner message to whatever `pair_request` it receives.
PairingTransportFactory _factoryReplyingWith(
  Map<String, dynamic> reply, {
  Future<void>? beforeReply,
  void Function()? onRequest,
  void Function(_MemTransport transport)? onTransport,
}) {
  return (qr, deviceEd25519, _) async {
    final q1 = _Q();
    final q2 = _Q();
    final iTrans = _MemTransport(send: q1, recv: q2);
    final rTrans = _MemTransport(send: q2, recv: q1);
    onTransport?.call(iTrans);

    // Responder runs in background and performs the real signed Pi half.
    unawaited(() async {
      final raw = await rTrans.receive();
      onRequest?.call();
      await beforeReply;
      final req = PairRequest.fromJson(
        jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
      );
      final resp = Map<String, dynamic>.from(reply);
      resp['in_reply_to'] = req.id;
      if (resp['type'] == 'pair_ok') {
        final appDhPublic = base64.decode(req.dhPk!);
        final ownerPublic = await deviceEd25519.extractPublicKey();
        final piDh = await generateOwnerChannelKeyPair();
        final transcript = buildPiOwnerChannelTranscript(
          token: qr.token,
          appDhPublicKey: appDhPublic,
          piDhPublicKey: piDh.publicKey,
          ownerEdPublicKey: ownerPublic.bytes,
        );
        final signature = await Ed25519().sign(
          transcript,
          keyPair: _piSigningKey,
        );
        resp['dh_pk'] = base64.encode(piDh.publicKey);
        resp['dh_sig'] = base64.encode(signature.bytes);
      }
      await rTrans.send(Uint8List.fromList(utf8.encode(jsonEncode(resp))));
    }());

    return iTrans;
  };
}

// ---------------------------------------------------------------------------
// Spy ConnectionManager — records adopt/disconnect (plan/31: PairingViewModel
// now drives the ConnectionManager directly). Overrides skip super so no
// ping/connect timers are started.
// ---------------------------------------------------------------------------

class _SpyConn extends ConnectionManager {
  _SpyConn()
    : super(
        factory: (_, _) async => throw UnimplementedError(),
        storage: _FakeStorage(),
      );

  IChannel? adoptedChannel;
  PeerRecord? adoptedPeer;
  int disconnectCalls = 0;

  @override
  void adopt(IChannel channel, PeerRecord peer) {
    adoptedChannel = channel;
    adoptedPeer = peer;
  }

  @override
  Future<void> disconnect() async => disconnectCalls++;
}

// ---------------------------------------------------------------------------
// Unit tests — PairingViewModel
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _piSigningKey = await Ed25519().newKeyPair();
    final piPublic = await _piSigningKey.extractPublicKey();
    final epk = base64Url.encode(piPublic.bytes).replaceAll('=', '');
    _qrUri =
        'outpostpi://pair?t=AAAAAAAAAAAAAAAAAAAAAA&epk=$epk&'
        'r=ws%3A%2F%2Flocalhost&n=test+session';
  });

  group('PairingViewModel', () {
    test('initial state is PairingScanning', () async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final vm = PairingViewModel(
        storage,
        (qr, key, cancellation) async =>
            throw Exception('should not be called'),
        _SpyConn(),
        _PrefsForTest(),
        bridge,
      );
      expect(vm.state, isA<PairingScanning>());
      vm.dispose();
    });

    test('invalid QR is ignored — stays PairingScanning', () async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final vm = PairingViewModel(
        storage,
        (qr, key, cancellation) async =>
            throw Exception('should not be called'),
        _SpyConn(),
        _PrefsForTest(),
        bridge,
      );
      await vm.onQrScanned('https://example.com/not-a-qr');
      expect(vm.state, isA<PairingScanning>());
      vm.dispose();
    });

    test(
      'malformed but intentional pairing code surfaces PairingError',
      () async {
        final storage = _FakeStorage();
        final bridge = await _bootedBridge(storage);
        final vm = PairingViewModel(
          storage,
          (qr, key, cancellation) async =>
              throw Exception('should not be called'),
          _SpyConn(),
          _PrefsForTest(),
          bridge,
        );
        // Looks like a pairing code (outpostpi://) but has a bad token —
        // must surface an error rather than silently swallowing it.
        await vm.onQrScanned('outpostpi://pair?t=BADTOKEN&epk=AAAA&n=test');
        expect(vm.state, isA<PairingError>());
        final error = vm.state as PairingError;
        expect(error.canRetry, isTrue);
        expect(error.message, contains('could not be read'));
        vm.dispose();
      },
    );

    test(
      'unconfigured relay fails before disconnecting or opening transport',
      () async {
        final storage = _FakeStorage();
        final conn = _SpyConn();
        final bridge = await _bootedBridge(storage);
        var transportCalls = 0;
        final vm = PairingViewModel(
          storage,
          (qr, key, cancellation) async {
            transportCalls++;
            throw StateError('transport must not be opened');
          },
          conn,
          _PrefsForTest(relay: null),
          bridge,
        );

        await vm.onQrScanned(_qrUri);

        expect(vm.state, isA<PairingError>());
        final error = vm.state as PairingError;
        expect(error.canRetry, isFalse);
        expect(error.message, contains('Settings'));
        expect(transportCalls, 0);
        expect(conn.disconnectCalls, 0);

        vm.dispose();
        conn.dispose();
      },
    );

    test('scan → connecting → paired (channel adopted)', () async {
      final storage = _FakeStorage();
      final fakeRepo = _SpyConn();
      final bridge = await _bootedBridge(storage);
      final factory = _factoryReplyingWith({
        'type': 'pair_ok',
        'session_name': 'test session',
      });
      final vm = PairingViewModel(
        storage,
        factory,
        fakeRepo,
        _PrefsForTest(),
        bridge,
      );

      final fut = vm.onQrScanned(_qrUri);
      expect(vm.state, isA<PairingConnecting>());

      await fut;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(vm.state, isA<PairingPaired>());
      expect(storage._saved, hasLength(1));
      expect(storage._saved.first.sessionName, 'test session');
      expect(fakeRepo.adoptedChannel, isNotNull);
      expect(fakeRepo.adoptedPeer?.remoteEpk, isNotEmpty);
      expect(fakeRepo.disconnectCalls, 1);

      vm.dispose();
    });

    test('pair_error → PairingError(canRetry: true)', () async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final factory = _factoryReplyingWith({
        'type': 'pair_error',
        'code': 'token_expired',
        'message': 'Token expired',
      });
      final vm = PairingViewModel(
        storage,
        factory,
        _SpyConn(),
        _PrefsForTest(),
        bridge,
      );

      await vm.onQrScanned(_qrUri);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(vm.state, isA<PairingError>());
      final err = vm.state as PairingError;
      expect(err.canRetry, isTrue);
      expect(err.message, contains('QR expired'));
      expect(storage._saved, isEmpty);

      vm.dispose();
    });

    test(
      'transport failure → PairingError + retry returns to scanning',
      () async {
        final storage = _FakeStorage();
        final bridge = await _bootedBridge(storage);
        final vm = PairingViewModel(
          storage,
          (qr, key, cancellation) async => throw Exception('socket exception'),
          _SpyConn(),
          _PrefsForTest(),
          bridge,
        );

        await vm.onQrScanned(_qrUri);
        expect(vm.state, isA<PairingError>());
        expect((vm.state as PairingError).canRetry, isTrue);

        vm.retry();
        expect(vm.state, isA<PairingScanning>());

        vm.dispose();
      },
    );

    test(
      'disposal mid-pairing closes its transient transport without emitting',
      () async {
        final storage = _FakeStorage();
        final bridge = await _bootedBridge(storage);
        final conn = _SpyConn();
        final transport = _HangingTransport();
        final factoryCalled = Completer<void>();
        final vm = PairingViewModel(
          storage,
          (qr, key, cancellation) async {
            factoryCalled.complete();
            return transport;
          },
          conn,
          _PrefsForTest(),
          bridge,
        );

        final attempt = vm.onQrScanned(_qrUri);
        await factoryCalled.future;
        vm.dispose();
        await attempt;

        expect(transport.closeCalls, 1);
        expect(conn.adoptedChannel, isNull);
        expect(vm.state, isA<PairingConnecting>());

        conn.dispose();
      },
    );

    test('transport readiness timeout awaits cancellation cleanup', () async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final conn = _SpyConn();
      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final factoryResult = Completer<PeerTransport>();
      var cleanupFinished = false;
      final vm = PairingViewModel(
        storage,
        (qr, key, cancellation) {
          cancellation.addCancellationListener(() async {
            cleanupStarted.complete();
            await releaseCleanup.future;
            cleanupFinished = true;
            factoryResult.completeError(StateError('connect cancelled'));
          });
          return factoryResult.future;
        },
        conn,
        _PrefsForTest(),
        bridge,
        transportConnectTimeout: Duration.zero,
      );

      var pairingSettled = false;
      final pairing = vm
          .onQrScanned(_qrUri)
          .whenComplete(() => pairingSettled = true);
      await cleanupStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(
        pairingSettled,
        isFalse,
        reason: 'timeout completion must wait for socket cleanup',
      );

      releaseCleanup.complete();
      await pairing;

      expect(cleanupFinished, isTrue);
      expect(vm.state, isA<PairingError>());
      expect((vm.state as PairingError).message, contains('Timed out'));
      expect(conn.adoptedChannel, isNull);

      vm.dispose();
      conn.dispose();
    });

    test(
      'a stale pairing completion cannot adopt a channel or emit paired',
      () async {
        final storage = _FakeStorage();
        final bridge = await _bootedBridge(storage);
        final conn = _SpyConn();
        final releaseReply = Completer<void>();
        final requestSent = Completer<void>();
        final vm = PairingViewModel(
          storage,
          _factoryReplyingWith(
            {'type': 'pair_ok', 'session_name': 'stale session'},
            beforeReply: releaseReply.future,
            onRequest: requestSent.complete,
          ),
          conn,
          _PrefsForTest(),
          bridge,
        );

        final attempt = vm.onQrScanned(_qrUri);
        await requestSent.future;
        vm.retry();
        releaseReply.complete();
        await attempt;

        expect(vm.state, isA<PairingScanning>());
        expect(storage._saved, isEmpty);
        expect(conn.adoptedChannel, isNull);

        vm.dispose();
        conn.dispose();
      },
    );

    test(
      'retry during peer persistence fences the write and closes its attempt transport',
      () async {
        final storage = _DeferredPairingStorage();
        final bridge = await _bootedBridge(storage);
        final conn = _SpyConn();
        late _MemTransport firstTransport;
        final secondTransport = _HangingTransport();
        final secondFactoryStarted = Completer<void>();
        final firstFactory = _factoryReplyingWith({
          'type': 'pair_ok',
          'session_name': 'stale persistence',
        }, onTransport: (value) => firstTransport = value);
        var factoryCalls = 0;
        final vm = PairingViewModel(
          storage,
          (qr, key, cancellation) async {
            if (factoryCalls++ == 0) {
              return firstFactory(qr, key, cancellation);
            }
            secondFactoryStarted.complete();
            return secondTransport;
          },
          conn,
          _PrefsForTest(),
          bridge,
        );

        final emitted = <PairingState>[];
        vm.addListener(() => emitted.add(vm.state));
        final pairing = vm.onQrScanned(_qrUri);
        await storage.saveStarted.future;
        emitted.clear();
        vm.retry();
        final retryPairing = vm.onQrScanned(_qrUri);
        await secondFactoryStarted.future;
        storage.releaseSave.complete();
        await pairing;

        expect(storage._saved, isEmpty);
        expect(firstTransport.closeCalls, 1);
        expect(secondTransport.closeCalls, 0);
        expect(conn.adoptedChannel, isNull);
        expect(vm.state, isA<PairingConnecting>());
        expect(emitted.whereType<PairingPaired>(), isEmpty);
        expect(emitted.whereType<PairingError>(), isEmpty);

        vm.dispose();
        await retryPairing;
        expect(secondTransport.closeCalls, 1);
        conn.dispose();
      },
    );

    test(
      'dispose during peer persistence fences the write and closes its attempt transport',
      () async {
        final storage = _DeferredPairingStorage();
        final bridge = await _bootedBridge(storage);
        final conn = _SpyConn();
        late _MemTransport transport;
        final vm = PairingViewModel(
          storage,
          _factoryReplyingWith({
            'type': 'pair_ok',
            'session_name': 'disposed persistence',
          }, onTransport: (value) => transport = value),
          conn,
          _PrefsForTest(),
          bridge,
        );

        final emitted = <PairingState>[];
        vm.addListener(() => emitted.add(vm.state));
        final pairing = vm.onQrScanned(_qrUri);
        await storage.saveStarted.future;
        emitted.clear();
        vm.dispose();
        storage.releaseSave.complete();
        await pairing;

        expect(storage._saved, isEmpty);
        expect(transport.closeCalls, 1);
        expect(conn.adoptedChannel, isNull);
        expect(vm.state, isA<PairingConnecting>());
        expect(emitted.whereType<PairingPaired>(), isEmpty);
        expect(emitted.whereType<PairingError>(), isEmpty);

        conn.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // Widget harness test — page reacts to ViewModel state changes
  // -------------------------------------------------------------------------

  group('PairingPage widget', () {
    testWidgets('navigates via PairingPaired after pair_ok', (tester) async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final factory = _factoryReplyingWith({
        'type': 'pair_ok',
        'session_name': 'test session',
      });
      final conn = _SpyConn();
      final vm = PairingViewModel(
        storage,
        factory,
        conn,
        _PrefsForTest(),
        bridge,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: vm,
            child: _PairingPageTestHarness(vm: vm),
          ),
        ),
      );

      await tester.runAsync(() async {
        await vm.onQrScanned(_qrUri);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(vm.state, isA<PairingPaired>());
      expect(find.text('Done'), findsOneWidget);

      vm.dispose();
      conn.dispose(); // cancel the watchdog before the timer-pending check
    });

    testWidgets('shows error view on pair_error', (tester) async {
      final factory = _factoryReplyingWith({
        'type': 'pair_error',
        'code': 'token_consumed',
        'message': 'Already used',
      });
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final conn = _SpyConn();
      final vm = PairingViewModel(
        storage,
        factory,
        conn,
        _PrefsForTest(),
        bridge,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: vm,
            child: _PairingPageTestHarness(vm: vm),
          ),
        ),
      );

      await tester.runAsync(() async {
        await vm.onQrScanned(_qrUri);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(vm.state, isA<PairingError>());
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(vm.state, isA<PairingScanning>());

      vm.dispose();
      conn.dispose(); // cancel the watchdog before the timer-pending check
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal widget harness that renders PairingState without MobileScanner
// ---------------------------------------------------------------------------

class _PairingPageTestHarness extends StatelessWidget {
  final PairingViewModel vm;
  const _PairingPageTestHarness({required this.vm});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PairingViewModel>().state;

    return Scaffold(
      body: switch (state) {
        PairingIdle() => const Text('Idle'),
        PairingScanning() => const Text('Scanning'),
        PairingConnecting() => const Text('Connecting…'),
        PairingPaired() => const Text('Done'),
        PairingError(:final message) => Column(
          children: [
            Text(message),
            ElevatedButton(onPressed: vm.retry, child: const Text('Try again')),
          ],
        ),
      },
    );
  }
}
