// Tests for the new room-related control frames (plan 17).

import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ControlInbound — rooms (plan 17)', () {
    test('room_announced parses with name + cwd', () {
      final c = ControlInbound.tryFromJson({
        'type': 'room_announced',
        'peer': 'epk_A',
        'room_id': 'room-uuid-1',
        'name': 'work',
        'cwd': '/Users/jacob/projects/app',
        'started_at': 1700000000000,
      });
      expect(c, isA<RoomAnnounced>());
      final r = c! as RoomAnnounced;
      expect(r.peer, 'epk_A');
      expect(r.roomId, 'room-uuid-1');
      expect(r.name, 'work');
      expect(r.cwd, '/Users/jacob/projects/app');
      expect(r.startedAt, 1700000000000);
    });

    test('room_announced tolerates missing name + cwd', () {
      final c = ControlInbound.tryFromJson({
        'type': 'room_announced',
        'peer': 'epk_A',
        'room_id': 'main',
        'started_at': 1700000000000,
      });
      expect(c, isA<RoomAnnounced>());
      final r = c! as RoomAnnounced;
      expect(r.name, isNull);
      expect(r.cwd, isNull);
    });

    test('room_ended parses', () {
      final c = ControlInbound.tryFromJson({
        'type': 'room_ended',
        'peer': 'epk_A',
        'room_id': 'room-uuid-1',
        'since_ts': 1700000010000,
      });
      expect(c, isA<RoomEnded>());
      final r = c! as RoomEnded;
      expect(r.roomId, 'room-uuid-1');
      expect(r.sinceTs, 1700000010000);
    });

    test('rooms snapshot parses with nested RoomInfo list', () {
      final c = ControlInbound.tryFromJson({
        'type': 'rooms',
        'peer': 'epk_A',
        'rooms': [
          {
            'room_id': 'r1',
            'name': 'one',
            'cwd': '/one',
            'started_at': 1000,
          },
          {
            'room_id': 'r2',
            'started_at': 2000,
          },
        ],
      });
      expect(c, isA<RoomsSnapshot>());
      final r = c! as RoomsSnapshot;
      expect(r.peer, 'epk_A');
      expect(r.rooms, hasLength(2));
      expect(r.rooms[0].roomId, 'r1');
      expect(r.rooms[0].cwd, '/one');
      expect(r.rooms[1].name, isNull);
      expect(r.rooms[1].cwd, isNull);
    });

    test('room_announced parses optional model and context telemetry', () {
      final c = ControlInbound.tryFromJson({
        'type': 'room_announced',
        'peer': 'epk_A',
        'room_id': 'r1',
        'started_at': 1700000000000,
        'model': 'claude-sonnet-4.5',
        'branch': 'main',
        'ctx_percent': 92,
        'ctx_max': 1000000,
      });
      expect(c, isA<RoomAnnounced>());
      final room = c! as RoomAnnounced;
      expect(room.model, 'claude-sonnet-4.5');
      expect(room.branch, 'main');
      expect(room.ctxPercent, 92);
      expect(room.ctxMax, 1000000);
    });

    test('room_meta_updated parses model and context telemetry', () {
      final c = ControlInbound.tryFromJson({
        'type': 'room_meta_updated',
        'peer': 'epk_A',
        'room_id': 'r1',
        'meta': {
          'model': 'gpt-4o',
          'branch': 'feature/telemetry',
          'ctx_percent': 85,
          'ctx_max': 272000,
        },
      });
      expect(c, isA<RoomMetaUpdated>());
      final r = c! as RoomMetaUpdated;
      expect(r.peer, 'epk_A');
      expect(r.roomId, 'r1');
      expect(r.model, 'gpt-4o');
      expect(r.branch, 'feature/telemetry');
      expect(r.ctxPercent, 85);
      expect(r.ctxMax, 272000);
      expect(r.hasBranch, isTrue);
      expect(r.hasCtxPercent, isTrue);
      expect(r.hasCtxMax, isTrue);
    });

    test('room_meta_updated tolerates missing meta / model (clears value)', () {
      final c = ControlInbound.tryFromJson({
        'type': 'room_meta_updated',
        'peer': 'epk_A',
        'room_id': 'r1',
      });
      expect(c, isA<RoomMetaUpdated>());
      expect((c! as RoomMetaUpdated).model, isNull);
    });

    test('RoomInfo serializes + parses model and telemetry round-trip', () {
      const r = RoomInfo(
        roomId: 'r1',
        startedAt: 100,
        name: 'work',
        cwd: '/x',
        model: 'claude-sonnet-4.5',
        branch: 'main',
        ctxPercent: 92,
        ctxMax: 1000000,
      );
      final back = RoomInfo.fromJson(r.toJson());
      expect(back, r);
      expect(back.model, 'claude-sonnet-4.5');
      expect(back.branch, 'main');
      expect(back.ctxPercent, 92);
      expect(back.ctxMax, 1000000);
    });

    test('RoomMetaUpdated applies set, null-clear, and absent-preserve', () {
      const initial = RoomInfo(
        roomId: 'r1',
        startedAt: 100,
        model: 'gpt-4o',
        branch: 'main',
        ctxPercent: 42,
        ctxMax: 1000000,
      );
      const set = RoomMetaUpdated(
        peer: 'epk_A',
        roomId: 'r1',
        model: 'claude-opus',
        hasThinking: false,
        hasSessionId: false,
        branch: 'feature/telemetry',
        ctxPercent: 85,
        ctxMax: 272000,
      );
      expect(
        set.applyTo(initial),
        initial.copyWith(
          model: 'claude-opus',
          branch: 'feature/telemetry',
          ctxPercent: 85,
          ctxMax: 272000,
        ),
      );

      const cleared = RoomMetaUpdated(
        peer: 'epk_A',
        roomId: 'r1',
        hasModel: false,
        hasThinking: false,
        hasSessionId: false,
        branch: null,
        ctxPercent: null,
        ctxMax: null,
      );
      final clearedRoom = cleared.applyTo(initial);
      expect(clearedRoom.branch, isNull);
      expect(clearedRoom.ctxPercent, isNull);
      expect(clearedRoom.ctxMax, isNull);
      expect(clearedRoom.model, initial.model);

      const absent = RoomMetaUpdated(
        peer: 'epk_A',
        roomId: 'r1',
        hasModel: false,
        hasThinking: false,
        hasSessionId: false,
        hasBranch: false,
        hasCtxPercent: false,
        hasCtxMax: false,
      );
      expect(absent.applyTo(initial), initial);
      expect(initial.copyWith(ctxPercent: null).ctxPercent, isNull);
    });

    test('outbound subscribe_rooms helper has correct shape', () {
      expect(subscribeRoomsFrame(['a', 'b']), {
        'type': 'subscribe_rooms',
        'peers': ['a', 'b'],
      });
      expect(unsubscribeRoomsFrame(['a']), {
        'type': 'unsubscribe_rooms',
        'peers': ['a'],
      });
      expect(roomsCheckFrame(['a']), {
        'type': 'rooms_check',
        'peers': ['a'],
      });
    });
  });
}
