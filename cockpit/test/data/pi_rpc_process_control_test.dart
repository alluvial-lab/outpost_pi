import 'dart:convert';

import 'package:cockpit/app/cockpit/data/rpc/pi_rpc_process.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_ui_response.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/rpc_error.dart';
import 'package:flutter_test/flutter_test.dart';

const expectedRelayCommands = <PiRelayControlAction, String>{
  PiRelayControlAction.on: 'relay_on',
  PiRelayControlAction.off: 'relay_off',
  PiRelayControlAction.toggle: 'relay_toggle',
  PiRelayControlAction.status: 'relay_status',
};

Map<String, Object?> decodeControl(PiControlCommand command) =>
    jsonDecode(schemaControlPromptForTesting(command)['message']! as String)
        as Map<String, Object?>;

void main() {
  group('PiRpcProcess metadata-only diagnostics', () {
    test('summarizes frames without exposing payload-bearing fields', () {
      const canaries = <String>[
        'prompt-secret-7F3A',
        'tool-output-secret-8B4C',
        'image-base64-secret-9D5E',
        'pairing-token-secret-0A6F',
      ];
      final line = jsonEncode(<String, Object?>{
        'type': 'malicious-type-${canaries[0]}',
        'id': 'malicious-id-${canaries[1]}',
        'message': canaries[0],
        'result': canaries[1],
        'images': <String>[canaries[2]],
        'token': canaries[3],
      });

      final input = rpcFrameDiagnosticForTesting(
        '$line\n',
        processOutput: false,
      );
      final output = rpcFrameDiagnosticForTesting(line, processOutput: true);

      expect(input, startsWith('[rpc-mode-agent][in] bytes='));
      expect(input, contains('category=event'));
      expect(output, startsWith('[rpc-mode-agent][out] bytes='));
      expect(output, contains('category=event'));
      for (final canary in canaries) {
        expect(input, isNot(contains(canary)));
        expect(output, isNot(contains(canary)));
      }
      expect(input, isNot(contains('malicious-type')));
      expect(input, isNot(contains('malicious-id')));
    });

    test('retains only fixed categories and generated request ids', () {
      // `req-42` survives ONLY because its provenance is known (Cockpit
      // generated it and it is in the pending set). Shape alone is insufficient.
      final response = rpcFrameDiagnosticForTesting(
        jsonEncode(<String, Object?>{
          'type': 'response',
          'id': 'req-42',
          'data': 'secret-response-body',
        }),
        processOutput: true,
        knownRequestIds: {'req-42'},
      );
      final nonObject = rpcFrameDiagnosticForTesting(
        jsonEncode(<Object?>['secret-list-item']),
        processOutput: true,
      );
      const malformedSecret = '{secret-malformed-json';
      final malformed = rpcFrameDiagnosticForTesting(
        malformedSecret,
        processOutput: true,
      );

      expect(response, contains('category=response'));
      expect(response, contains('id=req-42'));
      expect(response, isNot(contains('secret-response-body')));
      expect(nonObject, contains('category=non_object'));
      expect(nonObject, isNot(contains('secret-list-item')));
      expect(malformed, contains('category=malformed'));
      expect(malformed, isNot(contains(malformedSecret)));
    });

    test('strips a shape-matching request id whose provenance is unknown', () {
      // An untrusted child can craft `id: req-<numeric-secret>` with a
      // syntactically valid shape; only membership in the pending set proves
      // Cockpit generated it. A numeric secret smuggled this way must NOT
      // survive into the diagnostic.
      final malicious = rpcFrameDiagnosticForTesting(
        jsonEncode(<String, Object?>{
          'type': 'event',
          'id': 'req-1337',
          'data': 'irrelevant',
        }),
        processOutput: true,
        // `req-1337` is NOT in the pending set — unknown provenance.
        knownRequestIds: {'req-42'},
      );
      expect(malicious, contains('category=event'));
      // The smuggled numeric id is stripped because its provenance is unknown.
      expect(malicious, isNot(contains('req-1337')));
      expect(malicious, isNot(contains('1337')));
      // And the response-body content is still stripped.
      expect(malicious, isNot(contains('irrelevant')));
    });
  });

  group('PiRpcProcess cockpit control serialization', () {
    test('emits every relay control as its exact schema prompt envelope', () {
      expect(
        expectedRelayCommands.keys.toSet(),
        PiRelayControlAction.values.toSet(),
        reason: 'every relay action must have an independent wire oracle',
      );

      for (final entry in expectedRelayCommands.entries) {
        final prompt = schemaControlPromptForTesting(
          PiControlCommand.relay(entry.key),
        );

        expect(prompt, containsPair('type', 'prompt'));
        expect(prompt['message'], isA<String>());
        expect(prompt['message'], isNot(contains('\u0000outpost-pi-ctrl:')));
        expect(decodeControl(PiControlCommand.relay(entry.key)), {
          'type': 'outpost_pi_control',
          'command': entry.value,
        });
      }
    });

    test('serializes every UI response variant at the process boundary', () {
      expect(
        schemaUiResponseForTesting('value-id', const RpcUiValueResponse('ok')),
        <String, Object?>{
          'type': 'extension_ui_response',
          'id': 'value-id',
          'value': 'ok',
        },
      );
      expect(
        schemaUiResponseForTesting(
          'yes-id',
          const RpcUiConfirmationResponse(true),
        ),
        <String, Object?>{
          'type': 'extension_ui_response',
          'id': 'yes-id',
          'confirmed': true,
        },
      );
      expect(
        schemaUiResponseForTesting(
          'no-id',
          const RpcUiConfirmationResponse(false),
        ),
        <String, Object?>{
          'type': 'extension_ui_response',
          'id': 'no-id',
          'confirmed': false,
        },
      );
      expect(
        schemaUiResponseForTesting('cancel-id', const RpcUiCancelledResponse()),
        <String, Object?>{
          'type': 'extension_ui_response',
          'id': 'cancel-id',
          'cancelled': true,
        },
      );
    });

    test('emits rename controls with a trimmed schema name argument', () {
      expect(decodeControl(PiControlCommand.rename('  desk-agent  ')), {
        'type': 'outpost_pi_control',
        'command': 'rename',
        'name': 'desk-agent',
      });
    });

    test('rejects an empty rename before serializing a prompt frame', () {
      expect(
        () => schemaControlPromptForTesting(PiControlCommand.rename('   ')),
        throwsA(
          isA<RpcError>().having(
            (error) => error.message,
            'message',
            'Control rename requires a non-empty name.',
          ),
        ),
      );
    });
  });
}
