# Session note — 2026-07-05 — epic reframed to observability-first; relay log gap closed; debug-log adapter done

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## What happened this session

Continued from the 2026-07-04 epic-scope review. The operator opened
`epic-targeting-and-session-lifecycle-contracts` to see if a foundational
issue was contributing to a bug class. This session: reframed the epic,
closed the relay log gap, and shipped the debug-log adapter foundation
through a rigorous 4-pass adversarial review.

### Epic reframe — observability-first (not contract-first)

The original epic thesis was "undefined state machines at the boundaries →
pin contracts in PROTOCOL.md first." Two adversarial reviews (openai-codex/
gpt-5.5, cross-model) showed that over-aggregated confirmed code defects, SDK
seam constraints, and **unreproduced** hypotheses under one banner, and risked
canonizing unverified assumptions as current-state truth (the draft's
"collision conditions" premise was already invalidated once by operator Q2).

The operator's framing resolved the central tension: **the foundational issue
is the inability to capture productions/reproductions on the app side except
anecdotally.** The bug class exists because we're observability-blind on the
phone (and relay) side where the bugs manifest — the extension side is already
retroactive (`audit.jsonl`).

Reframed to: **observability + reproduction is the critical path; contract
prose is a downstream evidence-sourced audit.** 3 child features:
- `feature-cross-side-observability` (promoted critical path)
- `feature-reconnect-reproduction` (split-out observation workstream)
- `feature-contract-gap-audit` (demoted, downstream, consumes released
  bold-refactor outputs — `epic-bold-canonical-session`/`-transcript-event-log`/
  `-reachability-contract`/`-turn-state-machine`, all `stage: done` in
  `.work/releases/v0.6.0/`)

3 superseded features retired to `.work/archive/` with `status: superseded`
pointers.

### Relay log gap closed — `story-relay-retroactive-file-logging` (stage: review)

- `REMOTEPI_RELAY_LOG_DIR` + `tracing-appender` daily rotation (non-blocking,
  stdout unchanged by default). `EnvFilter` from `RUST_LOG` (default info).
- Cross-PC `pi_envelope` forward-path `debug!` with `from_tail`/`to_pc_tail`/
  `room`/`env_id_tail` for cross-side correlation (app `[msg-send] id` ↔
  extension `app user_message id` ↔ relay `env_id_tail`).
- Review caught 3 issues, all fixed: blocker DoS (`id_tail` UTF-8 panic on
  non-ASCII envelope ids → char-boundary-safe + 9 tests), full-pubkey privacy
  regression (now tail-only via `peer_tail`), overstrong comment softened.
- `cargo fmt --check` + `cargo clippy -D warnings` + `cargo test` (113) green.

### Dangling pi-extension fixes committed

Prior session left `resolveRemoteSessionId` stale-ctx guard + `compactionSummary`
transcript mapping uncommitted. Committed as `4b7daa8`.

### Debug-log adapter — `story-app-debug-log-adapter` (stage: DONE)

Units 1+2 of `feature-cross-side-observability`. The foundation: no UI, no
capture sites yet.

- **Unit 1 (domain):** `DebugEvent` sealed class + `DebugTag` enum + 12 typed
  variants (incl. `ConnChannelLostEvent.stale` — the duplicate-connection-
  takeover proof). `abstract interface class DebugLog implements Service`.
  Compiler-enforced `tagOf()` exhaustiveness switch + positive per-tag
  `kAllowedKeys` allow-list + expanded `kForbiddenKeys` deny-list.
- **Unit 2 (data):** `DebugLogImpl` — 1 MiB snapshot-write cap (not append-
  only), export-from-file (source of truth), critical-event immediate flush,
  serialized flushes via `_flushFuture` chain, race-safe `clear()` (awaits
  in-flight flush), shared `_loadFuture` (reentrancy-safe), never-throws
  (whole-body catch incl. `_debugEnabled()`), UTF-8 byte accounting, dispose-
  wired via `addService<DebugLog>`.
- 26 tests (10 registry + 16 adapter); flutter analyze clean; full suite
  640 passed (614 existing + 26 new).

### The 4-pass review arc (the high-value part)

Each round caught a real issue the prior missed:
- **v1 (NEEDS FIXES):** blocker file-cap/export-from-file, 4 importants, 2
  nits, privacy gap.
- **v2 (NEEDS FIXES, re-review):** confirmed v1 fixes landed; caught a NEW
  blocker (clear-vs-flush race introduced by the snapshot-write restructure).
- **v3 (NEEDS FIXES):** caught that the v2 fix commit (d941567) CLAIMED to fix
  `clear()` but the edit never applied — and the regression test passed for
  trivial timing reasons. **This is the catch that mattered:** it would have
  shipped a false sense of security (a "fix" that wasn't there, validated by
  a test that didn't test).
- **v4 (ACCEPTED):** independently verified the actual fix (f7793b0), proved
  the rewritten regression test has teeth (revert experiment: test FAILS
  without the fix, PASSES with it), nothing regressed.

The `@visibleForTesting` seams (`pendingFlush` + `flushDelayForTesting`) are
what made the regression test deterministic — the test holds the flush
in-flight, captures it via `pendingFlush`, starts `clear()` without awaiting,
asserts `clearDone.isCompleted` is false, then releases and asserts no
resurrection.

## Process lesson — the inline-build over-reach (twice)

The operator asked for the logging stories to be "scoped and built as work
items." I scoped them, then **implemented the app half inline** and left the
repo non-compiling (dangling `_DebugSection` reference, missing imports).
Reverted, re-scoped, re-designed (twice — v1 then v2 after the operator's
debug-toggle reframe), THEN implemented with review discipline. The lesson:
**design-first when the operator steers the scope, even if the change feels
mechanical.** And: a commit that claims a fix but doesn't contain it (v3) is
worse than no commit — the review caught it only because the reviewer read
the actual code, not the commit message.

## What's next (resume here)

Both `stage: implementing`, depend on the done adapter:
- **`story-app-debug-toggle-ui`** (Unit 3): `Preferences.debugLogging` +
  `addService<DebugLog>` DI wiring + settings toggle + export/clear UI +
  `share_plus` dep. Natural next — makes the ring log operator-controllable.
- **`story-app-capture-routing`** (Unit 4): route the 15 existing `debugPrint`
  sites + add the 6 `ConnectionManager` events (incl. the `conn-channel-lost`
  takeover proof at `connection_manager.dart:1162-1175`, both branches).
  Line numbers verified against actual code in the v2 design review.

Then the broader epic:
- `feature-reconnect-reproduction` (consumes the instrumentation to attribute
  the reconnect cluster) — depends on `feature-cross-side-observability`.
- `feature-contract-gap-audit` (downstream) — depends on both.
- `story-relay-duplicate-auth-supersession-log` (drafting) — the relay half
  of the takeover proof; builds on the shipped file sink.

## Review discipline to carry forward

Apply the same 4-pass discipline to the next stories: implement → adversarial
review (openai-codex/gpt-5.5) → fix → re-review until ACCEPTED → fast-lane
advance to done. The v3 catch (claimed-but-unapplied fix) is the failure
mode to watch for — always have the reviewer verify the fix is actually IN
the file, not just in the commit message, and that regression tests have
teeth (a revert experiment is the proof).

## Commit graph (this session)

```
b942302 review: story-app-debug-log-adapter → done (Approve, fast-lane advance)
141de9a review: story-app-debug-log-adapter (ACCEPTED after 4 adversarial passes), stage→review
f7793b0 fix(app/debug-log): actually apply clear()-vs-flush serialization + deterministic regression test
d941567 fix(app/debug-log): address review NEEDS FIXES — snapshot-write, clear race, registry exhaustiveness
8c39e96 implement: story-app-debug-log-adapter (typed DebugEvent registry + file adapter + lifecycle)
92e20cf feature-design v2 fixes: duplicate-conn takeover proof + DI contract + line-number corrections
da516cb feature-design revision: debug-gated app-global ring log + expanded capture
69c6abc feature-design: feature-cross-side-observability (7 units, stage→implementing)
856fb86 work: track pre-existing resilience stories and backlog ideas (2026-07-03)
4b7daa8 pi-extension: guard stale-ctx in resolveRemoteSessionId + map compactionSummary
c4543f6 relay: retroactive file logging + cross-side correlation; reframe epic to observability-first
a2726b5 (prior session) scope: epic-targeting-and-session-lifecycle-contracts
```

Working tree clean. All reviews committed. Ready to pause for context reset.
