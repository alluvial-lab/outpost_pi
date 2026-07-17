import 'dart:convert';

import 'package:cockpit/app/cockpit/data/rpc/pi_rpc_process.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_ui_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
