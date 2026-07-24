import { EventEmitter } from "node:events";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { ClientMessage } from "../protocol/types.js";
import type { RelayClient } from "./relay_client.js";
import {
  MAX_PENDING_OWNER_FRAMES,
  MAX_PENDING_OWNER_OUTBOUND_BYTES,
  MAX_PENDING_OWNER_OUTBOUND_FRAMES,
  OWNER_CHANNEL_AUDIT_MAX_BYTES,
  SecurePeerChannel,
} from "./peer_channel.js";
import { open, seal } from "./secure_channel.js";

class FakeRelay extends EventEmitter {
  send = vi.fn();
}

const tempDirs: string[] = [];
afterEach(() => {
  for (const dir of tempDirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function makeAuditPath(): string {
  const dir = mkdtempSync(join(tmpdir(), "owner-channel-audit-"));
  tempDirs.push(dir);
  return join(dir, "audit.jsonl");
}

function emitOuter(relay: FakeRelay, peer: string, frame: Uint8Array): void {
  relay.emit("message", JSON.stringify({
    peer,
    room: "main",
    ct: Buffer.from(frame).toString("base64"),
  }));
}

function makeChannel(options: {
  relay?: FakeRelay;
  peer?: string;
  sendSeq?: bigint;
  recvSeq?: bigint;
  onMessage?: (message: ClientMessage) => void;
  onDisconnect?: () => void;
  auditPath?: string;
  persisted?: { send: bigint; recv: bigint };
  reserveSendSeq?: () => Promise<bigint | null>;
  compareAndAdvanceRecvSeq?: (
    recvSeq: bigint,
  ) => Promise<"accepted" | "replay" | "stale_generation">;
}) {
  const relay = options.relay ?? new FakeRelay();
  const persisted = options.persisted ?? { send: options.sendSeq ?? 0n, recv: options.recvSeq ?? 0n };
  const sendKey = new Uint8Array(32).fill(31);
  const recvKey = new Uint8Array(32).fill(32);
  const channel = new SecurePeerChannel(
    relay as unknown as RelayClient,
    options.peer ?? "owner-a",
    options.onMessage ?? vi.fn(),
    {
      keys: { send: sendKey, recv: recvKey },
      recvSeq: options.recvSeq ?? persisted.recv,
      reserveSendSeq: options.reserveSendSeq ?? (async () => {
        persisted.send += 1n;
        return persisted.send;
      }),
      compareAndAdvanceRecvSeq: options.compareAndAdvanceRecvSeq ?? (async (recvSeq) => {
        if (recvSeq <= persisted.recv) return "replay";
        persisted.recv = recvSeq;
        return "accepted";
      }),
      onDisconnect: options.onDisconnect ?? vi.fn(),
      auditPath: options.auditPath ?? makeAuditPath(),
    },
  );
  return { channel, relay, persisted, sendKey, recvKey };
}

describe("SecurePeerChannel", () => {
  test("seals outbound and opens inbound frames through the relay adapter", async () => {
    const received = vi.fn();
    const { channel, relay, persisted, sendKey, recvKey } = makeChannel({ onMessage: received });

    channel.send({ type: "pong", in_reply_to: "ping-out" });
    await channel.whenIdle();
    expect(relay.send).toHaveBeenCalledTimes(1);
    const outer = JSON.parse(relay.send.mock.calls[0]![0] as string) as { peer: string; room: string; ct: string };
    expect(outer).toMatchObject({ peer: "owner-a", room: "main" });
    expect(open(sendKey, Buffer.from(outer.ct, "base64"), 0n)).toEqual({
      seq: 1n,
      json: JSON.stringify({ type: "pong", in_reply_to: "ping-out" }),
    });
    expect(persisted.send).toBe(1n);

    emitOuter(relay, "owner-a", seal(recvKey, 3n, JSON.stringify({ type: "ping", id: "ping-in" })));
    await channel.whenIdle();
    expect(received).toHaveBeenCalledWith({ type: "ping", id: "ping-in" });
    expect(persisted.recv).toBe(3n);
    channel.detach();
  });

  test("durable replay gate rejects a frame when local state is stale without regressing it", async () => {
    const auditPath = makeAuditPath();
    const received = vi.fn();
    const onDisconnect = vi.fn();
    const durableRecv = 10n;
    const compareAndAdvanceRecvSeq = vi.fn(async (seq: bigint) =>
      seq <= durableRecv ? "replay" as const : "accepted" as const
    );
    const { channel, relay, recvKey } = makeChannel({
      auditPath,
      recvSeq: 2n,
      onMessage: received,
      onDisconnect,
      compareAndAdvanceRecvSeq,
    });
    const replay = seal(
      recvKey,
      5n,
      JSON.stringify({ type: "cancel", id: "captured-cancel", target_id: "turn-1" }),
    );

    for (let index = 0; index < 5; index += 1) emitOuter(relay, "owner-a", replay);
    await channel.whenIdle();

    expect(compareAndAdvanceRecvSeq).toHaveBeenCalledTimes(5);
    expect(received).not.toHaveBeenCalled();
    expect((channel as unknown as { recvSeq: bigint }).recvSeq).toBe(2n);
    expect(onDisconnect).toHaveBeenCalledTimes(1);
    expect(readFileSync(auditPath, "utf8")).toContain('"reason":"open_failed"');
  });

  test("stale key generation is audited and detached without dispatch", async () => {
    const auditPath = makeAuditPath();
    const received = vi.fn();
    const onDisconnect = vi.fn();
    const { channel, relay, recvKey } = makeChannel({
      auditPath,
      onMessage: received,
      onDisconnect,
      compareAndAdvanceRecvSeq: async () => "stale_generation",
    });

    emitOuter(relay, "owner-a", seal(recvKey, 1n, JSON.stringify({ type: "session_new", id: "stale" })));
    await channel.whenIdle();

    expect(received).not.toHaveBeenCalled();
    expect((channel as unknown as { recvSeq: bigint }).recvSeq).toBe(0n);
    expect(onDisconnect).toHaveBeenCalledTimes(1);
    expect(readFileSync(auditPath, "utf8")).toContain('"reason":"stale_generation"');
  });

  test("drops plaintext after key establishment and writes a content-free audit line", async () => {
    const auditPath = makeAuditPath();
    const received = vi.fn();
    const { channel, relay } = makeChannel({ auditPath, onMessage: received });
    const plaintext = Buffer.from(JSON.stringify({ type: "ping", id: "secret-id" }));

    emitOuter(relay, "owner-a", plaintext);
    await channel.whenIdle();

    expect(received).not.toHaveBeenCalled();
    const audit = readFileSync(auditPath, "utf8");
    expect(audit).toContain('"reason":"plaintext_post_key"');
    expect(audit).not.toContain("secret-id");
    channel.detach();
  });

  test("hostile plaintext ingress coalesces accurately with bounded work and file size", async () => {
    const auditPath = makeAuditPath();
    const { channel, relay } = makeChannel({ auditPath });

    for (let index = 0; index < 2_000; index += 1) {
      emitOuter(relay, "owner-a", Buffer.from("plaintext"));
    }

    const auditState = (channel as unknown as {
      auditor: { stats(): { bucketCount: number; activeWrites: number; pendingEvents: number } };
    }).auditor.stats();
    expect(auditState.bucketCount).toBe(1);
    expect(auditState.activeWrites).toBeLessThanOrEqual(1);
    expect(auditState.pendingEvents).toBeLessThanOrEqual(2_000);

    await channel.whenIdle();
    const lines = readFileSync(auditPath, "utf8").trim().split("\n").map((line) => JSON.parse(line) as {
      reason: string;
      count: number;
    });
    const plaintextLines = lines.filter((line) => line.reason === "plaintext_post_key");
    expect(plaintextLines.reduce((total, line) => total + line.count, 0)).toBe(2_000);
    expect(plaintextLines.length).toBeLessThan(25);
    expect(statSync(auditPath).size).toBeLessThanOrEqual(OWNER_CHANNEL_AUDIT_MAX_BYTES);
    channel.detach();
  });

  test("audit rotation bounds a pre-existing full file and one predecessor", async () => {
    const auditPath = makeAuditPath();
    writeFileSync(auditPath, "x".repeat(OWNER_CHANNEL_AUDIT_MAX_BYTES));
    const { channel, relay } = makeChannel({ auditPath });

    emitOuter(relay, "owner-a", Buffer.from("plaintext"));
    await channel.whenIdle();

    expect(statSync(auditPath).size).toBeLessThanOrEqual(OWNER_CHANNEL_AUDIT_MAX_BYTES);
    expect(existsSync(`${auditPath}.1`)).toBe(true);
    expect(statSync(`${auditPath}.1`).size).toBeLessThanOrEqual(OWNER_CHANNEL_AUDIT_MAX_BYTES);
    channel.detach();
  });

  test("sustained bad protected ingress stays queued-bounded and detaches after five failures", async () => {
    const auditPath = makeAuditPath();
    const onDisconnect = vi.fn();
    const { channel, relay, recvKey } = makeChannel({ auditPath, onDisconnect });
    const bad = seal(recvKey, 1n, JSON.stringify({ type: "ping", id: "bad" }));
    bad[bad.length - 1] ^= 1;

    for (let index = 0; index < 1_000; index += 1) emitOuter(relay, "owner-a", bad);
    const ingressState = channel as unknown as {
      inboundQueue: Uint8Array[];
      inboundDrain: Promise<void> | null;
    };
    expect(ingressState.inboundQueue.length).toBeLessThanOrEqual(MAX_PENDING_OWNER_FRAMES);
    expect(ingressState.inboundDrain).not.toBeNull();

    await channel.whenIdle();

    expect(onDisconnect).toHaveBeenCalledTimes(1);
    expect(relay.listenerCount("message")).toBe(0);
    expect(ingressState.inboundQueue).toHaveLength(0);
    const lines = readFileSync(auditPath, "utf8").trim().split("\n").map((line) => JSON.parse(line) as {
      reason: string;
      count: number;
      consecutive_failures?: number;
    });
    expect(lines.reduce((total, line) => total + line.count, 0)).toBe(1_000);
    expect(Math.max(...lines.map((line) => line.consecutive_failures ?? 0))).toBe(5);
    expect(statSync(auditPath).size).toBeLessThanOrEqual(OWNER_CHANNEL_AUDIT_MAX_BYTES);
  });

  test("reserves the send high-water before sealing and exposing its frame", async () => {
    let resolveReservation!: (value: bigint | null) => void;
    const reservation = new Promise<bigint | null>((resolve) => { resolveReservation = resolve; });
    const reserveSendSeq = vi.fn(() => reservation);
    const { channel, relay } = makeChannel({ reserveSendSeq });

    channel.send({ type: "pong", in_reply_to: "persist-first" });
    await vi.waitFor(() => expect(reserveSendSeq).toHaveBeenCalledTimes(1));
    expect(relay.send).not.toHaveBeenCalled();

    resolveReservation(41n);
    await channel.whenIdle();
    expect(relay.send).toHaveBeenCalledTimes(1);
    const outer = JSON.parse(relay.send.mock.calls[0]![0] as string) as { ct: string };
    const frame = Buffer.from(outer.ct, "base64");
    expect(new DataView(frame.buffer, frame.byteOffset + 1, 8).getBigUint64(0, true)).toBe(41n);
    channel.detach();
  });

  test("bounds blocked outbound reservation, detaches on overflow, and drains accepted sends in sequence", async () => {
    const auditPath = makeAuditPath();
    const onDisconnect = vi.fn();
    let resolveFirstReservation!: (value: bigint | null) => void;
    const firstReservation = new Promise<bigint | null>((resolve) => { resolveFirstReservation = resolve; });
    const persistedSeqs: bigint[] = [];
    let durableSeq = 0n;
    const reserveSendSeq = vi.fn(async () => {
      const reserved = durableSeq + 1n;
      const next = reserved === 1n ? await firstReservation : reserved;
      if (next === null) return null;
      durableSeq = next;
      persistedSeqs.push(next);
      return next;
    });
    const { channel, relay } = makeChannel({ auditPath, onDisconnect, reserveSendSeq });

    for (let index = 0; index < MAX_PENDING_OWNER_OUTBOUND_FRAMES; index += 1) {
      channel.send({ type: "pong", in_reply_to: `accepted-${index}` });
    }
    await vi.waitFor(() => expect(reserveSendSeq).toHaveBeenCalledTimes(1));
    const outboundState = channel as unknown as {
      pendingOutboundFrames: number;
      pendingOutboundBytes: number;
    };
    expect(outboundState.pendingOutboundFrames).toBe(MAX_PENDING_OWNER_OUTBOUND_FRAMES);
    expect(outboundState.pendingOutboundBytes).toBeLessThanOrEqual(MAX_PENDING_OWNER_OUTBOUND_BYTES);
    expect(relay.send).not.toHaveBeenCalled();

    channel.send({ type: "pong", in_reply_to: "secret-overflow-suffix" });
    expect(onDisconnect).toHaveBeenCalledTimes(1);
    expect(relay.listenerCount("message")).toBe(0);
    expect(outboundState.pendingOutboundFrames).toBe(MAX_PENDING_OWNER_OUTBOUND_FRAMES);
    await vi.waitFor(() => {
      const audit = readFileSync(auditPath, "utf8");
      expect(audit).toContain('"reason":"outbound_overflow"');
      expect(audit).not.toContain("secret-overflow-suffix");
    });

    resolveFirstReservation(1n);
    await channel.whenIdle();

    expect(outboundState).toMatchObject({ pendingOutboundFrames: 0, pendingOutboundBytes: 0 });
    expect(persistedSeqs).toEqual(
      Array.from({ length: MAX_PENDING_OWNER_OUTBOUND_FRAMES }, (_, index) => BigInt(index + 1)),
    );
    expect(relay.send).toHaveBeenCalledTimes(MAX_PENDING_OWNER_OUTBOUND_FRAMES);
    const exposedSeqs = relay.send.mock.calls.map(([serialized]) => {
      const outer = JSON.parse(serialized as string) as { ct: string };
      const frame = Buffer.from(outer.ct, "base64");
      return new DataView(frame.buffer, frame.byteOffset + 1, 8).getBigUint64(0, true);
    });
    expect(exposedSeqs).toEqual(persistedSeqs);
  });

  test("bounds blocked outbound payload bytes before the frame-count cap", async () => {
    const onDisconnect = vi.fn();
    let resolveReservation!: (value: bigint | null) => void;
    const reservation = new Promise<bigint | null>((resolve) => { resolveReservation = resolve; });
    const reserveSendSeq = vi.fn(() => reservation);
    const { channel } = makeChannel({ onDisconnect, reserveSendSeq });
    const message = {
      type: "agent_chunk",
      session_id: "session-1",
      in_reply_to: "turn-1",
      delta: "x".repeat(1024 * 1024),
    } as const;
    const messageBytes = Buffer.byteLength(JSON.stringify(message), "utf8");
    const acceptedByBytes = Math.floor(MAX_PENDING_OWNER_OUTBOUND_BYTES / messageBytes);
    expect(acceptedByBytes).toBeLessThan(MAX_PENDING_OWNER_OUTBOUND_FRAMES);

    for (let index = 0; index < acceptedByBytes; index += 1) channel.send(message);
    await vi.waitFor(() => expect(reserveSendSeq).toHaveBeenCalledTimes(1));
    const outboundState = channel as unknown as {
      pendingOutboundFrames: number;
      pendingOutboundBytes: number;
    };
    expect(outboundState.pendingOutboundFrames).toBe(acceptedByBytes);
    expect(outboundState.pendingOutboundBytes).toBe(acceptedByBytes * messageBytes);

    channel.send(message);
    expect(onDisconnect).toHaveBeenCalledTimes(1);
    expect(outboundState.pendingOutboundFrames).toBe(acceptedByBytes);
    expect(outboundState.pendingOutboundBytes).toBe(acceptedByBytes * messageBytes);

    resolveReservation(1n);
    await channel.whenIdle();
    expect(outboundState).toMatchObject({ pendingOutboundFrames: 0, pendingOutboundBytes: 0 });
  });

  test("does not expose a frame when send-sequence reservation rejects", async () => {
    const auditPath = makeAuditPath();
    const onDisconnect = vi.fn();
    const { channel, relay } = makeChannel({
      auditPath,
      onDisconnect,
      reserveSendSeq: async () => { throw new Error("disk unavailable"); },
    });

    channel.send({ type: "pong", in_reply_to: "persist-rejected" });
    await channel.whenIdle();

    expect(relay.send).not.toHaveBeenCalled();
    expect(onDisconnect).toHaveBeenCalledTimes(1);
    expect(readFileSync(auditPath, "utf8")).toContain('"reason":"sequence_persist_failed"');
  });

  test("a detached stale channel cannot disconnect its replacement when fenced persistence settles", async () => {
    const relay = new FakeRelay();
    const onDisconnect = vi.fn();
    let resolveReservation!: (value: bigint | null) => void;
    const reservation = new Promise<bigint | null>((resolve) => { resolveReservation = resolve; });
    const channel = new SecurePeerChannel(
      relay as unknown as RelayClient,
      "owner-stale",
      vi.fn(),
      {
        keys: { send: new Uint8Array(32).fill(1), recv: new Uint8Array(32).fill(2) },
        recvSeq: 0n,
        reserveSendSeq: () => reservation,
        compareAndAdvanceRecvSeq: async () => "accepted",
        onDisconnect,
        auditPath: makeAuditPath(),
      },
    );

    channel.send({ type: "pong", in_reply_to: "old-channel" });
    channel.detach();
    resolveReservation(null); // expected-channel-key fence after a re-pair
    await channel.whenIdle();

    expect(onDisconnect).not.toHaveBeenCalled();
  });

  test("persisted send sequence resumes across channel re-attach", async () => {
    const relay = new FakeRelay();
    const persisted = { send: 0n, recv: 0n };
    const first = makeChannel({ relay, persisted });
    first.channel.send({ type: "pong", in_reply_to: "one" });
    await first.channel.whenIdle();
    first.channel.detach();

    const second = makeChannel({ relay, persisted, sendSeq: persisted.send });
    second.channel.send({ type: "pong", in_reply_to: "two" });
    await second.channel.whenIdle();

    const firstOuter = JSON.parse(relay.send.mock.calls[0]![0] as string) as { ct: string };
    const secondOuter = JSON.parse(relay.send.mock.calls[1]![0] as string) as { ct: string };
    const firstFrame = Buffer.from(firstOuter.ct, "base64");
    expect(new DataView(firstFrame.buffer, firstFrame.byteOffset + 1, 8).getBigUint64(0, true)).toBe(1n);
    const secondFrame = Buffer.from(secondOuter.ct, "base64");
    expect(new DataView(secondFrame.buffer, secondFrame.byteOffset + 1, 8).getBigUint64(0, true)).toBe(2n);
    expect(persisted.send).toBe(2n);
    second.channel.detach();
  });
});
