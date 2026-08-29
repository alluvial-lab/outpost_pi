/** Name the process-level reason that fences new owner prompt delivery. */
export type OwnerDeliveryFenceReason = "hot_reload" | "fresh_session";

/** Report whether a managed fresh-session transition could own and finish shutdown. */
export type FreshSessionShutdownResult =
  | { status: "unavailable" }
  | { status: "already_quiescing" }
  | { status: "stale_runtime" }
  | { status: "exiting"; drain: "complete" | "deadline_exceeded" };

/** Supply the request-local effects that must precede runtime teardown. */
export interface FreshSessionShutdownRequest {
  /** Stage the managed-process ACK/reset tail before its runtime is disposed. */
  stageAcknowledgementAndReset?(): void;
  shutdownRuntime(reason: "new"): Promise<boolean>;
}

/** Configure whether a bare process may use the managed teardown sequence. */
export interface FreshSessionShutdownOptions {
  /** Permit the same fenced teardown for a bare process without a supervisor. */
  allowUnmanaged?: boolean;
}

export interface FreshSessionShutdownDependencies {
  isRestartManaged(): boolean;
  drainAcceptedDeliveries(): Promise<void>;
  terminate(exitCode: number): void;
  shutdownDeadlineMs: number;
  exitCode: number;
}

const DEADLINE = Symbol("fresh-session-shutdown-deadline");

/** Coordinate one process-owned fresh-session drain behind a synchronous ingress fence. */
export class FreshSessionShutdownCoordinator {
  private fence: OwnerDeliveryFenceReason | null = null;
  private transitionActive = false;

  constructor(private readonly deps: FreshSessionShutdownDependencies) {}

  /** Return the current process-level owner-delivery fence, if any. */
  get fenceReason(): OwnerDeliveryFenceReason | null {
    return this.fence;
  }

  /** Install the hot-reload fence synchronously when no other shutdown owns ingress. */
  beginHotReloadFence(): boolean {
    if (this.fence !== null) return false;
    this.fence = "hot_reload";
    return true;
  }

  /**
   * Fence ingress, drain admitted prompts, stage the reset tail, and terminate.
   *
   * The fence changes before the first await. Deadline exhaustion deliberately
   * leaves the underlying cleanup running until process termination wins.
   */
  request(
    input: FreshSessionShutdownRequest,
    options: FreshSessionShutdownOptions = {},
  ): Promise<FreshSessionShutdownResult> {
    if (!this.deps.isRestartManaged() && !options.allowUnmanaged) {
      return Promise.resolve({ status: "unavailable" });
    }
    if (this.fence !== null || this.transitionActive) {
      return Promise.resolve({ status: "already_quiescing" });
    }

    this.fence = "fresh_session";
    this.transitionActive = true;
    const transition = this.run(input);
    return transition.finally(() => {
      this.transitionActive = false;
    });
  }

  /** Clear a completed fence in isolated tests or a same-process test successor. */
  resetForTest(): void {
    if (this.transitionActive) return;
    this.fence = null;
  }

  private async run(
    input: FreshSessionShutdownRequest,
  ): Promise<FreshSessionShutdownResult> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let deadlineExceeded = false;
    const work = this.perform(input, () => deadlineExceeded);
    const deadline = new Promise<typeof DEADLINE>((resolve) => {
      timer = setTimeout(() => resolve(DEADLINE), this.deps.shutdownDeadlineMs);
    });
    const outcome = await Promise.race([work, deadline]);
    if (timer !== undefined) clearTimeout(timer);

    if (outcome === DEADLINE) {
      deadlineExceeded = true;
      // Start normal adapter cleanup even when an admitted SDK call or relay
      // close stalls. Runtime disposal claims ownership synchronously; the
      // process-manager exit remains the bounded liveness fallback.
      void input.shutdownRuntime("new").catch(() => undefined);
      void work.catch(() => undefined);
      this.deps.terminate(this.deps.exitCode);
      return { status: "exiting", drain: "deadline_exceeded" };
    }
    if (outcome === "stale_runtime") {
      this.fence = null;
      return { status: "stale_runtime" };
    }

    this.deps.terminate(this.deps.exitCode);
    return { status: "exiting", drain: "complete" };
  }

  private async perform(
    input: FreshSessionShutdownRequest,
    deadlineExceeded: () => boolean,
  ): Promise<"ready_to_exit" | "stale_runtime"> {
    try {
      await this.deps.drainAcceptedDeliveries();
    } catch {
      // The app outbox is authoritative when an admitted-delivery drain itself
      // fails. Continue normal lifecycle cleanup rather than stranding process.
    }

    if (deadlineExceeded()) return "ready_to_exit";

    try {
      input.stageAcknowledgementAndReset?.();
    } catch {
      // A lost final action ACK/reset frame is recovered through canonical room
      // rotation and the app outbox; teardown must still release resources.
    }

    try {
      return await input.shutdownRuntime("new")
        ? "ready_to_exit"
        : "stale_runtime";
    } catch {
      // Runtime ownership was claimed synchronously before adapter teardown.
      // Adapter failures do not bypass process-manager recovery.
      return "ready_to_exit";
    }
  }
}
