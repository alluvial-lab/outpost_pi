---
id: story-relay-duplicate-auth-supersession-log
kind: story
stage: drafting
tags: [relay, observability, bug]
parent: feature-cross-side-observability
depends_on:
  - story-relay-retroactive-file-logging
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-05
---

# Relay: log duplicate-auth supersession timing (the relay half of takeover proof)

## Brief

The app-side `conn-channel-lost {stale}` event (`story-app-capture-routing`)
proves what the **app** did with a stale channel's `onDone`. But the
`idea-mobile-drop-half-open-tcp` bug's literal question is relay-side: **did
the relay accept the new connection and kick the old one immediately on
duplicate auth, or did the old connection linger until ping timeout?** That
half isn't observable today — the relay logs `authenticated` at `peer.rs:99`
but doesn't distinguish a fresh peer from a duplicate reconnect superseding
an existing one.

This is the relay half of the cross-side takeover proof. Paired with the
app `conn-channel-lost {stale}` event, it attributes the ~5min recovery
window from `idea-mobile-drop-slow-recovery`:
- relay shows immediate supersession + app shows `stale:false` + long
  `delayMs` → bottleneck is **app backoff**.
- relay shows ping-timeout supersession (old conn lingered) → bottleneck is
  **relay detection speed**.
- app shows `stale:true` (correctly ignored) but user still saw a stall →
  bottleneck is **something else** (send queue, session gate, UI projection).

Without both halves, the bug stays anecdotal — which is why it's a gap today.

## Scope

- Enhance the `authenticated` log at `relay/src/handlers/peer.rs:99` (or the
  register call at `:104`) to note when a conn is a duplicate superseding an
  existing one at `(peer_id, room_id)`. The relay knows this —
  `registry.register` finds an existing conn for the key.
- Add a `superseded_existing: true/false` field (or a distinct
  `authenticated_superseded` event) at `info!` level so it's retroactive via
  the file sink from `story-relay-retroactive-file-logging` (no `RUST_LOG=debug`
  needed — this is a state transition, not per-frame).
- Optionally: log when the superseded old conn is actually closed (the relay's
  `disconnected` line at `peer.rs:200`), so the supersession→close gap is
  measurable. Confirm whether the relay eagerly closes the old conn on
  duplicate auth or waits for it to time out.

## Acceptance criteria

- [ ] A duplicate auth (same `(peer_id, room_id)` as an existing live conn)
      emits a log line marking `superseded_existing: true` (or equivalent).
- [ ] A fresh auth (no existing conn) emits `superseded_existing: false` (or
      no field — the default).
- [ ] The supersession→old-conn-close gap is measurable from the logs (either
      an eager close right after supersession, or a timeout-bounded close).
- [ ] No payload content logged — only peer tail, room, addr, supersession
      fact (matches the relay privacy convention).
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` clean
      (new test for the duplicate-auth log).

## Out of scope

- The app-side `conn-channel-lost {stale}` event (`story-app-capture-routing`).
- Changing the relay's duplicate-connection cleanup behavior (this story only
  makes the existing behavior observable — the `idea-mobile-drop-half-open-tcp`
  "should duplicate-auth immediately supersede?" question is answered by
  observation first, behavior change deferred).

## References

- Parent: `feature-cross-side-observability.md` (Unit 4b, the `conn-channel-lost`
  event's relay-side companion).
- `relay/src/handlers/peer.rs:99` — `authenticated` log.
- `relay/src/handlers/peer.rs:104` — `registry.register` (knows the duplicate).
- `relay/src/handlers/peer.rs:200` — `disconnected` log (the old conn's close).
- `relay/src/peers/registry.rs:358,397` — duplicate-conn handling tests.
- `.work/backlog/idea-mobile-drop-half-open-tcp.md` — the question this answers.
- `.work/backlog/idea-mobile-drop-slow-recovery.md` — the ~5min recovery this
  attributes.
- Review v2: `.work/reviews/review-feature-cross-side-observability-design-v2-2026-07-04.md`
  (the "where proven" question — answer: both sides; this is the relay half).
