import 'package:app/data/local/transcript_box_identity.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptBoxIdentity', () {
    test('separates tuples that collided under legacy sanitization', () {
      const first = TranscriptSessionKey(
        peerId: 'peer/id=',
        roomId: 'room:a',
        sessionId: 'session__one',
      );
      const second = TranscriptSessionKey(
        peerId: 'peer_id_',
        roomId: 'room_a',
        sessionId: 'session_one',
      );

      expect(
        TranscriptBoxIdentity.eventsName(first),
        isNot(TranscriptBoxIdentity.eventsName(second)),
      );
      expect(
        TranscriptBoxIdentity.messagesName(
          const RemoteSessionRef(
            peerEpk: 'peer/id=',
            roomId: 'room:a',
            sessionId: 'session__one',
          ),
        ),
        isNot(
          TranscriptBoxIdentity.messagesName(
            const RemoteSessionRef(
              peerEpk: 'peer_id_',
              roomId: 'room_a',
              sessionId: 'session_one',
            ),
          ),
        ),
      );
    });

    test('is deterministic and changes with every tuple segment', () {
      final baseline = TranscriptBoxIdentity.digest(
        peerId: 'peer',
        roomId: 'room',
        sessionId: 'session',
      );

      expect(
        TranscriptBoxIdentity.digest(
          peerId: 'peer',
          roomId: 'room',
          sessionId: 'session',
        ),
        baseline,
      );
      expect(
        TranscriptBoxIdentity.digest(
          peerId: 'other',
          roomId: 'room',
          sessionId: 'session',
        ),
        isNot(baseline),
      );
      expect(
        TranscriptBoxIdentity.digest(
          peerId: 'peer',
          roomId: 'other',
          sessionId: 'session',
        ),
        isNot(baseline),
      );
      expect(
        TranscriptBoxIdentity.digest(
          peerId: 'peer',
          roomId: 'room',
          sessionId: 'other',
        ),
        isNot(baseline),
      );
    });

    test('emits bounded lowercase ASCII for long Unicode identifiers', () {
      final name = TranscriptBoxIdentity.eventsName(
        TranscriptSessionKey(
          peerId: '配對端' * 500,
          roomId: '部屋/ROOM' * 500,
          sessionId: 'セッション' * 500,
        ),
      );

      expect(name.length, lessThanOrEqualTo(255));
      expect(name, matches(RegExp(r'^[a-z0-9_]+$')));
      expect(name, equals(name.toLowerCase()));
    });

    test('JSON tuple boundaries prevent concatenation aliases', () {
      expect(
        TranscriptBoxIdentity.digest(peerId: 'ab', roomId: 'c', sessionId: 'd'),
        isNot(
          TranscriptBoxIdentity.digest(
            peerId: 'a',
            roomId: 'bc',
            sessionId: 'd',
          ),
        ),
      );
    });
  });
}
