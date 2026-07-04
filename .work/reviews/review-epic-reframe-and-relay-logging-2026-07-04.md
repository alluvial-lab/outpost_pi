# Review: epic reframe + relay retroactive logging

## Verdict

**PROCEED WITH FIXES.** The epic reframe is substantially sound: it answers the prior review's central question by making verified evidence the gate for foundation-doc claims and moving phone/relay observability ahead of contract prose. The relay slice is useful, but it should not be marked done or deployed as-is: the new `id_tail` helper can panic on non-ASCII, unvalidated envelope ids, the new persistent debug logs record full Pi pubkeys despite the relay privacy convention preferring shortened tails, and the story/process state is lagging the implementation.

## Part 1: Reframe

### Finding 1 — The observability-first thesis addresses the prior review; it does not merely relabel it

The prior review's central question was: can this epic pin target-state hypotheses in foundation docs, or must it pin only verified current-state contracts and route everything else through harness/reproduction first? The reframed epic answers that question explicitly in the right direction: "Observability-first, not spec-first," "pins only verified current-state contracts," and every foundation-doc claim needs an evidence source. That resolves the prior objection rather than dodging it.

The important constraint is that the implementation of this reframe must preserve that evidence gate. `feature-contract-gap-audit` is only safe if it remains an audit against code/tests/released work/reproductions, not a delayed design pass that reintroduces target-state prose under a new name.

### Finding 2 — The 3-feature split is coherent, with one dependency/frontmatter gap

The split is conceptually coherent:

- `feature-cross-side-observability` owns the missing evidence capture: phone ring log, relay file sink/correlation, transport-frame observability, and the real-SDK session-replacement harness.
- `feature-reconnect-reproduction` consumes that instrumentation to reproduce/attribute the reconnect cluster.
- `feature-contract-gap-audit` records only verified gaps and amendments after evidence exists.

The frontmatter does not fully encode that design. `feature-contract-gap-audit` has `depends_on: [feature-cross-side-observability]`, while both the epic and the feature body say reconnect/reachability contract claims are gated on reproduction evidence from `feature-reconnect-reproduction`. Either add `feature-reconnect-reproduction` to `depends_on`, or split the audit into (a) noncontroversial verified doc drift cleanup depending only on observability/harness evidence and (b) reconnect-contract audit depending on the reproduction feature.

### Finding 3 — "Harvest invariants from already-fixed stories" is a real activity if made evidence-cited, not hand-waving

The harvest track in `feature-contract-gap-audit` can be legitimate: read stories after review, identify the invariant the fix proved, and update `PROTOCOL.md` / `docs/ARCHITECTURE.md` with a current-state rule backed by the code path and test evidence. That is exactly the right direction for `story-fix-stale-ctx-wrapactionctx-crash`, `story-mobile-chat-blank-on-pair-after-pre-pair-work`, and `story-mobile-assistant-message-duplicated-live-replay`.

The risk is execution: the feature should require each harvested invariant to cite the source story, implemented code path, and verification evidence. Without that acceptance criterion, "harvest" could degrade into ungrounded summary prose.

### Finding 4 — `feature-reconnect-reproduction` avoids the original aggregation failure, but only if decomposed into per-bug repro stories

The feature does collect five unreproduced or partially attributed reconnect bugs, so it could recreate the old over-aggregation failure if implemented as one monolithic "reconnect contract" task. The body currently avoids that by saying each item must be reproduced, attributed to a specific surface, then classified as code defect vs genuine contract gap.

Feature-design should preserve that by spawning per-symptom reproduction stories with explicit evidence outputs. Do not let this feature advance by writing a general reconnect state machine without traces.

### Finding 5 — The bold-refactor release claim is factually correct

The reframe's load-bearing factual claim checks out. These files exist under `.work/releases/v0.6.0/` and their frontmatter says `stage: done`:

- `.work/releases/v0.6.0/epic-bold-canonical-session.md`
- `.work/releases/v0.6.0/epic-bold-transcript-event-log.md`
- `.work/releases/v0.6.0/epic-bold-reachability-contract.md`
- `.work/releases/v0.6.0/epic-bold-turn-state-machine.md`

So the reframe is correct that the contract audit should consume/amend those outputs instead of designing parallel contracts. The related `docs/ARCHITECTURE.md` "in-flight" wording remains doc drift to fix downstream.

### Finding 6 — Dependency ordering is mostly sound, but the contract audit edge is underspecified

The intended order is sound: observability first, reconnect reproduction second, contract audit last. The only inversion is that `feature-contract-gap-audit` is frontmatter-blocked only on observability while its reconnect-facing scope is evidence-blocked on the reproduction feature. Encode that edge or split the audit as noted above.

## Part 2: Relay implementation

### Finding 1 — Important privacy regression: full Pi pubkeys are now persisted in debug logs

`relay/src/handlers/pi_forward.rs` logs `from = sender_peer_id` and `to_pc = %frame.to_pc` in each new `debug!` line. Those are full Pi public keys. The relay skill says to prefer shortened peer tails, room ids, frame type names, byte counts, and coarse reasons; existing peer logging follows that pattern with `peer_short` in `relay/src/handlers/peer.rs` and `dest_tail` in `relay/src/handlers/connection_actor.rs`.

This is not payload leakage like `ct` or message bodies, but it is a privacy regression relative to the established convention, and it is amplified by the new persistent file sink. Fix by logging `from_tail` / `to_pc_tail` only. If full keys are ever needed for a one-off incident, require an explicit higher-risk diagnostic mode, not default debug file logs.

Severity: **Important (privacy/operational metadata).**

### Finding 2 — The envelope id tail is useful, but the comment overstates its safety

Logging `env_id_tail` is much safer than logging message bodies, and it matches the story's correlation goal. However, `AgentEnvelope.id` is currently just `String` in `relay/src/protocol/generated/cross_pc.rs`; the relay does not validate that it is a UUID v7 or even ASCII. By convention it is structural routing metadata, but by enforcement it is untrusted client-provided text.

The tail-only choice limits exposure, but the code comment should not claim the id is categorically non-payload unless the relay validates it at the boundary. Prefer either validating the id shape before logging, or wording the comment as "expected protocol metadata; log only a tail and never log the full id."

Severity: **Important (privacy boundary clarity).**

### Finding 3 — Blocker correctness bug: `id_tail` can panic on non-ASCII ids

`id_tail` uses byte indexing:

```rust
let len = id.len();
id[len.saturating_sub(8)..].to_string()
```

Short ASCII ids and empty ids are fine because `saturating_sub(8)` yields `0`. Non-ASCII ids longer than 8 bytes can panic if the computed byte offset lands inside a UTF-8 code point. Because `AgentEnvelope.id` is unvalidated input, an authenticated peer can send a malformed/non-ASCII id and crash the connection task on the debug path (`not_authorized`, `forwarded`, or `offline`).

Fix with a char-boundary-safe helper, e.g. collect the last eight `chars()` or validate the id as ASCII/UUID before slicing. Add unit tests for empty, short ASCII, normal UUID, and non-ASCII ids.

Severity: **Blocker (untrusted-input panic / denial-of-service on the relay task).**

### Finding 4 — Tracing guard lifecycle is correct for graceful shutdown, with the usual caveats

`init_tracing()` returns `Option<WorkerGuard>`, and `main` holds it in `_log_guard` for the process lifetime. That is the correct lifecycle for `tracing_appender::non_blocking`; the guard flushes buffered file records when dropped during normal shutdown. If `REMOTEPI_RELAY_LOG_DIR` is unset, returning `None` is fine because no file writer exists.

Caveats: logs are not guaranteed on `SIGKILL`, abort, or container hard kill. Also, `tracing_subscriber::registry().init()` panics if a global subscriber is already installed. That behavior is not newly worse than the prior `tracing_subscriber::fmt::init()` in the binary, but if this function becomes test-invoked or library-exposed, switch to `try_init()`/error handling.

Severity: **No blocker; note for hardening.**

### Finding 5 — Borrow/move logic is correct; the comment is inaccurate

The implementation moves `frame.envelope` into `outbound`, then reads `outbound.envelope.id` for the tail. That is logically correct and avoids borrow-after-move. Continued use of `frame.to_pc` and `frame.to_room` after moving `frame.envelope` is valid because those fields were not moved.

The comment says "Capture the envelope id tail before `frame.envelope` is moved into `outbound` above," but the code captures it after the move from `outbound`. Fix the comment to match the code.

Severity: **Nit.**

### Finding 6 — Logging behavior is not tested, and the story acceptance is not fully evidenced

No tests were added for the new logging behavior. Existing `pi_forward.rs` tests assert `PiForwardResult` and transport-error shapes, not emitted `debug!` lines or `id_tail` behavior. It is acceptable not to deeply assert tracing formatting, but this story's acceptance criteria explicitly say a forwarded `pi_envelope` emits a debug line and dropped forwards carry the id. At minimum, the helper should have unit tests, and either a small tracing capture test or a manual verification note should record the exact command/output used.

There is also an acceptance mismatch: the story says a dropped forward emits the existing `warn!` plus the id, but the implementation adds `debug!` for `not_authorized` and `offline`; it does not add an id-bearing warn on the pi-envelope offline path. Decide whether debug-only is the intended no-INFO-spam behavior and update the story, or add the warn required by the acceptance criterion.

Severity: **Important (acceptance evidence gap).**

### Finding 7 — The auth test reformat is harmless but stray

The `relay/src/auth/auth_test.rs` change is a `cargo fmt` import reflow. It is harmless and common when running `cargo fmt`, but it is unrelated to the story. No action needed unless the operator wants ultra-minimal diffs.

Severity: **Nit.**

## Part 3: Process

### Repo-state check

`git status --short` and `git diff --stat` show the repo is not a clean relay-only review state:

- Relay logging files are modified: `relay/Cargo.toml`, `relay/Cargo.lock`, `relay/src/main.rs`, `relay/src/handlers/pi_forward.rs`, plus `relay/src/auth/auth_test.rs` fmt reflow.
- The reframed epic and new feature/story files are modified/untracked under `.work/`.
- There are unrelated-looking pi-extension modifications: `pi-extension/src/session/remote_session.ts`, `remote_session.test.ts`, and `transcript_projection.ts`.
- There are untracked `*.key` and `*.pem` files at repo root. These look like key material and must not be committed; verify whether they are test fixtures, move them out of the repo, or add an intentional ignore only if they are local secrets.

### Story-status accuracy

`story-app-persistent-ring-log.md` is accurate: it says design seed only and the app attempt was reverted; status shows no app code changes.

`story-relay-retroactive-file-logging.md` is accurate in its body that the relay half was implemented, but its frontmatter is still `stage: drafting` and the acceptance checkboxes are unchecked. That is a process bug. For a tiny inline slice, implementation without a full design cycle is understandable, but the work item should be advanced honestly (`drafting` → `implementing` → `review`) or rewritten as a completed/review-ready story before release. The current frontmatter says "not started" while the body says "implemented," which will confuse automation and reviewers.

The broader process concern is that the operator asked for logging stories to be scoped and built as work items, but the app half was attempted inline and had to be reverted. The current app story is honest about that cleanup; keep it clean by designing it before the next implementation attempt.

## Action items

1. **Fix `id_tail` before marking the relay story done** (`relay/src/handlers/pi_forward.rs`): make it UTF-8-safe or validate ids as ASCII/UUID before slicing; add tests for empty, short, UUID, and non-ASCII ids.
2. **Shorten peer identifiers in new debug logs** (`relay/src/handlers/pi_forward.rs`): replace full `sender_peer_id` / `to_pc` with tail helpers consistent with `peer_short` / `dest_tail` patterns.
3. **Clarify envelope-id privacy language** (`relay/src/handlers/pi_forward.rs`, `relay/src/main.rs`, `.work/active/stories/story-relay-retroactive-file-logging.md`): say tail-only protocol metadata, not categorically non-payload unless validated.
4. **Resolve the dropped-forward logging acceptance mismatch** (`.work/active/stories/story-relay-retroactive-file-logging.md`, `relay/src/handlers/pi_forward.rs`): either update acceptance to debug-only or add the promised id-bearing warn.
5. **Add acceptance evidence for relay logging** (`.work/active/stories/story-relay-retroactive-file-logging.md`): record tests/manual command for `REMOTEPI_RELAY_LOG_DIR` and `RUST_LOG=debug`; keep `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` evidence.
6. **Advance or bounce story stage honestly** (`.work/active/stories/story-relay-retroactive-file-logging.md`): it should not remain `stage: drafting` after implementation.
7. **Encode the contract audit's dependency on reproduction** (`.work/active/features/feature-contract-gap-audit.md`): add `feature-reconnect-reproduction` to `depends_on` or split the noncontroversial doc cleanup from the reconnect evidence audit.
8. **Quarantine untracked key material** (repo root `*.key`, `*.pem`): remove from the working tree or verify as intentional non-secret fixtures; do not commit them.
