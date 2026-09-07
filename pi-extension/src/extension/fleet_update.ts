/** Fleet update coordinator and local mesh arm protocol. */
import { randomUUID } from "node:crypto";
import type { ServerMessage } from "../protocol/types.js";

/** Legacy one-phase mesh kind. New coordinators use the phase-specific kinds. */
export const FLEET_ARM_RESTART_KIND = "outpost-pi.arm-restart";
/** Readiness request; a sibling must not arm in response to this message. */
export const FLEET_ARM_RESTART_PREPARE_KIND = "outpost-pi.arm-restart.prepare";
/** Commit request sent only after the coordinator has published `arming`. */
export const FLEET_ARM_RESTART_COMMIT_KIND = "outpost-pi.arm-restart.commit";

/** Acknowledgement state returned by a sibling when it receives an arm request. */
export type FleetPeerAckState = "armed" | "deferred" | "declined" | "no-ack";

/** The per-peer result included in the coordinator's arming status event. */
export type FleetPeerAck = {
  readonly peer: string;
  readonly state: FleetPeerAckState;
  readonly reason?: string;
};

/** The status event emitted while one fleet update run progresses. */
export type FleetUpdateStatusEvent = Extract<ServerMessage, { type: "fleet_update_status" }>;

/** The response produced by a local sibling arm handler. */
export type FleetArmRestartAck = {
  readonly state: Exclude<FleetPeerAckState, "no-ack">;
  readonly reason?: string;
};

/** Phase carried by extension-internal fleet mesh bodies. */
export type FleetArmRestartPhase = "legacy" | "prepare" | "commit";

/** A fleet arm-restart request as it travels the local agent mesh. */
export type FleetArmRestartRequest = {
  readonly kind:
    | typeof FLEET_ARM_RESTART_KIND
    | typeof FLEET_ARM_RESTART_PREPARE_KIND
    | typeof FLEET_ARM_RESTART_COMMIT_KIND;
  readonly update_id: string;
};

/** Default subprocess deadline for `pi update` before the run reports failure. */
export const DEFAULT_FLEET_UPDATE_TIMEOUT_MS = 10 * 60_000;

const DEFAULT_ACK_TIMEOUT_MS = 5_000;
const MAX_OUTPUT_TAIL_LENGTH = 4_000;

/** Narrow one inbound mesh body to a fleet arm-restart request. */
export function isFleetArmRestartRequest(value: unknown): value is FleetArmRestartRequest {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  const kind = record["kind"];
  return (kind === FLEET_ARM_RESTART_KIND ||
    kind === FLEET_ARM_RESTART_PREPARE_KIND ||
    kind === FLEET_ARM_RESTART_COMMIT_KIND) &&
    typeof record["update_id"] === "string" &&
    record["update_id"].length > 0;
}

/** Return the phase represented by a validated fleet arm body. */
export function fleetArmRestartPhase(body: FleetArmRestartRequest): FleetArmRestartPhase {
  if (body.kind === FLEET_ARM_RESTART_PREPARE_KIND) return "prepare";
  if (body.kind === FLEET_ARM_RESTART_COMMIT_KIND) return "commit";
  return "legacy";
}

/** Build the legacy one-phase body for compatibility with old callers/tests. */
export function fleetArmRestartRequest(updateId: string): FleetArmRestartRequest {
  return { kind: FLEET_ARM_RESTART_KIND, update_id: updateId };
}

/** Build the readiness body that must not stage an armed file. */
export function fleetArmRestartPrepareRequest(updateId: string): FleetArmRestartRequest {
  return { kind: FLEET_ARM_RESTART_PREPARE_KIND, update_id: updateId };
}

/** Build the commit body that stages the sibling's own armed file. */
export function fleetArmRestartCommitRequest(updateId: string): FleetArmRestartRequest {
  return { kind: FLEET_ARM_RESTART_COMMIT_KIND, update_id: updateId };
}

/**
 * Filter a broker `list_peers` reply body down to local-only peer addresses.
 *
 * v1 fleet scope is this VM only: cross-PC siblings (whose roster entries
 * carry a `pc` label, and whose fallback addresses contain a `<pc>:` prefix)
 * are excluded. Returns `null` when the reply carries neither a
 * `peers_detailed` nor a legacy `peers` array.
 */
export function localPeerAddresses(body: unknown): string[] | null {
  if (!body || typeof body !== "object") return null;
  const record = body as Record<string, unknown>;
  const detailed = record["peers_detailed"];
  if (Array.isArray(detailed)) {
    return detailed
      .filter((entry): entry is Record<string, unknown> =>
        !!entry && typeof entry === "object" && !entry["pc"])
      .map((entry) => entry["address"])
      .filter((address): address is string => typeof address === "string" && address.length > 0);
  }
  const peers = record["peers"];
  if (Array.isArray(peers)) {
    // Legacy broker fallback. New brokers always provide peers_detailed, which
    // keeps Windows local paths containing ':' distinguishable from remotes.
    return peers.filter((peer): peer is string =>
      typeof peer === "string" && peer.length > 0 && !peer.includes(":"));
  }
  return null;
}

/** Dependencies for the safety-gated sibling arm handler. */
export interface FleetArmRestartHandlerOptions {
  readonly isDisposed: () => boolean;
  readonly hotReloadEnabled: () => boolean;
  readonly hasActiveWork: () => boolean;
  /** Claim an update id exactly once and durably, returning false for replay. */
  readonly consumeUpdate?: (updateId: string) => boolean;
  /** Write this process's nonce-bound armed file; return false when it could not be written. */
  readonly arm: (updateId: string) => boolean;
}

/**
 * Build the sibling-side phase-aware arm handler used by the local mesh
 * adapter. Prepare only reports readiness. Commit validates and consumes the
 * update id, then writes this process's nonce-bound armed file; the settle hook
 * owns the eventual restart.
 */
export function createFleetArmRestartHandler(
  options: FleetArmRestartHandlerOptions,
): (updateId: string, phase?: FleetArmRestartPhase) => FleetArmRestartAck {
  return (updateId, phase: FleetArmRestartPhase = "commit") => {
    if (phase === "legacy") {
      return { state: "declined", reason: "unsupported fleet arm phase" };
    }
    if (options.isDisposed()) return { state: "declined", reason: "disposed" };
    if (!options.hotReloadEnabled()) {
      return { state: "declined", reason: "hot-reload disabled" };
    }

    if (phase === "prepare") {
      return options.hasActiveWork()
        ? { state: "deferred", reason: "turn active" }
        : { state: "armed" };
    }

    if (options.consumeUpdate && !options.consumeUpdate(updateId)) {
      return { state: "declined", reason: "update already consumed" };
    }
    if (!options.arm(updateId)) return { state: "declined", reason: "arm failed" };
    return options.hasActiveWork()
      ? { state: "deferred", reason: "turn active" }
      : { state: "armed" };
  };
}

type FleetUpdateResult = { readonly ok: boolean; readonly outputTail: string };

/** Result of the coordinator's own arm attempt. */
export type FleetSelfArmResult = { readonly ok: boolean; readonly reason?: string };

/** Injected operations that let the coordinator remain unit-testable. */
export interface FleetUpdateCoordinatorOptions {
  readonly emitStatus: (event: FleetUpdateStatusEvent) => void;
  readonly runUpdate: () => Promise<FleetUpdateResult>;
  /** Arm this process last, after all commitment messages and status delivery. */
  readonly armSelf: (updateId: string) => FleetSelfArmResult | void;
  /** Return local sibling addresses; async discovery is supported for live meshes. */
  readonly localPeers: () => string[] | Promise<string[]>;
  /** Send a mesh request and return its body-level acknowledgement, if any. */
  readonly meshRequest: (
    peer: string,
    body: unknown,
    timeoutMs: number,
  ) => Promise<{ readonly ack?: unknown } | null>;
  readonly updateTimeoutMs?: number;
  readonly ackTimeoutMs?: number;
}

/**
 * Drive one fleet update run: update, collect sibling readiness, publish the
 * arming table, commit sibling arms, then arm this coordinator last. Only one
 * run may own the process.
 */
export class FleetUpdateCoordinator {
  private inFlight = false;

  constructor(private readonly options: FleetUpdateCoordinatorOptions) {}

  /** Start one run, or publish `already_running` when another owns the process. */
  async handleRequest(updateId: string = randomUUID()): Promise<void> {
    if (this.inFlight) {
      this.options.emitStatus({
        type: "fleet_update_status",
        update_id: updateId,
        phase: "already_running",
        detail: "another fleet update is already running",
      });
      return;
    }

    this.inFlight = true;
    try {
      this.options.emitStatus({
        type: "fleet_update_status",
        update_id: updateId,
        phase: "updating",
      });

      const update = await this.runUpdateWithTimeout();
      if (!update.ok) {
        this.options.emitStatus({
          type: "fleet_update_status",
          update_id: updateId,
          phase: "update_failed",
          detail: outputTail(update.outputTail),
        });
        return;
      }

      const peers = await this.collectPeerAcks(updateId);
      // The report is the commit barrier: no sibling arm or coordinator arm
      // may occur before this event is handed to the owner channel.
      this.options.emitStatus({
        type: "fleet_update_status",
        update_id: updateId,
        phase: "arming",
        peers,
      });
      await this.commitPeerArms(updateId, peers);

      const selfArm = this.options.armSelf(updateId);
      if (selfArm && !selfArm.ok) {
        this.options.emitStatus({
          type: "fleet_update_status",
          update_id: updateId,
          phase: "update_failed",
          detail: `fleet restart not armed: ${selfArm.reason ?? "unknown reason"}`,
        });
      }
    } finally {
      this.inFlight = false;
    }
  }

  /** Expose ownership state to tests without exposing mutable internals. */
  inFlightForTest(): boolean {
    return this.inFlight;
  }

  private async runUpdateWithTimeout(): Promise<FleetUpdateResult> {
    const timeoutMs = positiveTimeout(this.options.updateTimeoutMs, DEFAULT_FLEET_UPDATE_TIMEOUT_MS);
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        this.options.runUpdate(),
        new Promise<FleetUpdateResult>((resolve) => {
          timer = setTimeout(() => resolve({ ok: false, outputTail: "pi update timed out" }), timeoutMs);
        }),
      ]);
    } catch (error) {
      return { ok: false, outputTail: error instanceof Error ? error.message : String(error) };
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  }

  private async collectPeerAcks(updateId: string): Promise<FleetPeerAck[]> {
    let peers: string[];
    try {
      peers = await this.options.localPeers();
    } catch {
      return [];
    }

    const uniquePeers = [...new Set(peers)].filter((peer) => peer.length > 0);
    const timeoutMs = positiveTimeout(this.options.ackTimeoutMs, DEFAULT_ACK_TIMEOUT_MS);
    const body = fleetArmRestartPrepareRequest(updateId);
    return Promise.all(uniquePeers.map(async (peer): Promise<FleetPeerAck> => {
      try {
        const response = await this.options.meshRequest(peer, body, timeoutMs);
        const ack = parseFleetArmAck(response?.ack);
        return ack
          ? { peer, state: ack.state, ...(ack.reason ? { reason: ack.reason } : {}) }
          : { peer, state: "no-ack", reason: "timeout" };
      } catch (error) {
        return {
          peer,
          state: "no-ack",
          reason: error instanceof Error ? error.message : "timeout",
        };
      }
    }));
  }

  private async commitPeerArms(updateId: string, peers: FleetPeerAck[]): Promise<void> {
    const commitPeers = peers
      .filter((peer) => peer.state === "armed" || peer.state === "deferred")
      .map((peer) => peer.peer);
    if (commitPeers.length === 0) return;
    const timeoutMs = positiveTimeout(this.options.ackTimeoutMs, DEFAULT_ACK_TIMEOUT_MS);
    const body = fleetArmRestartCommitRequest(updateId);
    await Promise.all(commitPeers.map(async (peer) => {
      try {
        // The status table is the readiness report. Commit acknowledgements
        // are deliberately not re-emitted as a new wire phase.
        await this.options.meshRequest(peer, body, timeoutMs);
      } catch {
        // The coordinator still arms itself; a missing commit ack is already
        // represented by the readiness table and cannot be repaired here.
      }
    }));
  }
}

function positiveTimeout(value: number | undefined, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : fallback;
}

function outputTail(value: string): string {
  const text = typeof value === "string" ? value : String(value);
  return text.length > MAX_OUTPUT_TAIL_LENGTH ? text.slice(-MAX_OUTPUT_TAIL_LENGTH) : text;
}

function parseFleetArmAck(value: unknown): FleetArmRestartAck | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  const state = record["state"];
  if (state !== "armed" && state !== "deferred" && state !== "declined") return null;
  const reason = record["reason"];
  return {
    state,
    ...(typeof reason === "string" && reason.length > 0 ? { reason } : {}),
  };
}
