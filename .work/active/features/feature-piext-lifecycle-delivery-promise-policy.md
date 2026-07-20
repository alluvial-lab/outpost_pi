---
id: feature-piext-lifecycle-delivery-promise-policy
kind: feature
stage: done
tags: [pi-extension, refactor, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: extension-0.2.0
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-20
reviewed: "2026-07-18 (standard, gpt-5.6-sol fresh-context → ready, no findings)"
---

# Pi-extension: failure policy for lifecycle and delivery promises

## Brief

Four gate findings in `pi-extension/src/session/` describe the same defect:
async work tied to session lifecycle and message delivery is launched with bare
`void`, so a rejected promise becomes an unobserved failure — the extension
keeps running as if the work succeeded, which breaks turn-state convergence and
can strand an inbound phone message (the symptom class the
`epic-remote-session-resilience-refactor` targets). This feature defines the
intended failure policy — observe, propagate to an owned boundary, or
deliberately tolerate with a logged reason — for each site:

- `gate-refactor-lifecycle-control-frame-fire-and-forget` — control-frame dispatch drops async command failures
- `gate-refactor-lifecycle-queued-delivery-promise` — observe rejected queued-message delivery promises (absorbed `gate-refactor-lifecycle-queued-delivery-fire-and-forget`)
- `gate-refactor-lifecycle-session-start-fire-and-forget` — session-start auto-start future discarded without error handling

## Simplification opportunity

Close the unobserved-promise class on the extension side so the
session-stable-delivery guarantee (shipped v0.1.0) isn't undermined by a
silently-rejected delivery or auto-start. Preserve turn-state convergence on
every exit path.

## Source

Promoted from backlog by `scope` (2026-07-15) as a child of
`epic-remote-session-resilience-refactor` — extension session lifecycle is in
the epic's scope. 3 `gate-refactor-lifecycle-*` findings (the fourth was folded
into `gate-refactor-lifecycle-queued-delivery-promise` during the groom dup
pass) from the v0.6.0 release `gate-refactor` (lifecycle library).

## Refactor Overview

Refactor-design pass (2026-07-16). All 3 findings valid; every cited line has
moved (updated below). Key decision: preserve which errors reach callers —
make the implicit policy explicit + observable (operator-visible, payload-free
log) WITHOUT adding phone-visible errors, requeuing, rolling back turn state,
or propagating to Pi's extension-error channel. Do NOT introduce a generic
`observePromise` helper (differs per site); a domain-specific
`_startRootInBackground` helper is justified (same `_cmdRoot` policy
triplicated).

## Black-box boundary (behavior changes that must NOT be in this refactor)

- Applying `delivery_error`, rolling back turn state, restoring/requeueing the
  queued message after an unexpected queued-delivery rejection.
- Broadcasting a new `internal_error` to the phone for that rejection.
- Returning/awaiting `_cmdRoot` from `session_start` so Pi reports the rejection
  (the Pi runner awaits lifecycle-handler promises + reports via extension
  error channel — changing that is behavior-changing).
- Sending a new failure response/event to Cockpit, or allowing failed control
  input to continue to the LLM.

Those route through feature-design, not this refactor.

## Refactor Steps

### Step 1: Make queued-delivery rejection policy explicit
**Priority:** High | **Risk:** Medium | **Source Lens:** pattern drift / missing abstraction
**Files:** `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/session/sdk_session_projection.test.ts`, `pi-extension/src/index.ts`
**Story:** `gate-refactor-lifecycle-queued-delivery-promise`

**Current State:**
```ts
maybeDrainQueuedMessage(deliver: (msg) => void | Promise<void>): void {
  // ... clears queue, broadcasts state ...
  void deliver(this.currentSessionMessage({...}));
}
// production adapter:
function _maybeDrainQueuedMessage(): void {
  _sdkSessionProjection.maybeDrainQueuedMessage((queued) =>
    _deliverUserMessage(queued, null, "normal"));
}
```
Queued state clears before delivery; rejection unobserved. Immediate user delivery already attaches a rejection handler at `index.ts:2603-2606`; queued delivery at `sdk_session_projection.ts:776` does not.

**Target State:**
```ts
maybeDrainQueuedMessage(
  deliver: (msg) => void | Promise<void>,
  onRejected: (msg, error: unknown) => void,
): void {
  // ... clears queue, broadcasts state ...
  const message = this.currentSessionMessage({...});
  const delivery = deliver(message);
  if (isPromiseLike(delivery)) {
    void delivery.catch((error: unknown) => onRejected(message, error));
  }
}
// production adapter:
function _maybeDrainQueuedMessage(): void {
  _sdkSessionProjection.maybeDrainQueuedMessage(
    (queued) => _deliverUserMessage(queued, null, "normal"),
    (queued, error) => {
      console.error(`[outpost-pi] queued delivery id=${queued.id} rejected: ${String(error)}`);
    });
}
```

**Implementation Notes:**
- Invoke `deliver` synchronously before testing its result (preserves synchronous-throw behavior reaching the owning SDK event handler).
- Catch only asynchronous rejection; deliberately tolerate after an operator-visible, payload-free log. Do not rethrow.
- Do NOT call `_sendDeliveryError`, restore `queued_message_state`, requeue, or mutate turn state.
- Keep the callback policy explicit; no generic `observePromise` helper.

**Acceptance Criteria:**
- [ ] Projection test supplies `Promise.reject(error)` + verifies `onRejected` receives the queued message + same error.
- [ ] Queue still cleared once; projection idle after rejection observer runs.
- [ ] Synchronous throws still propagate synchronously.
- [ ] Existing successful drain coverage `extension.test.ts:1495-1545` green.
- [ ] No new `ServerMessage`, retry, or queue restoration on rejection.
- [ ] Typecheck, targeted tests, full tests, build pass.

**Rollback:** Revert the callback parameter + rejection attachment together.

### Step 2: Give `_cmdRoot` auto-start one explicit owner
**Priority:** High | **Risk:** Medium | **Source Lens:** code smell / missing abstraction
**Files:** `pi-extension/src/extension/ports.ts`, `pi-extension/src/extension/legacy_ports.ts`, `pi-extension/src/extension/composition_root.ts`, `pi-extension/src/extension/composition_root.test.ts`, `pi-extension/src/index.ts`
**Story:** `gate-refactor-lifecycle-session-start-fire-and-forget`

**Current State:**
```ts
export interface CommandSurfacePort {
  ensureStarted?(ctx: ExtensionContext): void | Promise<void>;  // permits promise, both sides discard
  // ...
}
// composition_root.ts: void ports.commands.ensureStarted?.(ctx);
// index.ts: ensureStarted: (ctx) => { if (!_disposed) return; _disposed = false; void _cmdRoot(ctx); }
```
Same bare `_cmdRoot` policy at 3 sites (`index.ts:1691` session-start, `:1794` daemon-start setTimeout, `:2661` session-replacement).

**Target State:**
```ts
export interface CommandSurfacePort {
  ensureStarted?(ctx: ExtensionContext): void;  // void-only; adapter owns async + rejection
  // ...
}
function _startRootInBackground(
  ctx: Pick<ExtensionContext, "ui" | "cwd">,
  origin: "session-start" | "daemon-start" | "session-replacement",
): void {
  void _cmdRoot(ctx).catch((error: unknown) => {
    console.error(`[outpost-pi] ${origin} auto-start failed: ${String(error)}`);
  });
}
// all 3 sites: _startRootInBackground(ctx, "<origin>")
```

**Implementation Notes:**
- Make `ensureStarted` a synchronous trigger contract; adapter owns async work + rejection policy.
- Use the domain-specific helper at all 3 background launch sites so it can't drift back to bare `void`.
- Log + consume rejection; do NOT return it to `session_start`.
- Preserve current `_disposed` checks + ordering.
- Do NOT make the `session_start` callback `async` (Pi would await + report failures via a new caller-visible channel).
- Add/update JSDoc on the port: implementations synchronously trigger startup + internally observe background failure.

**Acceptance Criteria:**
- [ ] `CommandSurfacePort.ensureStarted` + `LegacyCommandSurfaceDeps.ensureStarted` are `void`-only.
- [ ] `composition_root.ts` has no `void ports.commands.ensureStarted`.
- [ ] All 3 background `_cmdRoot` launches use `_startRootInBackground`; slash-command path at `index.ts:1780` remains awaited normally.
- [ ] Existing idempotence/disposed-epoch coverage `composition_root.test.ts:84-99` green.
- [ ] Assert registered `session_start` handler returns synchronously.
- [ ] No new Pi extension error event or protocol response.
- [ ] Typecheck, targeted tests, full tests, build pass.

**Rollback:** Revert the port-contract change + helper substitutions as one unit. No partial rollback of the 3 launch sites.

### Step 3: Observe transparent control-command rejection without changing dispatch
**Priority:** Medium | **Risk:** Low | **Source Lens:** pattern drift
**Files:** `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`
**Story:** `gate-refactor-lifecycle-control-frame-fire-and-forget`

**Current State:**
```ts
function _dispatchControlFrame(frame: ParsedControlFrame): void {
  void _handleControl(frame.command);
}
```
Input hook `index.ts:1317-1320` immediately returns `{ action: "handled" }`; `_handleControl` can await relay startup or rename work.

**Target State:**
```ts
function _dispatchControlFrame(frame: ParsedControlFrame): void {
  void _handleControl(frame.command).catch((error: unknown) => {
    console.error(`[outpost-pi] control command failed: ${String(error)}`);
  });
}
```

**Implementation Notes:**
- Keep `_dispatchControlFrame` synchronous; preserve immediate input swallowing.
- Do NOT include the full command in the log (rename commands may contain operator-provided names).
- Do NOT rethrow; do NOT return the promise from the input handler.
- Existing command-level handling remains authoritative for expected failures; this catch is only the final observer for unexpected rejection.
- Do NOT add a Cockpit reply/event.

**Acceptance Criteria:**
- [ ] Control path has no bare `void _handleControl(...)`.
- [ ] Existing tests `extension.test.ts:4592-4622` still prove immediate `{ action: "handled" }` + successful async dispatch.
- [ ] Focused rejection test (via existing mock seam) verifies one error log + no unhandled rejection; don't add a production export solely to test this one-line observer.
- [ ] Failed control work still cannot reach the LLM or transcript.
- [ ] No new Cockpit protocol event or caller-visible rejection.
- [ ] Typecheck, targeted tests, full tests, build pass.

**Rollback:** Revert the attached catch, leaving control parsing/dispatch untouched.

## Implementation Order

1. `gate-refactor-lifecycle-queued-delivery-promise` — establish + test the explicit queued-delivery rejection callback.
2. `gate-refactor-lifecycle-session-start-fire-and-forget` — narrow the port contract + centralize all `_cmdRoot` background launches.
3. `gate-refactor-lifecycle-control-frame-fire-and-forget` — attach the final control-path observer.
4. Verify from `pi-extension/`: `corepack pnpm exec vitest run src/session/sdk_session_projection.test.ts src/extension/composition_root.test.ts src/extension.test.ts`, `corepack pnpm typecheck`, `corepack pnpm test`, `corepack pnpm build`.

One feature-owning implementation worker; the 3 stories are sequential verification checkpoints, not separate ownership units.

## Implementation

Completed all three lifecycle failure-policy checkpoints:

- queued delivery now takes an explicit rejection observer; production logs the
  queued id and error while preserving synchronous throws, queue clearing, and
  the existing no-retry/no-protocol-error policy;
- `CommandSurfacePort.ensureStarted` is synchronous, and all three background
  `_cmdRoot` launches use `_startRootInBackground` with origin-labelled,
  consumed rejection logs; the slash-command path remains awaited;
- control-frame dispatch remains synchronous and immediately swallows input,
  while its async command rejection is consumed by a payload-free operator log.

No phone-visible error, requeue, turn rollback, Cockpit failure event, or Pi
extension-error propagation was added.

Verification from `pi-extension/`:

- Passing: `./node_modules/.bin/tsc --noEmit`.
- Passing targeted lifecycle coverage:
  `./node_modules/.bin/vitest run src/session/sdk_session_projection.test.ts
  src/extension/composition_root.test.ts src/extension.test.ts -t 'control
  dispatch observes unexpected async command rejection|input hook swallows a
  CTRL_PREFIX|legacy CTRL_PREFIX input dispatches relay status|structured
  outpost_pi_control input is swallowed'`.
- Passing focused suites: `./node_modules/.bin/vitest run
  src/session/sdk_session_projection.test.ts` (42),
  `src/extension/composition_root.test.ts` (4), and the control rejection
  focused extension selection (4).
- Full `./node_modules/.bin/vitest run`: 843 passed, 8 failed, 3 skipped.
  Failures are the documented read-only `/tmp` `cwd_lock.test.ts` failures
  (7) plus the documented stale same-name lock assertion in
  `extension.test.ts`; no changed-scope test failed.
- Passing build: `./node_modules/.bin/tsc` (generated `dist/` remains ignored).

The prescribed combined lifecycle command was also attempted; its extension
suite encountered the same read-only/stale-lock environment cascade, while the
focused changed-scope tests above passed.
