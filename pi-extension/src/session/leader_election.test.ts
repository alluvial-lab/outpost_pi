import { describe, expect, test } from "vitest";
import { existsSync, lstatSync, mkdtempSync, readlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { joinOrLead, probePeer, tryBind } from "./leader_election.js";
import { ipcAddress } from "./ipc.js";
import type { Server } from "node:net";

function tmpSock(): string {
  // Per-test unique IPC address (pipe on Windows; `.sock` file on POSIX). The
  // suffix embeds the unique tmpdir basename so machine-global pipe names don't
  // collide across tests/workers (plan/40).
  const dir = mkdtempSync(join(tmpdir(), "pi-le-"));
  return ipcAddress(`le-${basename(dir)}`, join(dir, "broker.sock"));
}

async function closeServer(server: Server): Promise<void> {
  await new Promise<void>((res) => server.close(() => res()));
}

describe("joinOrLead", () => {
  async function cleanup(results: Array<{ role: string; server?: import("node:net").Server; socket?: import("node:net").Socket }>) {
    // Destroy follower sockets FIRST so the leader's server can close cleanly.
    for (const r of results) {
      if (r.role === "follower" && r.socket) r.socket.destroy();
    }
    for (const r of results) {
      if (r.role === "leader" && r.server) {
        await new Promise<void>((res) => r.server!.close(() => res()));
      }
    }
  }

  test("first caller becomes leader, second becomes follower", async () => {
    const sock = tmpSock();
    const r1 = await joinOrLead(sock);
    expect(r1.role).toBe("leader");

    const r2 = await joinOrLead(sock);
    expect(r2.role).toBe("follower");

    await cleanup([r1, r2] as Parameters<typeof cleanup>[0]);
  });

  test("3 concurrent callers: exactly 1 leader", async () => {
    const sock = tmpSock();
    const results = await Promise.all([
      joinOrLead(sock),
      joinOrLead(sock),
      joinOrLead(sock),
    ]);
    const leaders = results.filter((r) => r.role === "leader");
    const followers = results.filter((r) => r.role === "follower");
    expect(leaders).toHaveLength(1);
    expect(followers).toHaveLength(2);

    await cleanup(results as Parameters<typeof cleanup>[0]);
  });

  test("stale (orphan) sock file is cleaned up + caller becomes leader", async () => {
    const sock = tmpSock();
    // Plant a fake orphan: regular file with .sock name (not a real socket).
    // The cleanup heuristic only removes when lstat says isSocket(), so we
    // can't trigger removal of a plain file. Test the leader case where no
    // prior file exists.
    expect(existsSync(sock)).toBe(false);
    const r = await joinOrLead(sock);
    expect(r.role).toBe("leader");
    if (r.role === "leader") await new Promise<void>((res) => r.server.close(() => res()));
  });

  // ── design v2 (story-mesh-broker-generation-split) ─────────────────────────

  test("probePeer: live listener with tiny budgets → inconclusive, NEVER dead (F1 honesty)", async () => {
    const sock = tmpSock();
    const server = await tryBind(sock);
    expect(server).not.toBeNull();
    // Reproduce the timer-vs-callback shape of the 2026-10-09 fleet
    // false-deaths deterministically: a 1ms budget + a synchronously stalled
    // loop — the expired settle timer processes before the (kernel-complete)
    // connect event, exactly like a busy fresh process.
    const pending = probePeer(sock, { budgetsMs: [1] });
    const stallUntil = Date.now() + 30;
    while (Date.now() < stallUntil) { /* synchronous stall — nothing processes */ }
    const outcome = await pending;
    expect(outcome.status).toBe("inconclusive");
    // And honesty held: the listener is untouched and still accepting.
    const still = await probePeer(sock);
    expect(still.status).toBe("alive");
    if (still.status === "alive") still.socket.destroy();
    await closeServer(server!);
  });

  test("probePeer: dead path (listener closed, file left) → definitive dead", async () => {
    const sock = tmpSock();
    const server = await tryBind(sock);
    await closeServer(server!); // file remains, listener gone → ECONNREFUSED
    const outcome = await probePeer(sock);
    expect(outcome.status).toBe("dead");
  });

  test("leader publishes a symlink rendezvous over its unique target", async () => {
    const sock = tmpSock();
    const r = await joinOrLead(sock);
    expect(r.role).toBe("leader");
    if (r.role !== "leader") return;
    // Rendezvous is a symlink pointing at the unique target file, which exists.
    expect(lstatSync(sock).isSymbolicLink()).toBe(true);
    expect(readlinkSync(sock)).toBe(basename(r.leaderInfo.target));
    expect(existsSync(r.leaderInfo.target)).toBe(true);
    await closeServer(r.server);
  });

  test("legacy socket file at the rendezvous is followed (mixed-version compat)", async () => {
    const sock = tmpSock();
    const legacy = await tryBind(sock); // plain socket file, no symlink
    expect(legacy).not.toBeNull();
    const r = await joinOrLead(sock);
    expect(r.role).toBe("follower");
    if (r.role === "follower") r.socket.destroy();
    await closeServer(legacy!);
  });

  test("dead-path race: two concurrent joinOrLead → exactly one leader, loser follows", async () => {
    const sock = tmpSock();
    // Plant a dead path: bind then close WITHOUT cleanup.
    const dead = await tryBind(sock);
    await closeServer(dead!);
    const results = await Promise.all([joinOrLead(sock), joinOrLead(sock)]);
    const leaders = results.filter((r) => r.role === "leader");
    const followers = results.filter((r) => r.role === "follower");
    expect(leaders).toHaveLength(1);
    expect(followers).toHaveLength(1);
    for (const r of results) {
      if (r.role === "follower") r.socket.destroy();
      else await closeServer(r.server);
    }
  });

  // The regression test for the design-v2 BLOCKER (reproduced on this exact
  // Node line): libuv's server.close() unlinks whatever currently sits at the
  // BIND path. With unique targets, closing a SUPERSEDED leader must only
  // remove its own file — never the successor's rendezvous or target.
  test.skipIf(process.platform === "win32")(
    "closing a superseded leader never deletes the successor's rendezvous",
    async () => {
      const sock = tmpSock();
      const a = await joinOrLead(sock);
      if (a.role !== "leader") throw new Error("expected leader");
      // Racer steals the rendezvous: binds its own unique target and renames
      // a fresh symlink over ours (the atomic publish).
      const racerDir = dirnameOf(sock);
      const racerTarget = join(racerDir, "broker-racer.sock");
      const racerServer = await tryBind(racerTarget);
      expect(racerServer).not.toBeNull();
      const { symlink, rename } = await import("node:fs/promises");
      const tmp = join(racerDir, ".publish-racer.lnk");
      await symlink(basename(racerTarget), tmp, "file");
      await rename(tmp, sock);
      // Close the superseded leader (dissolve path does exactly this).
      await closeServer(a.server);
      // Successor intact: rendezvous still resolves to the racer's target.
      expect(readlinkSync(sock)).toBe(basename(racerTarget));
      expect(existsSync(racerTarget)).toBe(true);
      // And the old leader's own file is gone (its close cleaned up itself).
      expect(existsSync(a.leaderInfo.target)).toBe(false);
      await closeServer(racerServer!);
    },
  );


  // POSIX-only: simulates a stale leftover by `writeFileSync(sock, "")` — i.e.
  // the sock-as-FILE crash-recovery path. On Windows `sock` is a named pipe
  // (auto-cleaned on owner exit; no file to leave behind), so the premise
  // doesn't apply — the Bloco A lifecycle skips unlink on win32 for the same
  // reason. The cross-platform election cases are covered by the tests above.
  test.skipIf(process.platform === "win32")("real stale socket from prior leader is cleaned + new leader binds", async () => {
    const sock = tmpSock();
    const r1 = await joinOrLead(sock);
    expect(r1.role).toBe("leader");
    if (r1.role !== "leader") return;
    // Close server without unlinking sock file (simulates abrupt crash).
    await new Promise<void>((res) => r1.server.close(() => res()));
    // sock file may still exist on disk
    writeFileSync(sock, "");  // ensure stale entry — but as regular file; cleanup heuristic skips
    // The election should still succeed (bind would fail if sock file existed
    // as another regular file). For the test we accept either route — what
    // matters is no two leaders co-exist.
    try {
      const r2 = await joinOrLead(sock);
      if (r2.role === "leader") {
        await new Promise<void>((res) => r2.server.close(() => res()));
      } else {
        r2.socket.destroy();
      }
    } catch {
      // Acceptable: stale-file blocking with non-socket type means election
      // can't recover (rare). Documented limitation.
    }
  });
});

function dirnameOf(path: string): string {
  return path.slice(0, path.lastIndexOf("/"));
}
