// Fleet update ViewModel state-machine tests.
//
// Drives the real ConnectionManager + ActionsRepository over a fake channel
// (the same harness pattern as actions_repository_test) so the tests cover
// the production send path and the derivation rules: transport drop during
// a run → restarting (connection-error UX suppressed), room re-announce →
// verified, no recovery within the window → lost, and every terminal path
// clearing the suppression flag.

import 'dart:async';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/settings/fleet_update_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeChannel implements IChannel, IControlLink {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final _controlCtrl = StreamController<ControlInbound>.broadcast();
  final List<ClientMessage> sent = [];

  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;

  @override
  Stream<ControlInbound> get controlFrames => _controlCtrl.stream;

  @override
  Future<void> send(ClientMessage msg) async {
    sent.add(msg);
  }

  @override
  void sendControl(Map<String, dynamic> json) {}

  @override
  Future<void> close() async {
    await _ctrl.close();
    await _controlCtrl.close();
  }

  void push(ServerMessage m) => _ctrl.add(m);
  void pushControl(ControlInbound m) => _controlCtrl.add(m);
}

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];
}

const _peer = PeerRecord(
  remoteEpk: 'epk_fleet',
  sessionName: 'pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

void _seedSession(_FakeChannel ch, String sessionId) {
  ch.push(
    PairOk(
      inReplyTo: 'pair-fleet',
      sessionName: 'pi',
      sessionStartedAt: DateTime.utc(2026).millisecondsSinceEpoch,
      roomId: 'main',
      sessionId: sessionId,
    ),
  );
}

class _Harness {
  final ConnectionManager cm;
  final FleetUpdateViewModel vm;
  final _FakeChannel channel;

  _Harness(this.cm, this.vm, this.channel);

  /// Re-adopt a fresh channel + session announce (the fleet-came-back path).
  Future<void> reconnect() async {
    final ch = _FakeChannel();
    final online = _waitFor(cm.statusStream, (s) => s is StatusOnline);
    cm.adopt(ch, _peer);
    await online;
    _seedSession(ch, 'session-fleet-next');
  }
}

Future<void> _waitFor<T>(
  Stream<T> stream,
  bool Function(T) test, {
  Duration timeout = const Duration(seconds: 2),
}) {
  return stream.where(test).first.timeout(timeout);
}

Future<_Harness> _setup({
  Duration recoveryTimeout = const Duration(milliseconds: 150),
  Duration requestTimeout = const Duration(milliseconds: 60),
}) async {
  final ch = _FakeChannel();
  final cm = ConnectionManager(
    factory: (_, _) async => ch,
    storage: _FakeStorage(),
    emitDebounce: Duration.zero,
  );
  final repo = ActionsRepository(cm);
  final vm = FleetUpdateViewModel(
    cm,
    repo,
    recoveryTimeout: recoveryTimeout,
    requestTimeout: requestTimeout,
  );
  final online = _waitFor(cm.statusStream, (s) => s is StatusOnline);
  cm.adopt(ch, _peer);
  await online;
  _seedSession(ch, 'session-fleet');
  // Let the PairOk-driven rooms snapshot settle before asserting.
  await Future<void>.delayed(Duration.zero);
  return _Harness(cm, vm, ch);
}

Future<void> waitForState(
  FleetUpdateViewModel vm,
  bool Function() test, {
  Duration timeout = const Duration(seconds: 2),
}) {
  if (test()) return Future.value();
  final completer = Completer<void>();
  void listener() {
    if (test() && !completer.isCompleted) completer.complete();
  }

  vm.addListener(listener);
  return completer.future.timeout(timeout).whenComplete(() {
    vm.removeListener(listener);
  });
}

void main() {
  group('wire-event → state mapping', () {
    test('harness reaches a connected owned room', () async {
      final h = await _setup();
      expect(h.vm.roomConnected, isTrue);
      expect(h.vm.startBlockedReason, isNull);
      h.cm.dispose();
      h.vm.dispose();
    });

    test('updating → FleetUpdating with suppression active', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdating);
      expect(h.vm.suppressConnectionErrors, isTrue);
      expect(h.vm.canStart, isFalse);
      h.cm.dispose();
      h.vm.dispose();
    });

    test(
      'arming → FleetArming with parsed peer table, malformed rows dropped',
      () async {
        final h = await _setup();
        h.channel.push(
          const FleetUpdateStatus(
            updateId: 'u1',
            phase: 'arming',
            peers: [
              {'peer': '/vm@a', 'state': 'armed'},
              {'peer': '/vm@b', 'state': 'deferred', 'reason': 'turn active'},
              {
                'peer': '/vm@c',
                'state': 'declined',
                'reason': 'hot-reload disabled',
              },
              {'peer': '/vm@d', 'state': 'no-ack'},
              {'peer': '/vm@bad', 'state': 'nonsense'},
              {'peer': '', 'state': 'armed'},
              'not-a-map',
            ],
          ),
        );
        await waitForState(h.vm, () => h.vm.state is FleetArming);
        final state = h.vm.state as FleetArming;
        expect(state.peers, [
          const FleetPeerAck(peer: '/vm@a', state: 'armed'),
          const FleetPeerAck(
            peer: '/vm@b',
            state: 'deferred',
            reason: 'turn active',
          ),
          const FleetPeerAck(
            peer: '/vm@c',
            state: 'declined',
            reason: 'hot-reload disabled',
          ),
          const FleetPeerAck(peer: '/vm@d', state: 'no-ack'),
        ]);
        expect(h.vm.suppressConnectionErrors, isTrue);
        h.cm.dispose();
        h.vm.dispose();
      },
    );

    test('update_failed → FleetUpdateFailed carrying the detail', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(
          updateId: 'u1',
          phase: 'update_failed',
          detail: 'npm ERR! network',
        ),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdateFailed);
      expect((h.vm.state as FleetUpdateFailed).detail, 'npm ERR! network');
      expect(
        h.vm.suppressConnectionErrors,
        isFalse,
        reason: 'terminal path clears the suppression flag',
      );
      expect(h.vm.canStart, isTrue);
      h.cm.dispose();
      h.vm.dispose();
    });

    test('already_running → FleetUpdateFailed', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(
          updateId: 'u2',
          phase: 'already_running',
          detail: 'another fleet update is already running',
        ),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdateFailed);
      expect(
        (h.vm.state as FleetUpdateFailed).detail,
        'another fleet update is already running',
      );
      h.cm.dispose();
      h.vm.dispose();
    });
  });

  group('trigger', () {
    test(
      'start() sends a session-scoped fleet_update on the live channel',
      () async {
        final h = await _setup();
        final accepted = await h.vm.start();
        expect(accepted, isTrue);
        final frame = h.channel.sent.whereType<FleetUpdate>().single;
        expect(frame.sessionId, 'session-fleet');
        expect(frame.id, isNotEmpty);
        h.cm.dispose();
        h.vm.dispose();
      },
    );

    test(
      'request that never produces status fails via the request timeout',
      () async {
        final h = await _setup();
        await h.vm.start();
        await waitForState(h.vm, () => h.vm.state is FleetUpdateFailed);
        expect(
          (h.vm.state as FleetUpdateFailed).detail,
          contains('No fleet-update response'),
        );
        expect(h.vm.suppressConnectionErrors, isFalse);
        h.cm.dispose();
        h.vm.dispose();
      },
    );

    test(
      'synchronous error reply correlated by in_reply_to fails the run',
      () async {
        final h = await _setup();
        await h.vm.start();
        final frame = h.channel.sent.whereType<FleetUpdate>().single;
        h.channel.push(
          ErrorMessage(
            inReplyTo: frame.id,
            code: 'bad_request',
            message: 'unknown client type fleet_update',
          ),
        );
        await waitForState(h.vm, () => h.vm.state is FleetUpdateFailed);
        expect(
          (h.vm.state as FleetUpdateFailed).detail,
          contains('unknown client type fleet_update'),
        );
        h.cm.dispose();
        h.vm.dispose();
      },
    );

    test(
      'error replies for unrelated ids never touch the fleet state',
      () async {
        final h = await _setup();
        h.channel.push(
          const ErrorMessage(
            inReplyTo: 'someone-else',
            code: 'bad_request',
            message: 'unrelated',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(h.vm.state, isA<FleetIdle>());
        h.cm.dispose();
        h.vm.dispose();
      },
    );

    test('start() is refused while a run is live', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdating);
      final sendsBefore = h.channel.sent.length;
      expect(await h.vm.start(), isFalse);
      expect(h.channel.sent.length, sendsBefore);
      h.cm.dispose();
      h.vm.dispose();
    });

    test(
      'start() is refused with a reason when no room is connected',
      () async {
        final h = await _setup();
        await h.cm.disconnect();
        await Future<void>.delayed(Duration.zero);
        expect(h.vm.roomConnected, isFalse);
        expect(h.vm.startBlockedReason, isNotNull);
        expect(await h.vm.start(), isFalse);
        expect(h.channel.sent.whereType<FleetUpdate>(), isEmpty);
        h.vm.dispose();
      },
    );
  });

  group('derivation rules', () {
    test(
      'drop during updating → restarting, room re-announce → verified, suppression cleared',
      () async {
        final h = await _setup();
        h.channel.push(
          const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
        );
        await waitForState(h.vm, () => h.vm.state is FleetUpdating);

        // The coordinator Pi exits behind its own arming — the channel drops.
        await h.cm.disconnect();
        await waitForState(h.vm, () => h.vm.state is FleetRestarting);
        expect(
          h.vm.suppressConnectionErrors,
          isTrue,
          reason: 'expected mass disconnect must not trip error UX',
        );

        // Fleet comes back: fresh channel, fresh session announce.
        await h.reconnect();
        await waitForState(h.vm, () => h.vm.state is FleetVerified);
        expect(h.vm.suppressConnectionErrors, isFalse);
        expect(h.vm.canStart, isTrue);
        h.cm.dispose();
        h.vm.dispose();
      },
    );

    test('drop during arming also derives restarting', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(
          updateId: 'u1',
          phase: 'arming',
          peers: [
            {'peer': '/vm@a', 'state': 'armed'},
          ],
        ),
      );
      await waitForState(h.vm, () => h.vm.state is FleetArming);
      await h.cm.disconnect();
      await waitForState(h.vm, () => h.vm.state is FleetRestarting);
      expect(h.vm.suppressConnectionErrors, isTrue);
      h.vm.dispose();
    });

    test('no recovery within the window → lost and error UX resumes', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdating);
      await h.cm.disconnect();
      await waitForState(h.vm, () => h.vm.state is FleetRestarting);
      await waitForState(h.vm, () => h.vm.state is FleetUpdateLost);
      expect(h.vm.suppressConnectionErrors, isFalse);
      expect(h.vm.canStart, isTrue);
      h.vm.dispose();
    });

    test(
      'wire events after a flap resume the run instead of wedging it',
      () async {
        final h = await _setup();
        h.channel.push(
          const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
        );
        await waitForState(h.vm, () => h.vm.state is FleetUpdating);
        await h.cm.disconnect();
        await waitForState(h.vm, () => h.vm.state is FleetRestarting);

        // Same-session room returns (a flap, not a restart) and the
        // coordinator keeps reporting — the app resumes wire-following.
        final ch2 = _FakeChannel();
        final online = _waitFor(h.cm.statusStream, (s) => s is StatusOnline);
        h.cm.adopt(ch2, _peer);
        await online;
        _seedSession(ch2, 'session-fleet'); // SAME session id — no verify
        ch2.push(
          const FleetUpdateStatus(
            updateId: 'u1',
            phase: 'arming',
            peers: [
              {'peer': '/vm@a', 'state': 'armed'},
            ],
          ),
        );
        await waitForState(h.vm, () => h.vm.state is FleetArming);
        expect(h.vm.suppressConnectionErrors, isTrue);
        h.cm.dispose();
        h.vm.dispose();
      },
    );

    test(
      'room loss while still online derives restarting (production fleet-restart path)',
      () async {
        final h = await _setup();
        await h.vm.start();
        h.channel.push(
          const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
        );
        await waitForState(h.vm, () => h.vm.state is FleetUpdating);

        // The Pi exits: the relay ends its room while the app's own relay
        // socket stays online. A snapshot without the active room must trip
        // the restart derivation.
        h.channel.pushControl(
          const RoomsSnapshot(
            peer: 'epk_fleet',
            rooms: [RoomInfo(roomId: 'other-cwd', startedAt: 0)],
          ),
        );
        await waitForState(h.vm, () => h.vm.state is FleetRestarting);
        expect(h.vm.suppressConnectionErrors, isTrue);

        // The active-room selector may retarget to another live room after
        // loss; verification must remain bound to the run's original room.
        h.cm.switchRoom('other-cwd');

        // Fresh process announces the room under a fresh session id.
        h.channel.pushControl(
          const RoomsSnapshot(
            peer: 'epk_fleet',
            rooms: [
              RoomInfo(
                roomId: 'main',
                startedAt: 1,
                sessionId: 'session-fleet-2',
              ),
            ],
          ),
        );
        await waitForState(h.vm, () => h.vm.state is FleetVerified);
        expect(h.vm.suppressConnectionErrors, isFalse);
        h.cm.dispose();
        h.vm.dispose();
      },
    );

    test('rooms snapshot without the active room does not verify', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdating);
      await h.cm.disconnect();
      await waitForState(h.vm, () => h.vm.state is FleetRestarting);

      // A different room re-announces (e.g. another cwd on the same peer):
      // not the room this run targeted, so the run stays restarting.
      final ch2 = _FakeChannel();
      final online = _waitFor(h.cm.statusStream, (s) => s is StatusOnline);
      h.cm.adopt(ch2, _peer);
      await online;
      ch2.pushControl(
        const RoomsSnapshot(
          peer: 'epk_fleet',
          rooms: [
            RoomInfo(roomId: 'other-cwd', startedAt: 0, sessionId: 'fresh'),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(h.vm.state, isA<FleetRestarting>());
      h.cm.dispose();
      h.vm.dispose();
    });

    test(
      'same-session room return does not verify (flap, not restart)',
      () async {
        final h = await _setup();
        h.channel.push(
          const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
        );
        await waitForState(h.vm, () => h.vm.state is FleetUpdating);
        await h.cm.disconnect();
        await waitForState(h.vm, () => h.vm.state is FleetRestarting);

        // The room re-announces under the SAME session id: the coordinator
        // Pi never restarted. The run must not claim verification.
        final ch2 = _FakeChannel();
        final online = _waitFor(h.cm.statusStream, (s) => s is StatusOnline);
        h.cm.adopt(ch2, _peer);
        await online;
        _seedSession(ch2, 'session-fleet');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(h.vm.state, isA<FleetRestarting>());
        h.cm.dispose();
        h.vm.dispose();
      },
    );
  });

  group('terminal paths clear the suppression flag (scan-lifecycle)', () {
    test('wire failure terminal', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdating);
      h.channel.push(
        const FleetUpdateStatus(
          updateId: 'u1',
          phase: 'update_failed',
          detail: 'boom',
        ),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdateFailed);
      expect(h.vm.suppressConnectionErrors, isFalse);
      h.cm.dispose();
      h.vm.dispose();
    });

    test('request-timeout terminal', () async {
      final h = await _setup();
      await h.vm.start();
      await waitForState(h.vm, () => h.vm.state is FleetUpdateFailed);
      expect(h.vm.suppressConnectionErrors, isFalse);
      h.cm.dispose();
      h.vm.dispose();
    });

    test('verified terminal after restart window', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(
          updateId: 'u1',
          phase: 'arming',
          peers: [
            {'peer': '/vm@a', 'state': 'armed'},
          ],
        ),
      );
      await waitForState(h.vm, () => h.vm.state is FleetArming);
      await h.cm.disconnect();
      await waitForState(h.vm, () => h.vm.state is FleetRestarting);
      await h.reconnect();
      await waitForState(h.vm, () => h.vm.state is FleetVerified);
      expect(h.vm.suppressConnectionErrors, isFalse);
      h.cm.dispose();
      h.vm.dispose();
    });

    test('lost terminal after recovery timeout', () async {
      final h = await _setup();
      h.channel.push(
        const FleetUpdateStatus(updateId: 'u1', phase: 'updating'),
      );
      await waitForState(h.vm, () => h.vm.state is FleetUpdating);
      await h.cm.disconnect();
      await waitForState(h.vm, () => h.vm.state is FleetUpdateLost);
      expect(h.vm.suppressConnectionErrors, isFalse);
      h.cm.dispose();
      h.vm.dispose();
    });
  });
}
