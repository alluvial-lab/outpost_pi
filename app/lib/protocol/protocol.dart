// Public protocol facade. Generated DTOs live under generated/ and are
// regenerated from the canonical schema; do not hand-edit generated files.
//
// The relay-control schema family (`relayControl`) IS in the schema IR
// (protocol/schema/relay-control.schema.json, declared in manifest.json).
// The hand-maintained relay-control DTO island exported below exists because
// Dart codegen for the relay-control family is deferred, not because the
// schema is absent. Retire this island when Dart relay-control generation ships.
import 'generated/protocol.g.dart';

export 'control_frames.dart';
export 'generated/protocol.g.dart';

const Set<String> sessionScopedClientTypes =
    generatedSessionScopedClientMessageTypes;
const Set<String> sessionScopedServerTypes =
    generatedSessionScopedServerMessageTypes;

bool isSessionScopedClientType(String type) =>
    isGeneratedSessionScopedClientMessageType(type);

bool isSessionScopedServerType(String type) =>
    isGeneratedSessionScopedServerMessageType(type);
