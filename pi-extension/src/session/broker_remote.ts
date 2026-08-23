import type { Broker, RemoteInjectStatus, RemoteRouter, PeerInfo } from "./broker.js";
import { type Envelope, envelope, uuidv7 } from "./envelope.js";
import type { PiForwardClient } from "../transport/pi_forward_client.js";
import type {
  RelayControlFrameRoomAnnounced,
  RelayControlFrameRoomEnded,
  RelayControlFrameRooms,
} from "../protocol/generated/protocol.generated.js";

/**
 * Plan/25 Wave B/C — cross-PC broker.
 *
 * Maintains a cache of `<pc_label> → { peers, pc_pubkey, ts }` populated
 * by `peers_update` envelopes pushed from sibling Pis and refreshed lazily
 * via `peers_request` on cache miss.
 *
 * Owns two halves of the protocol:
 *
 *  - **Outbound** (`tryRouteOutbound`): broker hands off envelopes with a
 *    known `<pc>:` prefix. We rewrite `env.from` with our own pc_label,
 *    pack onto the relay via `pi_forward_client.sendEnvelopeToPi`.
 *
 *  - **Inbound** (`handleIncoming`): `pi_forward_client` emits envelopes
 *    received from a verified `from_pc`. We:
 *      1. Anti-spoof the `envelope.from` prefix against the sibling cache
 *         keyed by `from_pc` (defends against a Pi lying about its own
 *         `pc_label`).
 *      2. Intercept control envelopes (`peers_update`, `peers_request`,
 *         `transport_error`) before any local UDS delivery.
 *      3. Strip the `<pc>:` prefix from `env.to` and call
 *         `broker.injectFromRemote`. Build a one-way ACK envelope back via
 *         the relay so the cross-PC sender's `sendWithAck` resolves.
 *
 * plan/34: cross-PC injection always delivers when the local peer exists
 * (no busy-drop); `broker_remote` just forwards the broker's `received |
 * denied` status in the ACK it sends back.
 *
 * Siblings (`Map<pc_label, pc_pubkey>`) are seeded externally by the
 * extension at bootstrap (typically from `mesh_versions` of every paired
 * Owner). Membership is the only thing we trust to ground anti-spoof —
 * the cache of peers is just for routing UX.
 */

const CACHE_TTL_MS = 5 * 60_000;
const PEERS_REQUEST_TIMEOUT_MS = 2_000;
/** Periodic re-announce interval. Must stay comfortably under `CACHE_TTL_MS`
 *  so that a single dropped push (laptop sleep, NAT rebind, WS reconnect race)
 *  still gets a follow-up before the sibling's cache of us — and our cache of
 *  them — expires and silently empties `list_peers`. At 2 min vs a 5 min TTL,
 *  one miss is harmless (next push lands at 4 min < 5 min). Without this, a
 *  STABLE sibling set never re-pushes (`setSiblings` only pings NEW siblings),
 *  so the roster silently drains overnight even though phone routing — a
 *  separate, TTL-less live-WS path on the relay — stays healthy. */
const REANNOUNCE_INTERVAL_MS = 2 * 60_000;
const BROKER_NAME = "broker";

/** A sibling peer as carried on the wire in `peers_update.peers_detailed`:
 *  the sibling's LOCAL `(cwd, name, address)` — no `pc`/prefix (the receiver
 *  fills `pc` from the verified sibling label). */
export interface WirePeerInfo {
  cwd: string;
  name: string;
  address: string;
}

/**
 * Caches one sibling's most recently announced local roster.
 *
 * The timestamp drives TTL expiry, while the verified public key binds the
 * cached label to mesh membership before cross-PC addresses are projected.
 */
export interface RemotePeerEntry {
  /** The sibling's local peers (unprefixed `(cwd, name, address)`). */
  infos: WirePeerInfo[];
  pcPubkey: string;
  ts: number;
}

interface SiblingInfo {
  pcLabel: string;
  pcPubkey: string;
}

/**
 * Wires a broker to the relay-backed cross-PC routing adapter.
 *
 * The caller supplies verified local identity and sibling membership. The
 * adapter subscribes to `pi` immediately and retains an optional re-announce
 * timer until {@link BrokerRemote.detach} releases both resources.
 */
export interface BrokerRemoteOptions {
  broker: Broker;
  pi: PiForwardClient;
  selfPcLabel: string;
  selfPcPubkey: string;
  /** Initial sibling Pis of the same Owner. May be extended later. */
  siblings?: SiblingInfo[];
  /** TTL override (testing). */
  cacheTtlMs?: number;
  /** Re-announce interval override (testing). `0`/negative disables the timer. */
  reannounceIntervalMs?: number;
  /** Logger (defaults to console.error). */
  log?: (msg: string) => void;
}

interface PeersUpdateBody {
  type: "peers_update";
  /** Addresses — always sent for backward compatibility with Phase-1-only siblings. */
  peers: string[];
  /** Structured roster (Plan/38 Phase 2). Optional: a Phase-1-only sibling omits
   *  it, and the receiver synthesizes `{cwd:"", name:addr, address:addr}` from
   *  `peers`. A new sibling sends both. */
  peers_detailed?: WirePeerInfo[];
}

interface PeersRequestBody {
  type: "peers_request";
}

interface AckBody {
  type: "ack";
  status: RemoteInjectStatus;
  target: string;
}

/** Promise + resolver for pending `peers_request` cache fills. */
interface PendingFill {
  resolve: () => void;
  timer: ReturnType<typeof setTimeout>;
}

/**
 * Route broker envelopes across verified sibling Pis and maintain their rosters.
 *
 * Construction subscribes to relay envelopes, registers this instance as the
 * broker's remote router, warms sibling caches, and may start a re-announce
 * timer. Call {@link detach} exactly once at the owning mesh-node teardown to
 * unregister the listener, stop the timer, and restore the broker boundary.
 */
export class BrokerRemote implements RemoteRouter {
  private readonly broker: Broker;
  private readonly pi: PiForwardClient;
  private readonly selfPcLabel: string;
  private readonly selfPcPubkey: string;
  private readonly cacheTtlMs: number;
  private readonly reannounceIntervalMs: number;
  private readonly log: (msg: string) => void;

  /** Siblings: pc_label → pc_pubkey. Authoritative for anti-spoof. */
  private readonly siblingByLabel = new Map<string, string>();
  /** Reverse index built from siblings: pc_pubkey → pc_label. */
  private readonly siblingByPubkey = new Map<string, string>();

  /** Cache of peers per remote pc_label. */
  private readonly remotePeers = new Map<string, RemotePeerEntry>();
  /** Relay-authoritative live room IDs per sibling pubkey, ordered oldest-first. */
  private readonly siblingRooms = new Map<string, Set<string>>();
  /** Start timestamps used to keep `siblingRooms` deterministic across snapshots/pushes. */
  private readonly siblingRoomStartedAt = new Map<string, Map<string, number>>();
  /** Room subscriptions and one-shot snapshots installed on this relay connection. */
  private readonly subscribedRooms = new Set<string>();
  private readonly pendingRoomChecks = new Set<string>();
  /** In-flight `peers_request` calls, keyed by pc_label. */
  private readonly pendingFills = new Map<string, Set<PendingFill>>();

  private readonly onIncoming: (env: Envelope, fromPc: string, toRoom: string) => void;
  private readonly onRooms: (frame: RelayControlFrameRooms) => void;
  private readonly onRoomAnnounced: (frame: RelayControlFrameRoomAnnounced) => void;
  private readonly onRoomEnded: (frame: RelayControlFrameRoomEnded) => void;
  private reannounceTimer: ReturnType<typeof setInterval> | null = null;
  private detached = false;

  constructor(opts: BrokerRemoteOptions) {
    this.broker = opts.broker;
    this.pi = opts.pi;
    this.selfPcLabel = opts.selfPcLabel;
    this.selfPcPubkey = opts.selfPcPubkey;
    this.cacheTtlMs = opts.cacheTtlMs ?? CACHE_TTL_MS;
    this.reannounceIntervalMs = opts.reannounceIntervalMs ?? REANNOUNCE_INTERVAL_MS;
    this.log = opts.log ?? ((msg) => console.error(msg));

    for (const s of opts.siblings ?? []) this._addSibling(s);

    this.onIncoming = (env, fromPc, toRoom) => this.handleIncoming(env, fromPc, toRoom);
    this.onRooms = (frame) => this._handleRooms(frame);
    this.onRoomAnnounced = (frame) => this._handleRoomAnnounced(frame);
    this.onRoomEnded = (frame) => this._handleRoomEnded(frame);
    this.pi.on("envelope", this.onIncoming);
    this.pi.on("rooms", this.onRooms);
    this.pi.on("room_announced", this.onRoomAnnounced);
    this.pi.on("room_ended", this.onRoomEnded);

    this.broker.setRemoteRouter(this);

    // Discover each sibling's relay-authoritative live rooms before any
    // room-targeted envelope is sent. The first `rooms` snapshot fans a
    // `peers_request` to every room; only the sibling leader handles it.
    // Best-effort: offline siblings are learned later through the installed
    // room subscription.
    this._bootstrapWithSiblings();

    // Periodic re-announce: the bootstrap pair (request + push) only fires
    // again for siblings NEWLY added via `setSiblings`. With a stable mesh,
    // nothing re-pushes — so once a `peers_update` is missed, both sides' caches
    // age past `CACHE_TTL_MS` and the peer silently drops from `list_peers`
    // until a process restart. Re-running the bootstrap on a timer (well under
    // the TTL) keeps every sibling's roster warm. `unref` so this never holds
    // the process open on its own.
    if (this.reannounceIntervalMs > 0) {
      this.reannounceTimer = setInterval(() => {
        if (this.detached || this.siblingByLabel.size === 0) return;
        this._bootstrapWithSiblings();
      }, this.reannounceIntervalMs);
      this.reannounceTimer.unref?.();
    }
  }

  /** Subscribe to relay-authoritative room changes, then announce/request over a live room when known. */
  private _bootstrapWithSiblings(): void {
    const body = this._localPeersBody();
    for (const [, pcPubkey] of this.siblingByLabel) {
      this._subscribeToRooms(pcPubkey);
      const room = this._pickRoom(pcPubkey);
      if (!room) continue;
      this._sendControlEnvelopeToRoom(pcPubkey, room, { type: "peers_request" });
      this._sendControlEnvelopeToRoom(pcPubkey, room, body);
    }
  }

  /** Fresh local inventory for a `peers_update` push, read straight from the
   *  broker (authoritative + sync — no stale cache, drive-letter-safe: the
   *  broker knows its real local peers, no `:`-heuristic). Always carries BOTH
   *  `peers` (addresses, backward compatible with Phase-1-only siblings) and
   *  the structured `peers_detailed` (Plan/38 Phase 2). */
  private _localPeersBody(): PeersUpdateBody {
    const detailed = this.broker.localPeerInfos();
    return {
      type: "peers_update",
      peers: detailed.map((p) => p.address),
      peers_detailed: detailed.map((p) => ({ cwd: p.cwd, name: p.name, address: p.address })),
    };
  }

  detach(): void {
    if (this.detached) return;
    this.detached = true;
    if (this.reannounceTimer) {
      clearInterval(this.reannounceTimer);
      this.reannounceTimer = null;
    }
    this.pi.off("envelope", this.onIncoming);
    this.pi.off("rooms", this.onRooms);
    this.pi.off("room_announced", this.onRoomAnnounced);
    this.pi.off("room_ended", this.onRoomEnded);
    this.broker.setRemoteRouter(null);
  }

  // ── Sibling management ────────────────────────────────────────────────────

  /** Replace the sibling set and restart its roster bootstrap.
   *  Removes missing siblings, subscribes newly added ones, and re-announces
   *  across known rooms so a publication repairs an earlier dropped exchange. */
  setSiblings(next: SiblingInfo[]): void {
    if (this.detached) return;
    const prevPubkeys = new Set(this.siblingByPubkey.keys());
    this.siblingByLabel.clear();
    this.siblingByPubkey.clear();
    for (const s of next) this._addSibling(s);
    // Drop cache and relay-discovery state for siblings that disappeared.
    for (const label of [...this.remotePeers.keys()]) {
      if (!this.siblingByLabel.has(label)) this.remotePeers.delete(label);
    }
    for (const pubkey of prevPubkeys) {
      if (this.siblingByPubkey.has(pubkey)) continue;
      this.siblingRooms.delete(pubkey);
      this.siblingRoomStartedAt.delete(pubkey);
      this.subscribedRooms.delete(pubkey);
      this.pendingRoomChecks.delete(pubkey);
    }
    // Membership publication is also a convergence trigger. The bridge may
    // have discovered this same sibling before its remote side was ready, so
    // limiting bootstrap to newly-added pubkeys can preserve two empty rosters
    // until the periodic reannounce. Known rooms get an immediate request +
    // update; unknown rooms receive the normal subscribe + snapshot request.
    this._bootstrapWithSiblings();
  }

  private _addSibling(s: SiblingInfo): void {
    if (!s.pcLabel || !s.pcPubkey) return;
    if (s.pcLabel === this.selfPcLabel) return;  // never list self as sibling
    if (s.pcPubkey === this.selfPcPubkey) return;
    this.siblingByLabel.set(s.pcLabel, s.pcPubkey);
    this.siblingByPubkey.set(s.pcPubkey, s.pcLabel);
  }

  // ── Public cache API ──────────────────────────────────────────────────────

  /** Structured cached peers for a remote pc_label (the sibling's local
   *  `(cwd,name,address)`), or [] when unknown / expired. */
  private _remoteInfos(pcLabel: string): WirePeerInfo[] {
    const entry = this.remotePeers.get(pcLabel);
    if (!entry) return [];
    if (Date.now() - entry.ts > this.cacheTtlMs) return [];
    return entry.infos;
  }

  /** Returns the cached peer ADDRESSES for a remote pc_label (the sibling's
   *  local, unprefixed addresses), or [] when unknown / expired. */
  getRemotePeers(pcLabel: string): string[] {
    return this._remoteInfos(pcLabel).map((i) => i.address);
  }

  /** Returns the full cross-PC inventory: pc_label → addresses (TTL-respected). */
  getAllRemote(): Record<string, string[]> {
    const out: Record<string, string[]> = {};
    for (const [label] of this.remotePeers) {
      const peers = this.getRemotePeers(label);
      if (peers.length > 0) out[label] = peers;
    }
    return out;
  }

  /** Aggregated remote peer addresses (`<pc>:<cwd>@<name>`) for the broker's
   *  `list_peers` `peers` field. Skips siblings with no cache entry. */
  listRemotePeers(): string[] {
    const out: string[] = [];
    for (const [label] of this.remotePeers) {
      for (const info of this._remoteInfos(label)) {
        out.push(`${label}:${info.address}`);
      }
    }
    return out;
  }

  /** Structured remote roster (Plan/38 Phase 2): one `PeerInfo` per cross-PC
   *  peer with `pc` = sibling label, `cwd`/`name` from the sibling's inventory,
   *  and `address` prefixed `<pc>:<cwd>@<name>`. Powers `peers_detailed`. */
  listRemotePeerInfos(): PeerInfo[] {
    const out: PeerInfo[] = [];
    for (const [label] of this.remotePeers) {
      for (const info of this._remoteInfos(label)) {
        out.push({ pc: label, cwd: info.cwd, name: info.name, address: `${label}:${info.address}` });
      }
    }
    return out;
  }

  // ── Proactive push ─────────────────────────────────────────────────────────

  /**
   * Called whenever the local UDS broker's peer set changes
   * (peer_joined/peer_left). We push a `peers_update` envelope to every
   * sibling so their caches stay fresh without polling.
   */
  onLocalPeersChanged(_peers: string[]): void {
    if (this.detached) return;
    // The arg is just a change TRIGGER — we push the broker's authoritative
    // inventory (`_localPeersBody`), not the caller's list, so a caller that
    // miscomputed "local" (e.g. a naive `:`-split on Windows) can't poison what
    // siblings see.
    if (this.siblingByLabel.size === 0) return;
    const body = this._localPeersBody();
    for (const [, pcPubkey] of this.siblingByLabel) {
      this._sendControlEnvelope(pcPubkey, body);
    }
  }

  // ── RemoteRouter ──────────────────────────────────────────────────────────

  /**
   * Broker hook (plan/25 Wave C). Inspect `env.to` for a `<pc>:` prefix:
   *
   *   - no prefix or prefix == selfPcLabel → return false (broker delivers
   *     locally; if same-self prefix is present we DON'T strip it here —
   *     the local resolver will treat it as a literal name, which works
   *     because local names don't carry colons in practice)
   *   - prefix === known sibling label → rewrite `env.from`, pack onto the
   *     relay, return true. A cold room cache starts `rooms_check` and leaves
   *     the existing ACK timeout to report this attempt; the resulting room
   *     snapshot warms subsequent sends and fans out the roster request.
   *   - prefix is not a known sibling label → return false (backward-compat
   *     for hypothetical local names containing `:`)
   */
  tryRouteOutbound(env: Envelope): boolean {
    if (this.detached) return false;
    if (typeof env.to !== "string") return false;
    const parsed = parseAddress(env.to);
    if (!parsed) return false;
    const { pcLabel } = parsed;
    if (pcLabel === this.selfPcLabel) return false;  // same-PC: local handles
    const siblingPk = this.siblingByLabel.get(pcLabel);
    if (!siblingPk) return false;  // unknown prefix → fall through

    // We have a destination PC. Rewrite `from` with our own pc_label.
    const rewritten: Envelope = {
      ...env,
      from: `${this.selfPcLabel}:${env.from}`,
    };

    // Optimistic send once the relay has supplied a live destination room.
    // On a cold cache `_pickRoom` starts `rooms_check`; returning true keeps
    // the broker's existing ACK-timeout contract while the discovery snapshot
    // warms the next attempt instead of sending to a fabricated room.
    const room = this._pickRoom(siblingPk);
    if (room) this.pi.sendEnvelopeToPi(siblingPk, room, rewritten);
    if (this.remotePeers.get(pcLabel) === undefined) {
      this._sendControlEnvelope(siblingPk, { type: "peers_request" } satisfies PeersRequestBody);
      void this._awaitPeersFill(pcLabel, PEERS_REQUEST_TIMEOUT_MS);
    }
    return true;
  }

  // ── Inbound ───────────────────────────────────────────────────────────────

  /**
   * Entry point for envelopes the relay forwards to us. Receives the
   * envelope verbatim, verified `from_pc` (Pi-pubkey of the sender), and
   * relay-validated inbound `to_room`, which is threaded onto the ACK.
   */
  handleIncoming(env: Envelope, fromPc: string, toRoom: string): void {
    if (this.detached) return;
    // ── transport_error from relay ─────────────────────────────────────────
    // The relay synthesises these with `from_pc = "_relay"` and
    // `envelope.from = "_relay"`. Inject locally as a system envelope
    // addressed to the original sender (env.to is the original sender's
    // prefixed address; strip the prefix and deliver via UDS).
    if (fromPc === "_relay") {
      this._propagateTransportError(env);
      return;
    }

    // ── anti-spoof ─────────────────────────────────────────────────────────
    const claimedLabel = this.siblingByPubkey.get(fromPc);
    if (!claimedLabel) {
      this.log(
        `[broker_remote] drop: from_pc ${fromPc.slice(0, 12)}… not in sibling cache`,
      );
      return;
    }
    if (typeof env.from === "string") {
      const fromPrefix = env.from.split(":", 1)[0];
      if (fromPrefix !== claimedLabel) {
        this.log(
          `[broker_remote] drop: envelope.from "${env.from}" prefix ` +
          `mismatches sibling label "${claimedLabel}"`,
        );
        return;
      }
    }

    const body = env.body as { type?: unknown } | null;
    const bodyType = body && typeof body === "object" ? body.type : undefined;

    // ── control: peers_update ──────────────────────────────────────────────
    if (bodyType === "peers_update") {
      this._setRemoteCache(claimedLabel, fromPc, _parsePeersUpdate(body as PeersUpdateBody));
      return;
    }

    // ── control: peers_request ─────────────────────────────────────────────
    if (bodyType === "peers_request") {
      // Always query the broker directly for the current peer list. We
      // can't rely on `lastLocalPeers` because that cache is fed by the
      // `peer_joined`/`peer_left` broadcast in `session/broker.ts` — and the broker
      // never delivers a `peer_joined` to the peer that just joined (see
      // `_broadcastSystem(..., excludeName=assigned)`). In a single-peer
      // mesh, no event ever fires → `lastLocalPeers` stays `[]` →
      // siblings see us as "no peers" → cache populates empty → cross-PC
      // `list_peers` misses us. Querying broker.peerNames() resolves
      // sync (Map keys), so this is essentially free.
      this._sendControlEnvelope(fromPc, this._localPeersBody());
      return;
    }

    // ── control: ack ───────────────────────────────────────────────────────
    // ACK envelopes from a remote wrapper are addressed to our local
    // sender. Strip prefix from `to` and inject so the sender's
    // `sendWithAck` pending resolves. (No special-casing needed — generic
    // injection below covers them; plan/34 made injection always-deliver.)

    // ── regular envelope: strip `to` prefix and inject ─────────────────────
    if (typeof env.to !== "string") {
      this.log("[broker_remote] drop: cross-PC envelope must be unicast string");
      return;
    }
    const toParsed = parseAddress(env.to);
    let injectedEnv = env;
    if (toParsed && toParsed.pcLabel === this.selfPcLabel) {
      injectedEnv = { ...env, to: toParsed.peerName };
    } else if (toParsed) {
      // `to` carries a third-party prefix — not for us. Drop.
      this.log(
        `[broker_remote] drop: envelope.to "${env.to}" not addressed to ` +
        `selfPcLabel "${this.selfPcLabel}"`,
      );
      return;
    }

    const status = this.broker.injectFromRemote(injectedEnv);
    // Only generate an ACK for non-ACK envelopes — otherwise we'd loop
    // ACKing the ACK. Detect by body shape.
    if (bodyType === "ack") return;

    // Forward an ACK envelope back to fromPc. The cross-PC sender's
    // `sendWithAck` correlates by `re = env.id`.
    const ackBody: AckBody = { type: "ack", status, target: injectedEnv.to as string };
    const ackEnv: Envelope = {
      from: `${this.selfPcLabel}:${BROKER_NAME}`,
      to: env.from,
      id: uuidv7(),
      re: env.id,
      body: ackBody,
    };
    this.pi.sendEnvelopeToPi(fromPc, toRoom, ackEnv);
  }

  /**
   * Send one test-support envelope through the authenticated Pi forwarder.
   *
   * This bypasses only the known-open remote-roster/room-cache lookup. The
   * relay authorization, destination anti-spoof check, local broker injection,
   * and extension mesh-ingress path remain production code.
   */
  sendEnvelopeForTest(input: {
    toPc: string;
    toRoom: string;
    toAddress: string;
    fromAddress: string;
    body: unknown;
  }): boolean {
    if (this.detached) return false;
    const canonicalToPc = Buffer.from(input.toPc, "base64").toString("base64");
    const destinationLabel = this.siblingByPubkey.get(canonicalToPc);
    if (!destinationLabel) return false;
    const outgoing = envelope(
      `${this.selfPcLabel}:${input.fromAddress}`,
      `${destinationLabel}:${input.toAddress}`,
      input.body,
      null,
    );
    this.pi.sendEnvelopeToPi(canonicalToPc, input.toRoom, outgoing);
    return true;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  private _subscribeToRooms(pcPubkey: string): void {
    if (this.detached || this.subscribedRooms.has(pcPubkey)) return;
    this.subscribedRooms.add(pcPubkey);
    this.pi.sendRoomControl({ type: "subscribe_rooms", peers: [pcPubkey] });
  }

  private _requestRooms(pcPubkey: string): void {
    if (this.detached || this.pendingRoomChecks.has(pcPubkey)) return;
    this.pendingRoomChecks.add(pcPubkey);
    this.pi.sendRoomControl({ type: "rooms_check", peers: [pcPubkey] });
  }

  private _pickRoom(pcPubkey: string): string | undefined {
    const room = this.siblingRooms.get(pcPubkey)?.values().next().value;
    if (room) return room;
    this._subscribeToRooms(pcPubkey);
    this._requestRooms(pcPubkey);
    return undefined;
  }

  private _handleRooms(frame: RelayControlFrameRooms): void {
    if (this.detached || !this.siblingByPubkey.has(frame.peer)) return;
    this.pendingRoomChecks.delete(frame.peer);
    const startedAt = new Map(frame.rooms.map((room) => [room.room_id, room.started_at]));
    this.siblingRoomStartedAt.set(frame.peer, startedAt);
    this._replaceOrderedRooms(frame.peer);

    // A snapshot is the only safe cold-cache bootstrap: fan the control
    // request to every live room because only the sibling leader listens for
    // Pi envelopes. Data sends remain single-room after this cache is warm.
    for (const roomId of this.siblingRooms.get(frame.peer) ?? []) {
      this._sendControlEnvelopeToRoom(frame.peer, roomId, { type: "peers_request" });
    }
  }

  private _handleRoomAnnounced(frame: RelayControlFrameRoomAnnounced): void {
    if (this.detached || !this.siblingByPubkey.has(frame.peer)) return;
    this.pendingRoomChecks.delete(frame.peer);
    const startedAt = this.siblingRoomStartedAt.get(frame.peer) ?? new Map<string, number>();
    startedAt.set(frame.room_id, frame.started_at);
    this.siblingRoomStartedAt.set(frame.peer, startedAt);
    this._replaceOrderedRooms(frame.peer);
  }

  private _handleRoomEnded(frame: RelayControlFrameRoomEnded): void {
    if (this.detached || !this.siblingByPubkey.has(frame.peer)) return;
    this.siblingRoomStartedAt.get(frame.peer)?.delete(frame.room_id);
    this._replaceOrderedRooms(frame.peer);
  }

  private _replaceOrderedRooms(pcPubkey: string): void {
    const startedAt = this.siblingRoomStartedAt.get(pcPubkey) ?? new Map<string, number>();
    // The UDS leader is the first Pi process to register; prefer the oldest
    // live relay room while retaining deterministic room-id tie breaking.
    const ordered = [...startedAt.entries()]
      .sort(([roomA, startedA], [roomB, startedB]) => startedA - startedB || roomA.localeCompare(roomB))
      .map(([roomId]) => roomId);
    this.siblingRooms.set(pcPubkey, new Set(ordered));
  }

  private _setRemoteCache(
    pcLabel: string,
    pcPubkey: string,
    infos: WirePeerInfo[],
  ): void {
    this.remotePeers.set(pcLabel, { infos, pcPubkey, ts: Date.now() });
    // Resolve any pending `peers_request` waiters for this label.
    const pending = this.pendingFills.get(pcLabel);
    if (pending) {
      for (const slot of pending) {
        clearTimeout(slot.timer);
        slot.resolve();
      }
      this.pendingFills.delete(pcLabel);
    }
  }

  private _awaitPeersFill(pcLabel: string, timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve) => {
      const slot: PendingFill = {
        resolve,
        timer: setTimeout(() => {
          const set = this.pendingFills.get(pcLabel);
          set?.delete(slot);
          resolve();
        }, timeoutMs),
      };
      const set = this.pendingFills.get(pcLabel) ?? new Set<PendingFill>();
      set.add(slot);
      this.pendingFills.set(pcLabel, set);
    });
  }

  private _propagateTransportError(env: Envelope): void {
    // Strip prefix from to (if any) and deliver to the local sender by
    // injecting the envelope into the broker. Per plan/25 spec the
    // wrapper's `sendWithAck` will see this as a body with
    // `type:"transport_error"` correlated by `re`. The ackPending matcher
    // only resolves for body.type === "ack", so transport_error envelopes
    // fall through to handlers — which is what we want (sender's pending
    // map times out, then handler dispatches inbox notification).
    if (typeof env.to !== "string") return;
    const parsed = parseAddress(env.to);
    const injected: Envelope = parsed && parsed.pcLabel === this.selfPcLabel
      ? { ...env, to: parsed.peerName }
      : env;
    this.broker.injectFromRemote(injected);
  }

  private _sendControlEnvelope(
    toPc: string,
    body: PeersUpdateBody | PeersRequestBody,
  ): void {
    const room = this._pickRoom(toPc);
    if (!room) return;
    this._sendControlEnvelopeToRoom(toPc, room, body);
  }

  private _sendControlEnvelopeToRoom(
    toPc: string,
    toRoom: string,
    body: PeersUpdateBody | PeersRequestBody,
  ): void {
    if (this.detached) return;
    const env: Envelope = envelope(
      `${this.selfPcLabel}:_broker_remote`,
      `${this._labelForPubkey(toPc) ?? "?"}:_broker_remote`,
      body,
      null,
    );
    this.pi.sendEnvelopeToPi(toPc, toRoom, env);
  }

  private _labelForPubkey(pcPubkey: string): string | undefined {
    return this.siblingByPubkey.get(pcPubkey);
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Parse a `<pc>:<peer>` address. Returns null when the input doesn't
 * carry a `:`. Note: callers are responsible for deciding whether the
 * parsed `pcLabel` is meaningful (i.e., matches selfPcLabel or a known
 * sibling); a non-null return here does NOT imply the address is remote.
 * The broker's prefix routing uses this — local names containing literal
 * `:` continue working as long as no sibling carries the same prefix.
 */
export function parseAddress(
  to: string,
): { pcLabel: string; peerName: string } | null {
  const idx = to.indexOf(":");
  if (idx <= 0 || idx === to.length - 1) return null;
  return { pcLabel: to.slice(0, idx), peerName: to.slice(idx + 1) };
}

/**
 * Parse an inbound `peers_update` body into structured `WirePeerInfo[]`
 * (Plan/38 Phase 2), tolerant of two sender generations:
 *
 *   - **Phase 2 sibling** sends `peers_detailed` → use it (validating each entry
 *     has string `cwd`/`name`/`address`).
 *   - **Phase 1-only sibling** sends only `peers: string[]` (addresses) → each
 *     becomes `{cwd:"", name:addr, address:addr}` so the mesh stays mixed-safe.
 *
 * Untrusted input: every field is shape-checked; malformed entries are dropped.
 */
function _parsePeersUpdate(body: PeersUpdateBody): WirePeerInfo[] {
  const detailed = body.peers_detailed;
  if (Array.isArray(detailed)) {
    return detailed.filter(
      (e): e is WirePeerInfo =>
        !!e && typeof e === "object" &&
        typeof (e as WirePeerInfo).cwd === "string" &&
        typeof (e as WirePeerInfo).name === "string" &&
        typeof (e as WirePeerInfo).address === "string",
    );
  }
  const peers = Array.isArray(body.peers) ? body.peers : [];
  return peers
    .filter((p): p is string => typeof p === "string")
    .map((address) => ({ cwd: "", name: address, address }));
}
