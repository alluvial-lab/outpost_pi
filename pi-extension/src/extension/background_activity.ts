import type { EventBus } from "@earendil-works/pi-coding-agent";

/** Describe the number of background subagents currently tracked by the extension. */
export interface BackgroundActivitySnapshot {
  readonly activeCount: number;
}

type BackgroundPayload = { id?: unknown };

const CREATED_EVENT = "subagents:created";
const TERMINAL_EVENTS = [
  "subagents:completed",
  "subagents:failed",
  "subagents:resumed",
] as const;

function backgroundId(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) return null;
  const id = (payload as BackgroundPayload).id;
  return typeof id === "string" ? id : null;
}

/** Tracks live background subagents through the shared Pi event bus. */
export class BackgroundActivityTracker {
  private readonly activeIds = new Set<string>();
  private readonly subscribedBuses = new WeakSet<object>();
  private readonly emissionBuses: EventBus[] = [];
  private disposed = false;

  constructor(private readonly onChange: (snapshot: BackgroundActivitySnapshot) => void) {}

  /**
   * Subscribe once per event-bus identity so repeated composition is harmless.
   * Also RE-EMITS the transition on the bus as `outpost-pi:background`
   * `{active: boolean}` — content-free, transition-gated — so sibling
   * extensions (e.g. herdr-agent-state) can hold activity state while
   * background work runs. Without this, fleet tooling that SIGTERMs
   * "idle" pis kills in-process background work (2026-09-07 incident:
   * wrap-agents.sh vs a pi waiting on subagent execution).
   */
  subscribe(bus: EventBus): void {
    if (this.disposed) return;
    const identity = bus as object;
    if (this.subscribedBuses.has(identity)) return;
    this.subscribedBuses.add(identity);
    this.emissionBuses.push(bus);
    // Pi 0.84 tracks `pi.events.on` subscriptions and removes them when the
    // owning runtime is invalidated; retaining manual closures would outlive
    // the session-scoped listener contract.

    bus.on(CREATED_EVENT, (payload) => {
      this.add(backgroundId(payload));
    });
    const onTerminal = (payload: unknown): void => {
      this.remove(backgroundId(payload));
    };
    for (const event of TERMINAL_EVENTS) bus.on(event, onTerminal);
  }

  /** Clear session-scoped activity and publish the idle edge when necessary. */
  clearForSessionBoundary(): void {
    if (this.disposed || this.activeIds.size === 0) return;
    this.activeIds.clear();
    this.emitChange();
  }

  get activeCount(): number {
    return this.activeIds.size;
  }

  /** Stop processing lifecycle events and release all tracked activity. */
  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    if (this.activeIds.size === 0) return;
    this.activeIds.clear();
    this.emitChange();
  }

  private add(id: string | null): void {
    if (this.disposed || id === null || this.activeIds.has(id)) return;
    const wasEmpty = this.activeIds.size === 0;
    this.activeIds.add(id);
    if (wasEmpty) this.emitChange();
  }

  private remove(id: string | null): void {
    if (this.disposed || id === null || !this.activeIds.delete(id)) return;
    if (this.activeIds.size === 0) this.emitChange();
  }

  private emitChange(): void {
    this.onChange({ activeCount: this.activeIds.size });
    // Re-broadcast on every subscribed bus (transition edges only) so sibling
    // extensions can hold activity state during background work. Emission list
    // is a parallel identity-deduped array — the WeakSet guard stays for
    // subscribe idempotence, but WeakSets are not iterable.
    for (const bus of this.emissionBuses) {
      try {
        bus.emit("outpost-pi:background", { active: this.activeIds.size > 0 });
      } catch {
        // A stale runtime-scoped bus must never break transition handling.
      }
    }
  }
}
