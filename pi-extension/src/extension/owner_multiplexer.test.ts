import { describe, expect, test, vi } from "vitest";
import {
  OFFLINE_BUFFER_MAX_BYTES,
  OFFLINE_BUFFER_MAX_FRAMES,
  OwnerMultiplexer,
  type CreateOwnerChannelInput,
  type OwnerMultiplexerDeps,
  type PeerChannelHandle,
} from "./owner_multiplexer.js";
import { decodeRelayIngress } from "../protocol/relay_ingress.js";
import { ed25519Sign, ed25519Verify, generateEd25519Keypair } from "../pairing/crypto.js";
import { decodePeerChannelKeys } from "../pairing/storage.js";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import {
  appTranscript,
  computePairMac,
  deriveDirectionalKeys,
  generateX25519Keypair,
  pairTokenId,
  piTranscript,
  x25519Shared,
} from "../transport/secure_channel.js";

class FakeOwnerChannel implements PeerChannelHandle {
  readonly sent: ServerMessage[] = [];
  detached = false;
  onSend?: (message: ServerMessage) => void;
  failNextSend = false;

  constructor(readonly input: CreateOwnerChannelInput) {}

  send(message: ServerMessage): void {
    if (this.failNextSend) {
      this.failNextSend = false;
      throw new Error("injected send failure");
    }
    this.sent.push(message);
    this.onSend?.(message);
  }

  detach(): void {
    this.detached = true;
  }

  receive(message: ClientMessage): void | Promise<void> {
    return this.input.onMessage(message);
  }
}

function encodeClientMessage(message: ClientMessage): string {
  return Buffer.from(JSON.stringify(message)).toString("base64");
}

function ownerIngress(peer: string, ct: string) {
  const ingress = decodeRelayIngress(JSON.stringify({ peer, room: "room-1", ct }));
  if (ingress.kind !== "outer") throw new Error("expected outer relay ingress");
  return ingress;
}

function agentChunk(delta: string): ServerMessage {
  return { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta };
}

function signedPairRequest(identityPk: Uint8Array, token = "pair-token") {
  const owner = generateEd25519Keypair();
  const appDh = generateX25519Keypair();
  const tokenId = pairTokenId(token);
  const signature = ed25519Sign(owner.secretKey, appTranscript(token, appDh.pk, identityPk));
  return {
    owner,
    appDh,
    token,
    peerId: Buffer.from(owner.publicKey).toString("base64"),
    message: {
      type: "pair_request",
      id: "pair-1",
      token_id: Buffer.from(tokenId).toString("base64"),
      pair_mac: Buffer.from(computePairMac(token, tokenId, owner.publicKey, appDh.pk, identityPk)).toString("base64"),
      device_name: "Phone",
      dh_pk: Buffer.from(appDh.pk).toString("base64"),
      dh_sig: Buffer.from(signature).toString("base64"),
    } satisfies Extract<ClientMessage, { type: "pair_request" }>,
  };
}

function makeMultiplexer() {
  const channels: FakeOwnerChannel[] = [];
  const knownPeers = new Map<string, {
    name: string;
    remote_epk: string;
    paired_at: string;
    channel_key?: string;
    send_seq?: string;
    recv_seq?: string;
  }>();
  const identity = generateEd25519Keypair();
  const findPairTokenById = vi.fn<OwnerMultiplexerDeps["findPairTokenById"]>((tokenId) =>
    tokenId === Buffer.from(pairTokenId("pair-token")).toString("base64") ? "pair-token" : null,
  );
  const consumePairToken = vi.fn<OwnerMultiplexerDeps["consumePairToken"]>(() => "unknown");
  const auditDrop = vi.fn<OwnerMultiplexerDeps["auditDrop"]>();
  const refreshFooter = vi.fn();
  const persisted = vi.fn();
  const ownerAttached = vi.fn();
  const ownerPaired = vi.fn();
  const fanoutPresenceChanged = vi.fn();
  const deps: OwnerMultiplexerDeps = {
    createChannel: (input) => {
      const channel = new FakeOwnerChannel(input);
      channels.push(channel);
      return channel;
    },
    refreshFooter,
    listPeers: async () => [...knownPeers.values()],
    findKnownPeer: async (peerId) => knownPeers.get(peerId) ?? null,
    findPairTokenById,
    consumePairToken,
    addPeer: async (record) => { knownPeers.set(record.remote_epk, record); },
    currentIdentity: () => identity,
    auditDrop,
    onPeerPersisted: persisted,
    currentPairingSession: () => ({
      sessionName: "test-session",
      sessionStartedAt: 123,
      sessionId: "session-1",
      roomId: "room-1",
    }),
    makeUnknownPeerError: () => ({
      type: "error",
      session_id: "session-1",
      code: "unknown_peer",
      message: "Peer not paired — re-scan QR",
    }),
    onOwnerAttached: ownerAttached,
    onOwnerPaired: ownerPaired,
    onFanoutPresenceChanged: fanoutPresenceChanged,
  };
  return {
    mux: new OwnerMultiplexer(deps),
    channels,
    knownPeers,
    refreshFooter,
    persisted,
    ownerAttached,
    ownerPaired,
    fanoutPresenceChanged,
    identity,
    findPairTokenById,
    consumePairToken,
    auditDrop,
    deps,
  };
}

describe("OwnerMultiplexer", () => {
  test("reattaching the same owner replaces the stale channel", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();

    const first = mux.attach({ peerId: "owner-1", onMessage });
    const second = mux.attach({ peerId: "owner-1", onMessage });

    expect(first).not.toBe(second);
    expect(channels[0]!.detached).toBe(true);
    expect(channels[1]!.detached).toBe(false);
    expect(mux.activeCount()).toBe(1);
    expect(mux.has("owner-1")).toBe(true);
    expect(mux.entries()).toEqual([{ peerId: "owner-1", channel: second }]);
  });

  test("broadcast fans out to every active owner channel", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ peerId: "owner-a", onMessage });
    mux.attach({ peerId: "owner-b", onMessage });

    const message: ServerMessage = { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta: "hello" };
    mux.broadcast(message);

    expect(channels[0]!.sent).toEqual([message]);
    expect(channels[1]!.sent).toEqual([message]);
  });

  test("peer_offline suspends only that peer and peer_online resumes fan-out", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ peerId: "owner-a", onMessage });
    mux.attach({ peerId: "owner-b", onMessage });

    expect(mux.markPeerOffline("owner-a", 123)).toBe(true);
    const droppedForA: ServerMessage = { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta: "while offline" };
    mux.broadcast(droppedForA);

    expect(channels[0]!.sent).toEqual([]);
    expect(channels[1]!.sent).toEqual([droppedForA]);

    expect(mux.markPeerOnline("owner-a")).toBe(true);
    const resumed: ServerMessage = { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta: "after reconnect" };
    mux.broadcast(resumed);

    expect(channels[0]!.sent).toEqual([droppedForA, resumed]);
    expect(channels[1]!.sent).toEqual([droppedForA, resumed]);
  });

  test("resume drains buffered and synchronously re-entrant frames before live fan-out", () => {
    const { mux, channels } = makeMultiplexer();
    mux.attach({ peerId: "owner-a", onMessage: vi.fn() });
    mux.markPeerOffline("owner-a");
    mux.broadcast(agentChunk("first"));
    mux.broadcast(agentChunk("second"));

    channels[0]!.onSend = (message) => {
      if (message.type === "agent_chunk" && message.delta === "first") {
        mux.broadcast(agentChunk("re-entrant"));
      }
    };

    mux.markPeerOnline("owner-a");
    channels[0]!.onSend = undefined;
    mux.broadcast(agentChunk("live"));

    expect(channels[0]!.sent.map((message) => message.type === "agent_chunk" ? message.delta : message.type))
      .toEqual(["first", "second", "re-entrant", "live"]);
  });

  test("a newly completed interval replaces the older completed interval", () => {
    const { mux, channels } = makeMultiplexer();
    mux.attach({ peerId: "owner-a", onMessage: vi.fn() });
    mux.markPeerOffline("owner-a");

    mux.broadcast(agentChunk("older turn"));
    mux.completeOfflineTurn();
    const newest = agentChunk("newest completed turn");
    mux.broadcast(newest);
    mux.completeOfflineTurn();
    mux.markPeerOnline("owner-a");

    expect(channels[0]!.sent).toEqual([newest]);
  });

  test("cap pressure evicts the completed interval before preserving a fitting current interval", () => {
    const { mux, channels } = makeMultiplexer();
    mux.attach({ peerId: "owner-a", onMessage: vi.fn() });
    mux.markPeerOffline("owner-a");

    mux.broadcast(agentChunk("older completed"));
    mux.completeOfflineTurn();
    const current = Array.from(
      { length: OFFLINE_BUFFER_MAX_FRAMES },
      (_, index) => agentChunk(`current-${index}`),
    );
    for (const message of current) mux.broadcast(message);
    mux.markPeerOnline("owner-a");

    expect(channels[0]!.sent).toEqual(current);
  });

  test("frame-cap overflow drops the whole active interval and recovers after a boundary", () => {
    const { mux, channels } = makeMultiplexer();
    mux.attach({ peerId: "owner-a", onMessage: vi.fn() });
    mux.markPeerOffline("owner-a");

    mux.broadcast(agentChunk("older completed"));
    mux.completeOfflineTurn();
    for (let index = 0; index <= OFFLINE_BUFFER_MAX_FRAMES; index += 1) {
      mux.broadcast(agentChunk(`current-${index}`));
    }
    mux.broadcast(agentChunk("suppressed suffix"));
    mux.completeOfflineTurn();
    const recovered = agentChunk("recovered after frame overflow");
    mux.broadcast(recovered);
    mux.markPeerOnline("owner-a");

    expect(channels[0]!.sent).toEqual([recovered]);
  });

  test("byte-cap and serialization failures suppress partial intervals without escaping broadcast", () => {
    const { mux, channels } = makeMultiplexer();
    mux.attach({ peerId: "owner-a", onMessage: vi.fn() });
    mux.markPeerOffline("owner-a");

    expect(() => mux.broadcast(agentChunk("x".repeat(OFFLINE_BUFFER_MAX_BYTES)))).not.toThrow();
    mux.broadcast(agentChunk("suppressed byte suffix"));
    mux.completeOfflineTurn();

    const cyclic: Record<string, unknown> = {};
    cyclic["self"] = cyclic;
    expect(() => mux.broadcast(cyclic as unknown as ServerMessage)).not.toThrow();
    mux.broadcast(agentChunk("suppressed serialization suffix"));
    mux.completeOfflineTurn();

    const recovered = agentChunk("recovered after byte and serialization overflow");
    mux.broadcast(recovered);
    mux.markPeerOnline("owner-a");

    expect(channels[0]!.sent).toEqual([recovered]);
  });

  test("sync-first reconnect discards buffered frames before routing authoritative history", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ peerId: "owner-a", onMessage });
    mux.markPeerOffline("owner-a");
    mux.broadcast(agentChunk("stale"));

    const sync: ClientMessage = {
      type: "session_sync",
      id: "sync-1",
      session_id: "session-1",
    };
    channels[0]!.receive(sync);
    expect(mux.isPeerOffline("owner-a")).toBe(false);
    expect(onMessage).toHaveBeenCalledWith(sync, channels[0]);
    expect(channels[0]!.sent).toEqual([]);

    mux.markPeerOnline("owner-a");
    expect(channels[0]!.sent).toEqual([]);
  });

  test("online-first compaction flush suppresses the same event from every later history replay", () => {
    const { mux, channels } = makeMultiplexer();
    const channel = mux.attach({ peerId: "owner-a", onMessage: vi.fn() });
    mux.markPeerOffline("owner-a");
    const compaction: ServerMessage = {
      type: "compaction",
      session_id: "session-1",
      summary: "offline compact",
      tokens_before: 123,
      ts: 1700,
    };
    mux.broadcast(compaction);
    mux.markPeerOnline("owner-a");

    const history: Extract<ServerMessage, { type: "session_history" }> = {
      type: "session_history",
      session_id: "session-1",
      in_reply_to: "sync-1",
      session_started_at: 1,
      events: [
        { type: "compaction", ts: 1600, summary: "earlier compact", tokens_before: 100 },
        { type: "compaction", ts: 1700, summary: "offline compact", tokens_before: 123 },
      ],
      eos: true,
      truncated: false,
    };

    expect(channels[0]!.sent).toEqual([compaction]);
    expect(mux.arbitrateSessionHistory(channel, history).events).toEqual([
      { type: "compaction", ts: 1600, summary: "earlier compact", tokens_before: 100 },
    ]);
    expect(mux.arbitrateSessionHistory(channel, history).events).toEqual([
      { type: "compaction", ts: 1600, summary: "earlier compact", tokens_before: 100 },
    ]);
  });

  test("a failed buffered send still converges the peer online", () => {
    const { mux, channels } = makeMultiplexer();
    mux.attach({ peerId: "owner-a", onMessage: vi.fn() });
    mux.markPeerOffline("owner-a");
    mux.broadcast(agentChunk("fails"));
    mux.broadcast(agentChunk("continues"));
    channels[0]!.failNextSend = true;

    expect(mux.markPeerOnline("owner-a")).toBe(true);
    expect(mux.isPeerOffline("owner-a")).toBe(false);
    mux.broadcast(agentChunk("live"));

    expect(channels[0]!.sent).toEqual([
      agentChunk("continues"),
      agentChunk("live"),
    ]);
  });

  test("suspend/resume diagnostic is one-shot and not emitted per dropped frame", () => {
    const { mux, fanoutPresenceChanged } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ peerId: "owner-a", onMessage });

    const first: ServerMessage = { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta: "first" };
    const second: ServerMessage = { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta: "second" };

    mux.markPeerOffline("owner-a", 456);
    mux.markPeerOffline("owner-a", 789);
    mux.broadcast(first);
    mux.broadcast(second);
    mux.markPeerOnline("owner-a");
    mux.markPeerOnline("owner-a");

    expect(fanoutPresenceChanged).toHaveBeenCalledTimes(2);
    expect(fanoutPresenceChanged).toHaveBeenNthCalledWith(1, {
      peerId: "owner-a",
      peerShortId: "owner-a".slice(0, 8),
      state: "suspended",
      sinceTs: 456,
    });
    expect(fanoutPresenceChanged).toHaveBeenNthCalledWith(2, {
      peerId: "owner-a",
      peerShortId: "owner-a".slice(0, 8),
      state: "resumed",
    });
  });

  test("reattach during an active turn clears stale offline state and remains a late-attach target", () => {
    const { mux, channels, fanoutPresenceChanged } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ peerId: "owner-a", onMessage, turnActive: true });
    mux.markPeerOffline("owner-a", 123);
    mux.broadcast(agentChunk("must not cross channel lifetime"));

    const reattached = mux.attach({ peerId: "owner-a", onMessage, turnActive: true });
    const message: ServerMessage = { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta: "resumed" };
    mux.broadcast(message);

    expect(channels[0]!.detached).toBe(true);
    expect(channels[1]!.sent).toEqual([message]);
    expect(reattached).toBe(channels[1]);
    expect(mux.lateAttachEntries()).toEqual([{ peerId: "owner-a", channel: channels[1] }]);
    expect(fanoutPresenceChanged).toHaveBeenCalledWith(expect.objectContaining({
      peerId: "owner-a",
      state: "resumed",
    }));
  });

  test("detach and relay-drop teardown free buffered frames", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ peerId: "owner-a", onMessage });
    mux.markPeerOffline("owner-a");
    mux.broadcast(agentChunk("detached stale"));
    mux.detach("owner-a");

    mux.attach({ peerId: "owner-a", onMessage });
    mux.broadcast(agentChunk("after detach"));
    expect(channels[1]!.sent).toEqual([agentChunk("after detach")]);

    mux.markPeerOffline("owner-a");
    mux.broadcast(agentChunk("relay-drop stale"));
    mux.detachAllForRelayDrop();
    mux.attach({ peerId: "owner-a", onMessage });
    mux.broadcast(agentChunk("after relay drop"));

    expect(channels[2]!.sent).toEqual([agentChunk("after relay drop")]);
  });

  test("detaching one owner preserves the other owner channel", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ peerId: "owner-a", onMessage });
    mux.attach({ peerId: "owner-b", onMessage });

    const result = mux.disconnectOwner("owner-a");

    expect(result).toEqual({ disconnected: true, activeOwnerCount: 1 });
    expect(channels[0]!.detached).toBe(true);
    expect(channels[1]!.detached).toBe(false);
    expect(mux.has("owner-a")).toBe(false);
    expect(mux.has("owner-b")).toBe(true);
  });

  test("known-owner reconnect attaches before the triggering frame is routed by secure fanout", async () => {
    const { mux, knownPeers, channels, ownerAttached } = makeMultiplexer();
    knownPeers.set("known-owner", {
      name: "Phone",
      remote_epk: "known-owner",
      paired_at: "now",
      channel_key: Buffer.alloc(64, 7).toString("base64"),
      send_seq: "0",
      recv_seq: "0",
    });
    const routed: { message: ClientMessage; sender: FakeOwnerChannel }[] = [];
    const message: ClientMessage = { type: "ping", id: "ping-1" };

    await mux.handleOuterFrame({
      ingress: ownerIngress("known-owner", encodeClientMessage(message)),
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage: (routedMessage, sender) => {
        routed.push({ message: routedMessage, sender: sender as FakeOwnerChannel });
      },
      onDisconnect: vi.fn(),
      sendToPeer: vi.fn(),
    });

    expect(mux.activeCount()).toBe(1);
    expect(mux.has("known-owner")).toBe(true);
    expect(ownerAttached).toHaveBeenCalledWith({ peerId: "known-owner", peerName: "Phone", activeCount: 1 });
    expect(routed).toEqual([]);
    await channels[0]!.receive(message);
    expect(routed).toEqual([{ message, sender: channels[0] }]);
  });

  test("missing token locator or proof fails closed without consuming or persisting", async () => {
    for (const field of ["token_id", "pair_mac"] as const) {
      const { mux, identity, consumePairToken, knownPeers } = makeMultiplexer();
      const pair = signedPairRequest(identity.publicKey);
      const sendToPeer = vi.fn();
      const message = { ...pair.message, [field]: undefined };

      await mux.handleOuterFrame({
        ingress: ownerIngress(pair.peerId, encodeClientMessage(message as ClientMessage)),
        roomId: "room-1",
        turnActive: () => false,
        isCurrent: () => true,
        onMessage: vi.fn(),
        onDisconnect: vi.fn(),
        sendToPeer,
      });

      expect(sendToPeer).toHaveBeenCalledWith(pair.peerId, expect.objectContaining({
        type: "pair_error",
        code: "token_unknown",
      }));
      expect(consumePairToken).not.toHaveBeenCalled();
      expect(knownPeers.size).toBe(0);
    }
  });

  test("unknown token ids and bad pair MACs are indistinguishable and do not burn the token", async () => {
    for (const mutation of ["unknown_id", "bad_mac"] as const) {
      const { mux, identity, consumePairToken, knownPeers } = makeMultiplexer();
      const pair = signedPairRequest(identity.publicKey);
      const sendToPeer = vi.fn();
      const message = mutation === "unknown_id"
        ? { ...pair.message, token_id: Buffer.alloc(16, 17).toString("base64") }
        : { ...pair.message, pair_mac: Buffer.alloc(32, 23).toString("base64") };

      await mux.handleOuterFrame({
        ingress: ownerIngress(pair.peerId, encodeClientMessage(message)),
        roomId: "room-1",
        turnActive: () => false,
        isCurrent: () => true,
        onMessage: vi.fn(),
        onDisconnect: vi.fn(),
        sendToPeer,
      });

      expect(sendToPeer).toHaveBeenCalledWith(pair.peerId, expect.objectContaining({
        type: "pair_error",
        code: "token_unknown",
      }));
      expect(consumePairToken).not.toHaveBeenCalled();
      expect(knownPeers.size).toBe(0);
    }
  });

  test("pair MAC is checked before the DH signature and token consumption", async () => {
    const { mux, identity, consumePairToken } = makeMultiplexer();
    const pair = signedPairRequest(identity.publicKey);
    const sendToPeer = vi.fn();
    const message = {
      ...pair.message,
      pair_mac: Buffer.alloc(32, 41).toString("base64"),
      dh_sig: Buffer.alloc(64, 42).toString("base64"),
    };

    await mux.handleOuterFrame({
      ingress: ownerIngress(pair.peerId, encodeClientMessage(message)),
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage: vi.fn(),
      onDisconnect: vi.fn(),
      sendToPeer,
    });

    expect(sendToPeer).toHaveBeenCalledWith(pair.peerId, expect.objectContaining({ code: "token_unknown" }));
    expect(consumePairToken).not.toHaveBeenCalled();
  });

  test("a relay-observed pairing proof cannot be replayed under a different Owner key", async () => {
    const { mux, identity, consumePairToken, knownPeers } = makeMultiplexer();
    consumePairToken.mockReturnValue("ok");
    const honest = signedPairRequest(identity.publicKey);
    const attacker = generateEd25519Keypair();
    const attackerPeerId = Buffer.from(attacker.publicKey).toString("base64");
    const replay = {
      ...honest.message,
      dh_sig: Buffer.from(ed25519Sign(
        attacker.secretKey,
        appTranscript(honest.token, honest.appDh.pk, identity.publicKey),
      )).toString("base64"),
    };
    const attackerReplies: ServerMessage[] = [];

    await mux.handleOuterFrame({
      ingress: ownerIngress(attackerPeerId, encodeClientMessage(replay)),
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage: vi.fn(),
      onDisconnect: vi.fn(),
      sendToPeer: (_peerId, message) => attackerReplies.push(message),
    });

    expect(attackerReplies[0]).toMatchObject({ type: "pair_error", code: "token_unknown" });
    expect(consumePairToken).not.toHaveBeenCalled();
    expect(knownPeers.size).toBe(0);

    await mux.handleOuterFrame({
      ingress: ownerIngress(honest.peerId, encodeClientMessage(honest.message)),
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage: vi.fn(),
      onDisconnect: vi.fn(),
      sendToPeer: vi.fn(),
    });

    expect(consumePairToken).toHaveBeenCalledTimes(1);
    expect(knownPeers.has(honest.peerId)).toBe(true);
  });

  test("missing or bad DH material fails before consuming the pair token or persisting", async () => {
    for (const mutation of ["missing_sig", "bad_sig", "missing_pk", "bad_pk"] as const) {
      const { mux, identity, consumePairToken, knownPeers } = makeMultiplexer();
      const pair = signedPairRequest(identity.publicKey);
      const message = mutation === "missing_sig"
        ? { ...pair.message, dh_sig: undefined }
        : mutation === "bad_sig"
          ? { ...pair.message, dh_sig: Buffer.alloc(64, 99).toString("base64") }
          : mutation === "missing_pk"
            ? { ...pair.message, dh_pk: undefined }
            : { ...pair.message, dh_pk: Buffer.alloc(31, 99).toString("base64") };
      const sendToPeer = vi.fn();

      await mux.handleOuterFrame({
        ingress: ownerIngress(pair.peerId, encodeClientMessage(message as ClientMessage)),
        roomId: "room-1",
        turnActive: () => false,
        isCurrent: () => true,
        onMessage: vi.fn(),
        onDisconnect: vi.fn(),
        sendToPeer,
      });

      expect(sendToPeer).toHaveBeenCalledWith(pair.peerId, expect.objectContaining({
        type: "pair_error",
        code: "bad_dh_sig",
      }));
      expect(consumePairToken).not.toHaveBeenCalled();
      expect(knownPeers.size).toBe(0);
      expect(mux.activeCount()).toBe(0);
    }
  });

  test("successful signed handshake persists keys before plaintext pair_ok and emits a verifiable Pi share", async () => {
    const { mux, identity, consumePairToken, knownPeers, deps } = makeMultiplexer();
    const pair = signedPairRequest(identity.publicKey);
    consumePairToken.mockReturnValue("ok");
    const order: string[] = [];
    deps.addPeer = async (record) => {
      order.push("persist");
      knownPeers.set(record.remote_epk, record);
    };
    const replies: ServerMessage[] = [];

    await mux.handleOuterFrame({
      ingress: ownerIngress(pair.peerId, encodeClientMessage(pair.message)),
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage: vi.fn(),
      onDisconnect: vi.fn(),
      sendToPeer: (_peerId, message) => {
        order.push("send");
        replies.push(message);
      },
    });

    expect(order.slice(0, 2)).toEqual(["persist", "send"]);
    const stored = knownPeers.get(pair.peerId)!;
    expect(stored).toMatchObject({ send_seq: "0", recv_seq: "0" });
    const storedKeys = decodePeerChannelKeys(stored.channel_key);
    expect(storedKeys).not.toBeNull();

    const pairOk = replies[0];
    expect(pairOk?.type).toBe("pair_ok");
    if (!pairOk || pairOk.type !== "pair_ok" || !pairOk.dh_pk || !pairOk.dh_sig) {
      throw new Error("expected extended pair_ok");
    }
    const piDhPk = Uint8Array.from(Buffer.from(pairOk.dh_pk, "base64"));
    expect(ed25519Verify(
      identity.publicKey,
      piTranscript(pair.token, pair.appDh.pk, piDhPk, pair.owner.publicKey),
      Buffer.from(pairOk.dh_sig, "base64"),
    )).toBe(true);

    const appKeys = deriveDirectionalKeys(x25519Shared(pair.appDh.sk, piDhPk), pair.token, "app");
    expect(storedKeys).toEqual({ send: appKeys.recv, recv: appKeys.send });
    expect(mux.has(pair.peerId)).toBe(true);
  });

  test("known pre-E2E owners are dropped and audited instead of attaching plaintext", async () => {
    const { mux, knownPeers, auditDrop, ownerAttached } = makeMultiplexer();
    knownPeers.set("legacy-owner", { name: "Old phone", remote_epk: "legacy-owner", paired_at: "now" });

    await mux.handleOuterFrame({
      ingress: ownerIngress("legacy-owner", encodeClientMessage({ type: "ping", id: "ping-legacy" })),
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage: vi.fn(),
      onDisconnect: vi.fn(),
      sendToPeer: vi.fn(),
    });

    expect(auditDrop).toHaveBeenCalledWith("legacy-owner", "missing_channel_key");
    expect(ownerAttached).not.toHaveBeenCalled();
    expect(mux.activeCount()).toBe(0);
  });

  test("invalid typed payload is ignored and unknown-owner ingress gets a sender-only error", async () => {
    const { mux } = makeMultiplexer();
    const sendToPeer = vi.fn();
    const onMessage = vi.fn();
    const inputBase = {
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage,
      onDisconnect: vi.fn(),
      sendToPeer,
    };

    await mux.handleOuterFrame({
      ...inputBase,
      ingress: ownerIngress("stranger", "not-json-base64"),
    });
    expect(sendToPeer).not.toHaveBeenCalled();
    expect(onMessage).not.toHaveBeenCalled();
    expect(mux.activeCount()).toBe(0);

    await mux.handleOuterFrame({
      ...inputBase,
      ingress: ownerIngress("stranger", encodeClientMessage({ type: "ping", id: "ping-2" })),
    });

    expect(sendToPeer).toHaveBeenCalledTimes(1);
    expect(sendToPeer).toHaveBeenCalledWith("stranger", {
      type: "error",
      session_id: "session-1",
      code: "unknown_peer",
      message: "Peer not paired — re-scan QR",
    });
    expect(onMessage).not.toHaveBeenCalled();
    expect(mux.activeCount()).toBe(0);
  });
});
