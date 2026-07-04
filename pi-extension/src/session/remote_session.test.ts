import { describe, expect, test } from "vitest";
import { RemoteSessionIssuer, resolveRemoteSessionId, uuid7 } from "./remote_session.js";

function ctx(id: unknown) {
  return { sessionManager: { getSessionId: () => id } };
}

describe("remote session identity", () => {
  test("resolves the Pi SDK session id when available", () => {
    expect(resolveRemoteSessionId(ctx("sdk-session-1"))).toBe("sdk-session-1");
  });

  test("falls back to UUIDv7 for legacy/test seams", () => {
    const id = resolveRemoteSessionId(ctx(undefined));
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  test("UUIDv7 helper emits version 7 ids", () => {
    expect(uuid7().split("-")[2]?.startsWith("7")).toBe(true);
  });

  test("issuer preserves id across reconnect-style current reads and rotates on replacement capture", () => {
    const issuer = new RemoteSessionIssuer();
    expect(issuer.capture(ctx("session-a"))).toBe("session-a");
    expect(issuer.currentOrCapture(ctx("session-a"))).toBe("session-a");
    expect(issuer.capture(ctx("session-b"))).toBe("session-b");
    expect(issuer.current()).toBe("session-b");
  });
});

/**
 * Regression: `resolveRemoteSessionId` must NOT crash pi when the captured ctx
 * is stale after a session replacement or `/reload`.
 *
 * The SDK marks a replaced ctx's guarded getters (`sessionManager`, `ui`,
 * `cwd`, …) to throw a stale-context error via `assertActive()`. The relay
 * message router calls `resolveRemoteSessionId` on EVERY inbound session-scoped
 * message (`_routeClientMessageFrom` → `_currentRemoteSessionId`), so an
 * unguarded `ctx.sessionManager` read here crashed pi through the router — the
 * same crash-class as `wrapActionCtx`'s `modelRegistry` access, one frame earlier
 * and more reachable. On a stale ctx the resolver must fall back to a fresh
 * UUID7 (so the session_gate rejects the stale message gracefully) instead of
 * throwing.
 */
describe("resolveRemoteSessionId stale-ctx crash guard", () => {
  const STALE_MSG =
    "This extension ctx is stale after session replacement or reload";

  function makeStaleCtx(): Record<string, unknown> {
    return {
      get sessionManager() { throw new Error(STALE_MSG); },
    };
  }

  test("does not throw when the sessionManager getter throws stale-context", () => {
    const id = resolveRemoteSessionId(makeStaleCtx());
    // Falls back to a UUID7 — the session_gate then rejects the stale message
    // gracefully instead of crashing pi.
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  test("does not throw when getSessionId() itself throws stale-context", () => {
    const ctx = {
      sessionManager: {
        getSessionId() { throw new Error(STALE_MSG); },
      },
    };
    expect(resolveRemoteSessionId(ctx)).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});
