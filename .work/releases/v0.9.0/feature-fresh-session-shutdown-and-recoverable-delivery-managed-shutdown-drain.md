---
id: feature-fresh-session-shutdown-and-recoverable-delivery-managed-shutdown-drain
kind: story
stage: done
tags: [pi-extension, lifecycle]
parent: feature-fresh-session-shutdown-and-recoverable-delivery
depends_on: [feature-fresh-session-shutdown-and-recoverable-delivery-retry-contract]
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Replace fixed-delay fresh exit with the lifecycle-owned drain

## Checkpoint

For wrapper/daemon `session_new` requests that lack an SDK command context,
install the owner-ingress fence synchronously, reject later `user_message`
frames with `delivery_retry`, settle user deliveries accepted before the fence,
then stage `action_ok` plus the empty-session projection. Invoke the active
runtime's normal `reason: new` shutdown and await owner-channel sequence
persistence/enqueue, relay/room close, mesh close, and cwd-lock release before
exiting with the existing `EXIT_FRESH_SESSION` (`42`) process-manager result.

The shutdown has a bounded liveness deadline, but that deadline is not treated
as delivery proof: on exhaustion the app's durable recovery path remains the
safety boundary. Direct SDK `newSession({withSession})` behavior remains
in-process and unchanged.

## Files

- `pi-extension/src/extension/fresh_session_shutdown.ts` (new coordinator)
- `pi-extension/src/extension/ports.ts`
- `pi-extension/src/extension/composition_root.ts`
- `pi-extension/src/index.ts`
- focused tests in
  `pi-extension/src/extension/fresh_session_shutdown.test.ts`,
  `pi-extension/src/extension/composition_root.test.ts`, and
  `pi-extension/src/extension.test.ts`

## Acceptance evidence

- [x] Setting the fresh-session fence is synchronous; a later prompt produces
      `delivery_retry` and never calls the Pi SDK.
- [x] A delivery already admitted before the fence settles before reset and
      runtime teardown begin.
- [x] `action_ok` and the reset projection enter the secure owner-channel tail
      before detach, and process exit does not occur until that tail and relay
      stop settle.
- [x] Relay stop failure or deadline exhaustion cannot skip the mesh/cwd-lock
      cleanup attempt; exit remains the final step.
- [x] Overlapping shutdown requests share one transition and do not reset or
      exit twice.
- [x] The `setTimeout(() => process.exit(42), 100)` path is deleted; wrapper and
      daemon process-manager tests retain the one-shot no-`--continue` launch.
- [x] Focused Vitest tests use explicit barriers rather than sleeps; extension
      typecheck, full tests, and build pass.

## Ordering

Depends on the schema-owned retry signal emitted by the fence.

## Implementation notes

- Execution/order: inline host worker (`openai-codex/gpt-5.6-sol`, xhigh),
  second checkpoint after the retry contract. The app resend sibling remained
  independently ready; drain was taken first only as the caller-approved
  sensible inline order, not as an added dependency.
- Added `FreshSessionShutdownCoordinator` as the process-level synchronous
  ingress-fence and bounded shutdown owner. Hot reload and managed fresh
  sessions now share the same `delivery_retry` producer; the former ad hoc
  `_hotReloading` branch and fixed 100 ms exit timer are gone.
- The coordinator drains the stable snapshot of admitted SDK deliveries before
  staging correlated `action_ok` and the empty-session projection. It then
  invokes the coordinator-approved runtime's normal `dispose("new")`; stale
  leases return false and never terminate the process. Overlapping requests do
  not stage or exit twice.
- Runtime disposal starts relay and mesh/cwd-lock cleanup attempts together and
  awaits both. Relay rejection cannot skip mesh cleanup. Deadline exhaustion
  also starts lease-scoped runtime disposal before exit 42; it is explicitly an
  uncertain-delivery fallback rather than delivery proof.
- Deterministic barrier tests prove pre-fence delivery settlement, post-fence
  zero-SDK rejection, protected ACK/reset ordering, one exit, stale-runtime
  refusal, cleanup attempts after relay failure/stall, and deadline behavior.
  Direct SDK `newSession({withSession})`, unmanaged action errors, wrapper exit
  42 fresh relaunch, and daemon spawn contracts remain covered.
- Verification: focused coordinator/composition tests passed (14); focused
  managed/unmanaged/hot-reload routing passed (4); full `extension.test.ts`
  passed (215); authoritative extension verification passed: typecheck, 60 test
  files with 1,098 passed / 3 skipped, and build. `git diff --check` passed.
