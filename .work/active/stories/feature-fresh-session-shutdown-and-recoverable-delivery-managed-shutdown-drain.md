---
id: feature-fresh-session-shutdown-and-recoverable-delivery-managed-shutdown-drain
kind: story
stage: implementing
tags: [pi-extension, lifecycle]
parent: feature-fresh-session-shutdown-and-recoverable-delivery
depends_on: [feature-fresh-session-shutdown-and-recoverable-delivery-retry-contract]
release_binding: null
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

- [ ] Setting the fresh-session fence is synchronous; a later prompt produces
      `delivery_retry` and never calls the Pi SDK.
- [ ] A delivery already admitted before the fence settles before reset and
      runtime teardown begin.
- [ ] `action_ok` and the reset projection enter the secure owner-channel tail
      before detach, and process exit does not occur until that tail and relay
      stop settle.
- [ ] Relay stop failure or deadline exhaustion cannot skip the mesh/cwd-lock
      cleanup attempt; exit remains the final step.
- [ ] Overlapping shutdown requests share one transition and do not reset or
      exit twice.
- [ ] The `setTimeout(() => process.exit(42), 100)` path is deleted; wrapper and
      daemon process-manager tests retain the one-shot no-`--continue` launch.
- [ ] Focused Vitest tests use explicit barriers rather than sleeps; extension
      typecheck, full tests, and build pass.

## Ordering

Depends on the schema-owned retry signal emitted by the fence.
