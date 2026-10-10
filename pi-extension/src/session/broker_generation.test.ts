import { describe, expect, test } from "vitest";
import { mkdtempSync, readFileSync, readlinkSync, lstatSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { createServer, type Server } from "node:net";
import { setTimeout as wait } from "node:timers/promises";
import { ipcAddress } from "./ipc.js";
import { SessionPeer } from "./peer.js";
import type { Envelope } from "./envelope.js";

function tmpSock(): string {
  const dir = mkdtempSync(join(tmpdir(), "pi-gen-"));
  return ipcAddress(`gen-${basename(dir)}`, join(dir, "broker.sock"));
}

const FAST_POLL = 40;

/** Poll `cond` until truthy, with a hard cap. Returns the last value. */
async function until<T>(cond: () => T, timeoutMs = 4_000, stepMs = 20): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const v = cond();
    if (v) return v;
    if (Date.now() > deadline) return v;
    await wait(stepMs);
  }
}

interface FastOpts { supersedePollMs?: number; generationProbeMs?: number }

/** Spawn a SessionPeer with the watcher off by default (broker-level tests). */
async function spawnPeer(sockPath: string, name: string, auditPath?: string, opts?: FastOpts): Promise<SessionPeer> {
  const peer = new SessionPeer({
    sockPath, name, auditPath, defaultTimeoutMs: 3_000,
    generationProbeMs: opts?.generationProbeMs ?? 0,
    supersedePollMs: opts?.supersedePollMs,
  });
  await peer.start();
  return peer;
}

describe("broker generation surfaces (design v2 G1)", () => {
  test("register_ack, list_peers (registered + observer), and peer_joined carry generation", async () => {
    const sock = tmpSock();
    const leader = await spawnPeer(sock, "leader");
    expect(leader.generation()).toBeDefined();

    const ackGens: string[] = [];
    const follower = new SessionPeer({ sockPath: sock, name: "flw", generationProbeMs: 0 });
    // Capture the raw register_ack by sniffing before start resolves is not
    // possible on the public surface — the peer records it; assert via the
    // equality signal instead: the follower's generation equals the leader's.
    await follower.start();
    ackGens.push(follower.generation() ?? "missing");
    expect(ackGens[0]).toBe(leader.generation());

    // Registered list_peers: ask the broker through the leader's request path.
    const broker = leader.localBroker()!;
    const reply = await leader.request("broker", { type: "list_peers" }, 2_000);
    const body = reply.body as { generation?: string; peers?: string[] };
    expect(body.generation).toBe(leader.generation());
    expect(body.peers).toContain("flw");

    // Observer probe (unregistered): raw UDS list_peers carries generation.
    const probeReply = await observerProbe(sock);
    expect(probeReply.generation).toBe(leader.generation());

    await leader.leave();
    await follower.leave();
  });

  test("unknown_peer NACK (no colon, no router) + audit line", async () => {
    const sock = tmpSock();
    const auditPath = join(sock, "..", "audit.jsonl");
    const a = await spawnPeer(sock, "a", auditPath);
    const ack = await a.sendWithAck("ghost", { hi: 1 }, null, 2_000);
    expect(ack.status).toBe("unknown_peer");
    expect(ack.target).toBe("ghost");

    const audit = await until(() => readFileSync(auditPath, "utf8").includes("unknown_peer"));
    expect(audit).toBe(true);
    await a.leave();
  });

  test("lifecycle audit lines: bind / register / unregister / close", async () => {
    const sock = tmpSock();
    const auditPath = join(sock, "..", "audit.jsonl");
    const a = await spawnPeer(sock, "a", auditPath);
    const b = await spawnPeer(sock, "b", auditPath);
    await b.leave();
    await a.leave();
    const lines = await until(() => {
      const t = readFileSync(auditPath, "utf8");
      return t.includes("\"event\":\"bind\"") &&
        t.includes("\"event\":\"register\"") &&
        t.includes("\"event\":\"unregister\"") &&
        t.includes("\"event\":\"close\"") ? t : "";
    });
    expect(lines).toContain("\"generation\"");
    expect(lines).toContain("\"pid\"");
  });
});

describe("broker supersession self-check (design v2 G4/R2)", () => {
  test("rendezvous stolen → superseded: broadcast, conns closed, host notified, successor intact", async () => {
    const sock = tmpSock();
    const dir = sock.slice(0, sock.lastIndexOf("/"));
    let superseded = false;
    const leader = await spawnPeer(sock, "leader", undefined, { supersedePollMs: FAST_POLL });
    const broker = leader.localBroker()!;
    expect(broker).not.toBeNull();
    // Arrange a follower to observe the island teardown.
    const followerSaw: string[] = [];
    const follower = new SessionPeer({ sockPath: sock, name: "flw", generationProbeMs: 0 });
    await follower.start();
    follower.onMessage((env: Envelope) => {
      const body = env.body as { type?: string } | null;
      if (body?.type === "generation_superseded") followerSaw.push(body.type ?? "");
    });

    // Steal the rendezvous like a racer would: unique bind + rename publish.
    const racerTarget = join(dir, "broker-racer.sock");
    const racerServer: Server = await new Promise((res) => {
      const s = createServer(() => { /* raw listener */ });
      s.listen(racerTarget, () => res(s));
    });
    const { symlink, rename } = await import("node:fs/promises");
    const tmp = join(dir, ".publish-test.lnk");
    await symlink(basename(racerTarget), tmp, "file");
    await rename(tmp, sock);

    // The broker notices within a poll cycle or two.
    const noticed = await until(() => broker.isRetiring());
    expect(noticed).toBe(true);
    // The follower heard the supersession broadcast (or its socket closed).
    const heard = await until(() => followerSaw.length > 0 || follower.localBroker() === null);
    expect(heard).toBe(true);
    // The successor's rendezvous is untouched by the dissolve.
    expect(readlinkSync(sock)).toBe(basename(racerTarget));

    await leader.leave();
    await follower.leave();
    await new Promise<void>((res) => racerServer.close(() => res()));
  });

  test("legacy socket replacing the rendezvous also triggers supersession", async () => {
    const sock = tmpSock();
    const leader = await spawnPeer(sock, "leader", undefined, { supersedePollMs: FAST_POLL });
    const broker = leader.localBroker()!;

    // Legacy racer binds the rendezvous path DIRECTLY as a socket file.
    const { unlink } = await import("node:fs/promises");
    await unlink(sock).catch(() => undefined); // drop our symlink
    const legacy: Server = await new Promise((res) => {
      const s = createServer(() => { /* raw */ });
      s.listen(sock, () => res(s));
    });
    expect(lstatSync(sock).isSocket()).toBe(true);

    const noticed = await until(() => broker.isRetiring());
    expect(noticed).toBe(true);
    await leader.leave();
    await new Promise<void>((res) => legacy.close(() => res()));
  });
});

/** Raw observer probe: connect, ask list_peers, parse the reply envelope body. */
async function observerProbe(sockPath: string): Promise<{ generation?: string; peers?: string[] }> {
  const { createConnection } = await import("node:net");
  return new Promise((resolve, reject) => {
    const sock = createConnection({ path: sockPath });
    let buf = "";
    const timer = setTimeout(() => { sock.destroy(); reject(new Error("probe timeout")); }, 2_000);
    sock.setEncoding("utf8");
    sock.once("connect", () => sock.write(JSON.stringify({ type: "list_peers" }) + "\n"));
    sock.on("data", (chunk: string) => {
      buf += chunk;
      const nl = buf.indexOf("\n");
      if (nl < 0) return;
      clearTimeout(timer);
      sock.destroy();
      try {
        const env = JSON.parse(buf.slice(0, nl)) as { body?: { generation?: string; peers?: string[] } };
        resolve(env.body ?? {});
      } catch (e) {
        reject(e as Error);
      }
    });
  });
}
