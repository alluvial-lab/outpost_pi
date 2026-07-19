import 'dart:convert';

import 'package:cockpit/app/cockpit/data/rpc/pi_rpc_process.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_ui_response.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final response = rpcFrameDiagnosticForTesting(
        jsonEncode(<String, Object?>{
          'type': 'response',
          'id': 'req-42',
          'data': 'secret-response-body',
        }),
        processOutput: true,
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
  });

  group('PiRpcProcess cockpit control serialization', () {
    test(
      'emits relay controls as schema envelopes on the prompt transport',
      () {
        final prompt = schemaControlPromptForTesting(
          PiControlCommand.relay(PiRelayControlAction.status),
        );

        expect(prompt['type'], 'prompt');
        expect(prompt['message'], isA<String>());
        expect(prompt['message'], isNot(contains('\u0000outpost-pi-ctrl:')));

        final envelope = jsonDecode(prompt['message'] as String);
        expect(envelope, <String, Object>{
          'type': 'outpost_pi_control',
          'command': 'relay_status',
        });
      },
    );

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

    test('emits rename controls with the schema name argument', () {
      final prompt = schemaControlPromptForTesting(
        PiControlCommand.rename('  desk-agent  '),
      );

      final envelope = jsonDecode(prompt['message'] as String);
      expect(envelope, <String, Object>{
        'type': 'outpost_pi_control',
        'command': 'rename',
        'name': 'desk-agent',
      });
    });
  });
}
