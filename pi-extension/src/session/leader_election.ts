import { randomUUID } from "node:crypto";
import { Server, Socket, createConnection, createServer } from "node:net";
import { chmodSync, lstatSync, unlinkSync } from "node:fs";
import { readdir, readlink, symlink, rename, unlink, rm } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";
import { basename, dirname, join } from "node:path";
import { usesNamedPipe } from "./ipc.js";
import { uuidv7 } from "./envelope.js";

const MAX_ATTEMPTS = 20;
const BASE_BACKOFF_MS = 30;
const JITTER_MS = 70;
const PROBE_TIMEOUT_MS = 500;
/** Second-chance budget for `probePeer`/`tryConnect`: a busy fresh event loop
 *  can fire the settle timer before the queued connect-success callback (the
 *  timer-vs-callback race behind the 2026-10-09 fleet false-deaths). The
 *  escalation distinguishes "no answer yet" from a definitive refusal. */
const PROBE_ESCALATION_MS = 3000;
/** Wall-clock budget for one `joinOrLead` call. Bind races retry fast inside
 *  it; exhausting it on *inconclusive* probes rejects to the caller, which
 *  owns a background retry (never a blind publish). */
const ELECTION_DEADLINE_MS = 12_000;
/** Age after which an unreferenced `broker-<gen>.sock` target is treated as a
 *  crashed broker's leftover and collected at the next bind. Frozen-but-alive
 *  owners are unaffected operationally: their supersession check reads the
 *  rendezvous pointer, not their own file. */
const ORPHAN_TARGET_GC_MS = 60 * 60 * 1000;

/** Return the elected role together with the live handle whose lifecycle the caller must own. */
export type ElectionResult =
  | { role: "leader"; server: Server; leaderInfo: LeaderInfo }
  | { role: "follower"; socket: Socket };

/** Identity of a won election: the generation this broker incarnates and the
 *  unique bind target it owns. The rendezvous symlink must point at `target`
 *  for this leader to still own the mesh. */
export interface LeaderInfo {
  /** Opaque equality token (uuidv7). Never ordered — same-host wall-clock
   *  skew and same-ms collisions make time-ordering meaningless here. */
  generation: string;
  /** Absolute path of the unique `broker-<gen>.sock` the server is bound to. */
  target: string;
}

/** Outcome of one honest path probe. `dead` requires a definitive kernel
 *  refusal (error event) — a timeout is NEVER death, because the probe's own
 *  event loop may simply have been busy (F1, 2026-10-09: single fresh
 *  connectors false-deathed idle healthy brokers). */
export type ProbeOutcome =
  | { status: "alive"; socket: Socket }
  | { status: "dead"; code: string }
  | { status: "inconclusive" };

export interface ProbeOptions {
  /** Escalating wait budgets (ms). Default `[500, 3000]`. */
  budgetsMs?: number[];
}

/** Definitive-refusal codes. Anything else (EACCES, EAGAIN/backlog-full, …)
 *  is NOT proof the listener is gone — a backlog-full pipe is practically
 *  proof of life — so those classify as `inconclusive`. */
function isDefinitiveDeath(code: string): boolean {
  return code === "ECONNREFUSED" || code === "ENOENT";
}

/** Probe a UDS path with honest tri-state semantics: `alive` (connected —
 *  caller owns the socket), `dead` (definitive kernel refusal), or
 *  `inconclusive` (no event within the escalated budgets — must never be
 *  treated as permission to unlink or republish). */
export function probePeer(sockPath: string, opts: ProbeOptions = {}): Promise<ProbeOutcome> {
  const budgets = opts.budgetsMs ?? [PROBE_TIMEOUT_MS, PROBE_ESCALATION_MS];
  return new Promise<ProbeOutcome>((resolve) => {
    const sock = createConnection({ path: sockPath });
    let settled = false;
    let budgetIdx = 0;
    const timers: NodeJS.Timeout[] = [];
    const settle = (val: ProbeOutcome) => {
      if (settled) return;
      settled = true;
      for (const t of timers) clearTimeout(t);
      if (val.status !== "alive") sock.destroy();
      resolve(val);
    };
    sock.once("connect", () => settle({ status: "alive", socket: sock }));
    sock.once("error", (err: NodeJS.ErrnoException) => {
      if (isDefinitiveDeath(String(err.code))) settle({ status: "dead", code: String(err.code) });
      // Non-definitive errors keep waiting out the budget before classifying.
      else if (budgetIdx >= budgets.length) settle({ status: "inconclusive" });
    });
    const armNext = (): void => {
      if (settled) return;
      if (budgetIdx >= budgets.length) {
        settle({ status: "inconclusive" });
        return;
      }
      const budget = budgets[budgetIdx++];
      timers.push(setTimeout(armNext, budget));
    };
    armNext();
  });
}

/**
 * UDS-based leader election, v2 (symlink rendezvous, 2026-10-10 story
 * `story-mesh-broker-generation-split`).
 *
 * POSIX: a leader binds a UNIQUE sibling target `broker-<gen>.sock` and
 * atomically publishes `sockPath` as a symlink to it via tmpsymlink +
 * `rename()` — rename replaces legacy socket files, dead files, and rival
 * symlinks with no unlink window, and libuv's close-time unlink (which
 * deletes whatever currently sits at the bind path — reproduced on Node
 * 24.21) can only ever touch the leader's OWN unique file. After publishing,
 * the winner re-reads the rendezvous: if a rival renamed over it, it demotes
 * itself (closing its unique target) and follows the winner — racer
 * collision is benign last-writer-wins, which IS the fencing operation.
 * There is no shared-name unlink anywhere.
 *
 * Followers connect through `sockPath` (symlink follows to the current
 * generation; a plain socket file is a legacy broker and works the same).
 *
 * Honesty rules (F1/F2): a definitive probe refusal (`ECONNREFUSED`,
 * `ENOENT`) is the only path toward leading; `inconclusive` probes back off
 * and retry and NEVER publish. Exhausting the deadline rejects — the caller
 * owns the background retry — rather than risking a split.
 *
 * Windows named pipes: no symlinks — the legacy direct-bind flow keeps the
 * honesty rules that still apply (definitive-death-only bind, no blind
 * unlink).
 */
export async function joinOrLead(sockPath: string): Promise<ElectionResult> {
  const deadline = Date.now() + ELECTION_DEADLINE_MS;
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    if (Date.now() > deadline) break;

    const probe = await probePeer(sockPath);
    if (probe.status === "alive") return { role: "follower", socket: probe.socket };
    if (probe.status === "inconclusive") {
      // Never unlink, never publish on unproven death. Back off and re-probe.
      await delay(BASE_BACKOFF_MS + Math.random() * JITTER_MS);
      continue;
    }

    if (usesNamedPipe()) {
      // Named pipes auto-disappear with their owner: a definitive refusal is
      // a dead pipe; bind the rendezvous directly (no indirection exists).
      const server = await tryBind(sockPath);
      if (server) {
        return {
          role: "leader",
          server,
          leaderInfo: { generation: uuidv7(), target: sockPath },
        };
      }
      await delay(BASE_BACKOFF_MS + Math.random() * JITTER_MS);
      continue;
    }

    const led = await leadViaRendezvous(sockPath);
    if (led) return led;
    // Lost the publish race (or bind failed) — back off; the next probe
    // connects to the winner and we follow it.
    await delay(BASE_BACKOFF_MS + Math.random() * JITTER_MS);
  }
  throw new Error(
    `leader election failed after ${MAX_ATTEMPTS} attempts (deadline ${ELECTION_DEADLINE_MS}ms): ${sockPath}`,
  );
}

/** Bind a unique sibling target, atomically publish the rendezvous symlink,
 *  and verify ownership. Returns null when another racer won the rename or
 *  the bind failed — the caller backs off and re-probes. */
async function leadViaRendezvous(sockPath: string): Promise<ElectionResult | null> {
  const dir = dirname(sockPath);
  const generation = uuidv7();
  const target = join(dir, `broker-${generation}.sock`);
  const server = await tryBind(target);
  if (!server) return null;

  const tmpLink = join(dir, `.broker-publish-${generation}-${randomUUID().slice(0, 8)}.lnk`);
  try {
    // Relative target so the session dir stays movable; rename() is the
    // atomic fencing publish — it replaces ANY prior rendezvous entry.
    await symlink(basename(target), tmpLink, "file");
    await rename(tmpLink, sockPath);
  } catch {
    await rm(tmpLink, { force: true }).catch(() => undefined);
    await closeServer(server);
    return null;
  }

  if (!(await rendezvousPointsAt(sockPath, target))) {
    // A rival renamed over us between our publish and verify. Demote: close
    // our server — libuv unlinks only OUR unique target — and let the caller
    // follow the winner on the next probe.
    await closeServer(server);
    return null;
  }

  void gcOrphanTargets(dir, target).catch(() => undefined);
  return { role: "leader", server, leaderInfo: { generation, target } };
}

/** True iff `sockPath` is a symlink resolving to `target` (relative form). */
async function rendezvousPointsAt(sockPath: string, target: string): Promise<boolean> {
  try {
    return (await readlink(sockPath)) === basename(target);
  } catch {
    return false;
  }
}

/** Which unique target the rendezvous currently points at, `"legacy"` for a
 *  non-symlink entry (plain socket file = legacy broker), or `null` when
 *  missing. Read errors other than ENOENT read as `"unknown"` — callers must
 *  treat that as "cannot judge", never as superseded-or-dead. */
export async function rendezvousOwner(
  sockPath: string,
): Promise<string | "legacy" | "unknown" | null> {
  try {
    return basename(await readlink(sockPath));
  } catch (err) {
    const code = String((err as NodeJS.ErrnoException).code);
    if (code === "EINVAL") return "legacy"; // exists but is not a symlink
    if (code === "ENOENT") return null;
    return "unknown";
  }
}

/** Collect `broker-<gen>.sock` leftovers from crashed brokers: unreferenced
 *  by the rendezvous, not ours, and older than the GC age. Best-effort. */
async function gcOrphanTargets(dir: string, ownTarget: string): Promise<void> {
  const entries = await readdir(dir).catch(() => [] as string[]);
  let referenced: string | null = null;
  const rendezvous = join(dir, "broker.sock");
  if (rendezvous === ownTarget) return; // direct-bind mode (tests): nothing to GC
  referenced = await readlink(rendezvous).then((s) => basename(s)).catch(() => null);
  const now = Date.now();
  for (const entry of entries) {
    if (!/^broker-[0-9a-fA-F-]{36}\.sock$/.test(entry)) continue;
    if (entry === referenced || join(dir, entry) === ownTarget) continue;
    const path = join(dir, entry);
    try {
      const st = lstatSync(path);
      if (!st.isSocket()) continue;
      if (now - st.mtimeMs < ORPHAN_TARGET_GC_MS) continue;
      await unlink(path);
    } catch {
      /* raced away or vanished — fine */
    }
  }
}

async function closeServer(server: Server): Promise<void> {
  await new Promise<void>((resolve) => {
    server.close(() => resolve());
    // Connections are not tracked here (election-level); force-close waits
    // only for the listener. Lingering accepted sockets close with the
    // caller's higher-level teardown.
  });
}

/**
 * Probes a UDS path: if a live listener responds, returns the connected
 * socket; otherwise returns null. Legacy two-state surface kept for
 * `cwd_lock` and the supervisor liveness check — internally escalated to the
 * honest budgets so its null is at least "no answer in 3.5s", not "no answer
 * in 500ms". Destructive consumers of null remain a documented follow-up
 * (story `story-mesh-broker-generation-split`, design v2 scope boundary).
 */
export function tryConnect(sockPath: string): Promise<Socket | null> {
  return probePeer(sockPath).then((outcome) =>
    outcome.status === "alive" ? outcome.socket : null,
  );
}

/**
 * Attempts to bind a UDS server on `sockPath`. Returns the live server on
 * success, null when the path is already held (EADDRINUSE) or any other
 * bind error. Caller is responsible for `unlink`ing a stale sock file
 * before retrying.
 */
export function tryBind(sockPath: string): Promise<Server | null> {
  return _tryBind(sockPath);
}

/** Unlinks the sock file if it exists and is actually a socket. No-op
 *  otherwise. Used to clear stale sockets left behind by a crashed peer. */
export function removeStaleSock(sockPath: string): void {
  _removeStaleSock(sockPath);
}

function _tryBind(sockPath: string): Promise<Server | null> {
  return new Promise((resolve) => {
    const server = createServer();
    let settled = false;
    const settle = (val: Server | null) => {
      if (settled) return;
      settled = true;
      if (!val) {
        try { server.close(); } catch { /* ignored */ }
      }
      resolve(val);
    };
    server.once("error", () => settle(null));
    server.listen(sockPath, () => {
      // Best-effort owner-only perms. The bind already succeeded, so a chmod
      // failure must not crash acquisition. The socket file can disappear
      // between `listen` binding it and this callback firing when a concurrent
      // teardown sweeps the locks dir (e.g. the restart-sweep test's rmSync,
      // or a rapid process restart) — ENOENT here was an unhandled error that
      // turned ci.yml's unit run red. Guard it like the other chmod sites.
      if (!usesNamedPipe()) {
        try { chmodSync(sockPath, 0o600); } catch { /* best-effort — socket may be gone */ }
      }
      settle(server);
    });
  });
}

function _removeStaleSock(sockPath: string): void {
  try {
    const stat = lstatSync(sockPath);
    if (stat.isSocket()) unlinkSync(sockPath);
  } catch {
    // ENOENT or not-a-socket — nothing to clean up.
  }
}
