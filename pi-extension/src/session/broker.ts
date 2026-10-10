import type { Server, Socket } from "node:net";
import { appendFile, mkdir, rename, stat, unlink } from "node:fs/promises";
import { basename, dirname } from "node:path";
import { type Envelope, parse, serialize, uuidv7, EnvelopeError } from "./envelope.js";
import { sanitizeSegment } from "./local_config.js";
import { rendezvousOwner } from "./leader_election.js";

/**
 * Structured view of one mesh peer (plan/38). The `address` is the canonical
 * routing key; the other fields let a client group/label peers WITHOUT parsing
 * the address string. `pc` is undefined for local peers (filled cross-PC in
 * Phase 2). Returned by `list_peers` as `peers_detailed`.
 */
export interface PeerInfo {
  /** Cross-PC label; undefined for a local peer. */
  pc?: string;
  /** Working directory (realpath). Empty string for a legacy peer (no cwd). */
  cwd: string;
  /** Clean leaf name (carries a `#N` only on a same-(cwd,name) collision). */
  name: string;
  /** Canonical address — the broker's Map key and the `to`/`from` on the wire. */
  address: string;
}

/**
 * THE sole encoder of a peer address (plan/38): `[<pc>:]<cwd>@<name>`.
 *
 * - `cwd` present → `<cwd>@<name>` (the `@` separates name from path so a `/`
 *   in the path never confuses lookup, which is exact-match anyway).
 * - `cwd` empty (legacy peer that sent no cwd) → `address == name`, preserving
 *   pre-plan/38 behavior so a mixed mesh keeps routing.
 * - `pc` present (cross-PC, Phase 2) → prefixed `<pc>:`.
 *
 * Does NOT sanitize — callers sanitize the `name` once (see `sanitizeMeshName`)
 * before composing, so an already-appended `#N` collision suffix survives.
 * Everyone else ECHOES `peer.address` verbatim; only the broker composes.
 */
export function composeAddress(parts: { pc?: string; cwd: string; name: string }): string {
  const base = parts.cwd ? `${parts.cwd}@${parts.name}` : parts.name;
  return parts.pc ? `${parts.pc}:${base}` : base;
}

/**
 * Sanitize a requested mesh name to a safe leaf while PRESERVING a trailing
 * `#N` collision suffix (which the cwd-lock or a prior assignment may have
 * added — `sanitizeSegment` alone would mangle `#`→`-`). The base is run through
 * `sanitizeSegment` (af66d04); an unusable base (empty / reserved keyword) falls
 * back to `"agent"`.
 */
export function sanitizeMeshName(raw: string): string {
  const m = /^(.*?)(#\d+)?$/.exec(raw);
  const base = sanitizeSegment(m?.[1] ?? raw) ?? "agent";
  return m?.[2] ? base + m[2] : base;
}

/**
 * Broker hosted by the session leader. Accepts UDS connections, maintains a
 * `name → connection` map, routes envelopes per the `to` field, and appends
 * each routed message to an `audit.jsonl` log.
 *
 * Auto-suffix on name collision: when a peer registers a name already taken,
 * the broker assigns `<name>#N` and returns it in the register ack.
 *
 * ## ACK protocol (plan/25 Wave 0; reliable delivery per plan/34)
 *
 * For **unicast non-broker** envelopes the broker synchronously emits an ACK
 * envelope back to the sender once it has delivered:
 *
 *   - target online → deliver envelope, ACK `received`
 *   - no such peer  → silent drop (sender times out)
 *
 * plan/34 removed the busy-drop: a message that arrives while the target is
 * mid-turn is **always delivered**, never dropped. The Pi harness
 * (`sendMessage(triggerTurn:true)`) enqueues mid-turn messages and processes
 * them in the upcoming turn, so the broker needs no busy gate or mailbox.
 * Consequently `busy` is no longer a possible ACK status for unicast new
 * work — the sender always gets `received`. (Turn-lifecycle / working
 * indicators live in `index.ts` via room_meta over the relay, not here.)
 *
 * Broadcast/multicast/broker-addressed envelopes are not ACKed (no single
 * authoritative recipient or no semantic match). The audit log carries the
 * ACK status (`received | denied | none`) per envelope.
 */
export interface BrokerOptions {
  server: Server;
  auditPath?: string;
  /** Optional callback invoked after each successful route (testing/observability). */
  onRouted?: (env: Envelope, deliveredTo: string[]) => void;
  /** Rendezvous path this broker was elected at (design v2). When set
   *  together with `targetPath`, the broker self-checks every
   *  `supersedePollMs` that the rendezvous still points at its own unique
   *  target; on mismatch it dissolves (broadcast + close + notify host). */
  sockPath?: string;
  /** This broker's unique bind target (`broker-<gen>.sock`). */
  targetPath?: string;
  /** Incarnation token; minted when absent. Equality-only semantics. */
  generation?: string;
  /** Supersession poll interval (default 5s; inject smaller in tests). */
  supersedePollMs?: number;
  /** Notified after a supersession dissolve completes teardown steps that
   *  are synchronous (audit/broadcast are fire-and-forget); the host uses it
   * to clear leader state. */
  onSuperseded?: () => void;
}

/**
 * Hook the broker calls before doing local routing, so cross-PC prefixes
 * (`<pc_label>:<peer_name>`) can be handed off to a remote forwarder
 * without baking transport knowledge into the broker. Wave C (plan/25)
 * wires `broker_remote.ts` here.
 */
export interface RemoteRouter {
  /**
   * Try to claim responsibility for routing this envelope cross-PC.
   * Returns true if claimed (broker MUST NOT also deliver locally). Returns
   * false if the envelope should fall through to local routing — e.g., the
   * prefix matches the local `pc_label`, the prefix is not a known remote
   * label (backward-compat for local names containing `:`), or there's no
   * prefix at all.
   */
  tryRouteOutbound(env: Envelope): boolean;
  /** Aggregated remote peer addresses (`<pc_label>:<cwd>@<name>`) for the
   *  `list_peers` reply's `peers` (string) field. Empty when nothing known. */
  listRemotePeers(): string[];
  /** Structured remote roster (plan/38 Phase 2): one `PeerInfo` per cross-PC
   *  peer with `pc` filled (the sibling label), `cwd`/`name` from the sibling's
   *  inventory, and `address` prefixed `<pc>:<cwd>@<name>`. Powers the
   *  `peers_detailed` half of `list_peers` so clients group by `pc`/`cwd`
   *  without parsing. Empty when nothing known. */
  listRemotePeerInfos(): PeerInfo[];
}

/** Local outcome of a cross-PC envelope injection. broker_remote uses this
 *  to construct the ACK envelope it sends back via the relay. plan/34: `busy`
 *  is gone — injection always delivers when the peer exists. */
export type RemoteInjectStatus = "received" | "denied";

interface PeerConn {
  /** Clean leaf name (may carry a `#N` on a same-(cwd,name) collision). */
  name: string;
  /** Working directory the peer registered with — the second half of the
   *  (cwd, name) identity. Empty string for legacy peers that sent no cwd. */
  cwd: string;
  /** Canonical address `composeAddress({cwd, name})` — this conn's Map key and
   *  the value forced onto `env.from`. Empty until registered. */
  address: string;
  socket: Socket;
  buf: string;
}

const BROKER_NAME = "broker";
const BROKER_AUDIT_MAX_BYTES = 256 * 1024;
const BROKER_AUDIT_MAX_RECIPIENTS = 32;
const BROKER_AUDIT_MAX_FIELD_LENGTH = 256;

function auditText(value: unknown): string {
  return typeof value === "string" ? value.slice(0, BROKER_AUDIT_MAX_FIELD_LENGTH) : "";
}

function auditRecipients(value: unknown): string[] {
  const recipients = Array.isArray(value) ? value : [value];
  return recipients
    .filter((recipient): recipient is string => typeof recipient === "string")
    .slice(0, BROKER_AUDIT_MAX_RECIPIENTS)
    .map((recipient) => recipient.slice(0, BROKER_AUDIT_MAX_FIELD_LENGTH));
}

type AckStatus = "received" | "denied" | "invalid_envelope" | "unknown_peer";

interface AckBody {
  type: "ack";
  status: "received" | "denied" | "invalid_envelope" | "unknown_peer";
  target: string;
}

interface RegisterMsg {
  type: "register";
  name: string;
  /** Optional working directory — enables (cwd,name) take-over (see
   *  `_handleRegister`). Absent → legacy `#N`-on-collision behavior. */
  cwd?: string;
}

interface RegisterAck {
  type: "register_ack";
  /** Canonical address (plan/38). New clients route by this. */
  address_assigned: string;
  /** Clean leaf name actually assigned (carries `#N` on a same-(cwd,name)
   *  collision). New clients use it for display; for a legacy peer (no cwd)
   *  it equals `address_assigned`. */
  name_assigned: string;
  /** Broker incarnation token (design v2) — additive; legacy clients ignore
   *  it, new clients use it as their registered-generation equality token. */
  generation?: string;
}

interface SystemBody {
  type: "peer_joined" | "peer_left" | "generation_superseded" | "list_peers_reply";
  /** Compat: carries the peer's ADDRESS (the Map key), not the bare name. */
  name?: string;
  /** Explicit address (plan/38) for clients that prefer the typed field. */
  address?: string;
  /** Addresses (legacy clients route by these). */
  peers?: string[];
  /** Structured roster (plan/38) — clients group by `cwd`/`pc` without parsing. */
  peers_detailed?: PeerInfo[];
  /** Incarnation token of the emitting broker (design v2, additive). */
  generation?: string;
}

/** Own a leader's UDS peer registry and route local or delegated cross-PC envelopes until {@link close} releases its sockets. */
export class Broker {
  private readonly peers = new Map<string, PeerConn>();
  /** Every accepted connection — registered peers AND unregistered observer
   *  probes — so teardown (close/dissolve) can never strand a socket. */
  private readonly conns = new Set<PeerConn>();
  private readonly auditPath?: string;
  private readonly onRouted?: BrokerOptions["onRouted"];
  private readonly server: Server;
  /** Plan/25 Wave C: optional handoff for cross-PC routing. Null = local only. */
  private remoteRouter: RemoteRouter | null = null;
  private auditWrite: Promise<void> = Promise.resolve();
  /** Opaque incarnation token (design v2 R5: equality-only, never ordered). */
  private readonly generation: string;
  /** Rendezvous supersession watch (design v2 R2). Undefined → no watch
   *  (legacy embeds, tests, named-pipe platforms). */
  private readonly sockPath?: string;
  /** This broker's unique bind target — the rendezvous must point here. */
  private readonly targetPath?: string;
  private readonly supersedePollMs: number;
  private supersedeTimer: ReturnType<typeof setInterval> | null = null;
  private dissolving = false;
  private closed = false;
  private readonly onSuperseded?: () => void;

  constructor(opts: BrokerOptions) {
    this.server = opts.server;
    this.auditPath = opts.auditPath;
    this.onRouted = opts.onRouted;
    this.generation = opts.generation ?? uuidv7();
    this.sockPath = opts.sockPath;
    this.targetPath = opts.targetPath;
    this.supersedePollMs = opts.supersedePollMs ?? 5_000;
    this.onSuperseded = opts.onSuperseded;
    this.server.on("connection", (socket) => this._handleConnection(socket));
    this._startSupersedeWatch();
    void this._appendLifecycle("bind", { target: this.targetPath ?? null });
  }

  /** This broker incarnation's generation token (opaque, equality-only). */
  getGeneration(): string {
    return this.generation;
  }

  /** True once supersession teardown or close has begun — callers must not
   *  route or register through a retiring broker. */
  isRetiring(): boolean {
    return this.dissolving || this.closed;
  }

  /** Attach (or detach with null) a cross-PC router. Idempotent. */
  setRemoteRouter(router: RemoteRouter | null): void {
    this.remoteRouter = router;
  }

  /**
   * Plan/25 Wave C entry point: deliver an envelope that arrived from a
   * remote PC (via relay forward) into the local UDS mesh. Skips the
   * `force from = conn.name` rule (that defense is anti-spoof for local
   * peers; cross-PC has its own defense via the relay's verified `from_pc`).
   *
   * Returns the ACK status so the caller (broker_remote) can pack and
   * forward an ACK envelope back across the relay:
   *   - `received` — target exists, envelope delivered (plan/34: always
   *     delivered when the peer is online — the Pi harness enqueues mid-turn
   *     messages, so there is no busy-drop)
   *   - `denied` — no such local peer (or write failed) — caller maps to
   *     transport_error or denied ACK as it sees fit
   */
  injectFromRemote(env: Envelope): RemoteInjectStatus {
    if (typeof env.to !== "string" || env.to === "broadcast" || env.to === BROKER_NAME) {
      // Cross-PC is unicast-only at this protocol layer.
      return "denied";
    }
    const targetName = env.to;
    const peer = this.peers.get(targetName);
    if (!peer) return "denied";

    const line = serialize(env);
    try {
      peer.socket.write(line);
    } catch {
      return "denied";
    }
    void this._appendAudit(env, [targetName], "received", "relay");
    this.onRouted?.(env, [targetName]);
    return "received";
  }

  /** Peers currently registered. Snapshot, safe to read. */
  peerNames(): string[] {
    return [...this.peers.keys()];
  }

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    this._stopSupersedeWatch();
    void this._appendLifecycle("close", {});
    for (const c of this.conns) {
      try { c.socket.destroy(); } catch { /* already gone */ }
    }
    this.conns.clear();
    this.peers.clear();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
  }

  // ── supersession watch (design v2 R2/R6) ──────────────────────────────

  private _startSupersedeWatch(): void {
    // Pointer-based supersession only exists on POSIX rendezvous platforms:
    // named pipes have no symlink/filename indirection (direct bind), and on
    // direct-bind fallbacks target === sockPath — watching would false-dissolve
    // every cycle. (Review finding 7.)
    if (!this.sockPath || !this.targetPath) return;
    if (this.targetPath === this.sockPath) return;
    this.supersedeTimer = setInterval(() => void this._checkSuperseded(), this.supersedePollMs);
    this.supersedeTimer.unref?.();
  }

  private _stopSupersedeWatch(): void {
    if (this.supersedeTimer !== null) {
      clearInterval(this.supersedeTimer);
      this.supersedeTimer = null;
    }
  }

  /** One rendezvous ownership check. Exposed for tests. Superseded iff the
   *  rendezvous exists and does not point at our unique target (a rival's
   *  symlink or a legacy socket file), or is gone entirely (orphaned).
 *  `"unknown"` read errors are NOT supersession — never demote on an
   *  unreadable state. */
  async _checkSuperseded(): Promise<boolean> {
    if (this.dissolving || this.closed) return false;
    if (!this.sockPath || !this.targetPath) return false;
    const owner = await rendezvousOwner(this.sockPath);
    if (owner === "unknown") return false;
    if (owner !== basename(this.targetPath)) {
      void this._dissolve(owner === null ? "orphaned" : owner === "legacy" ? "replaced-legacy" : "replaced");
      return true;
    }
    return false;
  }

  /** Supersession teardown: audit, tell the island, destroy every
   *  connection (registered peers AND observers), close the listener —
   *  which, bound to our UNIQUE target, can only unlink our own file — and
   *  hand the host its demotion. In-flight intra-island envelopes may be
   *  lost (accepted, documented: `received` means broker-to-socket write,
   *  not end-to-end processing). */
  private async _dissolve(reason: string): Promise<void> {
    if (this.dissolving || this.closed) return;
    this.dissolving = true;
    this._stopSupersedeWatch();
    void this._appendLifecycle("superseded", { reason });
    this._broadcastSystem({ type: "generation_superseded", generation: this.generation }, "");
    for (const c of this.conns) {
      try { c.socket.destroy(); } catch { /* already gone */ }
    }
    this.conns.clear();
    this.peers.clear();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
    this.onSuperseded?.();
  }

  // ── connection lifecycle ──────────────────────────────────────────────────

  private _handleConnection(socket: Socket): void {
    const conn: PeerConn = { name: "", cwd: "", address: "", socket, buf: "" };
    this.conns.add(conn);
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => this._onData(conn, chunk));
    socket.on("close", () => this._onClose(conn));
    socket.on("error", () => { /* ignored — close will follow */ });
  }

  private _onData(conn: PeerConn, chunk: string): void {
    conn.buf += chunk;
    let nl: number;
    while ((nl = conn.buf.indexOf("\n")) >= 0) {
      const line = conn.buf.slice(0, nl);
      conn.buf = conn.buf.slice(nl + 1);
      if (!line) continue;
      void this._handleLine(conn, line);
    }
  }

  private async _handleLine(conn: PeerConn, line: string): Promise<void> {
    // Unregistered conn: a read-only `list_peers` probe (the `outpost-pi peers`
    // CLI — answered without registering, so it leaves no trace on the mesh) or
    // the mandatory `register` handshake. Anything else `_handleRegister` drops.
    if (!conn.name) {
      if (this._tryObserverProbe(conn, line)) return;
      this._handleRegister(conn, line);
      return;
    }
    // Already registered — must be a regular envelope.
    let env: Envelope;
    try {
      env = parse(line);
    } catch (e) {
      if (e instanceof EnvelopeError) {
        // Malformed envelope — fail LOUD, never silently: a silent drop
        // surfaces at the sender as an opaque send-timeout with no trace to
        // diagnose (the 2026-10-09 pair-delivery incident: non-UUID `re`
        // vanished here for an afternoon). NACK the sender and audit it.
        this._handleInvalidEnvelope(conn, line, e.message);
        return;
      }
      throw e;
    }
    // Force `from` to the registered ADDRESS (security: peer can't spoof; and
    // replies/ACKs address back by the same canonical key the Map is keyed on).
    env.from = conn.address;
    await this._route(env);
  }

  /** Malformed client envelope: NACK `invalid_envelope` (keyed by the raw
   *  `id` when extractable, so the sender's `sendWithAck` resolves instead of
   *  timing out) and leave an audit trace with the reject reason. Best-effort
   * by construction — this is the broken-input path and must never throw. */
  private _handleInvalidEnvelope(conn: PeerConn, line: string, reason: string): void {
    let raw: { id?: unknown; to?: unknown; re?: unknown } | null = null;
    try {
      raw = JSON.parse(line) as { id?: unknown; to?: unknown; re?: unknown };
    } catch {
      raw = null; // not even JSON — nothing to correlate a NACK with
    }
    const id = raw !== null && typeof raw.id === "string" ? raw.id : null;
    if (id !== null) {
      const ackEnv: Envelope = {
        from: BROKER_NAME,
        to: conn.address,
        id: uuidv7(),
        re: id,
        body: { type: "ack", status: "invalid_envelope", target: conn.address } satisfies AckBody,
      };
      try {
        conn.socket.write(serialize(ackEnv));
      } catch {
        // sender dropped mid-write; close handler will fire
      }
    }
    if (this.auditPath) {
      const auditLine = JSON.stringify({
        ts: Date.now(),
        from: auditText(conn.address),
        to: raw !== null && typeof raw.to === "string" ? auditText(raw.to) : null,
        id: id === null ? null : auditText(id),
        re: raw !== null && typeof raw.re === "string" ? auditText(raw.re) : null,
        delivered: [],
        ack_status: "invalid_envelope",
        via: "uds",
        error: reason,
      }) + "\n";
      const write = this.auditWrite.then(async () => {
        await mkdir(dirname(this.auditPath!), { recursive: true, mode: 0o700 });
        await appendFile(this.auditPath!, auditLine, "utf8");
      });
      this.auditWrite = write.catch(() => undefined);
    }
  }

  private _handleRegister(conn: PeerConn, line: string): void {
    let req: RegisterMsg;
    try {
      const parsed = JSON.parse(line) as unknown;
      if (
        !parsed ||
        typeof parsed !== "object" ||
        (parsed as { type?: unknown }).type !== "register" ||
        typeof (parsed as { name?: unknown }).name !== "string"
      ) {
        conn.socket.destroy();
        return;
      }
      req = parsed as RegisterMsg;
    } catch {
      conn.socket.destroy();
      return;
    }

    // (cwd, name) identity (plan/38). The cwd is the first-class axis: the
    // address embeds it, so two same-named agents in DIFFERENT folders get
    // distinct addresses and never collide — `#N` fires only on the same cwd +
    // same name. A legacy peer (no cwd) → cwd "" → `address == name`, preserving
    // the old global-name behavior so a mixed mesh keeps routing.
    conn.cwd = typeof req.cwd === "string" ? req.cwd : "";

    const { name, address } = this._uniqueIdentity(conn.cwd, req.name);
    conn.name = name;
    conn.address = address;
    this.peers.set(address, conn);

    // `name_assigned` doubles as the compat alias: for a legacy peer it equals
    // `address_assigned` (cwd empty → address == name), so old clients that read
    // `name_assigned` still get a routable identity.
    const ack: RegisterAck = { type: "register_ack", address_assigned: address, name_assigned: name, generation: this.generation };
    try {
      conn.socket.write(JSON.stringify(ack) + "\n");
    } catch { /* peer hung up */ }

    // Notify others (peer_joined broadcast). The field carries the ADDRESS.
    this._broadcastSystem({ type: "peer_joined", name: address, address, generation: this.generation }, address);
    void this._appendLifecycle("register", { address });
  }

  /**
   * Answer a read-only `list_peers` request from an UNREGISTERED connection
   * (the `outpost-pi peers` CLI probe). Returns true when the line was such a
   * probe — the reply is written and the connection stays unregistered: no
   * name assigned, no `peer_joined`/`peer_left` broadcast, no sibling push, so
   * querying the roster from the shell never perturbs the mesh. Returns false
   * (not a probe) so the caller falls through to the register handshake.
   */
  private _tryObserverProbe(conn: PeerConn, line: string): boolean {
    let parsed: { type?: unknown };
    try {
      parsed = JSON.parse(line) as { type?: unknown };
    } catch {
      return false;  // not JSON → let _handleRegister destroy it
    }
    if (!parsed || typeof parsed !== "object" || parsed.type !== "list_peers") {
      return false;
    }
    const reply: Envelope = {
      from: BROKER_NAME,
      to: "observer",  // synthetic: the conn has no registered name
      id: uuidv7(),
      re: null,
      body: {
        type: "list_peers_reply",
        peers: this._allPeerNames(),
        peers_detailed: this._allPeerInfos(),
        generation: this.generation,
      } as SystemBody,
    };
    try { conn.socket.write(serialize(reply)); } catch { /* probe hung up */ }
    return true;
  }

  /** Local UDS peer names plus cross-PC `<pc>:<peer>` entries from the remote
   *  router (empty when no bridge). Shared by the registered `list_peers`
   *  handler and the unregistered observer probe. */
  private _allPeerNames(): string[] {
    const remote = this.remoteRouter ? this.remoteRouter.listRemotePeers() : [];
    return [...this.peerNames(), ...remote];
  }

  /** Structured roster of LOCAL UDS peers (plan/38): one `PeerInfo` each, no
   *  `pc` (they're on this machine). Public so the cross-PC router
   *  (`broker_remote`) can read the authoritative local inventory directly to
   *  push to siblings — no `list_peers` round-trip, no stale cache. */
  localPeerInfos(): PeerInfo[] {
    return [...this.peers.values()].map((p) => ({
      cwd: p.cwd,
      name: p.name,
      address: p.address,
    }));
  }

  /** Structured roster (plan/38): local peers (no `pc`) + cross-PC peers with
   *  `pc`/`cwd`/`name` filled by the remote router (Phase 2). */
  private _allPeerInfos(): PeerInfo[] {
    const remote = this.remoteRouter?.listRemotePeerInfos() ?? [];
    return [...this.localPeerInfos(), ...remote];
  }

  /**
   * Resolve a free `(name, address)` for a register, keyed by **(cwd, name)**
   * (plan/38): the collision check is on the composed ADDRESS, so a name only
   * collides with another peer in the SAME cwd. `#N` is appended to the name
   * (matching the cwd-lock's suffix scheme) until the address is free; for a
   * legacy peer (cwd "") the address is the name, preserving global-name `#N`.
   */
  private _uniqueIdentity(cwd: string, requested: string): { name: string; address: string } {
    const sanitized = sanitizeMeshName(requested);
    let address = composeAddress({ cwd, name: sanitized });
    if (!this.peers.has(address)) return { name: sanitized, address };
    // Collision: strip any client-provided `#N`, then re-suffix from #2.
    const base = sanitized.replace(/#\d+$/, "");
    for (let n = 2; n < 1000; n++) {
      const name = `${base}#${n}`;
      address = composeAddress({ cwd, name });
      if (!this.peers.has(address)) return { name, address };
    }
    throw new Error(`name space exhausted for ${base} in ${cwd || "(no cwd)"}`);
  }

  private _onClose(conn: PeerConn): void {
    this.conns.delete(conn);
    if (!conn.address) return;
    this.peers.delete(conn.address);
    void this._appendLifecycle("unregister", { address: conn.address });
    this._broadcastSystem({ type: "peer_left", name: conn.address, address: conn.address, generation: this.generation }, conn.address);
  }

  // ── routing ───────────────────────────────────────────────────────────────

  private async _route(env: Envelope): Promise<void> {
    // Special handling for messages addressed to the broker itself.
    if (env.to === BROKER_NAME) {
      this._handleBrokerMessage(env);
      return;
    }

    // Plan/25 Wave C: give the cross-PC router a chance to claim this
    // envelope. It returns true when the `to` field carries a known remote
    // prefix and the envelope was packed onto the relay; on miss it falls
    // through so locally-named peers (including ones with literal `:` in
    // their names) still work.
    if (this.remoteRouter && typeof env.to === "string") {
      if (this.remoteRouter.tryRouteOutbound(env)) return;
    }

    const targets = this._resolveTargets(env);
    const delivered: string[] = [];
    const line = serialize(env);
    const isUnicast = typeof env.to === "string" && env.to !== "broadcast";

    // plan/34: reliable delivery — always write to the target's socket. The
    // Pi harness enqueues messages that arrive mid-turn, so there is no
    // busy-drop and `busy` is no longer a possible ACK status. Unicast sends
    // to an online peer always ACK `received`.
    let ackStatus: AckStatus | "none" = "none";
    let matchedAny = false;
    for (const targetName of targets) {
      const peer = this.peers.get(targetName);
      if (!peer) continue;  // see the unknown_peer NACK below for unicast
      matchedAny = true;

      try {
        peer.socket.write(line);
        delivered.push(targetName);
        if (isUnicast) {
          ackStatus = "received";
          this._sendAckToSender(env, "received", targetName);
        }
      } catch {
        // peer dropped mid-write — close handler will fire; treat as silent
      }
    }

    // Design v2 (F4): unicast to an address this broker does not know is NO
    // LONGER a silent drop — NACK `unknown_peer` so the sender can
    // distinguish "not routed by THIS broker at this instant" (roster may
    // be split, or the peer is simply offline) from a transport failure.
    // Broadcast/multicast keep silent semantics (no single authoritative
    // recipient). Exclusion: a cross-PC-PREFIXED target with NO router
    // attached keeps the legacy silent drop — an un-bridged broker cannot
    // judge another PC's roster, and bridgeless leaders are exactly where
    // relay-side ACK injection (broker_remote) must stay possible. With a
    // router attached, reaching this point means the router already
    // declined the prefix — NACK is then legitimate.
    if (
      isUnicast && !matchedAny &&
      !(typeof env.to === "string" && env.to.includes(":") && !this.remoteRouter)
    ) {
      ackStatus = "unknown_peer";
      this._sendAckToSender(env, "unknown_peer", typeof env.to === "string" ? env.to : "");
    }

    if (this.auditPath) await this._appendAudit(env, delivered, ackStatus);
    this.onRouted?.(env, delivered);
  }

  private _resolveTargets(env: Envelope): string[] {
    if (env.to === "broadcast") {
      // plan/38 decision C: broadcast is scoped to the sender's cwd (folder
      // colleagues), local-only. A peer in /a/b never hears /a/c. The sender is
      // keyed by its address (= env.from); legacy peers (cwd "") broadcast among
      // other cwd-less peers, matching pre-plan/38 behavior.
      const sender = this.peers.get(env.from);
      const scope = sender?.cwd ?? "";
      return [...this.peers.values()]
        .filter((p) => p.address !== env.from && p.cwd === scope)
        .map((p) => p.address);
    }
    if (Array.isArray(env.to)) {
      return env.to.filter((n) => n !== env.from);
    }
    // Unicast: drop self-loops too. The skill warns "useless" but the LLM
    // might still try (especially with deceiving `re` reply chains). A
    // self-loop has no upside and risks unbounded message ↔ inject ↔ message
    // cycles when the inbound injector tells the LLM "reply with re=…".
    if (env.to === env.from) return [];
    return [env.to];
  }

  /**
   * Writes an ACK envelope to the original sender's socket. Synchronous —
   * the caller is inside `_route` and must keep busy-check/busy-set atomic.
   * Broker → sender: `from="broker"`, `to=env.from`, `re=env.id`,
   * `body={type:"ack", status, target}`.
   */
  private _sendAckToSender(env: Envelope, status: AckStatus, target: string): void {
    const sender = this.peers.get(env.from);
    if (!sender) return;  // sender vanished mid-write
    const body: AckBody = { type: "ack", status, target };
    const ackEnv: Envelope = {
      from: BROKER_NAME,
      to: env.from,
      id: uuidv7(),
      re: env.id,
      body,
    };
    try {
      sender.socket.write(serialize(ackEnv));
    } catch { /* sender dropped; close handler will fire */ }
  }

  private _handleBrokerMessage(env: Envelope): void {
    const body = env.body as { type?: string; peers?: unknown } | null;
    if (!body || typeof body !== "object") return;
    if (body.type === "list_peers") {
      const reply: Envelope = {
        from: BROKER_NAME,
        to: env.from,
        id: uuidv7(),
        re: env.id,
        body: {
          type: "list_peers_reply",
          peers: this._allPeerNames(),       // addresses — legacy clients route by these
          peers_detailed: this._allPeerInfos(),  // plan/38 — clients group without parsing
          generation: this.generation,          // design v2 — divergence watcher signal
        } as SystemBody,
      };
      const peer = this.peers.get(env.from);
      if (peer) {
        try { peer.socket.write(serialize(reply)); } catch { /* ignored */ }
      }
      return;
    }
    // plan/34: `turn_state` is no longer consumed — the broker doesn't gate
    // delivery on busy state. The Pi extension still publishes working state
    // as room_meta over the relay (index.ts), independent of the broker.
  }

  private _broadcastSystem(body: SystemBody, excludeAddress: string): void {
    for (const [address, peer] of this.peers) {
      if (address === excludeAddress) continue;
      const env: Envelope = {
        from: BROKER_NAME,
        to: address,
        id: uuidv7(),
        re: null,
        body,
      };
      try {
        peer.socket.write(serialize(env));
      } catch { /* ignored */ }
    }
  }

  /** Lifecycle audit line (design v2 R5/G6): bind/superseded/close/register/
   *  unregister events, always carrying the generation + pid so split-brain
   *  forensics no longer need /proc + ss. Diagnostic evidence, not a ledger:
   *  during a split multiple brokers append broker-locally, and audit
   *  completion never gates demotion. */
  private _appendLifecycle(event: string, extra: Record<string, unknown>): void {
    if (!this.auditPath) return;
    const line = JSON.stringify({
      ts: Date.now(),
      event,
      generation: this.generation,
      pid: process.pid,
      ...extra,
    }) + "\n";
    const write = this.auditWrite.then(() => this._appendAuditLine(line));
    this.auditWrite = write.catch(() => undefined);
  }

  /** Shared chained writer body (rotation + append). Both envelope audit and
   *  lifecycle lines serialize through this so ordering is preserved per
   *  broker. */
  private async _appendAuditLine(line: string): Promise<void> {
    if (!this.auditPath) return;
    await mkdir(dirname(this.auditPath), { recursive: true, mode: 0o700 });
    const bytes = Buffer.byteLength(line);
    const currentBytes = await stat(this.auditPath).then((entry) => entry.size).catch(() => 0);
    if (currentBytes > 0 && currentBytes + bytes > BROKER_AUDIT_MAX_BYTES) {
      const previous = `${this.auditPath}.1`;
      await unlink(previous).catch(() => undefined);
      if (currentBytes <= BROKER_AUDIT_MAX_BYTES) {
        await rename(this.auditPath, previous);
      } else {
        // Drop an unbounded pre-hardening log instead of preserving it as the
        // predecessor and carrying the oversized segment forward indefinitely.
        await unlink(this.auditPath);
      }
    }
    await appendFile(this.auditPath, line, "utf8");
  }

  private async _appendAudit(
    env: Envelope,
    delivered: string[],
    ackStatus: AckStatus | "none",
    /**
     * Plan/25 Wave D: provenance hint for the audit reader. `"relay"` marks
     * envelopes injected via `injectFromRemote` (cross-PC). Local UDS
     * delivery keeps the default `"uds"` so existing audit consumers see
     * a uniform field rather than an undefined hole.
     */
    via: "uds" | "relay" = "uds",
  ): Promise<void> {
    if (!this.auditPath) return;
    const line = JSON.stringify({
      ts: Date.now(),
      from: auditText(env.from),
      to: Array.isArray(env.to) ? auditRecipients(env.to) : auditText(env.to),
      id: auditText(env.id),
      re: env.re === null ? null : auditText(env.re),
      delivered: auditRecipients(delivered),
      ack_status: ackStatus,
      via,
    }) + "\n";
    const write = this.auditWrite.then(() => this._appendAuditLine(line));
    this.auditWrite = write.catch(() => undefined);
    await write.catch(() => undefined);
  }
}
