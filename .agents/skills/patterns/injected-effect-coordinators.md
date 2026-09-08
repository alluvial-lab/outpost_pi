# Injected Effect Coordinators

## Rationale

Long-lived extension operations that combine asynchronous work, lifecycle state, and external effects stay testable when the orchestration class receives those effects through one constructor options object. The coordinator owns sequencing, timeout, deduplication, and teardown invariants; the composition root supplies process, transport, filesystem, clock, and publication adapters. Tests can then exercise the real state machine without starting Pi, invoking a shell, or opening a relay.

This is a structural boundary pattern rather than a requirement to inject every helper: the class should own a cohesive operation whose effect ports make its ordering and failure behavior explicit.

## Examples

### Example 1: Session telemetry injects sampling and publication effects

**File**: `pi-extension/src/extension/session_telemetry.ts:47-65`

```ts
export class SessionTelemetryPublisher {
  constructor(private readonly opts: {
    publish: (patch: SessionTelemetryPatch) => void;
    usage: ContextUsageSource;
    cwd: CwdSource;
    runGitBranch: (cwd: string, timeoutMs: number) => Promise<string | null>;
    gitTimeoutMs?: number;
  }) {
    this.gitTimeoutMs = opts.gitTimeoutMs ?? 2_000;
  }
}
```

The sampler owns generation fencing and edge-triggered publication, while the SDK usage, cwd lookup, and git process are supplied by callers.

### Example 2: Fleet update coordinates injected update, mesh, and arm effects

**File**: `pi-extension/src/extension/fleet_update.ts:158-188`

```ts
export interface FleetUpdateCoordinatorOptions {
  readonly emitStatus: (event: FleetUpdateStatusEvent) => void;
  readonly runUpdate: () => Promise<FleetUpdateResult>;
  readonly armSelf: (updateId: string) => FleetSelfArmResult | void;
  readonly localPeers: () => string[] | Promise<string[]>;
  readonly meshRequest: (
    peer: string,
    body: unknown,
    timeoutMs: number,
  ) => Promise<{ readonly ack?: unknown } | null>;
  readonly updateTimeoutMs?: number;
  readonly ackTimeoutMs?: number;
}

export class FleetUpdateCoordinator {
  constructor(private readonly options: FleetUpdateCoordinatorOptions) {}
}
```

The coordinator owns the update/readiness/commit ordering and single-run fence without importing the process runner, mesh transport, or status channel.

### Example 3: Capture upload isolates bounded lifecycle effects

**File**: `pi-extension/src/actions/capture_upload_handler.ts:65-92`

```ts
export interface CaptureUploadHandlerOptions {
  cwd(): string;
  note(message: string): void;
  now?: () => number;
  staleAfterMs?: number;
}

export class CaptureUploadHandler {
  constructor(private readonly options: CaptureUploadHandlerOptions) {
    this.now = options.now ?? Date.now;
    this.staleAfterMs = options.staleAfterMs ?? DEFAULT_STALE_AFTER_MS;
    this.gcTimer = setInterval(() => this.gc(), ...);
  }
}
```

The upload handler owns retained bytes, stale-upload cleanup, and disposal; filesystem location, diagnostics, and time remain replaceable boundary effects.

## When to Use

- Use for a cohesive asynchronous operation that crosses process, transport, filesystem, clock, or publication boundaries.
- Put effect ports and bounded policy values in a typed options object, then keep ordering and lifecycle state inside the coordinator.
- Use the same seam in tests to provide deterministic fakes and explicit completion barriers.

## When NOT to Use

- Do not create an options object for a stateless one-line helper or a class with no meaningful lifecycle or effect boundary.
- Do not use this as a generic command-adapter rule; command parsing belongs to `command-surface-adapter-classes`.
- Do not hide domain policy in injected callbacks merely to avoid defining a clear owner.

## Common Violations

- Constructing subprocesses, sockets, timers, or SDK handles directly inside an orchestrator, making ordering and failure paths hard to test.
- Passing a broad service locator or `Record<string, unknown>` instead of narrow typed effect ports.
- Letting an injected callback mutate coordinator state behind its back, bypassing the coordinator's generation, timeout, or single-run fences.
- Forgetting to document which owner disposes resources created by an injected effect.

## Index entry

- **injected-effect-coordinators**: Keep asynchronous orchestration in lifecycle-owning classes with narrow constructor-injected effect ports.
