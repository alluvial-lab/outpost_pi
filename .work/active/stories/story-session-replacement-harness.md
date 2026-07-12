---
id: story-session-replacement-harness
kind: story
stage: done
review_addressed: 2026-07-05
tags: [pi-extension, testing, observability, session-lifecycle]
parent: feature-cross-side-observability
depends_on: [story-app-capture-routing]
release_binding: v0.1.0
gate_origin: null
created: 2026-07-05
updated: 2026-07-05
---

# Session-replacement SDK-seam integration harness (Unit 7)

## Brief

The session-replacement bug class (`/new`, `/reload`, `/resume`, `/fork`) is the
highest-risk area of the epic, and the one where mock-only tests have repeatedly
given false confidence (this session's `factoryApi` re-arm and single-process
framing both passed their mock-based tests because the mocks didn't model
`runtime.assertActive()` or real SDK session replacement). Unit 7 is the
test-side analog of the ring log: make session-replacement failures
reproducible in CI instead of only in live use.

The Unit 7 **feasibility spike** (`spike-extension-runner-headless.test.ts`,
committed 2026-07-05) established the verdict:

> **PARTIALLY FEASIBLE.** `ExtensionRunner` can be instantiated headlessly and
> `createContext()` returns a real SDK `ExtensionContext`, but `ExtensionRunner`
> alone CANNOT drive a real session replacement — `ctx.newSession()` exists only
> on `createCommandContext()` and delegates to a host-bound `newSessionHandler`
> that defaults to a no-op (`runner.js:139`). The real replacement lives higher
> up in `AgentSessionRuntime.newSession()` (`agent-session-runtime.js:144-168`),
> which tears down the current session, applies a fresh runtime, and finishes
> via `finishSessionReplacement(options?.withSession)`. The fresh
> post-replacement `sendUserMessage` comes from
> `AgentSession.createReplacedSessionContext()` (`agent-session.js:2529-2533`),
> which clones `runner.createCommandContext()` and binds real
> `sendUserMessage`/`sendMessage`.

So a pure `ExtensionRunner` harness is insufficient, but an **SDK-seam wrapper
harness** composing real `ExtensionRunner` + real `AgentSessionRuntime.newSession()`
+ a minimal fake `AgentSession` shell IS feasible and was empirically proven
(passing spike test #4). This is the alternate verification plan the feature
design required (NOT "xfail + ring log").

## Scope

Build `pi-extension/test/support/sdk_session_replacement_harness.ts` + a test
suite that drives the REAL session-replacement path and asserts the
post-replacement invariants the mock-based tests couldn't catch:

### The harness composition
- Real `ExtensionRunner` (headless, per spike).
- Real `SessionManager.inMemory()` (or temp persisted sessions — prefer
  in-memory for speed and isolation unless a test specifically needs persistence).
- Real `AgentSessionRuntime.newSession()` for the replacement.
- A minimal fake `AgentSession` shell that:
  - exposes `extensionRunner`, `sessionManager`, `sessionFile`;
  - invalidates the old runner in `dispose()` (the stale-ctx trigger);
  - returns `createReplacedSessionContext()` using SDK-compatible
    `runner.createCommandContext()` + spies for `sendUserMessage`/`sendMessage`.
- Load/register the actual Remote Pi extension into the runner so `session_start`
  and the app actions (`session_new`, `session_resume`) run against real code.

### The assertion matrix (the whole point — these must have teeth)
- [ ] `session_start` (reason: `new`) rebinds the fresh ctx; the extension's
      `session_start` hook sees the new `ExtensionContext`.
- [ ] The OLD `ExtensionContext` throws stale after replacement — calling
      `runtime.assertActive()` (or any active-gated op) on the old ctx throws.
      THIS is the catch that would have failed this session's wrong fixes.
- [ ] The app `session_new` action calls `newSession({ withSession })` on the
      runtime (verify the action→runtime wiring is real, not a mock stub).
- [ ] `onReplaced` (or the extension's replacement hook) recaptures the fresh
      ctx; subsequent `sendUserMessage` lands on the fresh ctx, not the stale one.
- [ ] Subsequent app actions land on the fresh ctx.
- [ ] Resume-style `session_start` (reason: `resume`) backfills history from
      `SessionManager.buildSessionContext()` — covers the
      `story-mobile-chat-blank-on-pair-after-pre-pair-work` path.

### `/reload` — explicit non-goal for the first cut
The spike noted `/reload` is a separate concern: it's a same-session
`session_start:reload` against a re-`require`d module, which is a Pi-process
concern, not an `ExtensionRunner`/`AgentSessionRuntime` concern. The first cut
of this harness covers `/new` and `/resume` (the stale-ctx throw + fresh delivery
path). `/reload` is filed as a follow-up below; do not block the harness on it.
If a future process-level harness is needed for exact `/reload` behavior, that's
a separate story.

## Acceptance Criteria
- [ ] `pi-extension/test/support/sdk_session_replacement_harness.ts` exists
      and composes real `ExtensionRunner` + `AgentSessionRuntime.newSession()`
      + minimal fake `AgentSession` shell as described.
- [ ] The actual Remote Pi extension is registered into the runner (real code
      path, not a mock).
- [ ] All 6 assertion-matrix items above have passing tests with teeth (a
      revert experiment: if the extension's stale-ctx guard were removed,
      would the "old ctx throws stale" test fail? If yes, teeth.).
- [ ] The harness does NOT modify production code. If a production testability
      seam is needed, STOP and report it as a finding (do not add it silently).
- [ ] `corepack pnpm typecheck` clean; `corepack pnpm test` green (the new
      suite + all existing).
- [ ] The spike file `spike-extension-runner-headless.test.ts` is either
      reworked into the durable harness test or deleted (not left as a
      duplicate). Recommend the former if the harness subsumes it.

## Out of scope
- `/reload` exact-process behavior (follow-up story).
- A real Pi process-level harness (only needed if the SDK-seam harness can't
  cover a required case — the spike says it covers /new and /resume).
- The ring log (Unit 1-4, done) — this harness is CI reproducibility, not
  retroactive capture.

## Risks
- **`AgentSessionRuntime`/`AgentSession` are internal SDK seams**: they're not
  guaranteed stable across SDK versions. Mitigation: pin to the installed
  `@earendil-works/pi-coding-agent` version; if the SDK changes the seam, the
  harness breaks loudly (which is acceptable — it means re-verifying against
  the new SDK).
- **The fake `AgentSession` shell could mask a real bug**: if the shell's
  `dispose()`/`createReplacedSessionContext()` doesn't exactly mirror the SDK's
  stale-ctx invalidation, the "old ctx throws stale" assertion could be fake.
  Mitigation: use the REAL `runner.createCommandContext()` (not a mock) for the
  replaced context, and base the shell's invalidation on the SDK's actual
  `assertActive()` guard, not a hand-rolled `disposed=true` flag. The spike
  proved this is possible.
- **History backfill shape**: `SessionManager.buildSessionContext()` may
  require a specific session-file format. If the in-memory manager can't
  produce a backfillable history, fall back to a temp persisted session.

## References
- Parent: `feature-cross-side-observability.md` (Unit 7, the pre-mortem spike
  directive, the alternate-verification-plan requirement).
- Spike: `pi-extension/test/spike-extension-runner-headless.test.ts` (the
  empirical proof + SDK source findings).
- SDK source findings (from the spike report):
  - `node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/runner.js:148`
    (constructor), `:139` (no-op default handler), `:494-496` (delegated newSession).
  - `agent-session-runtime.js:144-168` (real replacement).
  - `agent-session.js:2529-2533` (fresh `createReplacedSessionContext`).
- Extension session code:
  - `pi-extension/src/session/sdk_session_projection.ts` (`ExtensionRunner.createContext`).
  - `pi-extension/src/session/remote_session.ts` (`ExtensionRunner.assertActive`).
  - `pi-extension/src/session/sdk_session_projection.test.ts` (existing fake-ctx pattern).
- `.agents/skills/pi-extension-typescript/SKILL.md` — pi-extension test commands
  + sandbox env (PNPM_HOME/npm_config_cache/XDG_CACHE_HOME redirection).

## Follow-up (filed separately)
- `story-session-reload-process-harness` (drafting) — `/reload` exact-process
  behavior if the SDK-seam harness can't cover it.

## Implementation notes

### Harness composition built

- Added `pi-extension/test/support/sdk_session_replacement_harness.ts`.
- The harness composes a real SDK `ExtensionRunner`, `SessionManager.inMemory()`
  by default, and real `AgentSessionRuntime.newSession()` / `switchSession()`
  replacement paths.
- The only fake is the minimal `AgentSession` shell required by
  `AgentSessionRuntime`: it exposes `extensionRunner`, `sessionManager`,
  `sessionFile`, `agent.state.messages`, `dispose()`, and
  `createReplacedSessionContext()`.
- `dispose()` calls the real `runner.invalidate()`, so stale assertions are
  backed by the SDK's `ExtensionRunner.assertActive()` guarded getters/methods,
  not by a hand-rolled `disposed` flag.
- `createReplacedSessionContext()` clones the real
  `runner.createCommandContext()` with property descriptors and attaches
  `sendUserMessage` / `sendMessage` delivery spies, matching the SDK seam from
  `AgentSession.createReplacedSessionContext()`.
- The actual Remote Pi extension factory (`src/index.ts`) is registered into
  the runner. A tiny probe extension is registered alongside it only to record
  lifecycle reasons/session ids; app actions and session hooks run through real
  Remote Pi code.
- The harness uses the existing test-only `_setDisposedForTest(false)` during
  `AgentSessionRuntime.setBeforeSessionInvalidate()` to suppress headless
  relay/mesh auto-start after `session_shutdown`; this does not replace the
  stale-ctx guard and avoids a fire-and-forget `_cmdRoot` racing test cleanup.

### Per-file changes

- Added `pi-extension/test/support/sdk_session_replacement_harness.ts` — reusable
  SDK-seam harness and `TestPeerChannel`.
- Added `pi-extension/test/sdk-session-replacement.test.ts` — durable Unit 7
  suite covering `/new` and `/resume` session replacement.
- Deleted `pi-extension/test/spike-extension-runner-headless.test.ts` — the
  spike findings are subsumed by the durable harness and no duplicate spike
  suite remains.

### Assertion matrix coverage

1. `session_start:new` rebinds the fresh ctx; actual extension hook sees the new
   `ExtensionContext` — covered by
   `direct SDK newSession emits session_start:new on the actual extension and makes the old ctx stale`
   via lifecycle sequence `startup -> shutdown:new -> start:new` and
   `_getRemoteSessionIdForTest() === freshSessionId`.
2. OLD `ExtensionContext` throws stale after replacement — covered by the same
   test and by
   `app session_new delegates to runtime newSession({ withSession }) and the replacement callback delivers on the fresh ctx`,
   both asserting `oldCommandCtx.cwd` throws `/stale after session replacement or reload/`.
   Revert-experiment teeth: if the fake shell stopped calling `runner.invalidate()`
   (or the SDK `assertActive()` stale guard stopped firing), these assertions
   would fail because the old guarded getter would not throw.
3. App `session_new` action calls `newSession({ withSession })` on the runtime —
   covered by
   `app session_new delegates to runtime newSession({ withSession }) and the replacement callback delivers on the fresh ctx`,
   asserting the real action route records `{ sessionLabel: "initial", hasWithSession: true }`.
4. `onReplaced` / replacement callback recaptures fresh ctx and subsequent
   `sendUserMessage` lands fresh — covered by the same app `session_new` test,
   which routes a `user_message` through the pre-replacement module after
   `withSession` and observes `sendUserMessage` on `replacement-2`.
5. Subsequent app actions land on fresh ctx — covered by
   `subsequent app actions route through the fresh session ctx after app-triggered replacement`,
   which sends `session_compact` after app-triggered `session_new` and observes
   the compact call on `replacement-2`.
6. Resume-style `session_start:resume` backfills persisted history from
   `SessionManager.buildSessionContext()` — covered by
   `resume-style session_start backfills history from SessionManager.buildSessionContext`,
   which uses a temp persisted `SessionManager`, drives real
   `AgentSessionRuntime.switchSession()`, and verifies `session_sync` returns
   `user_input` + `agent_message` history.

### Verification output

Commands run from `pi-extension/` with the required sandbox env prefix:

```text
PNPM_HOME=/home/agent/projects/remote_pi/.pnpm-store npm_config_cache=/home/agent/projects/remote_pi/.npm-cache XDG_CACHE_HOME=/home/agent/projects/remote_pi/.xdg-cache corepack pnpm typecheck
[WARN] The "pnpm" field in package.json is no longer read by pnpm. The following keys were ignored: "pnpm.onlyBuiltDependencies". See https://pnpm.io/settings for the new home of each setting.
$ tsc --noEmit
```

```text
PNPM_HOME=/home/agent/projects/remote_pi/.pnpm-store npm_config_cache=/home/agent/projects/remote_pi/.npm-cache XDG_CACHE_HOME=/home/agent/projects/remote_pi/.xdg-cache corepack pnpm test
[WARN] The "pnpm" field in package.json is no longer read by pnpm. The following keys were ignored: "pnpm.onlyBuiltDependencies". See https://pnpm.io/settings for the new home of each setting.
$ vitest run

 RUN  v4.1.9 /home/agent/projects/remote_pi/pi-extension


 Test Files  46 passed (46)
      Tests  743 passed | 3 skipped (746)
   Start at  18:41:01
   Duration  7.69s (transform 3.23s, setup 0ms, import 7.50s, tests 15.92s, environment 6ms)
```

### Deviations / notes

- No production code was modified and no production testability seam was added.
- `/reload` remains out of scope per story.
- Resume backfill requires a real persisted session file, so that test uses a
  temp persisted `SessionManager`; `/new` paths use in-memory session managers.

## Review fixes (adversarial review, 1 pass)

NEEDS FIXES → APPROVED after 1 fix pass (openai-codex/gpt-5.5):

- **[I1] onReplaced rebind teeth gap** (`sdk-session-replacement.test.ts`): the
  original suite proved the SDK invalidates the old ctx (`oldCommandCtx.cwd`
  throws via real `assertActive()`) and that fresh delivery lands on the fresh
  session, but did NOT prove the extension's `onReplaced`/
  `_bindReplacementSessionContext()` rebind retained a fresh command-capable
  ctx. The fresh-delivery assertions could pass via `session_start`/factory
  rebinding even if the extension's `onReplaced` rebind were broken. Fixed by
  adding a 5th test: "a second app session_new after replacement proves the
  fresh ctx is command-capable (onReplaced rebind teeth)" — sends a first
  `session_new` (rotates id), then a SECOND `session_new`, asserting the second
  call records `{ sessionLabel: "replacement-2", hasWithSession: true }`
  (proving it came from the FRESH session's bound command actions, not the
  initial) AND the session id rotates a second time. If the extension held a
  stale command ctx after the first replacement, the second `session_new`
  would either throw stale or route to the old session's handler — recording
  the wrong label and not rotating the id — so the test fails. This closes the
  teeth gap.

- **Nits**: removed the unused `importNonce` field. The `modelRegistry` as
  `{ } as never` was advisory/acceptable (the harness paths exercised by this
  story don't touch the registry) — left as-is.

Final verification: `corepack pnpm test` → 744 passed | 3 skipped (was 743;
+1 new teeth test). `corepack pnpm typecheck` clean. No production code
modified (`git diff HEAD -- pi-extension/src/` empty). Spike file deleted
(subsumed by the durable harness).
