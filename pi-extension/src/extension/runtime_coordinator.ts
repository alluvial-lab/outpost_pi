import type { EventBus, ExtensionAPI } from "@earendil-works/pi-coding-agent";

const COORDINATOR_VERSION = 1 as const;
const COORDINATOR_SYMBOL = Symbol.for("remote-pi.runtime-coordinator.v1");
const COORDINATOR_MARKER = Symbol.for("remote-pi.runtime-coordinator.schema");
const LEASE_BRAND: unique symbol = Symbol("remote-pi.factory-lease");

export type SessionLifecycleReason = "startup" | "reload" | "new" | "resume" | "fork" | "quit";

export interface FactoryLease {
  readonly [LEASE_BRAND]: true;
}

type LeaseDisposition = "candidate" | "satellite" | "owner";
type CoordinatorState =
  | { kind: "UNOWNED" }
  | { kind: "CANDIDATE"; candidate: FactoryLease }
  | { kind: "ACTIVE"; owner: FactoryLease; sessionId: string; api: ExtensionAPI }
  | { kind: "REPLACING"; previousOwner: FactoryLease; reason: Exclude<SessionLifecycleReason, "startup" | "quit">; candidate?: FactoryLease }
  | { kind: "DISPOSED" };

type Activation =
  | { status: "activated" }
  | { status: "duplicate" }
  | { status: "denied"; reason: "child" | "satellite" | "disposed" };

/**
 * Process-scoped authority for Remote Pi's phone-facing SDK binding.
 *
 * Extension factories are also invoked for in-process child AgentSessions. A
 * factory therefore receives only an opaque lease; it gains authority over
 * process-global ingress/resources if its session_start is accepted. All
 * destructive lifecycle operations validate that exact lease.
 */
export class RemotePiRuntimeCoordinator {
  readonly schemaVersion = COORDINATOR_VERSION;
  readonly [COORDINATOR_MARKER] = COORDINATOR_VERSION;
  private state: CoordinatorState = { kind: "UNOWNED" };
  private readonly leases = new Map<FactoryLease, LeaseDisposition>();
  private readonly childSessionIds = new Set<string>();
  private readonly subscribedBuses = new WeakSet<object>();

  acquireFactory(): FactoryLease {
    const lease = Object.freeze({ [LEASE_BRAND]: true }) as FactoryLease;
    if (this.state.kind === "UNOWNED") {
      this.state = { kind: "CANDIDATE", candidate: lease };
      this.leases.set(lease, "candidate");
    } else if (this.state.kind === "REPLACING" && !this.state.candidate) {
      this.state = { ...this.state, candidate: lease };
      this.leases.set(lease, "candidate");
    } else {
      this.leases.set(lease, "satellite");
    }
    return lease;
  }

  observeChildLifecycle(bus: EventBus): void {
    const identity = bus as object;
    if (this.subscribedBuses.has(identity)) return;
    this.subscribedBuses.add(identity);
    bus.on("subagents:child:session-created", (payload) => {
      const sessionId = childSessionId(payload);
      if (sessionId) this.childSessionIds.add(sessionId);
    });
    bus.on("subagents:child:disposed", (payload) => {
      const sessionId = childSessionId(payload);
      if (sessionId) this.childSessionIds.delete(sessionId);
    });
  }

  activate(
    lease: FactoryLease,
    sessionId: string,
    api: ExtensionAPI,
  ): Activation {
    const disposition = this.leases.get(lease);
    if (this.state.kind === "DISPOSED") return { status: "denied", reason: "disposed" };
    if (this.state.kind === "ACTIVE" && this.state.owner === lease
        && this.state.sessionId === sessionId) {
      return { status: "duplicate" };
    }

    if (this.childSessionIds.has(sessionId)) {
      this.rejectCandidate(lease);
      return { status: "denied", reason: "child" };
    }
    if (this.state.kind === "ACTIVE" && this.state.owner === lease) {
      // A same-factory replacement is safe only for the current owner. Modern
      // Pi creates a fresh factory, but this preserves compatibility with SDKs
      // that re-fire session_start on an existing runtime.
      this.state = { kind: "ACTIVE", owner: lease, sessionId, api };
      return { status: "activated" };
    }
    if (disposition !== "candidate") return { status: "denied", reason: "satellite" };
    if (this.state.kind === "CANDIDATE" && this.state.candidate !== lease) {
      return { status: "denied", reason: "satellite" };
    }
    if (this.state.kind === "REPLACING" && this.state.candidate !== lease) {
      return { status: "denied", reason: "satellite" };
    }

    this.leases.set(lease, "owner");
    this.state = { kind: "ACTIVE", owner: lease, sessionId, api };
    return { status: "activated" };
  }

  beginShutdown(lease: FactoryLease, reason: SessionLifecycleReason): boolean {
    if (this.state.kind !== "ACTIVE" || this.state.owner !== lease) return false;
    if (reason === "quit" || reason === "startup") {
      this.state = { kind: "DISPOSED" };
    } else {
      this.state = { kind: "REPLACING", previousOwner: lease, reason };
    }
    return true;
  }

  isOwner(lease: FactoryLease): boolean {
    return this.state.kind === "ACTIVE" && this.state.owner === lease;
  }

  /** True while a replacement is in progress (successor expected to re-arm). */
  isReplacing(): boolean {
    return this.state.kind === "REPLACING";
  }

  /** Read-only diagnostics used by lifecycle integration tests. */
  snapshot(): Readonly<{ kind: CoordinatorState["kind"]; sessionId?: string; childCount: number }> {
    return {
      kind: this.state.kind,
      ...(this.state.kind === "ACTIVE" ? { sessionId: this.state.sessionId } : {}),
      childCount: this.childSessionIds.size,
    };
  }

  private rejectCandidate(lease: FactoryLease): void {
    if (this.state.kind === "ACTIVE" && this.state.owner === lease) return;
    this.leases.set(lease, "satellite");
    if (this.state.kind === "CANDIDATE" && this.state.candidate === lease) {
      this.state = { kind: "UNOWNED" };
    } else if (this.state.kind === "REPLACING" && this.state.candidate === lease) {
      const { candidate: _candidate, ...replacement } = this.state;
      this.state = replacement;
    }
  }
}

function childSessionId(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const sessionId = (payload as { sessionId?: unknown }).sessionId;
  return typeof sessionId === "string" && sessionId.length > 0 ? sessionId : null;
}

function isCoordinator(value: unknown): value is RemotePiRuntimeCoordinator {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<RemotePiRuntimeCoordinator> & { [COORDINATOR_MARKER]?: unknown };
  return candidate[COORDINATOR_MARKER] === COORDINATOR_VERSION
    && candidate.schemaVersion === COORDINATOR_VERSION
    && typeof candidate.acquireFactory === "function"
    && typeof candidate.activate === "function"
    && typeof candidate.beginShutdown === "function"
    && typeof candidate.isReplacing === "function";
}

export function getRemotePiRuntimeCoordinator(): RemotePiRuntimeCoordinator {
  const globals = globalThis as typeof globalThis & { [COORDINATOR_SYMBOL]?: unknown };
  const existing = globals[COORDINATOR_SYMBOL];
  if (existing !== undefined) {
    if (!isCoordinator(existing)) {
      throw new Error("remote-pi runtime coordinator global has an incompatible schema");
    }
    return existing;
  }
  const coordinator = new RemotePiRuntimeCoordinator();
  globals[COORDINATOR_SYMBOL] = coordinator;
  return coordinator;
}

/** Reset process-global ownership between isolated extension-factory tests. */
export function resetRemotePiRuntimeCoordinatorForTest(): void {
  const globals = globalThis as typeof globalThis & { [COORDINATOR_SYMBOL]?: unknown };
  delete globals[COORDINATOR_SYMBOL];
}
