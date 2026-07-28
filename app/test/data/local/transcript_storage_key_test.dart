import 'dart:convert';

import 'package:app/data/local/transcript_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptStorageKeyManager', () {
    test(
      'first access writes one 32-byte key and later loads reuse it',
      () async {
        final store = _MemoryKeyStore();
        final firstManager = TranscriptStorageKeyManager(store);
        final first = await firstManager.loadOrCreate(keyWasProvisioned: false);
        final second = await TranscriptStorageKeyManager(
          store,
        ).loadOrCreate(keyWasProvisioned: true);

        expect(first, hasLength(32));
        expect(second, first);
        expect(store.writes, 1);
      },
    );

    test('concurrent first access shares one provisioning write', () async {
      final store = _MemoryKeyStore(delayWrites: true);
      final manager = TranscriptStorageKeyManager(store);

      final keys = await Future.wait(<Future<List<int>>>[
        manager.loadOrCreate(keyWasProvisioned: false),
        manager.loadOrCreate(keyWasProvisioned: false),
        manager.loadOrCreate(keyWasProvisioned: false),
      ]);

      expect(store.writes, 1);
      expect(keys[1], keys[0]);
      expect(keys[2], keys[0]);
    });

    test('missing provisioned key fails closed', () async {
      final manager = TranscriptStorageKeyManager(_MemoryKeyStore());

      await expectLater(
        manager.loadOrCreate(keyWasProvisioned: true),
        throwsA(
          isA<TranscriptStorageKeyException>().having(
            (error) => error.code,
            'code',
            'missing_provisioned_key',
          ),
        ),
      );
    });

    test('malformed stored keys fail without replacement', () async {
      for (final malformed in <String>[
        'not base64 %',
        base64Encode(List<int>.filled(31, 7)),
      ]) {
        final store = _MemoryKeyStore(initial: malformed);
        await expectLater(
          TranscriptStorageKeyManager(
            store,
          ).loadOrCreate(keyWasProvisioned: false),
          throwsA(
            isA<TranscriptStorageKeyException>().having(
              (error) => error.code,
              'code',
              'malformed_key',
            ),
          ),
        );
        expect(store.writes, 0);
      }
    });

    test('failed key persistence is detected by re-read', () async {
      final store = _MemoryKeyStore(dropWrites: true);

      await expectLater(
        TranscriptStorageKeyManager(
          store,
        ).loadOrCreate(keyWasProvisioned: false),
        throwsA(
          isA<TranscriptStorageKeyException>().having(
            (error) => error.code,
            'code',
            'key_write_not_persisted',
          ),
        ),
      );
      expect(store.writes, 1);
    });
  });
}

final class _MemoryKeyStore implements TranscriptKeyValueStore {
  _MemoryKeyStore({
    this.initial,
    this.delayWrites = false,
    this.dropWrites = false,
  });

  String? initial;
  final bool delayWrites;
  final bool dropWrites;
  int writes = 0;

  @override
  Future<String?> read() async => initial;

  @override
  Future<void> write(String encodedKey) async {
    writes += 1;
    if (delayWrites) await Future<void>.delayed(Duration.zero);
    if (!dropWrites) initial = encodedKey;
  }

  @override
  Future<void> delete() async => initial = null;
}
