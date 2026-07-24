import 'dart:convert';
import 'dart:io';

import 'eventually.dart';

final class PiHostStatus {
  const PiHostStatus({
    required this.generation,
    required this.state,
    required this.sessionId,
    required this.roomId,
    required this.relayConnected,
    required this.sessionContextHasMessageActions,
  });

  factory PiHostStatus.fromJson(Map<String, dynamic> json) => PiHostStatus(
    generation: json['generation'] as String,
    state: json['state'] as String,
    sessionId: json['sessionId'] as String,
    roomId: json['roomId'] as String,
    relayConnected: json['relayConnected'] as bool,
    sessionContextHasMessageActions:
        json['sessionContextHasMessageActions'] as bool,
  );

  final String generation;
  final String state;
  final String sessionId;
  final String roomId;
  final bool relayConnected;
  final bool sessionContextHasMessageActions;
}

final class PiHostTurnControlStatus {
  const PiHostTurnControlStatus({required this.phase});

  factory PiHostTurnControlStatus.fromJson(Map<String, dynamic> json) =>
      PiHostTurnControlStatus(phase: json['phase'] as String);

  final String phase;
}

final class PiHostEvent {
  const PiHostEvent({
    required this.sequence,
    required this.kind,
    required this.payload,
  });

  factory PiHostEvent.fromJson(Map<String, dynamic> json) => PiHostEvent(
    sequence: (json['seq'] as num).toInt(),
    kind: json['kind'] as String,
    payload: json['payload'],
  );

  final int sequence;
  final String kind;
  final Object? payload;
}

/// Drive the narrow external Pi-host boundary: command in, status/events out.
final class PiHostClient {
  PiHostClient(this.baseUri);

  final Uri baseUri;

  Future<PiHostStatus> status() async =>
      PiHostStatus.fromJson(await _json('GET', '/status'));

  Future<PiHostStatus> waitUntilReady() => eventually<PiHostStatus>(
    () async {
      final value = await status();
      return value.relayConnected && value.state == 'started' ? value : null;
    },
    timeout: const Duration(seconds: 45),
    description: 'Pi host relay-ready state',
  );

  Future<void> invokeOutpostPi(String args) async {
    await _json('POST', '/command', body: <String, Object>{'args': args});
  }

  Future<List<PiHostEvent>> eventsAfter(int sequence) async {
    final response = await _json('GET', '/events?after=$sequence');
    return (response['events'] as List<dynamic>)
        .map((event) => PiHostEvent.fromJson(event as Map<String, dynamic>))
        .toList();
  }

  /// Read the production-generated pair code through the headless E2E seam.
  Future<Map<String, dynamic>> pairCode() => _json('GET', '/pair-code');

  /// Defer settlement of the next SDK user-message action.
  Future<PiHostTurnControlStatus> deferNextTurn() async =>
      PiHostTurnControlStatus.fromJson(
        await _json('POST', '/turn-control/defer-next'),
      );

  Future<PiHostTurnControlStatus> turnControlStatus() async =>
      PiHostTurnControlStatus.fromJson(await _json('GET', '/turn-control'));

  /// Resolve the deferred SDK action; callers poll for its settled phase.
  Future<void> resolveDeferredTurn() async {
    await _json('POST', '/turn-control/resolve');
  }

  Future<PiHostStatus> restartForIsolation() async {
    final before = await status();
    await _json('POST', '/__restart');
    return eventually<PiHostStatus>(
      () async {
        final value = await status();
        return value.generation != before.generation &&
                value.relayConnected &&
                value.state == 'started'
            ? value
            : null;
      },
      timeout: const Duration(seconds: 45),
      description: 'fresh Pi host generation',
    );
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, Object>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, baseUri.resolve(path));
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Pi host request failed ($method $path, ${response.statusCode})',
        );
      }
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
