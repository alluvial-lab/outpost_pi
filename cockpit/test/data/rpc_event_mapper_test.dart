import 'package:cockpit/app/cockpit/data/adapters/rpc_event_mapper.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/rpc_json_object.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = RpcEventMapper();

  group('RpcEventMapper cockpit control overlay', () {
    test('maps existing relay-state payload without changing fields', () {
      final event = mapper.fromJson(
        _customMessage('outpost-pi:relay-state', <String, Object?>{
          'status': 'connected',
          'connected': true,
          'relayUrl': 'https://relay.example',
          'room': 'main',
        }),
      );

      expect(event, isA<RpcRelayState>());
      final relayState = event as RpcRelayState;
      expect(relayState.status, RelayStatus.connected);
      expect(relayState.connected, isTrue);
      expect(relayState.relayUrl, 'https://relay.example');
      expect(relayState.room, 'main');
    });

    test('maps existing name-assigned payload without changing fields', () {
      final event = mapper.fromJson(
        _customMessage('outpost-pi:name-assigned', <String, Object?>{
          'requested': 'desk-agent',
          'assigned': 'desk-agent#2',
          'changed': true,
        }),
      );

      expect(event, isA<RpcNameAssigned>());
      final nameAssigned = event as RpcNameAssigned;
      expect(nameAssigned.requested, 'desk-agent');
      expect(nameAssigned.assigned, 'desk-agent#2');
      expect(nameAssigned.changed, isTrue);
    });

    test('preserves tool arguments and uses an empty object fallback', () {
      final tool = mapper.fromJson(<String, dynamic>{
        'type': 'tool_execution_start',
        'toolCallId': 'tool-1',
        'toolName': 'read_file',
        'args': <Object?, Object?>{'path': 'README.md', 7: true},
      });
      expect(tool, isA<RpcToolStart>());
      expect((tool as RpcToolStart).args.values, <String, Object?>{
        'path': 'README.md',
        '7': true,
      });

      final emptyTool = mapper.fromJson(<String, dynamic>{
        'type': 'tool_execution_start',
        'args': 'not-an-object',
      });
      expect((emptyTool as RpcToolStart).args, same(RpcJsonObject.empty));
    });

    test('maps paired and mesh-revoked schema neighbors', () {
      final meshWithDetails = mapper.fromJson(
        _customMessage('outpost-pi:mesh-revoked', <String, Object?>{
          'reason': 'removed',
          'future': <Object?>[1, 'two'],
        }),
      );
      expect((meshWithDetails as RpcMeshRevoked).details?.values, {
        'reason': 'removed',
        'future': <Object?>[1, 'two'],
      });
      final paired = mapper.fromJson(
        _customMessage('outpost-pi:paired', <String, Object?>{
          'name': 'Phone',
          'peerId': 'owner-peer',
          'pairedAt': 1760000000001,
        }),
      );
      expect(paired, isA<RpcPaired>());
      final pairedEvent = paired as RpcPaired;
      expect(pairedEvent.name, 'Phone');
      expect(pairedEvent.peerId, 'owner-peer');
      expect(pairedEvent.pairedAt, 1760000000001);

      final pairedWithoutSchemaDetails = mapper.fromJson(
        _customMessage('outpost-pi:paired', <String, Object?>{}),
      );
      expect(pairedWithoutSchemaDetails, isA<RpcUnknown>());
      expect(
        (pairedWithoutSchemaDetails as RpcUnknown).type,
        'message_start:paired:invalid-details',
      );

      final meshRevoked = mapper.fromJson(
        _customMessage('outpost-pi:mesh-revoked', null),
      );
      expect(meshRevoked, isA<RpcMeshRevoked>());
      expect((meshRevoked as RpcMeshRevoked).details, isNull);

      final nonMapDetails = mapper.fromJson(
        _customMessage('outpost-pi:mesh-revoked', 'not-an-object' as dynamic),
      );
      expect((nonMapDetails as RpcMeshRevoked).details, isNull);
    });

    test('keeps unknown custom event types isolated as RpcUnknown', () {
      final event = mapper.fromJson(
        _customMessage('outpost-pi:future-event', <String, Object?>{
          'newField': 'kept raw by pi but ignored by cockpit',
        }),
      );

      expect(event, isA<RpcUnknown>());
      expect((event as RpcUnknown).type, '<unknown-custom-message>');
    });

    test('projects unknown wire discriminators to fixed categories', () {
      const secret = 'path=/Users/operator token=secret-7F3A';
      final cases = <(Map<String, dynamic>, String)>[
        (<String, dynamic>{'type': secret}, '<unknown-frame>'),
        (
          _customMessage(secret, <String, Object?>{}),
          '<unknown-custom-message>',
        ),
        (
          <String, dynamic>{'type': 'extension_ui_request', 'method': secret},
          '<unknown-ui-request>',
        ),
        (
          <String, dynamic>{
            'type': 'message_update',
            'assistantMessageEvent': <String, dynamic>{'type': secret},
          },
          '<unknown-message-update>',
        ),
      ];

      for (final (frame, category) in cases) {
        final event = mapper.fromJson(frame);
        expect(event, isA<RpcUnknown>());
        final unknown = event as RpcUnknown;
        expect(unknown.type, category);
        expect(unknown.type, isNot(contains(secret)));
      }
    });
  });
}

Map<String, dynamic> _customMessage(String customType, Object? details) {
  final message = <String, dynamic>{
    'role': 'custom',
    'customType': customType,
    'content': '',
  };
  if (details != null) message['details'] = details;
  return <String, dynamic>{'type': 'message_start', 'message': message};
}
