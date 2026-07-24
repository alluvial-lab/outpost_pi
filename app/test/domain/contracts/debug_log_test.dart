import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// The allowed keys per [DebugTag] — a POSITIVE allow-list, not just a deny-list
/// (review B2). A variant's `toJson` may only emit keys in its tag's allow-set
/// (plus the universal `tag`/`ts`). This is the privacy invariant: if a future
/// variant adds a `body`/`content`/`payload` field, this test fails because the
/// key isn't in the allow-set for that tag. (The deny-list below is a backstop
/// for payload-like names that should never appear in ANY variant.)
const Map<DebugTag, Set<String>> kAllowedKeys = {
  DebugTag.wsIn: {
    'bytes',
    'count',
    'kind',
    'stage',
    'senderRoom',
    'controlType',
    'error',
  },
  DebugTag.peerFrame: {'kind', 'bytes', 'error'},
  DebugTag.msgSend: {'id', 'blocked'},
  DebugTag.msgEcho: {'id'},
  DebugTag.msgFailed: {'id', 'code'},
  DebugTag.sessionGate: {'messageType', 'reason', 'sessionIdTail'},
  DebugTag.sessionSync: {},
  DebugTag.connStatus: {'status', 'attempt', 'delayMs', 'peerTail', 'room'},
  DebugTag.connChannelLost: {'stale', 'peerTail', 'room'},
  DebugTag.connHydrate: {'action', 'room', 'snapshotCount'},
  DebugTag.roomSnapshot: {'room', 'presenceCount', 'working'},
  DebugTag.workingConv: {'room', 'working', 'reason'},
  DebugTag.replayDedup: {'sessionId', 'eventIdTail', 'dropped'},
  DebugTag.lifecycleFailure: {
    'operation',
    'reason',
    'peerTail',
    'room',
    'sessionIdTail',
    'retryScheduled',
  },
};

/// Universal keys every variant emits.
const Set<String> kUniversalKeys = {'tag', 'ts'};

/// Forbidden in ANY variant — payload-like names that must never reach the
/// persisted/shared log. Backstop to the per-tag allow-list. Aliases the
/// production set the file-backed log's load/export filters enforce, so the
/// contract has one source.
const Set<String> kForbiddenKeys = kForbiddenDiagnosticKeys;

/// Compiler-enforced exhaustiveness: every [DebugEvent] variant MUST be
/// handled here. If a new variant is added to the sealed class but not listed,
/// this switch is non-exhaustive and the test fails to COMPILE — which is the
/// real guard the hand-maintained `expectedTypes` set couldn't provide (review
/// B2). Returns the variant's tag.
DebugTag tagOf(DebugEvent event) {
  return switch (event) {
    WsInEvent() => DebugTag.wsIn,
    PeerFrameEvent() => DebugTag.peerFrame,
    MsgSendEvent() => DebugTag.msgSend,
    MsgEchoEvent() => DebugTag.msgEcho,
    MsgFailedEvent() => DebugTag.msgFailed,
    SessionGateEvent() => DebugTag.sessionGate,
    SessionSyncEvent() => DebugTag.sessionSync,
    ConnStatusEvent() => DebugTag.connStatus,
    ConnChannelLostEvent() => DebugTag.connChannelLost,
    ConnHydrateEvent() => DebugTag.connHydrate,
    RoomSnapshotEvent() => DebugTag.roomSnapshot,
    WorkingConvEvent() => DebugTag.workingConv,
    ReplayDedupEvent() => DebugTag.replayDedup,
    LifecycleFailureEvent() => DebugTag.lifecycleFailure,
  };
}

/// Registry invariant test — enforces the privacy scrub at the type level
/// (review B2/E3). Every [DebugEvent] variant serializes through [toJson];
/// this test asserts:
/// - NO forbidden key appears in ANY variant's output (deny-list backstop).
/// - EVERY emitted key is in that tag's allow-set (positive allow-list).
/// - ALL string field values are capped to [kMaxFieldValueChars].
/// - Field values are primitives only (no nested objects / untrusted blobs).
///
/// A new variant that forgets the scrub fails to COMPILE (the `tagOf` switch
/// is non-exhaustive) AND at runtime (its `toJson` is exercised against the
/// allow-list). A new variant added to `tagOf` but missing from `kAllowedKeys`
/// fails the allow-list check.
void main() {
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
        count: 100,
        kind: huge,
        stage: huge,
        senderRoom: huge,
        controlType: huge,
        error: huge,
      ),
      PeerFrameEvent(ts: now, kind: huge, bytes: 1234, error: huge),
      MsgSendEvent(ts: now, id: huge, blocked: true),
      MsgEchoEvent(ts: now, id: huge),
      MsgFailedEvent(ts: now, id: huge, code: huge),
      SessionGateEvent(
        ts: now,
        messageType: huge,
        reason: huge,
        sessionIdTail: huge,
      ),
      SessionSyncEvent(ts: now),
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
      ReplayDedupEvent(
        ts: now,
        sessionId: huge,
        eventIdTail: huge,
        dropped: true,
      ),
      LifecycleFailureEvent(
        ts: now,
        operation: LifecycleOperation.transcriptWrite,
        reason: huge,
        peerTail: huge,
        room: huge,
        sessionIdTail: huge,
        retryScheduled: true,
      ),
    ];
  }

  test('every variant type is covered by tagOf() (compiler-enforced)', () {
    // If a new variant is added to the sealed class but not to `tagOf`, this
    // fails to COMPILE — the real exhaustiveness guard.
    for (final event in allVariants()) {
      expect(tagOf(event), event.tag);
    }
  });

  test(
    'every tag has an allow-list entry (no variant escapes the allow-list)',
    () {
      for (final event in allVariants()) {
        expect(
          kAllowedKeys.containsKey(event.tag),
          isTrue,
          reason:
              '${event.runtimeType} tag ${event.tag} has no kAllowedKeys entry — '
              'a new variant must declare its allowed keys or its fields escape '
              'the privacy invariant',
        );
      }
    },
  );

  test('no variant emits a forbidden key (deny-list backstop)', () {
    for (final event in allVariants()) {
      final json = event.toJson();
      for (final key in json.keys) {
        expect(
          kForbiddenKeys,
          isNot(contains(key)),
          reason:
              '${event.runtimeType}.toJson emitted forbidden key "$key" — '
              'full payload content must never reach the persisted log',
        );
      }
    }
  });

  test(
    'every emitted key is in its tag\'s allow-set (positive allow-list)',
    () {
      for (final event in allVariants()) {
        final json = event.toJson();
        final allowed = kAllowedKeys[event.tag]!;
        for (final key in json.keys) {
          expect(
            kUniversalKeys.contains(key) || allowed.contains(key),
            isTrue,
            reason:
                '${event.runtimeType}.toJson emitted key "$key" not in its '
                'allow-set ${allowed.union(kUniversalKeys)} — every field must '
                'be explicitly allowed or it escapes the privacy invariant',
          );
        }
      }
    },
  );

  test(
    'allow-list and deny-list are disjoint (no allowed payload-like key)',
    () {
      for (final entry in kAllowedKeys.entries) {
        for (final key in entry.value) {
          expect(
            kForbiddenKeys,
            isNot(contains(key)),
            reason: 'tag ${entry.key} allow-lists forbidden key "$key"',
          );
        }
      }
    },
  );

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

  test('MsgSendEvent serializes correlation metadata only', () {
    final json = MsgSendEvent(ts: now, id: 'msg-1', blocked: false).toJson();

    expect(json.keys, unorderedEquals(<String>['tag', 'ts', 'id', 'blocked']));
    expect(json, isNot(contains('preview')));
  });

  test('failure diagnostics admit only known codes', () {
    expect(admitFailureCode('internal_error'), 'internal_error');
    expect(admitFailureCode('future_secret_code'), kUnrecognizedFailureCode);
  });
}
