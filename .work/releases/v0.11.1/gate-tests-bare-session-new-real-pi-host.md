---
id: gate-tests-bare-session-new-real-pi-host
kind: story
stage: done
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: v0.11.1
gate_origin: tests
created: 2026-08-29
updated: 2026-08-29
---

# Exercise bare mobile session replacement through Pi's installed host runtime

## Priority
High

## Value evidence
Item: `story-fix-new-wedge-bare-pi`

Contract / risk / regression / maintenance cost: the field incident left a bare
Pi process alive after its owner room had torn down, and the release contract is
now exhaustive: a mobile `session_new` must either rebind a usable successor or
terminate the process. The prior production test (formerly at
`pi-extension/src/extension.test.ts:2295-2363`) protected the in-process branch,
but supplied a hand-written `newSession` function and hand-written
`withSession` context. It therefore assumed the host behavior at the exact seam
that failed in production.

The repository already has stronger infrastructure, but no prior test routed
the mobile `session_new` action through it. `SdkSessionReplacementHarness`
loads the real production extension factory through Pi's installed
`loader.js`, uses the installed `ExtensionRunner`, and delegates replacement to
`AgentSessionRuntime`; current cases in
`pi-extension/src/session/runtime_coordinator.integration.test.ts` call host
replacement directly rather than entering through the mobile action. The
headless E2E Pi host is not a substitute: its `replaceSession` implementation
mutates one runner's `SessionManager` and emits `session_start` itself
(`pi-extension/test/support/e2e_pi_host_runtime.ts:380-425`), whereas Pi's real
runtime performs predecessor shutdown/disposal, creates and binds a new
runtime, then invokes `withSession`. Because the known regression is a
lifecycle-host seam, the unit model can stay green while real runner/loader
replacement behavior drifts.

## Gap type
e2e-seam / bug-regression / lifecycle replacement

## Suggested test
```ts
test("bare mobile session_new rebinds through installed AgentSessionRuntime", async () => {
  // Clear OUTPOST_PI_DAEMON and OUTPOST_PI_UNDER_RESTART_WRAPPER.
  // Create SdkSessionReplacementHarness, then prime the real registered
  // command context so the mobile action has Pi's installed newSession API.
  // Route production `session_new` through _routeClientMessageFrom.
  // Assert predecessor session_shutdown(new), successor session_start(new),
  // a changed room/session id, action_ok + empty successor history, and no exit.
  // Route a successor user_message and assert the replacement runtime delivers
  // it once through its fresh message API. Restore process env in finally.
});
```

Keep the existing no-command-context terminal-exit test and wrapper/daemon
exit-42 tests; this seam specifically proves that the command-capable bare path
matches Pi's installed loader/runner/runtime behavior rather than a test-owned
`newSession` model.

## Test location (suggested)
`pi-extension/src/session/runtime_coordinator.integration.test.ts`, using
`pi-extension/test/support/sdk_session_replacement_harness.ts`

## Resolution (2026-08-29)
Replaced the hand-written `/new` host context with a production-index test that primes the real registered command context, routes mobile `session_new` through the installed Pi loader, `ExtensionRunner`, and `AgentSessionRuntime`, and verifies predecessor shutdown, successor startup, fresh session identity, empty history, fresh message delivery, and no exit. The bare no-command test separately verifies lifecycle teardown completes before exit 42.

Verified with `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` from `pi-extension/`.
