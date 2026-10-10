import { describe, expect, test } from "vitest";
import { mkdtempSync, lstatSync, readlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { createServer, type Server } from "node:net";
import { setTimeout as wait } from "node:timers/promises";
import { ipcAddress } from "./ipc.js";
import { SessionPeer } from "./peer.js";

/**
 * Acceptance lane for `story-mesh-broker-generation-split` (design v2).
 * Deterministic via injected intervals: watchers at 60ms, supersede polls at
 * 40ms, and racers that are REAL live brokers (a second rendezvous in the
 * same session dir whose unique target the steal-symlink points at) — no
 * race windows in the fixtures themselves. The convergence bounds asserted
 * here are proportionally scaled from the production operating target
 * (≤20s at 10s/5s intervals).
 */

function tmpDir(): string {
  return mkdtempSync(join(tmpdir(), "pi-conv-"));
}

function sockIn(dir: string, leaf: string): string {
  return ipcAddress(`conv-${basename(dir)}-${leaf}`, join(dir, leaf));
}

const FAST = { generationProbeMs: 60, supersedePollMs: 40 };

async function until<T>(cond: () => T, timeoutMs = 6_000, stepMs = 20): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const v = cond();
    if (v) return v;
    if (Date.now() > deadline) return v;
    await wait(stepMs);
  }
}

async function spawn(sockPath: string, name: string): Promise<SessionPeer> {
  const peer = new SessionPeer({ sockPath, name, defaultTimeoutMs: 3_000, ...FAST });
  await peer.start();
  return peer;
}

function rosterOf(peer: SessionPeer): string[] {
  return peer.localBroker()?.peerNames() ?? [];
}

/** Steal `rendezvous` for the broker led by `racerPeer` (same dir): publish
 *  a symlink to the racer's unique target via tmp+rename — the exact atomic
 *  operation a re-binding racer performs. */
async function stealRendezvous(rendezvous: string, racerPeer: SessionPeer): Promise<void> {
  const dir = rendezvous.slice(0, rendezvous.lastIndexOf("/"));
  const racerTarget = (racerPeer.localBroker() as unknown as { targetPath?: string }).targetPath;
  if (!racerTarget) throw new Error("racer is not leading a broker");
  const { symlink, rename } = await import("node:fs/promises");
  const tmp = join(dir, `.steal-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.lnk`);
  await symlink(basename(racerTarget), tmp, "file");
  await rename(tmp, rendezvous);
}

describe("mesh generation convergence (design v2 acceptance)", () => {
  test("stale island heals: watchers re-resolve every member onto the path owner", async () => {
    const dir = tmpDir();
    const sock = sockIn(dir, "broker.sock");
    const a = await spawn(sock, "a"); // leader, generation G1
    const b = await spawn(sock, "b"); // follower on G1
    expect(a.currentRole()).toBe("leader");

    // A live racer broker in the same dir, reachable via its own rendezvous.
    const racerSock = sockIn(dir, "broker2.sock");
    const x = await spawn(racerSock, "x");
    expect(x.currentRole()).toBe("leader");
    expect(x.generation()).not.toBe(a.generation());

    // Racer steals the main rendezvous (legacy-racer shape: last rename wins).
    await stealRendezvous(sock, x);

    // Both a's island members detect and converge onto x's generation.
    const converged = await until(() =>
      rosterOf(x).includes("a") && rosterOf(x).includes("b") &&
      a.generation() === x.generation() && b.generation() === x.generation());
    expect(converged).toBe(true);
    expect(a.currentRole()).toBe("follower");
    expect(b.currentRole()).toBe("follower");

    await Promise.all([a.leave(), b.leave(), x.leave()]);
  });

  test("superseded leader self-demotes onto the successor", async () => {
    const dir = tmpDir();
    const sock = sockIn(dir, "broker.sock");
    const a = await spawn(sock, "a");
    expect(a.currentRole()).toBe("leader");
    // Pin the demotion MECHANISM (not just the end state): the loopback
    // client dials the leader's OWN unique target, so the dissolve destroys
    // it, the failover re-resolve runs, and onReconnect fires (review
    // finding 3: a loopback dialed at the mutable rendezvous would survive
    // the dissolve and the flag would stay false with a ghost registration).
    let reconnectFired = false;
    a.onReconnect(() => { reconnectFired = true; });

    const x = await spawn(sockIn(dir, "broker2.sock"), "x");
    await stealRendezvous(sock, x);

    // a's broker notices the stolen rendezvous, dissolves, and a's own
    // failover path re-joins it as a follower of x.
    const demoted = await until(() => a.currentRole() === "follower" && rosterOf(x).includes("a"));
    expect(demoted).toBe(true);
    expect(a.generation()).toBe(x.generation());
    const fired = await until(() => reconnectFired);
    expect(fired).toBe(true);

    await Promise.all([a.leave(), x.leave()]);
  });

  test("full-sweep acceptance: leader broker death + survivor failovers converge to ONE generation", async () => {
    const dir = tmpDir();
    const sock = sockIn(dir, "broker.sock");
    const a = await spawn(sock, "a"); // leader
    const b = await spawn(sock, "b");
    const c = await spawn(sock, "c");
    expect(rosterOf(a).length).toBe(3);

    // Leader's broker dies (crash-equivalent topology effect: connections
    // drop, its own unique target unlinks, the rendezvous dangles).
    const broker = a.localBroker()!;
    await broker.close();

    // Survivors (and the demoted leader) re-resolve via failover/watchers;
    // exactly one leader must emerge with the full roster.
    const converged = await until(() => {
      const leaders = [a, b, c].filter((p) => p.currentRole() === "leader");
      if (leaders.length !== 1) return false;
      const roster = rosterOf(leaders[0]!);
      return roster.includes("a") && roster.includes("b") && roster.includes("c") &&
        a.generation() === b.generation() && b.generation() === c.generation();
    }, 8_000);
    expect(converged).toBe(true);

    await Promise.all([a.leave(), b.leave(), c.leave()]);
  });

  test("legacy broker at the rendezvous: new-code clients register, detection stays passive", async () => {
    const dir = tmpDir();
    const sock = sockIn(dir, "broker.sock");

    // A minimal LEGACY broker: binds broker.sock directly as a socket file,
    // answers register with a generation-less ack and observer list_peers
    // with a generation-less reply envelope (pre-fix wire shape). Counts
    // registrations so passive-watcher behavior is provable.
    const registrations: string[] = [];
    const legacy: Server = await new Promise((res) => {
      const s = createServer((conn) => {
        let buf = "";
        conn.setEncoding("utf8");
        conn.on("data", (chunk: string) => {
          buf += chunk;
          let nl: number;
          while ((nl = buf.indexOf("\n")) >= 0) {
            const line = buf.slice(0, nl);
            buf = buf.slice(nl + 1);
            try {
              const msg = JSON.parse(line) as { type?: string; name?: string };
              if (msg.type === "register" && typeof msg.name === "string") {
                registrations.push(msg.name);
                conn.write(JSON.stringify({
                  type: "register_ack", name_assigned: msg.name, address_assigned: msg.name,
                }) + "\n");
              } else if (msg.type === "list_peers") {
                conn.write(JSON.stringify({
                  from: "broker", to: "observer",
                  id: "01976000-0000-7000-8000-0000000000aa", re: null,
                  body: { type: "list_peers_reply", peers: [] },
                }) + "\n");
              }
            } catch { /* ignore */ }
          }
        });
      });
      s.listen(sock, () => res(s));
    });
    expect(lstatSync(sock).isSocket()).toBe(true);

    const p = new SessionPeer({ sockPath: sock, name: "n1", defaultTimeoutMs: 3_000, ...FAST });
    await p.start();
    // Registered against the legacy broker: follower, no generation, and the
    // watcher must stay passive (no crash, no identity churn) over several
    // probe cycles.
    expect(p.currentRole()).toBe("follower");
    expect(p.generation()).toBeUndefined();
    const stableAddress = p.address();
    await wait(300);
    expect(p.address()).toBe(stableAddress);
    // Passive proof: exactly ONE registration ever reached the legacy broker —
    // the watcher probed (list_peers, generation-less → passive) and never
    // re-registered (review finding 9).
    expect(registrations).toEqual(["n1"]);

    await p.leave();
    await new Promise<void>((res) => legacy.close(() => res()));
  });

  test("same-generation retain: watcher false alarms never churn identity to #N", async () => {
    const sock = sockIn(tmpDir(), "broker.sock");
    const a = await spawn(sock, "a");
    const b = await spawn(sock, "b");
    const before = b.address();

    // Many watcher cycles against the healthy same-generation mesh.
    await wait(400);
    expect(b.address()).toBe(before);
    expect(rosterOf(a).length).toBe(2);
    expect(readlinkSync(sock)).toBeDefined();

    await Promise.all([a.leave(), b.leave()]);
  });

  test("probe error (uncertainty) with a live connection retains identity (review finding 6)", async () => {
    const sock = sockIn(tmpDir(), "broker.sock");
    const a = await spawn(sock, "a");
    // A peer whose probes always time out (busy/stalled broker) while its
    // actual connection stays perfectly healthy.
    class FlakyProbePeer extends SessionPeer {
      protected override _probeGeneration(): Promise<"match" | "mismatch" | "legacy" | "miss" | "error"> {
        return Promise.resolve("error");
      }
    }
    const b = new FlakyProbePeer({ sockPath: sock, name: "b", defaultTimeoutMs: 3_000, ...FAST });
    await b.start();
    const before = b.address();

    // Watcher ticks see "error" repeatedly. The threshold path schedules a
    // resolve whose own probe ALSO errors — and uncertainty must RETAIN the
    // live registration: no #2 churn, roster stays exactly 2.
    await wait(500);
    expect(b.address()).toBe(before);
    expect(rosterOf(a).length).toBe(2);

    await Promise.all([a.leave(), b.leave()]);
  });
});
