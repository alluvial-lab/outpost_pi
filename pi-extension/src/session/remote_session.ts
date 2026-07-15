import { randomBytes } from "node:crypto";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { RemoteSessionId } from "../protocol/session_scope.js";
import type { ThinkingLevel } from "../protocol/types.js";

export type { RemoteSessionId };

/** Describe the mobile-visible identity and runtime metadata of one Pi SDK session. */
export interface RemoteSession {
  sessionId: RemoteSessionId;
  peerId: string;
  roomId: string;
  cwd: string;
  name: string;
  startedAt: number;
  model?: string;
  thinking?: ThinkingLevel;
  working: boolean;
}

type SessionIdContext = Pick<ExtensionContext, "sessionManager">;

/**
 * Whether `value` exposes a usable `sessionManager.getSessionId()`. Reading the
 * `sessionManager` getter on a STALE SDK ctx throws a stale-context error via
 * `ExtensionRunner.assertActive()`, and this helper is reached from the relay
 * message router (`_routeClientMessageFrom` → `_currentRemoteSessionId` →
 * `resolveRemoteSessionId`) on EVERY inbound session-scoped message — so an
 * unguarded read here crashes pi (the same crash-class as `wrapActionCtx`'s
 * `modelRegistry` access, one frame earlier and more reachable). The stale
 * error is caught by the caller (`resolveRemoteSessionId`), which falls back to
 * a fresh UUID7 id; the session_gate then rejects the stale message gracefully
 * instead of crashing the process.
 */
function safeSessionManager(value: unknown): { getSessionId(): unknown } | undefined {
  if (typeof value !== "object" || value === null) return undefined;
  if (!("sessionManager" in value)) return undefined;
  let sm: unknown;
  try {
    sm = (value as { sessionManager?: unknown }).sessionManager;
  } catch {
    // Stale ctx: the guarded getter threw. Caller falls back to a UUID7.
    return undefined;
  }
  if (sm && typeof (sm as { getSessionId?: unknown }).getSessionId === "function") {
    return sm as { getSessionId(): unknown };
  }
  return undefined;
}

/** Generate a time-ordered UUID v7 fallback identity when the SDK session id is unavailable. */
export function uuid7(): string {
  const bytes = randomBytes(16);
  const now = BigInt(Date.now());
  bytes[0] = Number((now >> 40n) & 0xffn);
  bytes[1] = Number((now >> 32n) & 0xffn);
  bytes[2] = Number((now >> 24n) & 0xffn);
  bytes[3] = Number((now >> 16n) & 0xffn);
  bytes[4] = Number((now >> 8n) & 0xffn);
  bytes[5] = Number(now & 0xffn);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** Resolve the SDK session id, falling back to a new UUID v7 when a context is absent or stale. */
export function resolveRemoteSessionId(ctx: unknown): RemoteSessionId {
  const sm = safeSessionManager(ctx);
  if (sm) {
    let sdkId: unknown;
    try {
      sdkId = sm.getSessionId();
    } catch {
      // `getSessionId()` itself may throw on a stale runner; fall back.
      return uuid7();
    }
    if (typeof sdkId === "string" && sdkId.length > 0) return sdkId;
  }
  return uuid7();
}

/** Durable transcript identity shared with the mobile app's Hive key shape. */
export function remoteSessionDurableKey(
  session: Pick<RemoteSession, "peerId" | "roomId" | "sessionId">,
): string {
  return `${session.peerId}:${session.roomId}:${session.sessionId}`;
}

/** Cache the active remote-session identity and clear it at the owning session lifecycle boundary. */
export class RemoteSessionIssuer {
  private currentId: RemoteSessionId | null = null;

  current(): RemoteSessionId | null {
    return this.currentId;
  }

  capture(ctx: unknown): RemoteSessionId {
    const next = resolveRemoteSessionId(ctx);
    this.currentId = next;
    return next;
  }

  currentOrCapture(ctx: unknown): RemoteSessionId {
    return this.currentId ?? this.capture(ctx);
  }

  clear(): void {
    this.currentId = null;
  }
}
