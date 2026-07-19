import { describe, expect, test, vi } from "vitest";
import {
  OFFLINE_BUFFER_MAX_BYTES,
  OFFLINE_BUFFER_MAX_FRAMES,
  OwnerMultiplexer,
  type CreateOwnerChannelInput,
  type OwnerMultiplexerDeps,
  type PeerChannelHandle,
} from "./owner_multiplexer.js";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";

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

function agentChunk(delta: string): ServerMessage {
  return { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta };
}

function makeMultiplexer() {
  const channels: FakeOwnerChannel[] = [];
  const knownPeers = new Map<string, { name: string; remote_epk: string; paired_at: string }>();
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
    consumePairToken: () => "unknown",
    addPeer: async (record) => { knownPeers.set(record.remote_epk, record); },
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

  test("known-owner reconnect ingress attaches a channel and routes the triggering message", async () => {
    const { mux, knownPeers, channels, ownerAttached } = makeMultiplexer();
    knownPeers.set("known-owner", { name: "Phone", remote_epk: "known-owner", paired_at: "now" });
    const routed: { message: ClientMessage; sender: FakeOwnerChannel }[] = [];
    const message: ClientMessage = { type: "ping", id: "ping-1" };

    await mux.handleOuterLine({
      line: JSON.stringify({ peer: "known-owner", room: "room-1", ct: encodeClientMessage(message) }),
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
    expect(routed).toEqual([{ message, sender: channels[0] }]);
  });

  test("malformed ingress is ignored and unknown-owner ingress gets a sender-only error", async () => {
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

    await mux.handleOuterLine({ ...inputBase, line: "not-json" });
    await mux.handleOuterLine({ ...inputBase, line: JSON.stringify({ peer: "stranger", room: "room-1", ct: "not-json-base64" }) });
    expect(sendToPeer).not.toHaveBeenCalled();
    expect(onMessage).not.toHaveBeenCalled();
    expect(mux.activeCount()).toBe(0);

    await mux.handleOuterLine({
      ...inputBase,
      line: JSON.stringify({ peer: "stranger", room: "room-1", ct: encodeClientMessage({ type: "ping", id: "ping-2" }) }),
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
