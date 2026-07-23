import { EventEmitter } from "node:events";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { ClientMessage } from "../protocol/types.js";
import type { RelayClient } from "./relay_client.js";
import {
  MAX_PENDING_OWNER_FRAMES,
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
  persistSequences?: (patch: { sendSeq?: bigint; recvSeq?: bigint }) => Promise<boolean>;
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
      sendSeq: options.sendSeq ?? persisted.send,
      recvSeq: options.recvSeq ?? persisted.recv,
      persistSequences: options.persistSequences ?? (async (patch) => {
        if (patch.sendSeq !== undefined) persisted.send = patch.sendSeq;
        if (patch.recvSeq !== undefined) persisted.recv = patch.recvSeq;
        return true;
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

  test("persists the send high-water before exposing its frame to the relay", async () => {
    let resolvePersistence!: (value: boolean) => void;
    const persistence = new Promise<boolean>((resolve) => { resolvePersistence = resolve; });
    const persistSequences = vi.fn(() => persistence);
    const { channel, relay } = makeChannel({ persistSequences });

    channel.send({ type: "pong", in_reply_to: "persist-first" });
    await vi.waitFor(() => expect(persistSequences).toHaveBeenCalledWith({ sendSeq: 1n }));
    expect(relay.send).not.toHaveBeenCalled();

    resolvePersistence(true);
    await channel.whenIdle();
    expect(relay.send).toHaveBeenCalledTimes(1);
    channel.detach();
  });

  test("does not expose a frame when send high-water persistence rejects", async () => {
    const auditPath = makeAuditPath();
    const onDisconnect = vi.fn();
    const { channel, relay } = makeChannel({
      auditPath,
      onDisconnect,
      persistSequences: async () => { throw new Error("disk unavailable"); },
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
    let resolvePersistence!: (value: boolean) => void;
    const persistence = new Promise<boolean>((resolve) => { resolvePersistence = resolve; });
    const channel = new SecurePeerChannel(
      relay as unknown as RelayClient,
      "owner-stale",
      vi.fn(),
      {
        keys: { send: new Uint8Array(32).fill(1), recv: new Uint8Array(32).fill(2) },
        sendSeq: 0n,
        recvSeq: 0n,
        persistSequences: () => persistence,
        onDisconnect,
        auditPath: makeAuditPath(),
      },
    );

    channel.send({ type: "pong", in_reply_to: "old-channel" });
    channel.detach();
    resolvePersistence(false); // expected-channel-key fence after a re-pair
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
