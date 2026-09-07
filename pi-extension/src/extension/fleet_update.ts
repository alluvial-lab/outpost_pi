import { randomUUID } from "node:crypto";
import type { ServerMessage } from "../protocol/types.js";

/** Mesh message kind coordinating one fleet arm-restart across local siblings. */
export const FLEET_ARM_RESTART_KIND = "outpost-pi.arm-restart";

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

/** A fleet arm-restart request as it travels the local agent mesh. */
export type FleetArmRestartRequest = {
  readonly kind: typeof FLEET_ARM_RESTART_KIND;
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
  return record["kind"] === FLEET_ARM_RESTART_KIND &&
    typeof record["update_id"] === "string" && record["update_id"].length > 0;
}

/** Build the mesh body broadcast to each local sibling for one update run. */
export function fleetArmRestartRequest(updateId: string): FleetArmRestartRequest {
  return { kind: FLEET_ARM_RESTART_KIND, update_id: updateId };
}

/**
 * Filter a broker `list_peers` reply body down to local-only peer addresses.
 *
 * v1 fleet scope is this VM only: cross-PC siblings (whose roster entries
 * carry a `pc` label, and whose fallback addresses contain a `<pc>:` prefix)
 * are excluded. Returns `null` when the reply carries neither a
 * `peers_detailed` nor a legacy `peers` array, so callers can distinguish
 * "no roster answer" from "zero local peers".
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
    // Legacy broker fallback: no structured roster, so fall back to the
    // address-shape heuristic (Windows drive-letter addresses excluded in
    // practice because the structured roster is preferred whenever present).
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
  /** Write this process's nonce-bound armed file; return false when it could not be written. */
  readonly arm: () => boolean;
}

/**
 * Build the sibling-side arm handler used by the local mesh adapter.
 *
 * The handler never signals a process. It only validates the lifecycle/toggle
 * gates and writes the existing nonce-bound hot-reload request through `arm`.
 * The settle hook owns the eventual restart, so an active turn reports
 * `deferred` after the arm file is staged.
 */
export function createFleetArmRestartHandler(
  options: FleetArmRestartHandlerOptions,
): () => FleetArmRestartAck {
  return () => {
    if (options.isDisposed()) return { state: "declined", reason: "disposed" };
    if (!options.hotReloadEnabled()) {
      return { state: "declined", reason: "hot-reload disabled" };
    }
    if (!options.arm()) return { state: "declined", reason: "arm failed" };
    return options.hasActiveWork()
      ? { state: "deferred", reason: "turn active" }
      : { state: "armed" };
  };
}

type FleetUpdateResult = { readonly ok: boolean; readonly outputTail: string };

/** Injected operations that let the coordinator remain unit-testable. */
export interface FleetUpdateCoordinatorOptions {
  readonly emitStatus: (event: FleetUpdateStatusEvent) => void;
  readonly runUpdate: () => Promise<FleetUpdateResult>;
  /** Arm this process last, after the status event reaches the owner. */
  readonly armSelf: () => void;
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
 * Drive one fleet update run: update, arm local siblings, publish the arming
 * table, then arm this coordinator last. Only one run may own the process.
 *
 * The `arming` event is always emitted before `armSelf` — this process's own
 * restart interrupts the extension, so it cannot report after arming itself.
 */
export class FleetUpdateCoordinator {
  private inFlight = false;

  constructor(private readonly options: FleetUpdateCoordinatorOptions) {}

  /**
   * Start one run, or publish `already_running` when another owns the process.
   *
   * @param updateId - wire correlation id; defaults to a fresh UUID.
   */
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
      // This event must be visible before this process arms itself: its own
      // restart interrupts the current extension and cannot report afterward.
      this.options.emitStatus({
        type: "fleet_update_status",
        update_id: updateId,
        phase: "arming",
        peers,
      });
      this.options.armSelf();
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
      // No roster answer: report an empty table rather than blocking the run.
      return [];
    }

    const uniquePeers = [...new Set(peers)].filter((peer) => peer.length > 0);
    const timeoutMs = positiveTimeout(this.options.ackTimeoutMs, DEFAULT_ACK_TIMEOUT_MS);
    const body = fleetArmRestartRequest(updateId);
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
