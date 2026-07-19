// Public protocol facade. Generated DTOs live under generated/ and are
// regenerated from the canonical schema; do not hand-edit generated files.
import 'generated/protocol.g.dart';

export 'control_frames.dart';
export 'generated/protocol.g.dart';
export 'generated/relay_frames.g.dart';

const Set<String> sessionScopedClientTypes =
    generatedSessionScopedClientMessageTypes;
const Set<String> sessionScopedServerTypes =
    generatedSessionScopedServerMessageTypes;

bool isSessionScopedClientType(String type) =>
    isGeneratedSessionScopedClientMessageType(type);

bool isSessionScopedServerType(String type) =>
    isGeneratedSessionScopedServerMessageType(type);
