import type { Socket } from "node:net";
import { createConnection } from "node:net";
import { setTimeout as delay } from "node:timers/promises";
import { type Envelope, envelope, parse, serialize, EnvelopeError } from "./envelope.js";
import { joinOrLead, type ElectionResult } from "./leader_election.js";
import { Broker } from "./broker.js";

/**
 * Symmetric peer-in-session API. Hides whether you are leader or follower;
 * `send`, `request`, `onMessage`, `rename`, `leave` all work the same.
 *
 * Pending map demuxes parallel `request()` calls by message `id` → `re`.
 *
 * Failover: when the leader dies, follower socket emits `close`. Remaining
 * peers re-run `joinOrLead`. One becomes the new leader; others reconnect.
 *
 * Design v2 (`story-mesh-broker-generation-split`): connections are STAGED —
 * each socket owns its buffer, pre-ack listener, and a monotonically
 * increasing revision, so late callbacks from a replaced connection can
 * never corrupt a fresh handshake (the make-before-break re-join registers
 * the candidate BEFORE destroying the old socket). A divergence watcher
 * probes the rendezvous path with the unregistered `list_peers` observer
 * probe and re-resolves when the path's broker generation no longer matches
 * the one this peer registered under — stale islands dissolve on their own.
 */
export type MessageHandler = (env: Envelope) => void;
/** Receive notification after a successful post-failover rejoin, not during initial startup. */
export type ReconnectHandler = () => void;

/** Configure a local UDS peer and its routing identity, timeouts, and optional audit path. */
export interface SessionPeerOptions {
  sockPath: string;
  name: string;
  /**
   * Working directory of this agent. Sent in the `register` so the broker can
   * key peers by the (cwd, name) pair: two agents in the SAME folder with the
   * same name are the SAME logical agent reincarnating (switch_session /
   * restart), so the broker take-over the name instead of suffixing `#N`.
   * Optional for backward-compat with peers that predate this field.
   */
  cwd?: string;
  auditPath?: string;
  /** Per-request default timeout (ms). Override per call if needed. */
  defaultTimeoutMs?: number;
  /** Divergence-watcher interval (ms). Default 10s; inject smaller in tests. */
  generationProbeMs?: number;
  /** Passed through to the hosted Broker's supersession poll. Default 5s. */
  supersedePollMs?: number;
}

const DEFAULT_TIMEOUT_MS = 30_000;
const ACK_TIMEOUT_MS = 5_000;
const FAILOVER_RETRY_MS = 100;
const DEFAULT_GENERATION_PROBE_MS = 10_000;
/** Consecutive rendezvous misses before a re-resolve (suspicion, not proof —
 *  one stall can correlate two ticks). */
const GENERATION_MISS_THRESHOLD = 2;
/** Whole-probe budget (connect + reply). */
const GENERATION_PROBE_BUDGET_MS = 5_000;
/** Minimum spacing between unknown_peer-triggered probes (coalescing). */
const NACK_PROBE_MIN_INTERVAL_MS = 2_000;
/** Background rejoin backoff after an election failure: floor/cap, jittered. */
const REJOIN_BACKOFF_FLOOR_MS = 1_000;
const REJOIN_BACKOFF_CAP_MS = 30_000;

/** Classify the broker acknowledgement for a unicast delivery attempt. */
export type AckStatus = "received" | "busy" | "denied" | "timeout" | "invalid_envelope" | "unknown_peer";

/** Report the terminal acknowledgement result; timeout means no broker confirmation arrived. */
export interface AckResult {
  status: AckStatus;
  /** The original envelope id that was awaiting ACK. */
  id: string;
  /** Target name reported by broker (when ACK arrived). Undefined on timeout. */
  target?: string;
}

interface AckBody {
  type: "ack";
  status: "received" | "busy" | "denied" | "invalid_envelope" | "unknown_peer";
  target: string;
}

/** One live (or staged) broker connection. All mutable per-connection state
 *  lives here — never on the peer — so a replaced connection's late events
 *  are fenced by identity comparison against `this.conn`. */
interface ConnState {
  socket: Socket;
  buf: string;
  /** Pre-register-ack line listener (register handshake), else null. */
  preAck: ((raw: unknown) => void) | null;
  /** Handshake-death hook: set while the register handshake is pending so a
   *  socket close fails the handshake fast instead of waiting out the ack
   *  timeout. Cleared on promote/failure. */
  onDeath?: (err: Error) => void;
}

/** Own a peer's broker connection, pending requests, and failover rejoin lifecycle until {@link leave} tears them down. */
export class SessionPeer {
  private readonly opts: SessionPeerOptions;
  /** Clean leaf name actually assigned by the broker (may carry a `#N`
   *  collision suffix). Used for display + self-filtering. */
  private assignedName: string;
  /** Canonical address assigned by the broker (`[<pc>:]<cwd>@<name>`, or just
   * the name for a legacy broker). This is the routing/identity key the mesh
   * uses; callers ECHO it, never compose it. */
  private assignedAddress: string;
  /** Generation of the broker this peer is registered under. Undefined
   * against a legacy broker (detection off) or before the first register. */
  private registeredGeneration: string | undefined;
  private role: "leader" | "follower" = "follower";
  private broker: Broker | null = null;
  private conn: ConnState | null = null;
  /** Map of in-flight request ids → resolver. Used by `request()`. */
  private readonly pending = new Map<string, {
    resolve: (env: Envelope) => void;
    reject: (err: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  }>();
  /** Map of in-flight send ids → ACK resolver. Used by `sendWithAck()`. */
  private readonly ackPending = new Map<string, {
    resolve: (result: AckResult) => void;
    timer: ReturnType<typeof setTimeout>;
  }>();
  private readonly handlers = new Set<MessageHandler>();
  private readonly reconnectHandlers = new Set<ReconnectHandler>();
  private leftFlag = false;
  /** Single-flight chain for re-resolves (watcher / failover / NACK all funnel here). */
  private resolveChain: Promise<void> = Promise.resolve();
  /** In-flight register candidates (make-before-break staging). Owned here so
   *  `leave()` can destroy them and late ACKs can be fenced against disposal. */
  private readonly staged = new Set<ConnState>();
  /** Divergence watcher scheduling handle (recursive timeout, jittered). */
  private watcherTimer: ReturnType<typeof setTimeout> | null = null;
  private consecutiveMisses = 0;
  private lastNackProbeAt = 0;
  /** Background rejoin timer after an election failure. */
  private rejoinTimer: ReturnType<typeof setTimeout> | null = null;
  private rejoinBackoff = REJOIN_BACKOFF_FLOOR_MS;

  constructor(opts: SessionPeerOptions) {
    this.opts = opts;
    this.assignedName = opts.name;
    this.assignedAddress = opts.name;
  }

  // ── public API ────────────────────────────────────────────────────────────

  /** Joins or leads the session at `sockPath`. Resolves with the assigned
   *  name — or, when the election exhausts (wedged rendezvous, inconclusive
   *  probes), with the requested name while the mesh stays DEGRADED: a
   *  jittered background retry owns recovery and the divergence watcher is
   *  armed, so a transient startup stall no longer disables the mesh for the
   *  process lifetime (design v2 R4). Sends fail fast ("not connected")
   *  until a rejoin succeeds. */
  async start(): Promise<string> {
    try {
      const name = await this._rejoin("initial-start");
      this._startWatcher();
      return name;
    } catch {
      this._scheduleRejoinRetry();
      this._startWatcher();
      return this.opts.name;
    }
  }

  /** Returns the clean leaf name as assigned by the broker (after any `#N`). */
  name(): string {
    return this.assignedName;
  }

  /** Returns the canonical address (`[<pc>:]<cwd>@<name>`) assigned by the
   * broker — the key the mesh routes on. Equals `name()` against a legacy
   * broker that returns no address. */
  address(): string {
    return this.assignedAddress;
  }

  /** Returns "leader" or "follower" — current role. */
  currentRole(): "leader" | "follower" {
    return this.role;
  }

  /** Generation of the broker this peer is registered under (undefined when
   * the broker is legacy or before the first register). Equality-only token. */
  generation(): string | undefined {
    return this.registeredGeneration;
  }

  /** Returns the locally-hosted Broker when this peer is the leader, or
   * null when it's a follower. Wave 25C uses this to attach the
   * cross-PC router. */
  localBroker(): Broker | null {
    return this.broker;
  }

  /**
   * Fire-and-forget send. Doesn't await a reply.
   *
   * `re` (optional) lets the caller correlate this message as a reply to a
   * previous request — when an LLM peer is *answering* a question from
   * another agent, it must echo the original `id` here so the requester's
   * pending map can resolve. Without `re`, the requester treats this as a
   * new unsolicited message and its `request()` call times out.
   */
  async send(
    to: string | string[],
    body: unknown,
    re: string | null = null,
  ): Promise<void> {
    const env = envelope(this.assignedName, to, body, re);
    await this._writeEnvelope(env);
  }

  /**
   * Unicast send + await broker ACK. Returns the ACK status:
   *   - `received` — envelope written to the peer's socket; will be processed soon
   *   - `unknown_peer` — target not registered on THIS broker at this instant
   *     (peer offline, or the roster may be split — check `list_peers`)
   *   - `busy`     — legacy status; no longer produced (plan/34)
   *   - `denied`   — peer explicitly refused (reserved; no producer in MVP)
   *   - `timeout`  — no ACK within `timeoutMs`; treat as transport error
   *
   * Only meaningful for unicast non-broadcast addresses. The peer's body-level
   * reply (if any) is asynchronous and arrives as a normal inbound envelope
   * carrying `re=<this-send-id>` in a future turn — handled by `onMessage`.
   */
  async sendWithAck(
    to: string,
    body: unknown,
    re: string | null = null,
    timeoutMs: number = ACK_TIMEOUT_MS,
  ): Promise<AckResult> {
    const env = envelope(this.assignedName, to, body, re);
    return new Promise<AckResult>((resolve) => {
      const timer = setTimeout(() => {
        this.ackPending.delete(env.id);
        resolve({ status: "timeout", id: env.id });
      }, timeoutMs);
      this.ackPending.set(env.id, { resolve, timer });
      this._writeEnvelope(env).catch(() => {
        const slot = this.ackPending.get(env.id);
        if (!slot) return;
        clearTimeout(slot.timer);
        this.ackPending.delete(env.id);
        resolve({ status: "timeout", id: env.id });
      });
    });
  }

  /**
   * Send + await reply. Resolves with the first inbound envelope whose `re`
   * matches the outbound `id`. Rejects on timeout.
   */
  async request(
    to: string,
    body: unknown,
    timeoutMs: number = this.opts.defaultTimeoutMs ?? DEFAULT_TIMEOUT_MS,
  ): Promise<Envelope> {
    const env = envelope(this.assignedName, to, body, null);
    return new Promise<Envelope>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(env.id);
        reject(new Error(`request to ${to} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      this.pending.set(env.id, { resolve, reject, timer });
      this._writeEnvelope(env).catch((err) => {
        const slot = this.pending.get(env.id);
        if (!slot) return;
        clearTimeout(slot.timer);
        this.pending.delete(env.id);
        reject(err);
      });
    });
  }

  onMessage(handler: MessageHandler): () => void {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  /**
   * Fires after the peer successfully (re)joins following a failover —
   * leader died and we re-elected. NOT called for the initial `start()`,
   * only for post-drop reconnects. Consumers use this to re-query state
   * the broker may have lost in the transition (e.g., peer list).
   */
  onReconnect(handler: ReconnectHandler): () => void {
    this.reconnectHandlers.add(handler);
    return () => this.reconnectHandlers.delete(handler);
  }

  /**
   * Requests a different display name from the broker. Returns the name
   * actually assigned (may carry a #N suffix on collision). Implemented as
   * a soft rejoin: leaves & rejoins with the new name.
   */
  async rename(newName: string): Promise<string> {
    await this._teardownConn();
    this.opts.name = newName;
    this.assignedName = newName;
    await this._rejoin("rename");
    return this.assignedName;
  }

  async leave(): Promise<void> {
    this.leftFlag = true;
    this._stopWatcher();
    if (this.rejoinTimer !== null) {
      clearTimeout(this.rejoinTimer);
      this.rejoinTimer = null;
    }
    await this._teardownConn();
  }

  // ── join / failover loop ──────────────────────────────────────────────────

  /** Single-flight wrapper: every re-resolve trigger (watcher mismatch,
   *  rendezvous misses, socket close, unknown_peer NACK) funnels through one
   *  serialized chain so concurrent triggers can never double-register. */
  private _scheduleResolve(reason: string): void {
    this.resolveChain = this.resolveChain.then(
      () => this._resolvePath(reason),
      () => this._resolvePath(reason),
    );
  }

  private async _resolvePath(reason: string): Promise<void> {
    if (this.leftFlag) return;

    // Same-generation retain (design v2 R3): when the current connection is
    // alive and the rendezvous still serves OUR generation, a watcher or
    // failover trigger was a false alarm — keep the connection (and the
    // broker-assigned identity) instead of re-registering as `#N`. A probe
    // `error` (timeout, no reply) with a live connection is UNCERTAINTY, not
    // divergence — retain here too; only the watcher's consecutive-miss
    // threshold escalates uncertainty into a re-resolve.
    const connAlive = this.conn !== null && !this.conn.socket.destroyed;
    if (connAlive) {
      const probe = await this._probeGeneration();
      if (probe === "match") return;
      if (probe === "legacy" && this.registeredGeneration === undefined) return;
      if (probe === "error") return;
      // "mismatch" | "miss" | "legacy-with-generation" → re-resolve.
    }

    try {
      await this._rejoin(reason);
      if (this.leftFlag) return;
      this.rejoinBackoff = REJOIN_BACKOFF_FLOOR_MS;
      // The new broker's peers map starts fresh — consumers must re-query
      // any cached state (peer count, etc.) that depended on the old broker.
      for (const h of this.reconnectHandlers) {
        try { h(); } catch { /* handler errors don't break peer */ }
      }
    } catch {
      // Election exhausted (inconclusive probes, wedged rendezvous): never
      // destructive — schedule a jittered background retry and keep whatever
      // connection we still have (design v2 R4).
      this._scheduleRejoinRetry();
    }
  }

  private _scheduleRejoinRetry(): void {
    if (this.leftFlag || this.rejoinTimer !== null) return;
    const backoff = this.rejoinBackoff;
    this.rejoinBackoff = Math.min(this.rejoinBackoff * 2, REJOIN_BACKOFF_CAP_MS);
    const jittered = backoff + Math.random() * (backoff / 4);
    this.rejoinTimer = setTimeout(() => {
      this.rejoinTimer = null;
      this._scheduleResolve("rejoin-retry");
    }, jittered);
    this.rejoinTimer.unref?.();
  }

  /** Election seam (overridable in lifecycle tests for deterministic barriers). */
  protected _elect(): Promise<ElectionResult> {
    return joinOrLead(this.opts.sockPath);
  }

  /** One joinOrLead + staged register + atomic promote. Throws on election
   *  failure (caller owns the retry). The OLD connection is destroyed only
   *  after the candidate registered — make-before-break. */
  private async _rejoin(reason: string): Promise<string> {
    void reason;
    const result: ElectionResult = await this._elect();
    if (this.leftFlag) {
      if (result.role === "leader") {
        await new Promise<void>((resolve) => result.server.close(() => resolve()));
      } else {
        try { result.socket.destroy(); } catch { /* already gone */ }
      }
      return this.assignedName;
    }

    if (result.role === "leader") {
      this.role = "leader";
      // Take over the local broker role; onSuperseded clears it when the
      // rendezvous stops pointing at us — fenced to THIS broker incarnation,
      // so a late dissolve callback can never clear a newer leader the
      // watcher already installed. The loopback client's close then drives
      // this peer's re-resolve through the normal failover path.
      const broker = new Broker({
        server: result.server,
        auditPath: this.opts.auditPath,
        sockPath: this.opts.sockPath,
        targetPath: result.leaderInfo.target,
        generation: result.leaderInfo.generation,
        supersedePollMs: this.opts.supersedePollMs,
        onSuperseded: () => {
          if (this.broker === broker) {
            this.broker = null;
            this.role = "follower";
          }
        },
      });
      this.broker = broker;
      // Leader also registers itself as a peer so other followers see it +
      // can address it: a real client connection back to our own server —
      // dialed at OUR UNIQUE TARGET, never the mutable rendezvous, so a
      // racer publishing between verify and connect cannot wedge us into
      // the successor while still hosting the old broker.
      const sock = createConnection(result.leaderInfo.target);
      try {
        await new Promise<void>((resolve, reject) => {
          sock.once("connect", () => resolve());
          sock.once("error", reject);
        });
      } catch (err) {
        try { sock.destroy(); } catch { /* already gone */ }
        if (this.broker === broker) {
          this.broker = null;
          this.role = "follower";
        }
        await broker.close().catch(() => undefined);
        throw err;
      }
      if (this.leftFlag) {
        try { sock.destroy(); } catch { /* already gone */ }
        if (this.broker === broker) {
          this.broker = null;
          this.role = "follower";
        }
        await broker.close().catch(() => undefined);
        return this.assignedName;
      }
      return await this._registerStaged(sock);
    }

    this.role = "follower";
    return await this._registerStaged(result.socket);
  }

  /** Stage a candidate connection: wire its handlers to its OWN state, run
   *  the register handshake, and only then promote it to `this.conn`
   *  (destroying the previous connection, whose late events are fenced by
   *  the identity check in its close handler). The candidate is owned by
   *  `this.staged` for its whole handshake: `leave()` destroys it, a late
   *  ACK after `leave()` never promotes it, and a failed handshake destroys
   *  it — no ghost sockets, no post-disposal promotion. */
  private _registerStaged(sock: Socket): Promise<string> {
    const staged: ConnState = { socket: sock, buf: "", preAck: null };
    this.staged.add(staged);
    sock.setEncoding("utf8");
    sock.on("data", (chunk: string) => this._onData(staged, chunk));
    sock.on("close", () => {
      this.staged.delete(staged);
      // Handshake still pending → the candidate died before its ACK: fail
      // the registration fast (leave(), broker reset, crash) rather than
      // holding the rejoin hostage for the 5s ack timeout.
      if (staged.preAck) staged.onDeath?.(new Error("register socket closed before ack"));
      this._onConnClose(staged);
    });
    sock.on("error", () => { /* close will follow */ });

    let wait: ReturnType<typeof setTimeout> | null = null;
    const clearWait = (): void => {
      if (wait !== null) {
        clearTimeout(wait);
        wait = null;
      }
    };

    const fail = (reject: (err: Error) => void, err: Error): void => {
      clearWait();
      staged.preAck = null;
      staged.onDeath = undefined;
      this.staged.delete(staged);
      try { sock.destroy(); } catch { /* already gone */ }
      reject(err);
    };

    return new Promise<string>((resolve, reject) => {
      staged.onDeath = (err: Error) => fail(reject, err);
      // The first inbound line MUST be the register_ack. Buffer-aware.
      wait = setTimeout(() => {
        wait = null;
        fail(reject, new Error("register_ack timeout"));
      }, 5_000);
      wait.unref?.();
      staged.preAck = (raw: unknown) => {
        clearWait();
        // plan/38: a new broker returns `address_assigned` (canonical key) +
        // `name_assigned` (clean leaf). Read both with cross-fallback so we
        // work against either a new broker OR a legacy one (only
        // `name_assigned`, where address == name).
        const ack = raw as {
          type?: string; name_assigned?: string; address_assigned?: string; generation?: string;
        };
        const name = typeof ack?.name_assigned === "string" ? ack.name_assigned : ack?.address_assigned;
        const address = typeof ack?.address_assigned === "string" ? ack.address_assigned : ack?.name_assigned;
        if (ack && ack.type === "register_ack" && typeof name === "string" && typeof address === "string") {
          staged.preAck = null;
          staged.onDeath = undefined;
          this.staged.delete(staged);
          if (this.leftFlag) {
            // Disposed mid-handshake: acknowledge-and-drop — never promote a
            // ghost connection after leave().
            try { sock.destroy(); } catch { /* already gone */ }
            resolve(name);
            return;
          }
          this.assignedName = name;
          this.assignedAddress = address;
          this.registeredGeneration = typeof ack.generation === "string" ? ack.generation : undefined;
          // Promote: the staged connection becomes THE connection; the old
          // one (if any) is destroyed — its close handler sees `this.conn`
          // already swapped and stays a no-op.
          const previous = this.conn;
          this.conn = staged;
          if (previous && previous !== staged) {
            try { previous.socket.destroy(); } catch { /* already gone */ }
          }
          this.consecutiveMisses = 0;
          resolve(name);
        } else {
          fail(reject, new Error(`expected register_ack, got: ${JSON.stringify(raw)}`));
        }
      };
      const req = JSON.stringify({
        type: "register",
        name: this.opts.name,
        // Only include cwd when set — keeps the wire identical to the legacy
        // payload for callers that don't supply it (broker treats absent cwd
        // as "no take-over", i.e. the old #N behavior).
        ...(this.opts.cwd !== undefined ? { cwd: this.opts.cwd } : {}),
      }) + "\n";
      try {
        sock.write(req);
      } catch (e) {
        fail(reject, e as Error);
      }
    });
  }

  private _onData(conn: ConnState, chunk: string): void {
    conn.buf += chunk;
    let nl: number;
    while ((nl = conn.buf.indexOf("\n")) >= 0) {
      const line = conn.buf.slice(0, nl);
      conn.buf = conn.buf.slice(nl + 1);
      if (!line) continue;
      this._handleLine(conn, line);
    }
  }

  private _handleLine(conn: ConnState, line: string): void {
    // Before register_ack: parse loosely as an ack control message.
    if (conn.preAck) {
      try {
        const parsed = JSON.parse(line) as unknown;
        conn.preAck(parsed);
      } catch {
        // Garbage during register window — ignore.
      }
      return;
    }

    // Regular envelope.
    let env: Envelope;
    try {
      env = parse(line);
    } catch (e) {
      if (e instanceof EnvelopeError) return;
      throw e;
    }

    // Intercept broker ACKs first. Body shape `{type:"ack", status, target}`
    // from broker correlates by `re` against pending `sendWithAck` ids. Even
    // when no `sendWithAck` is waiting (e.g. message was sent via plain
    // `send()` or legacy `request()`), the ACK envelope must be swallowed
    // here — otherwise it would match `request()`'s pending map by `re` and
    // resolve the request with the ACK body instead of the peer's real reply.
    //
    // Plan/25 Wave D: cross-PC ACKs arrive with prefixed sender
    // (`<pcLabel>:broker`) since broker_remote rewrites `from` to include
    // the source PC label. Accept both forms here so cross-PC senders
    // resolve their `sendWithAck` Promise instead of timing out.
    if (env.re && (env.from === "broker" || env.from.endsWith(":broker"))) {
      const ackBody = env.body as { type?: string; status?: string; target?: string } | null;
      if (ackBody && ackBody.type === "ack" && typeof ackBody.status === "string") {
        const slot = this.ackPending.get(env.re);
        if (slot) {
          clearTimeout(slot.timer);
          this.ackPending.delete(env.re);
          const status = ackBody.status as AckBody["status"];
          slot.resolve({ status, id: env.re, target: ackBody.target });
        }
        // Design v2 (G2 fast-path): an unknown_peer NACK means "not routed
        // by this broker at this instant" — probe the rendezvous right away
        // (coalesced) so a split heals at send speed instead of watcher speed.
        if (ackBody.status === "unknown_peer") this._maybeProbeAfterNack();
        return;
      }
    }

    // Correlate replies for `request()`.
    if (env.re) {
      const slot = this.pending.get(env.re);
      if (slot) {
        clearTimeout(slot.timer);
        this.pending.delete(env.re);
        slot.resolve(env);
        return;
      }
    }

    // Otherwise dispatch to subscribers.
    for (const h of this.handlers) {
      try { h(env); } catch { /* handler errors don't break peer */ }
    }
  }

  private async _writeEnvelope(env: Envelope): Promise<void> {
    if (!this.conn || this.conn.socket.destroyed) {
      throw new Error("session peer not connected");
    }
    this.conn.socket.write(serialize(env));
  }

  private _onConnClose(closed: ConnState): void {
    if (this.leftFlag) return;  // intentional leave
    // Only the CURRENT connection dying is a real failover. A close from a
    // connection we've already replaced (rename, re-resolve promote, or a
    // prior reconnect) must NOT trigger another rejoin — the promote step
    // destroyed it deliberately and its events are fenced here.
    if (this.conn !== closed) return;
    // Attempt to re-elect once. New leader will bind sockPath; we either
    // become leader ourselves or rejoin as follower.
    void delay(FAILOVER_RETRY_MS).then(() => {
      if (this.leftFlag || this.conn !== closed) return;
      this._scheduleResolve("conn-closed");
    });
  }

  private async _teardownConn(): Promise<void> {
    // Destroy in-flight register candidates FIRST — a late ACK must never
    // promote a connection the peer has already abandoned.
    for (const candidate of this.staged) {
      try { candidate.socket.destroy(); } catch { /* already gone */ }
    }
    this.staged.clear();
    if (this.conn) {
      try { this.conn.socket.destroy(); } catch { /* ignored */ }
      this.conn = null;
    }
    if (this.broker) {
      try { await this.broker.close(); } catch { /* ignored */ }
      this.broker = null;
    }
    for (const slot of this.pending.values()) {
      clearTimeout(slot.timer);
      slot.reject(new Error("peer leaving"));
    }
    this.pending.clear();
    for (const slot of this.ackPending.values()) {
      clearTimeout(slot.timer);
      slot.resolve({ status: "timeout", id: "" });
    }
    this.ackPending.clear();
  }

  // ── divergence watcher (design v2 G2/R3) ─────────────────────────────────

  private _startWatcher(): void {
    if (this.leftFlag || this.opts.generationProbeMs === 0) return;
    this._armWatcher(Math.random() * (this.opts.generationProbeMs ?? DEFAULT_GENERATION_PROBE_MS));
  }

  private _stopWatcher(): void {
    if (this.watcherTimer !== null) {
      clearTimeout(this.watcherTimer);
      this.watcherTimer = null;
    }
  }

  private _armWatcher(delayMs: number): void {
    this._stopWatcher();
    this.watcherTimer = setTimeout(() => {
      this.watcherTimer = null;
      void this._watchTick();
    }, delayMs);
    this.watcherTimer.unref?.();
  }

  private async _watchTick(): Promise<void> {
    if (this.leftFlag) return;
    const interval = this.opts.generationProbeMs ?? DEFAULT_GENERATION_PROBE_MS;
    try {
      const probe = await this._probeGeneration();
      if (this.leftFlag) return;
      switch (probe) {
        case "match":
        case "legacy":
          this.consecutiveMisses = 0;
          break;
        case "mismatch":
          this.consecutiveMisses = 0;
          this._scheduleResolve("generation-mismatch");
          break;
        case "miss":
        case "error":
          this.consecutiveMisses++;
          if (this.consecutiveMisses >= GENERATION_MISS_THRESHOLD) {
            this.consecutiveMisses = 0;
            this._scheduleResolve("rendezvous-miss");
          }
          break;
      }
    } catch {
      /* probe trouble alone never mutates state */
    }
    if (!this.leftFlag) this._armWatcher(interval * (0.9 + Math.random() * 0.2));
  }

  /** Outcome of one rendezvous generation probe. `error` (whole-probe
   *  budget exhausted) is uncertainty for counting purposes, never a
   *  mismatch. Protected so tests can subclass and inject deterministic
   *  probe outcomes. */
  protected _probeGeneration(): Promise<"match" | "mismatch" | "legacy" | "miss" | "error"> {
    return new Promise((resolve) => {
      let settled = false;
      let buf = "";
      const settle = (val: "match" | "mismatch" | "legacy" | "miss" | "error") => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        try { sock.destroy(); } catch { /* ignored */ }
        resolve(val);
      };
      const sock = createConnection({ path: this.opts.sockPath });
      const timer = setTimeout(() => settle("error"), GENERATION_PROBE_BUDGET_MS);
      sock.setEncoding("utf8");
      sock.once("connect", () => {
        try {
          sock.write(JSON.stringify({ type: "list_peers" }) + "\n");
        } catch {
          settle("error");
        }
      });
      sock.once("error", () => settle("miss"));
      sock.on("data", (chunk: string) => {
        buf += chunk;
        const nl = buf.indexOf("\n");
        if (nl < 0) return;
        const line = buf.slice(0, nl);
        try {
          const env = parse(line) as Envelope & {
            body?: { type?: string; generation?: string } | null;
          };
          const body = env.body;
          if (body && body.type === "list_peers_reply") {
            const gen = body.generation;
            if (typeof gen !== "string") settle("legacy");
            else if (gen === this.registeredGeneration) settle("match");
            else settle("mismatch");
          } else {
            settle("error");
          }
        } catch {
          settle("error");
        }
      });
    });
  }

  /** Coalesced immediate probe after an unknown_peer NACK: at most one per
   *  NACK_PROBE_MIN_INTERVAL_MS; skips when a watcher probe or resolve is
   *  already in flight (the single-flight chain covers the resolve side). */
  private _maybeProbeAfterNack(): void {
    const now = Date.now();
    if (now - this.lastNackProbeAt < NACK_PROBE_MIN_INTERVAL_MS) return;
    this.lastNackProbeAt = now;
    void this._probeGeneration().then((probe) => {
      if (probe === "mismatch") this._scheduleResolve("nack-mismatch");
    });
  }
}
