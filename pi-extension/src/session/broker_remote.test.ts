import { describe, expect, test, vi } from "vitest";
import { EventEmitter } from "node:events";
import { BrokerRemote, parseAddress } from "./broker_remote.js";
import type { Broker, RemoteInjectStatus } from "./broker.js";
import { envelope, type Envelope } from "./envelope.js";
import { PlainPeerChannel } from "../transport/peer_channel.js";
import { PiForwardClient } from "../transport/pi_forward_client.js";

// ── Test doubles ─────────────────────────────────────────────────────────────

/**
 * Minimal `PiForwardClient` stand-in. Records every outbound `sendEnvelopeToPi`
 * call so tests can assert on what was packed onto the relay, and exposes
 * `emit("envelope", env, fromPc)` so tests can simulate inbound delivery.
 */
class FakePi extends EventEmitter {
  readonly sent: { toPc: string; toRoom: string; env: Envelope }[] = [];
  readonly controls: object[] = [];
  sendEnvelopeToPi(toPc: string, toRoom: string, env: Envelope): void {
    this.sent.push({ toPc, toRoom, env });
  }
  sendRoomControl(frame: object): void {
    this.controls.push(frame);
  }
  detach(): void { /* no-op */ }
}

function announceRooms(fakePi: FakePi, peer: string, roomIds: string[]): void {
  fakePi.emit("rooms", {
    type: "rooms",
    peer,
    rooms: roomIds.map((room_id, index) => ({
      room_id,
      working: false,
      started_at: index + 1,
    })),
  });
}

interface FakeBrokerOptions {
  injectStatus?: RemoteInjectStatus;
  /** Local peer names the fake broker reports via `peerNames()`. Used by
   *  `BrokerRemote` to seed `lastLocalPeers` and to answer
   *  `peers_request` envelopes. Defaults to a single self peer. */
  localPeers?: string[];
}

function makeFakeBroker(opts: FakeBrokerOptions = {}): {
  broker: Broker;
  injectFromRemote: ReturnType<typeof vi.fn>;
  setRemoteRouter: ReturnType<typeof vi.fn>;
  peerNames: ReturnType<typeof vi.fn>;
  localPeerInfos: ReturnType<typeof vi.fn>;
  injected: Envelope[];
} {
  const injected: Envelope[] = [];
  const status = opts.injectStatus ?? "received";
  const injectFromRemote = vi.fn((env: Envelope) => {
    injected.push(env);
    return status;
  });
  const setRemoteRouter = vi.fn();
  let _localPeers = opts.localPeers ?? ["self"];
  const peerNames = vi.fn(() => [..._localPeers]);
  // plan/38 Phase 2: the cross-PC push reads the structured local inventory.
  // Synthesize `{cwd:"", name:addr, address:addr}` from the same address list.
  const localPeerInfos = vi.fn(() => _localPeers.map((address) => ({ cwd: "", name: address, address })));
  // Expose a setter for tests that mutate the local set mid-test.
  (peerNames as unknown as { set: (p: string[]) => void }).set = (p: string[]) => {
    _localPeers = p;
  };
  const broker = {
    injectFromRemote,
    setRemoteRouter,
    peerNames,
    localPeerInfos,
  } as unknown as Broker;
  return { broker, injectFromRemote, setRemoteRouter, peerNames, localPeerInfos, injected };
}

// ── parseAddress ─────────────────────────────────────────────────────────────

describe("parseAddress", () => {
  test("no prefix → null", () => {
    expect(parseAddress("backend")).toBeNull();
  });
  test("colon at end → null (empty peer name)", () => {
    expect(parseAddress("trab:")).toBeNull();
  });
  test("colon at start → null (empty pc label)", () => {
    expect(parseAddress(":agent")).toBeNull();
  });
  test("simple pc:peer → both parts", () => {
    expect(parseAddress("trab:agent-1")).toEqual({ pcLabel: "trab", peerName: "agent-1" });
  });
  test("multiple colons → split on first", () => {
    expect(parseAddress("trab:sub:agent")).toEqual({ pcLabel: "trab", peerName: "sub:agent" });
  });
});

// ── tryRouteOutbound ────────────────────────────────────────────────────────

describe("BrokerRemote.tryRouteOutbound", () => {
  test("no prefix → false (broker delivers locally)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "self", selfPcPubkey: "K_SELF",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    fakePi.sent.length = 0;  // drop bootstrap peers_request

    const env = envelope("sess-3", "agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(false);
    expect(fakePi.sent.length).toBe(0);
  });

  test("self prefix → false (local handles)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "self", selfPcPubkey: "K_SELF",
    });

    const env = envelope("sess-3", "self:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(false);
    expect(fakePi.sent.length).toBe(0);
  });

  test("unknown prefix → false (backward-compat for local names with ':')", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "self", selfPcPubkey: "K_SELF",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    fakePi.sent.length = 0;  // drop bootstrap peers_request

    const env = envelope("sess-3", "weird:peer", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(false);
    expect(fakePi.sent.length).toBe(0);
  });

  test("known sibling prefix → targets a relay-discovered live room and rewrites from", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    announceRooms(fakePi, "K_B", ["room-b-live"]);
    fakePi.sent.length = 0;

    const env = envelope("sess-3", "trab:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(true);
    const main = fakePi.sent.find((s) => s.env.id === env.id);
    expect(main).toBeDefined();
    expect(main!.toPc).toBe("K_B");
    expect(main!.toRoom).toBe("room-b-live");
    expect(main!.env.from).toBe("casa:sess-3");
    expect(main!.env.to).toBe("trab:agent-1");
  });

  test("cold room cache triggers rooms_check without inventing a destination room", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    fakePi.sent.length = 0;

    const env = envelope("sess-3", "trab:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(true);

    // The constructor starts discovery and the cold send reuses that in-flight
    // check rather than flooding the relay or targeting a fabricated room.
    expect(fakePi.sent.find((s) => s.env.id === env.id)).toBeUndefined();
    expect(fakePi.controls).toEqual([
      { type: "subscribe_rooms", peers: ["K_B"] },
      { type: "rooms_check", peers: ["K_B"] },
    ]);
  });

  test("does not trigger peers_request when cache is already populated", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    // Prime both relay room discovery and the remote roster cache.
    announceRooms(fakePi, "K_B", ["room-b-live"]);
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), "K_B", "room-a-live");

    fakePi.sent.length = 0;
    const env = envelope("sess-3", "trab:agent-1", { x: 1 });
    br.tryRouteOutbound(env);

    const peersReq = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(peersReq).toBeUndefined();
  });
});

// ── handleIncoming ──────────────────────────────────────────────────────────

describe("BrokerRemote.handleIncoming (anti-spoof + injection)", () => {
  test("from_pc not in sibling cache → drop + log", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
      log: (m) => logs.push(m),
    });

    fakePi.emit("envelope", envelope("evil:sess", "casa:agent-1", { x: 1 }), "K_UNKNOWN");

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs.some((l) => /not in sibling cache/.test(l))).toBe(true);
  });

  test("envelope.from prefix mismatches sibling label → drop", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
      log: (m) => logs.push(m),
    });

    // K_B claims to be "evil" — spoof attempt
    fakePi.emit("envelope", envelope("evil:sess", "casa:agent-1", { x: 1 }), "K_B");

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs.some((l) => /prefix\s+mismatches/.test(l))).toBe(true);
  });

  test("valid envelope → strip to-prefix, injectFromRemote, ACK to threaded inbound room", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker({ injectStatus: "received" });
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    const inbound = envelope("trab:agent-1", "casa:sess-3", { hello: "world" });
    fakePi.emit("envelope", inbound, "K_B", "threaded-room-a");

    expect(injectFromRemote).toHaveBeenCalledTimes(1);
    const injected = injectFromRemote.mock.calls[0]![0] as Envelope;
    expect(injected.from).toBe("trab:agent-1");
    expect(injected.to).toBe("sess-3");  // prefix stripped

    // ACK packed back to K_B
    const ack = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(ack).toBeDefined();
    expect(ack!.toPc).toBe("K_B");
    expect(ack!.toRoom).toBe("threaded-room-a");
    expect(ack!.env.re).toBe(inbound.id);
    expect((ack!.env.body as { status: string }).status).toBe("received");
  });

  test("envelope addressed to third-party PC → drop", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
      log: (m) => logs.push(m),
    });

    const inbound = envelope("trab:agent-1", "other:peer", { x: 1 });
    fakePi.emit("envelope", inbound, "K_B");

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs.some((l) => /not addressed/.test(l))).toBe(true);
  });

  test("incoming ACK does not generate a recursive ACK", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    const ackEnv: Envelope = envelope(
      "trab:broker", "casa:sess-3",
      { type: "ack", status: "received", target: "agent-1" },
      "01976000-0000-7000-8000-000000000000",
    );
    fakePi.emit("envelope", ackEnv, "K_B");

    const generatedAck = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(generatedAck).toBeUndefined();
  });
});

// ── peers_update / peers_request control ────────────────────────────────────

describe("BrokerRemote: control envelopes (peers_update / peers_request)", () => {
  test("peers_update populates cache (getRemotePeers returns)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1", "agent-2"] },
    ), "K_B");

    expect(br.getRemotePeers("trab")).toEqual(["agent-1", "agent-2"]);
    expect(br.listRemotePeers()).toEqual(["trab:agent-1", "trab:agent-2"]);
  });

  test("peers_update with peers_detailed → listRemotePeerInfos fills pc + prefixes address (plan/38 Phase 2)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      {
        type: "peers_update",
        peers: ["/w/app@App", "/w/api@Api"],
        peers_detailed: [
          { cwd: "/w/app", name: "App", address: "/w/app@App" },
          { cwd: "/w/api", name: "Api", address: "/w/api@Api" },
        ],
      },
    ), "K_B");

    // Addresses (the `peers` half) get the sibling-label prefix.
    expect(br.listRemotePeers()).toEqual(["trab:/w/app@App", "trab:/w/api@Api"]);
    // Structured: `pc` filled from the verified sibling label, cwd/name preserved,
    // address prefixed `<pc>:<cwd>@<name>` — this is what powers `peers_detailed`.
    expect(br.listRemotePeerInfos()).toEqual([
      { pc: "trab", cwd: "/w/app", name: "App", address: "trab:/w/app@App" },
      { pc: "trab", cwd: "/w/api", name: "Api", address: "trab:/w/api@Api" },
    ]);
  });

  test("back-compat: peers_update with ONLY peers[] (Phase-1 sibling) → synthesized infos, mesh not broken", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    // An older sibling sends addresses only — no peers_detailed.
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["/w/app@App"] },
    ), "K_B");

    expect(br.listRemotePeers()).toEqual(["trab:/w/app@App"]);
    // Synthesized: cwd "", name == address, pc filled, address prefixed. Routing
    // still works (address is intact); only cwd/name grouping is degraded.
    expect(br.listRemotePeerInfos()).toEqual([
      { pc: "trab", cwd: "", name: "/w/app@App", address: "trab:/w/app@App" },
    ]);
  });

  test("cache TTL expires entries", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
      cacheTtlMs: 10,  // tight TTL for tests
    });

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), "K_B");
    expect(br.getRemotePeers("trab")).toEqual(["agent-1"]);

    return new Promise<void>((resolve) => {
      setTimeout(() => {
        expect(br.getRemotePeers("trab")).toEqual([]);
        resolve();
      }, 30);
    });
  });

  test("peers_request triggers peers_update reply with current local peers", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker({ localPeers: ["sess-3", "agent-1"] });
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    announceRooms(fakePi, "K_B", ["room-b-live"]);
    fakePi.sent.length = 0;

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_request" },
    ), "K_B", "room-a-live");

    const reply = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(reply).toBeDefined();
    expect(reply!.toPc).toBe("K_B");
    expect((reply!.env.body as { peers: string[] }).peers).toEqual(["sess-3", "agent-1"]);
  });

  test("peers_request reply pulls the LIVE local inventory (broker.localPeerInfos), not a stale cache", () => {
    // Regression: in a single-peer mesh (only the wrapper itself), no
    // peer_joined event ever fires for the joiner, so a cached local list
    // would stay []. Reading the broker's live inventory bypasses that.
    const fakePi = new FakePi();
    const { broker, localPeerInfos } = makeFakeBroker({ localPeers: ["MacMini"] });
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "MacMini", selfPcPubkey: "K_B",
      siblings: [{ pcLabel: "MacBook", pcPubkey: "K_A" }],
    });
    announceRooms(fakePi, "K_A", ["macbook-room"]);
    // Note: no `onLocalPeersChanged` was ever called. Clear room-bootstrap
    // traffic so we observe the reply path cleanly.
    fakePi.sent.length = 0;

    fakePi.emit("envelope", envelope(
      "MacBook:_broker_remote", "MacMini:_broker_remote",
      { type: "peers_request" },
    ), "K_A", "macmini-room");

    const reply = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(reply).toBeDefined();
    const body = reply!.env.body as { peers: string[]; peers_detailed: Array<{ cwd: string; name: string; address: string }> };
    expect(body.peers).toEqual(["MacMini"]);
    // plan/38 Phase 2: the reply also carries the structured roster.
    expect(body.peers_detailed).toEqual([{ cwd: "", name: "MacMini", address: "MacMini" }]);
    expect(localPeerInfos).toHaveBeenCalled();
  });

  test("onLocalPeersChanged pushes peers_update to every sibling", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "trab", pcPubkey: "K_B" },
        { pcLabel: "movel", pcPubkey: "K_C" },
      ],
    });
    announceRooms(fakePi, "K_B", ["room-b-live"]);
    announceRooms(fakePi, "K_C", ["room-c-live"]);
    // Discard room-bootstrap traffic; we only care about the peers_update
    // emitted by `onLocalPeersChanged` below.
    fakePi.sent.length = 0;
    br.onLocalPeersChanged(["sess-3"]);

    const updates = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(updates.map((u) => u.toPc).sort()).toEqual(["K_B", "K_C"]);
  });

  test("periodic re-announce re-pushes to a STABLE sibling set (keeps roster warm vs TTL)", () => {
    // Regression: without a timer, a stable mesh never re-announces (only NEW
    // siblings get the bootstrap pair), so a single dropped push lets both
    // caches expire and the peer silently drops from list_peers overnight.
    vi.useFakeTimers();
    try {
      const fakePi = new FakePi();
      const { broker } = makeFakeBroker({ localPeers: ["sess-3"] });
      const br = new BrokerRemote({
        broker, pi: fakePi as never,
        selfPcLabel: "casa", selfPcPubkey: "K_A",
        siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
        reannounceIntervalMs: 1_000,
      });
      announceRooms(fakePi, "K_B", ["room-b-live"]);
      fakePi.sent.length = 0;  // drop room-bootstrap request fanout

      vi.advanceTimersByTime(1_000);
      // One full re-announce cycle = the bootstrap pair (request + push).
      const byType = (t: string) => fakePi.sent.filter(
        (s) => (s.env.body as { type?: string } | null)?.type === t,
      );
      expect(byType("peers_request").map((s) => s.toPc)).toEqual(["K_B"]);
      expect(byType("peers_update").map((s) => s.toPc)).toEqual(["K_B"]);

      // detach() stops the timer — no further traffic.
      br.detach();
      fakePi.sent.length = 0;
      vi.advanceTimersByTime(5_000);
      expect(fakePi.sent.length).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });
});

// ── transport_error propagation ──────────────────────────────────────────────

describe("BrokerRemote: transport_error from relay", () => {
  test("from_pc='_relay' → inject locally (no anti-spoof, no ACK back)", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    const err: Envelope = envelope(
      "_relay", "casa:sess-3",
      { type: "transport_error", reason: "offline" },
      "01976000-0000-7000-8000-000000000000",
    );
    fakePi.emit("envelope", err, "_relay");

    expect(injectFromRemote).toHaveBeenCalledTimes(1);
    const injected = injectFromRemote.mock.calls[0]![0] as Envelope;
    expect(injected.to).toBe("sess-3");  // prefix stripped
    expect((injected.body as { type: string }).type).toBe("transport_error");

    const ackBack = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(ackBack).toBeUndefined();
  });
});

// ── PiForwardClient relay frame decoding ────────────────────────────────────

describe("PiForwardClient room-aware relay events", () => {
  test("delegates room discovery controls to RelayClient.sendControl", () => {
    const relay = new EventEmitter() as EventEmitter & {
      send: ReturnType<typeof vi.fn>;
      sendControl: ReturnType<typeof vi.fn>;
    };
    relay.send = vi.fn();
    relay.sendControl = vi.fn();
    const pi = new PiForwardClient(relay as never);

    pi.sendRoomControl({ type: "subscribe_rooms", peers: ["K_B"] });
    pi.sendRoomControl({ type: "rooms_check", peers: ["K_B"] });

    expect(relay.sendControl.mock.calls.map((call) => call[0])).toEqual([
      { type: "subscribe_rooms", peers: ["K_B"] },
      { type: "rooms_check", peers: ["K_B"] },
    ]);
  });

  test("threads pi_envelope_in.to_room through the envelope event", () => {
    const relay = new EventEmitter() as EventEmitter & {
      send: ReturnType<typeof vi.fn>;
      sendControl: ReturnType<typeof vi.fn>;
    };
    relay.send = vi.fn();
    relay.sendControl = vi.fn();
    const pi = new PiForwardClient(relay as never);
    const onEnvelope = vi.fn();
    pi.on("envelope", onEnvelope);
    const inbound = envelope("trab:agent", "casa:sess", { hello: "world" });

    relay.emit("message", JSON.stringify({
      type: "pi_envelope_in",
      from_pc: "K_B",
      to_room: "room-a-live",
      envelope: inbound,
    }));

    expect(onEnvelope).toHaveBeenCalledWith(inbound, "K_B", "room-a-live");
  });

  test("emits validated rooms, room_announced, and room_ended control events", () => {
    const relay = new EventEmitter() as EventEmitter & {
      send: ReturnType<typeof vi.fn>;
      sendControl: ReturnType<typeof vi.fn>;
    };
    relay.send = vi.fn();
    relay.sendControl = vi.fn();
    const pi = new PiForwardClient(relay as never);
    const onRooms = vi.fn();
    const onAnnounced = vi.fn();
    const onEnded = vi.fn();
    pi.on("rooms", onRooms);
    pi.on("room_announced", onAnnounced);
    pi.on("room_ended", onEnded);

    const rooms = {
      type: "rooms",
      peer: "K_B",
      rooms: [{ room_id: "room-b-live", working: false, started_at: 1 }],
    };
    const announced = {
      type: "room_announced",
      peer: "K_B",
      room_id: "room-b-next",
      working: true,
      started_at: 2,
    };
    const ended = {
      type: "room_ended",
      peer: "K_B",
      room_id: "room-b-live",
      since_ts: 3,
    };
    relay.emit("message", JSON.stringify(rooms));
    relay.emit("message", JSON.stringify(announced));
    relay.emit("message", JSON.stringify(ended));

    expect(onRooms).toHaveBeenCalledWith(rooms);
    expect(onAnnounced).toHaveBeenCalledWith(announced);
    expect(onEnded).toHaveBeenCalledWith(ended);
  });
});

// ── detached no-op guards ───────────────────────────────────────────────────

describe("detached cross-PC bridge components", () => {
  test("BrokerRemote ignores inbound envelopes and outbound sends after detach", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote, setRemoteRouter } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    fakePi.sent.length = 0;

    br.detach();
    br.handleIncoming(
      envelope("trab:agent-1", "casa:sess-3", { hello: "after-detach" }),
      "K_B",
      "room-a-live",
    );
    expect(injectFromRemote).not.toHaveBeenCalled();

    const outbound = envelope("sess-3", "trab:agent-1", { hello: "after-detach" });
    expect(br.tryRouteOutbound(outbound)).toBe(false);
    expect(fakePi.sent).toHaveLength(0);
    expect(setRemoteRouter.mock.calls.at(-1)?.[0]).toBeNull();
  });

  test("PlainPeerChannel ignores sends and already-queued inbound frames after detach", () => {
    let queuedInbound: ((line: string) => void) | undefined;
    const relay = {
      send: vi.fn(),
      on: vi.fn((_event: string, handler: (line: string) => void) => {
        queuedInbound = handler;
        return relay;
      }),
      off: vi.fn(() => relay),
    };
    const onMessage = vi.fn();
    const channel = new PlainPeerChannel(relay as never, "app-peer", onMessage);
    channel.detach();

    channel.send({ type: "pong", in_reply_to: "ping-1" } as never);
    expect(relay.send).not.toHaveBeenCalled();

    const ct = Buffer.from(JSON.stringify({ type: "ping", id: "ping-2" })).toString("base64");
    queuedInbound?.(JSON.stringify({ peer: "app-peer", ct }));
    expect(onMessage).not.toHaveBeenCalled();
  });

  test("PlainPeerChannel validates app-origin messages before routing", () => {
    let inbound: ((line: string) => void) | undefined;
    const relay = {
      send: vi.fn(),
      on: vi.fn((_event: string, handler: (line: string) => void) => {
        inbound = handler;
        return relay;
      }),
      off: vi.fn(() => relay),
    };
    const onMessage = vi.fn();
    new PlainPeerChannel(relay as never, "app-peer", onMessage);

    const malformedKnownClient = Buffer.from(JSON.stringify({
      type: "model_set",
      id: "bad-model",
      provider: 1,
      model_id: "gpt",
    })).toString("base64");
    inbound?.(JSON.stringify({ peer: "app-peer", ct: malformedKnownClient }));
    expect(onMessage).not.toHaveBeenCalled();

    const validClient = { type: "ping" as const, id: "ping-1" };
    const validCt = Buffer.from(JSON.stringify(validClient)).toString("base64");
    inbound?.(JSON.stringify({ peer: "app-peer", ct: validCt }));
    expect(onMessage).toHaveBeenCalledWith(validClient);
  });

  test("PiForwardClient ignores sends and already-queued inbound relay frames after detach", () => {
    let queuedInbound: ((line: string) => void) | undefined;
    const relay = {
      send: vi.fn(),
      on: vi.fn((_event: string, handler: (line: string) => void) => {
        queuedInbound = handler;
        return relay;
      }),
      off: vi.fn(() => relay),
    };
    const pi = new PiForwardClient(relay as never);
    const onEnvelope = vi.fn();
    pi.on("envelope", onEnvelope);

    pi.detach();
    pi.sendEnvelopeToPi("K_B", "room-b-live", envelope("casa:sess", "trab:agent", { hello: "after-detach" }));
    expect(relay.send).not.toHaveBeenCalled();

    queuedInbound?.(JSON.stringify({
      type: "pi_envelope_in",
      from_pc: "K_B",
      envelope: envelope("trab:agent", "casa:sess", { hello: "after-detach" }),
    }));
    expect(onEnvelope).not.toHaveBeenCalled();
  });
});

// ── setSiblings ──────────────────────────────────────────────────────────────

describe("BrokerRemote.setSiblings", () => {
  test("dropping a sibling clears its cache entry", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "trab", pcPubkey: "K_B" },
        { pcLabel: "movel", pcPubkey: "K_C" },
      ],
    });
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), "K_B");
    expect(br.getRemotePeers("trab")).toEqual(["agent-1"]);

    br.setSiblings([{ pcLabel: "movel", pcPubkey: "K_C" }]);
    expect(br.getRemotePeers("trab")).toEqual([]);
  });

  test("self never appears in sibling set", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "casa", pcPubkey: "K_A" },     // self by both
        { pcLabel: "trab", pcPubkey: "K_B" },
      ],
    });

    const env = envelope("sess-3", "casa:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(false);  // self → local
  });
});

// ── Relay-authoritative room discovery bootstrap ─────────────────────────────

describe("BrokerRemote: relay-authoritative room discovery", () => {
  test("constructor subscribes to and snapshots every initial sibling's rooms", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "trab", pcPubkey: "K_B" },
        { pcLabel: "movel", pcPubkey: "K_C" },
      ],
    });

    expect(fakePi.controls).toEqual([
      { type: "subscribe_rooms", peers: ["K_B"] },
      { type: "rooms_check", peers: ["K_B"] },
      { type: "subscribe_rooms", peers: ["K_C"] },
      { type: "rooms_check", peers: ["K_C"] },
    ]);
    expect(fakePi.sent).toEqual([]);
  });

  test("rooms snapshot populates cache and fans peers_request out to every discovered room", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    fakePi.emit("rooms", {
      type: "rooms",
      peer: "K_B",
      rooms: [
        { room_id: "follower-room", working: false, started_at: 2 },
        { room_id: "leader-room", working: false, started_at: 1 },
      ],
    });

    const requests = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(requests.map((request) => request.toRoom)).toEqual(["leader-room", "follower-room"]);

    fakePi.sent.length = 0;
    const data = envelope("sess-3", "trab:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(data)).toBe(true);
    expect(fakePi.sent.find((send) => send.env.id === data.id)?.toRoom).toBe("leader-room");
  });

  test("no room controls or envelopes are emitted when there are zero siblings", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
    });

    expect(fakePi.controls).toEqual([]);
    expect(fakePi.sent).toEqual([]);
  });

  test("same membership publication reruns roster bootstrap after a dropped exchange", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const siblings = [{ pcLabel: "trab", pcPubkey: "K_B" }];
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings,
    });
    announceRooms(fakePi, "K_B", ["room-b-live"]);
    fakePi.sent.length = 0;

    br.setSiblings(siblings);

    expect(fakePi.sent.map((send) => (send.env.body as { type: string }).type)).toEqual([
      "peers_request",
      "peers_update",
    ]);
    expect(fakePi.sent.every((send) => send.toRoom === "room-b-live")).toBe(true);
  });

  test("setSiblings sends peers_request only to newly-added siblings", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    // Drop initial room-discovery controls so the assertion is isolated.
    fakePi.controls.length = 0;

    // Replace with set that keeps K_B and adds K_C. Only the new sibling gets
    // a room subscription + snapshot request; K_B is not re-subscribed.
    br.setSiblings([
      { pcLabel: "trab", pcPubkey: "K_B" },
      { pcLabel: "movel", pcPubkey: "K_C" },
    ]);

    expect(fakePi.controls).toEqual([
      { type: "subscribe_rooms", peers: ["K_C"] },
      { type: "rooms_check", peers: ["K_C"] },
    ]);
  });

  test("setSiblings removes a sibling without firing peers_request for the survivors", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "trab", pcPubkey: "K_B" },
        { pcLabel: "movel", pcPubkey: "K_C" },
      ],
    });
    fakePi.controls.length = 0;
    fakePi.sent.length = 0;

    br.setSiblings([{ pcLabel: "movel", pcPubkey: "K_C" }]);

    expect(fakePi.controls).toEqual([]);
    expect(fakePi.sent).toEqual([]);
  });

  test("room_announced populates the live cache and room_ended removes it", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    fakePi.emit("room_announced", {
      type: "room_announced",
      peer: "K_B",
      room_id: "room-b-live",
      working: false,
      started_at: 10,
    });
    fakePi.sent.length = 0;
    const first = envelope("sess", "trab:agent", { n: 1 });
    br.tryRouteOutbound(first);
    expect(fakePi.sent.find((send) => send.env.id === first.id)?.toRoom).toBe("room-b-live");

    fakePi.emit("room_ended", {
      type: "room_ended",
      peer: "K_B",
      room_id: "room-b-live",
      since_ts: 11,
    });
    fakePi.sent.length = 0;
    const second = envelope("sess", "trab:agent", { n: 2 });
    br.tryRouteOutbound(second);
    expect(fakePi.sent.find((send) => send.env.id === second.id)).toBeUndefined();
  });

  test("a fresh bridge re-issues subscribe_rooms after relay reconnect", () => {
    const firstPi = new FakePi();
    const { broker: firstBroker } = makeFakeBroker();
    const first = new BrokerRemote({
      broker: firstBroker, pi: firstPi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    first.detach();

    const reconnectedPi = new FakePi();
    const { broker: reconnectedBroker } = makeFakeBroker();
    new BrokerRemote({
      broker: reconnectedBroker, pi: reconnectedPi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    expect(firstPi.controls[0]).toEqual({ type: "subscribe_rooms", peers: ["K_B"] });
    expect(reconnectedPi.controls[0]).toEqual({ type: "subscribe_rooms", peers: ["K_B"] });
  });
});
