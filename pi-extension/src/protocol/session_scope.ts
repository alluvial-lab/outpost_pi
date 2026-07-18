import {
  SERVER_MESSAGE_TYPES,
  SESSION_SCOPED_CLIENT_MESSAGE_TYPES,
  SESSION_SCOPED_SERVER_MESSAGE_TYPES,
  type ClientMessageType,
  type ServerMessageType,
} from "./generated/protocol.generated.js";

/** Identify the currently active Outpost-Pi SDK session on session-scoped frames. */
export type RemoteSessionId = string;

export const SESSION_SCOPED_SERVER_TYPES = SESSION_SCOPED_SERVER_MESSAGE_TYPES;
export const SESSION_SCOPED_CLIENT_TYPES = SESSION_SCOPED_CLIENT_MESSAGE_TYPES;
export { SERVER_MESSAGE_TYPES };

export type SessionScopedServerType = typeof SESSION_SCOPED_SERVER_TYPES[number];
export type NonSessionScopedServerType = Exclude<ServerMessageType, SessionScopedServerType>;
export type SessionScopedClientType = typeof SESSION_SCOPED_CLIENT_TYPES[number];

const sessionScopedServerTypes = new Set<ServerMessageType>(SESSION_SCOPED_SERVER_TYPES);
const sessionScopedClientTypes = new Set<ClientMessageType>(SESSION_SCOPED_CLIENT_TYPES);

export const NON_SESSION_SCOPED_SERVER_TYPES = SERVER_MESSAGE_TYPES.filter(
  (type): type is NonSessionScopedServerType => !sessionScopedServerTypes.has(type),
);

/** Test whether a server message must carry the active remote-session identity. */
export function isSessionScopedServerType(type: string): type is SessionScopedServerType {
  return sessionScopedServerTypes.has(type as ServerMessageType);
}

/** Test membership in the canonical server-message type registry. */
export function isServerMessageType(type: string): type is ServerMessageType {
  return SERVER_MESSAGE_TYPES.includes(type as ServerMessageType);
}

/** Test whether a client message is rejected when it targets a stale remote session. */
export function isSessionScopedClientType(type: string): type is SessionScopedClientType {
  return sessionScopedClientTypes.has(type as ClientMessageType);
}
