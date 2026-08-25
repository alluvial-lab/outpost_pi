# Session note — 2026-07-05 (cont. into 07-06) — observability feature Units 3/4/6 done, Unit 7 harness in flight

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## What happened this session

Continued the `feature-cross-side-observability` critical path. The adapter
(Units 1+2) was done prior; this session shipped Units 3, 4, 6 and ran the
Unit 7 feasibility spike + spawned the harness story.

### `story-app-debug-toggle-ui` (Unit 3) — DONE

App-global "Debug logging" Settings switch persisted in `Preferences`;
`DebugLogImpl` registered via `addService<DebugLog>` (disposing path →
`disposeDependencies()` flushes on teardown). `_DebugSection` with Export
(real `share_plus` share sheet, jsonl file) + Clear (confirm dialog) + privacy
warning. APPROVE on first adversarial pass. flutter test 659 pass.

### `story-app-capture-routing` (Unit 4) — DONE (after 2 fix passes)

The actual gap closure. Routed the 15 existing `debugPrint` sites through
`DebugLog.log(<typed event>)` (logcat unchanged) + added 6 first-class
`ConnectionManager` events incl. the **`conn-channel-lost {stale}`
duplicate-connection-takeover proof** (`!identical(cur, ch)` branch, both
sides).

Review arc (the high-value part):
- v1 NEEDS FIXES: [I1] `ReplayDedupEvent.dropped` lied for within-batch
  duplicates; [I2] registry tag-exhaustive but not capture-site-exhaustive.
- Fix attempt: applied [I1]+[I2]; discovered the implementer added emissions to
  2 **unreachable dead branches** in `ws_transport.dart` (`envelopeBytes==null`
  under `enqueue`, `control==null` under `control` — the demux's `try/catch`
  routes all decode failures to `dropMalformed` before reaching them). Removed.
- v2 re-review NEEDS FIXES: caught that my [I1] test lacked teeth — it only
  exercised across-push dedup (which the OLD logic handled), not within-batch
  (the actual bug). **Exactly the v3 failure mode from the prior session.**
- Final fix + re-review APPROVE: added a real within-batch-duplicate test
  (same id + same ts → one `serverReplayEventId`), confirmed it FAILS under
  the old logic by trace. Also tightened the [I2] registry: tag-filtered,
  non-vacuous discriminants, `_markActiveRoomOffline` test via `FakeAsync` +
  injectable `pingInterval` (real constructor param, not a `@visibleForTesting`
  seam). flutter test 659 pass.

### `story-add-transport-frame-observability` (Unit 6) — DONE

Rescoped/collapsed: the original drafting brief imagined a broad app+relay+
pi-extension design task, but Unit 4 already shipped the `ws-in` relay-frame
observability and the relay file-logging story shipped the `debug!` forward
path. The real remaining gap was just the two silent-drop sites in
`peer_channel.dart` (`UnsupportedTypeException` + catch-all malformed).

Added `DebugTag.peerFrame` + `PeerFrameEvent` to the registry; injected
`DebugLog?` into `PlainPeerChannel`; emitted at both drop sites with
privacy-safe fields (`kind`, `bytes`=length, `error`=`runtimeType` only —
never the decode error message, which could leak raw bytes/content; fallback
to `'unknown_error'` constant, never `raw.toString()`). Wired both production
construction sites (reconnect factory + `PairingViewModel` post-pair adoption;
grep-confirmed no missed sites). APPROVE on first pass. flutter test 661 pass.

### Unit 7 spike — PARTIALLY FEASIBLE (committed, harness story spawned)

Empirical spike (`pi-extension/test/spike-extension-runner-headless.test.ts`,
4 passing tests): `ExtensionRunner` CAN be instantiated headlessly and
`createContext()` returns a real SDK `ExtensionContext`, BUT `ExtensionRunner`
alone CANNOT drive a real session replacement — `ctx.newSession()` exists only
on `createCommandContext()` and delegates to a host-bound `newSessionHandler`
that defaults to a no-op (`runner.js:139`). The real replacement lives higher
up in `AgentSessionRuntime.newSession()` (`agent-session-runtime.js:144-168`);
the fresh post-replacement `sendUserMessage` comes from
`AgentSession.createReplacedSessionContext()` (`agent-session.js:2529-2533`).

Verdict: an **SDK-seam wrapper harness** composing real `ExtensionRunner` +
`AgentSessionRuntime.newSession()` + a minimal fake `AgentSession` shell IS
feasible (proven by spike test #4). This is the alternate verification plan
the feature design required (NOT "xfail + ring log"). Spawned
`story-session-replacement-harness` with the concrete composition + 6-item
assertion matrix + `/reload` explicit non-goal.

### Unit 7 harness implementation — IN FLIGHT

Dispatched `openai-codex/gpt-5.5` subagent to build
`pi-extension/test/support/sdk_session_replacement_harness.ts` + suite covering
the 6-item matrix. Hard constraints: real SDK seams (not mocks that bypass
replacement logic), real Remote Pi extension loaded (not a mock), fake
`AgentSession` shell's stale-ctx invalidation based on the real `assertActive()`
guard (not a hand-rolled flag), no production code changes. Awaiting completion.

## Review discipline (the throughline)

Every story this session went through implement → adversarial review
(`openai-codex/gpt-5.5`, fresh context) → fix → re-review until ACCEPTED →
fast-lane advance. The v3 lesson held: the capture-routing [I1] re-review
caught a test that lacked teeth (across-push vs within-batch), exactly the
"claimed fix that doesn't actually test the bug" failure mode. The fix was a
regression test that FAILS under the old logic — proven by trace, not
assertion. The dead-branch discovery (Unit 4) and the `runtimeType`-vs-
`toString()` privacy catch (Unit 6) are the other review-caught findings.

## What's next (resume here)

1. **Unit 7 harness** (`story-session-replacement-harness`, in flight) — when
   the subagent returns, adversarial review (same discipline; the
   stale-ctx-teeth revert experiment is the key check), then commit + advance.
2. **Downstream of the feature**:
   - `story-relay-duplicate-auth-supersession-log` (drafting) — relay half of
     the takeover proof; builds on the shipped file sink.
   - `feature-reconnect-reproduction` — consumes the instrumentation to
     attribute the reconnect cluster; depends on `feature-cross-side-observability`.
   - `feature-contract-gap-audit` — downstream, consumes released bold-refactor
     outputs + what the observability feature finds.
3. Once `feature-cross-side-observability` is fully done (Unit 7 landing), the
   epic `epic-targeting-and-session-lifecycle-contracts` unblocks the
   reconnect-cluster attribution + the contract prose audit.

## Commit graph (this session)

```
d566f30 review: story-add-transport-frame-observability → done (APPROVE, fast-lane)
f838058 implement(app): story-add-transport-frame-observability — peer-channel frame-drop observability (Unit 6)
4b8e0d4 spike(pi-extension): Unit 7 ExtensionRunner headless feasibility — PARTIALLY FEASIBLE
2514b6c scope: story-add-transport-frame-observability collapsed to peer-channel delta (Unit 6)
b428c5f review: story-app-debug-toggle-ui + story-app-capture-routing → done (fast-lane)
b4c5a86 review: story-app-debug-toggle-ui + story-app-capture-routing (ACCEPTED), stage→review
d7bc84a implement(app): story-app-capture-routing — emit diagnostic events at capture surface (Unit 4)
8a65bcc implement(app): story-app-debug-toggle-ui — debug toggle + export/clear UI (Unit 3)
0020dd3 (prior session note)
```

Working tree clean except the in-flight Unit 7 harness edits (when the subagent
returns). All app-side observability (Units 1-6) committed and at stage:done.
