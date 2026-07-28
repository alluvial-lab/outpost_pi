import { describe, expect, test, vi, beforeEach } from "vitest";
import { EventEmitter } from "node:events";
import { readFileSync } from "node:fs";
import { generateEd25519Keypair } from "../pairing/crypto.js";
import { RELAY_AUTH_DOMAIN_PREFIX } from "../protocol/generated/protocol.generated.js";
import { RELAY_MAX_RAW_MESSAGE_BYTES } from "../protocol/relay_ingress.js";

// ── WS mock (class-based, vitest-hoisted) ─────────────────────────────────────
// Must use a proper class so `new WebSocket(...)` works inside RelayClient.

interface RelayAuthDomainVector {
  authDomainPrefix: string;
  nonceBase64: string;
  signingBytesBase64: string;
}

const relayAuthDomainVector = JSON.parse(
  readFileSync(new URL("../../../protocol/fixtures/relay/auth-domain-vector.json", import.meta.url), "utf8"),
) as RelayAuthDomainVector;

// Shared reference: set by the MockWS constructor so tests can access it.
const wsRef: { current: MockWS | null } = { current: null };

class MockWS extends EventEmitter {
  static OPEN = 1;
  readyState = MockWS.OPEN;
  readonly sent: string[] = [];

  constructor(
    _url: string,
    readonly options?: { maxPayload?: number },
  ) {
    super();
    wsRef.current = this;
    // Defer 'open' so RelayClient has time to attach its handlers first.
    setTimeout(() => this.emit("open"), 0);
  }

  send(data: string): void { this.sent.push(data); }
  close(): void { this.emit("close"); }
  terminate(): void { this.emit("close"); }
}

vi.mock("ws", () => ({ default: MockWS }));

// Import AFTER the mock so RelayClient picks up the mocked ws module.
const { RelayClient, relayAuthSigningBytes } = await import("./relay_client.js");

// ── Helpers ───────────────────────────────────────────────────────────────────

function currentWs(): MockWS {
  if (!wsRef.current) throw new Error("no MockWS instance created yet");
  return wsRef.current;
}

function simulateChallenge(ws: MockWS, nonceByte = 0xab): void {
  const nonce = Buffer.alloc(32, nonceByte);
  ws.emit(
    "message",
    Buffer.from(JSON.stringify({ type: "challenge", nonce: nonce.toString("base64") })),
  );
}

async function connectWithAuth(client: InstanceType<typeof RelayClient>, nonceByte = 0xab): Promise<void> {
  const p = client.connect();
  await vi.waitFor(() => expect(currentWs().sent.length).toBeGreaterThan(0));
  simulateChallenge(currentWs(), nonceByte);
  await p;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("RelayClient", () => {
  let keypair: ReturnType<typeof generateEd25519Keypair>;

  beforeEach(() => {
    keypair = generateEd25519Keypair();
    wsRef.current = null;
  });

  test("auth contract: generated prefix signs the shared byte vector", () => {
    const nonce = Buffer.from(relayAuthDomainVector.nonceBase64, "base64");

    expect(RELAY_AUTH_DOMAIN_PREFIX).toBe(relayAuthDomainVector.authDomainPrefix);
    expect(relayAuthSigningBytes(nonce).toString("base64")).toBe(
      relayAuthDomainVector.signingBytesBase64,
    );
  });

  test("connect: configures the generated relay raw-message ceiling", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    await connectWithAuth(client);

    expect(currentWs().options?.maxPayload).toBe(RELAY_MAX_RAW_MESSAGE_BYTES);
    client.close();
  });

  test("connect: sends hello with correct Ed25519 pubkey", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    await connectWithAuth(client);

    const ws = currentWs();
    const hello = JSON.parse(ws.sent[0]) as { type: string; pubkey: string; device_id: string };
    expect(hello.type).toBe("hello");
    expect(hello.pubkey).toBe(Buffer.from(keypair.publicKey).toString("base64"));
    expect(hello.device_id).toBe("test-device");

    client.close();
  });

  test("connect: preserves the narrower room metadata hello contract", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    const connecting = client.connect({
      roomId: "room-1",
      roomMeta: {
        name: "main",
        cwd: "/work",
        session_id: "session-1",
        model: "model-1",
        thinking: "high",
        working: true,
      },
    });
    await vi.waitFor(() => expect(currentWs().sent.length).toBeGreaterThan(0));
    simulateChallenge(currentWs());
    await connecting;

    expect(JSON.parse(currentWs().sent[0] ?? "null")).toEqual({
      type: "hello",
      pubkey: Buffer.from(keypair.publicKey).toString("base64"),
      device_id: "test-device",
      room_id: "room-1",
      room_meta: {
        name: "main",
        cwd: "/work",
        session_id: "session-1",
        model: "model-1",
        thinking: "high",
        working: true,
      },
    });

    client.close();
  });

  test("connect: sends auth with 64-byte Ed25519 signature", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    await connectWithAuth(client);

    const ws = currentWs();
    const auth = JSON.parse(ws.sent[1]) as { type: string; sig: string };
    expect(auth.type).toBe("auth");
    expect(Buffer.from(auth.sig, "base64")).toHaveLength(64);

    client.close();
  });

  test("connect: auth messages (hello + auth) are exactly 2 sends", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    await connectWithAuth(client);

    // hello + auth = 2 sends during auth phase only
    expect(currentWs().sent).toHaveLength(2);
    client.close();
  });

  test("connect: auth timeout removes its pending challenge listener", async () => {
    vi.useFakeTimers();
    try {
      const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
      const connecting = client.connect();
      const rejection = expect(connecting).rejects.toThrow("relay auth timeout");

      await vi.advanceTimersByTimeAsync(1);
      expect(currentWs().listenerCount("message")).toBe(1);
      await vi.advanceTimersByTimeAsync(5_000);

      await rejection;
      expect(currentWs().listenerCount("message")).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });

  test("connect: successful challenge replaces the auth listener with one data listener", async () => {
    vi.useFakeTimers();
    try {
      const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
      const received: string[] = [];
      client.on("message", (line) => received.push(line));
      const connecting = client.connect();

      await vi.advanceTimersByTimeAsync(1);
      const ws = currentWs();
      expect(ws.listenerCount("message")).toBe(1);
      simulateChallenge(ws);
      await connecting;
      expect(ws.listenerCount("message")).toBe(1);

      await vi.advanceTimersByTimeAsync(5_000);
      const outer = JSON.stringify({ peer: "app_peer_1", ct: "AAAA" });
      ws.emit("message", Buffer.from(outer));
      expect(received).toEqual([outer]);
      client.close();
    } finally {
      vi.useRealTimers();
    }
  });

  test("connect: malformed challenge errors never echo attacker-controlled content", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    const connecting = client.connect();
    await vi.waitFor(() => expect(currentWs().sent.length).toBeGreaterThan(0));
    currentWs().emit("message", Buffer.from("secret-attacker-frame"));

    await expect(connecting).rejects.toThrow("malformed challenge");
    await expect(connecting).rejects.not.toThrow("secret-attacker-frame");
  });

  test("connect: challenge message NOT forwarded as public 'message' event", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    const received: string[] = [];
    client.on("message", (line) => received.push(line));

    await connectWithAuth(client);

    // Challenge should NOT appear in public events
    expect(received.some((l) => l.includes("challenge"))).toBe(false);
    client.close();
  });

  test("connect: post-auth outer envelopes are forwarded as 'message' events", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    const received: string[] = [];
    client.on("message", (line) => received.push(line));

    await connectWithAuth(client);

    const outer = JSON.stringify({ peer: "app_peer_1", ct: "AAAA" });
    currentWs().emit("message", Buffer.from(outer));

    expect(received).toContain(outer);
    client.close();
  });

  test("send: writes raw line to the WebSocket", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
    await connectWithAuth(client);

    const ws = currentWs();
    const before = ws.sent.length;
    const outer = JSON.stringify({ peer: "x", ct: "BQID" });
    client.send(outer);
    expect(ws.sent[before]).toBe(outer);

    client.close();
  });

  // ── Liveness watchdog ───────────────────────────────────────────────────────
  // Regression for "daemon shows online but is dead after a few idle hours":
  // a silently half-open WS never fires `close`, so reconnect never triggers.

  async function connectFake(client: InstanceType<typeof RelayClient>): Promise<void> {
    const p = client.connect();
    await vi.advanceTimersByTimeAsync(1);  // MockWS defers 'open' via setTimeout(0)
    simulateChallenge(currentWs());        // resolves auth's _nextMsg
    await p;
  }

  test("liveness: force-closes (→ reconnect) after silence past the timeout", async () => {
    vi.useFakeTimers();
    try {
      const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
      await connectFake(client);
      let closed = false;
      client.on("close", () => { closed = true; });

      // No inbound frame for > 70s → watchdog terminates → close.
      await vi.advanceTimersByTimeAsync(90_000);
      expect(closed).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  test("liveness: relay's ~25s pings keep it alive (no spurious close)", async () => {
    vi.useFakeTimers();
    try {
      const client = new RelayClient("ws://localhost:9999", keypair, "test-device");
      await connectFake(client);
      let closed = false;
      client.on("close", () => { closed = true; });

      // Simulate the relay's keepalive ping every 25s for 2.5 min.
      for (let i = 0; i < 6; i++) {
        await vi.advanceTimersByTimeAsync(25_000);
        currentWs().emit("ping");
      }
      expect(closed).toBe(false);
      client.close();
    } finally {
      vi.useRealTimers();
    }
  });
});
