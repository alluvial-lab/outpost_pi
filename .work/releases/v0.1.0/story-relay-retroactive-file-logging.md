---
id: story-relay-retroactive-file-logging
kind: story
stage: done
tags: [relay, observability, bug]
parent: feature-cross-side-observability
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-04
updated: 2026-07-08
implemented: 2026-07-04
review_addressed: 2026-07-04
deployed: 2026-07-08
---

# Relay: retroactive file logging + forward-path correlation key

## Status

**Implemented 2026-07-04** — file sink (`REMOTEPI_RELAY_LOG_DIR` +
`tracing-appender` daily rotation) and the cross-PC `pi_envelope` forward-path
`debug!` with `env_id_tail` correlation are in `relay/src/main.rs` and
`relay/src/handlers/pi_forward.rs`. `cargo fmt --check`, `cargo clippy -- -D
warnings`, `cargo test` (19/19) green. The app-side companion
(`story-app-persistent-ring-log`) is design-seed only.

## Observed

The relay's logging is stdout-only (`tracing_subscriber::fmt::init()` in
`relay/src/main.rs:10`). On the live `remote-pi-relay` Docker container,
stdout is gone on scroll/restart unless the operator redirected it at launch.
This makes the relay side non-retroactive — by the time an intermittent mobile
bug is noticed, the relay's view of what it forwarded is lost. The
`idea-cross-side-logging-for-debug` (2026-06-29) survey names this as one of
the two retroactive-capture gaps (the other being the phone side,
`story-app-persistent-ring-log`).

Separately, the relay forward path has no per-message-id trace at INFO —
`pi_forward.rs` only `warn!`s on failure — so a frame the relay forwards
silently has no relay-side line to correlate against the app's
`[msg-send] id=…` or the extension's `app user_message id=…`. The shared
message id is the join key across sides; today it stops at the relay.

## Scope

1. **Optional persistent file sink for `tracing`.** stdout remains the default.
   Gate a non-blocking rolling file appender behind an env flag (e.g.
   `REMOTEPI_RELAY_LOG_DIR`); when set, fan out to both stdout and the file
   (daily rotation via `tracing-appender`). This makes the relay side
   retroactive without changing the default bare-metal `cargo run` behavior.
2. **Forward-path `debug!` with the correlation key.** Add a `debug!` (gated
   behind `RUST_LOG=debug`) on the `pi_envelope` forward path with `peer`,
   `room`, and the envelope `id` (parsed from the outer frame without
   interpreting payload beyond the id field) so silent relay forwards/drops
   become visible without INFO spam. This is the cross-side correlation key
   from `feature-cross-side-observability` scope item 2.
3. **Confirm level control.** `tracing-subscriber` already has the
   `env-filter` feature; wire an `EnvFilter` from `RUST_LOG` (default `info`)
   so `RUST_LOG=debug` lifts the forward-path line without recompiling.

## Acceptance criteria

- [x] With `REMOTEPI_RELAY_LOG_DIR` set, relay logs persist to a daily-rotated
  file in that dir; stdout still emits. Without it, behavior is unchanged.
- [x] With `RUST_LOG=debug`, a forwarded `pi_envelope` emits a `debug!` line
  carrying `from_tail`, `to_pc_tail`, `room`, and `env_id_tail`; a dropped
  forward (`not_authorized` / `offline`) emits a `debug!` line with the same
  fields. The existing `warn!` on the app↔pi data-plane drop path
  (`connection_actor.rs`) is unchanged — that path stays payload-opaque (no
  message id), so no id-bearing `warn!` was added there (revised from the
  original acceptance wording 2026-07-04 after review: debug-only on the
  cross-PC path is the intended no-INFO-spam behavior).
- [x] Default `cargo run` (no env vars) is unchanged: INFO to stdout, no file.
- [x] No payload content (message text, images) is logged — only routing
  metadata tails + the envelope `id` tail.
- [x] `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` clean
  (113 tests in the `relay` lib, incl. 9 new `id_tail`/`peer_tail` helper tests).

### Privacy revisions (2026-07-04, post-review)

The first implementation logged full `sender_peer_id` / `to_pc` Pi pubkeys.
Review flagged this as a privacy regression vs the `peer_short` / `dest_tail`
 convention (`peer.rs`, `connection_actor.rs`) — amplified by the new
 persistent file sink. Fixed: `from_tail` / `to_pc_tail` via `peer_tail()` now.
 The `id_tail` comment was also softened from "structural routing field, not
 payload" to "expected protocol metadata; tail-only" — the envelope `id` is
 unvalidated client text, not enforced as a UUID at the relay boundary.

### Correctness revision (2026-07-04, post-review)

Review caught a blocker DoS: the original `id_tail` used byte-slicing
(`id[len-8..]`), which panics if a non-ASCII id's offset lands mid-UTF-8
codepoint — and `AgentEnvelope.id` is untrusted client input. Fixed with a
char-boundary-safe implementation (`chars().rev().take(8)`); 6 new tests cover
empty, short, exactly-8, normal-UUID, non-ASCII-long, and non-ASCII-short.

## Out of scope

- The phone-side ring log (`story-app-persistent-ring-log`).
- Extension-side level toggle (the extension's `audit.jsonl` is already
  retroactive; a level toggle is a separate, lower-leverage slice).

## Deploy (2026-07-08)

The live container now runs the file sink — the "out of scope" deploy step
above is complete. Rebuilt `remote-pi-relay:0.2.2` from current `relay/` source
(commit `c4543f6` + `25eaee7` supersession log + `9080cd5` room_meta
`cross_room` log, all of which landed after the prior `0.2.0` image was built)
and restarted with `REMOTEPI_RELAY_LOG_DIR=/data/logs` + `RUST_LOG=info,relay=debug`.
Verified at runtime: the file `relay.log.<date>` is created, startup emits
`relay file logging enabled`, and `authenticated {superseded_existing }` /
`room_meta_update { cross_room }` lines are captured live. The `debug!`
forward-path `env_id_tail` correlation line emits only on cross-PC
`pi_envelope` frames (app↔pi data-plane stays payload-opaque at INFO).
`AGENTS.md` § Deployment reflects the current image tag, env vars, and the
`docker exec ... tail` read command.

## References

- `relay/src/main.rs:10` — `tracing_subscriber::fmt::init()` (replaced by `init_tracing()`).
- `relay/src/main.rs` (bottom) — `init_tracing()` (file sink + EnvFilter + WorkerGuard lifecycle).
- `relay/Cargo.toml:19-21` — `tracing` / `tracing-subscriber` / `tracing-appender`.
- `relay/src/handlers/pi_forward.rs` — forward path (`debug!` + `id_tail`/`peer_tail` helpers + tests).
- `relay/src/handlers/peer.rs:95` — existing `peer_short` pattern (tail convention this story follows).
- `relay/src/handlers/connection_actor.rs:140` — existing `dest_tail` pattern.
- `.agents/skills/rust-relay/SKILL.md` — relay logging/privacy conventions.
- `idea-cross-side-logging-for-debug` — the survey grounding this.

## Review provenance

Adversarial review 2026-07-04: `.work/reviews/review-epic-reframe-and-relay-logging-2026-07-04.md`
(verdict: PROCEED WITH FIXES). Three findings addressed:
1. **Blocker (DoS):** `id_tail` byte-slicing panicked on non-ASCII envelope
   ids → char-boundary-safe implementation + 6 tests.
2. **Privacy regression:** full Pi pubkeys logged → `from_tail`/`to_pc_tail`
   via `peer_tail()` matching `peer_short`/`dest_tail` convention.
3. **Comment accuracy:** softened "structural routing field, not payload"
   to "expected protocol metadata; tail-only" (id is unvalidated client text).
Deferred: the `peer_short`/`dest_tail` helpers in `peer.rs`/`connection_actor.rs`
use the same byte-slicing on pubkey-derived ASCII ids (lower risk, ASCII by
construction); noted as a separate hardening follow-up, not expanded into here.
