import 'dart:io';

import 'package:app/protocol/generated/relay_frames.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generated relay ingress contract', () {
    test('committed output matches the canonical schema generator', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'relay_frames_codegen_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });

      final output = File('${tempDir.path}/relay_frames.g.dart');
      final result = await Process.run('node', [
        '../tools/protocol-codegen/bin/protocol-codegen.mjs',
        '--target',
        'dart-relay',
        '--schema',
        '../protocol/schema/manifest.json',
        '--out',
        output.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        output.readAsStringSync(),
        File('lib/protocol/generated/relay_frames.g.dart').readAsStringSync(),
      );
    });

    test('projects canonical limits and directional server DTOs', () {
      expect(relayDefaultMaxDecodedBytes, 4 * 1024 * 1024);
      expect(relayMaxFrameOverheadBytes, 64 * 1024);
      expect(relayMaxPreAuthFrameBytes, 16 * 1024);
      expect(relayMaxRawMessageBytes, 5657944);
      expect(relayMaxDeviceIdBytes, 128);
      expect(relayMaxRoomIdBytes, 256);
      expect(relayMaxRoomNameBytes, 256);
      expect(relayMaxCwdBytes, 4096);
      expect(relayMaxSessionIdBytes, 512);
      expect(relayMaxModelBytes, 256);
      expect(relayMaxThinkingBytes, 32);

      expect(
        RelayServerControlFrameDto.fromJson({
          'type': 'peer_online',
          'peer': 'pi-a',
        }),
        isA<RelayPeerOnlineFrameDto>(),
      );
      expect(
        () => RelayServerControlFrameDto.fromJson({
          'type': 'subscribe_presence',
          'peers': <String>[],
        }),
        throwsFormatException,
      );
    });
  });
}
