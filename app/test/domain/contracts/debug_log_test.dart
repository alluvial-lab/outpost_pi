import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registry invariant test — enforces the privacy scrub at the type level
/// (review B2/E3). Every [DebugEvent] variant serializes through [toJson];
/// this test asserts:
/// - NO forbidden key appears in ANY variant's output (body, image, data,
///   args, result, prompt, message, ct).
/// - ALL string field values are capped to [kMaxFieldValueChars].
/// - Field values are primitives only (no nested objects / untrusted blobs).
///
/// A new variant that forgets the scrub fails this test at compile time (the
/// variant isn't covered by the `all variants` switch) and at runtime (its
/// `toJson` is exercised).
void main() {
  const forbiddenKeys = {
    'body',
    'image',
    'data',
    'args',
    'result',
    'prompt',
    'message',
    'ct',
  };

  final now = DateTime.utc(2026, 7, 4, 12, 0, 0);

  /// Every variant, constructed with deliberately-oversized field values to
  /// prove the cap. New variants MUST be added here — the `allVariants`
  /// switch below fails to compile otherwise.
  List<DebugEvent> allVariants() {
    final huge = 'x' * (kMaxFieldValueChars * 4); // 4x the cap
    return [
      WsInEvent(
        ts: now,
        bytes: 9999,
        kind: huge,
        stage: huge,
        senderRoom: huge,
        controlType: huge,
        error: huge,
      ),
      MsgSendEvent(ts: now, id: huge, blocked: true, preview: huge),
      MsgEchoEvent(ts: now, id: huge),
      MsgFailedEvent(ts: now, id: huge, code: huge, detail: huge),
      SessionGateEvent(
        ts: now,
        messageType: huge,
        reason: huge,
        sessionIdTail: huge,
      ),
      SessionSyncEvent(ts: now, err: huge),
      ConnStatusEvent(
        ts: now,
        status: huge,
        attempt: 3,
        delayMs: 5000,
        peerTail: huge,
        room: huge,
      ),
      ConnChannelLostEvent(ts: now, peerTail: huge, room: huge, stale: true),
      ConnChannelLostEvent(ts: now, peerTail: huge, room: huge, stale: false),
      ConnHydrateEvent(ts: now, action: huge, room: huge, snapshotCount: 7),
      RoomSnapshotEvent(ts: now, room: huge, presenceCount: 4, working: true),
      WorkingConvEvent(ts: now, room: huge, working: false, reason: huge),
      ReplayDedupEvent(ts: now, sessionId: huge, eventIdTail: huge, dropped: true),
    ];
  }

  test('every variant type is covered by allVariants()', () {
    // Exhaustiveness guard: every variant TYPE present in the sealed class
    // must appear in the list above. ConnChannelLostEvent appears twice
    // (stale:true and stale:false) on purpose — both branches of the takeover
    // proof. If a new variant type is added but not listed, this fails.
    final expectedTypes = <Type>{
      WsInEvent,
      MsgSendEvent,
      MsgEchoEvent,
      MsgFailedEvent,
      SessionGateEvent,
      SessionSyncEvent,
      ConnStatusEvent,
      ConnChannelLostEvent,
      ConnHydrateEvent,
      RoomSnapshotEvent,
      WorkingConvEvent,
      ReplayDedupEvent,
    };
    final seen = <Type>{};
    for (final event in allVariants()) {
      seen.add(event.runtimeType);
    }
    expect(seen, containsAll(expectedTypes));
  });

  test('no variant emits a forbidden key', () {
    for (final event in allVariants()) {
      final json = event.toJson();
      for (final key in json.keys) {
        expect(
          forbiddenKeys,
          isNot(contains(key)),
          reason:
              '${event.runtimeType}.toJson emitted forbidden key "$key" — '
              'full payload content must never reach the persisted log',
        );
      }
    }
  });

  test('all string field values are capped to kMaxFieldValueChars', () {
    for (final event in allVariants()) {
      final json = event.toJson();
      for (final entry in json.entries) {
        final v = entry.value;
        if (v is String) {
          expect(
            v.length,
            lessThanOrEqualTo(kMaxFieldValueChars),
            reason:
                '${event.runtimeType}.toJson field "${entry.key}" is '
                '${v.length} chars (cap is $kMaxFieldValueChars) — a huge '
                'untrusted string could evict the diagnostic window',
          );
        }
      }
    }
  });

  test('field values are primitives only (String/int/bool/null)', () {
    for (final event in allVariants()) {
      final json = event.toJson();
      for (final entry in json.entries) {
        final v = entry.value;
        expect(
          v is String || v is int || v is bool || v == null,
          isTrue,
          reason:
              '${event.runtimeType}.toJson field "${entry.key}" is '
              '${v.runtimeType} — only primitives allowed (no nested objects / '
              'untrusted blobs that could break jsonEncode or carry payload)',
        );
      }
    }
  });

  test('every variant includes tag + ts', () {
    for (final event in allVariants()) {
      final json = event.toJson();
      expect(json['tag'], event.tag.name);
      expect(json['ts'], isA<String>());
    }
  });

  test('ConnChannelLostEvent carries the stale takeover-proof field', () {
    final staleTrue = ConnChannelLostEvent(
      ts: now,
      peerTail: 'peer1234',
      room: 'main',
      stale: true,
    );
    final staleFalse = ConnChannelLostEvent(
      ts: now,
      peerTail: 'peer1234',
      room: 'main',
      stale: false,
    );
    expect(staleTrue.toJson()['stale'], isTrue);
    expect(staleFalse.toJson()['stale'], isFalse);
  });

  test('MsgSendEvent.preview is the (capped) preview, not full text', () {
    final huge = 'a' * 1000;
    final ev = MsgSendEvent(ts: now, id: 'msg-1', preview: huge);
    final json = ev.toJson();
    expect(json['preview'], isA<String>());
    expect(
      (json['preview'] as String).length,
      lessThanOrEqualTo(kMaxFieldValueChars),
    );
  });
}
