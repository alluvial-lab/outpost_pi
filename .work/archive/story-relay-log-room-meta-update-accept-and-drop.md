---
id: story-relay-log-room-meta-update-accept-and-drop
kind: story
stage: done
tags: [relay, observability, bug]
parent: null
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-06
updated: 2026-07-06
archived_atop: v0.6.0
git_ref: 9080cd5
---

# Log `room_meta_update` accept/drop (with cross-room flag) at INFO

## Why

`story-mobile-cross-session-history-leak` (Bug 2) is parked because the relay
does not emit any log line when it accepts or drops a `room_meta_update` frame.
The refined open question is: **does the extension ever send
`room_meta_update` for a room the process did NOT register (a sibling room
id)?** Under the shared-owner-epk topology (all 4 dev-VM Pis auth as
`l2X/dUc=`), a sibling patch for room `7ADky` resolves to key
`(l2X/dUc=, 7ADky)` which EXISTS, so the relay would accept it and overwrite
`7ADky`'s `session_id` — the candidate leak path. Today that path is invisible
in relay logs; triage requires the extension's own debug log or a decoded
ring-log `room_meta_updated` payload. A relay INFO line would make the leak
detectable from relay logs alone.

The existing drop branch already logs at WARN
(`control.rs:154-158`, "room_meta_update for unknown (peer, room), dropping")
but the **accept** branch is silent, and neither branch records whether the
target room matches the sender's own authenticated room — the exact signal
that distinguishes a self-patch from a sibling-patch.

## Goal

Add INFO logging to the `room_meta_update` handler so each accepted patch
records: sender peer tail, target room, authed room, and which patch field
changed — WITHOUT logging any field VALUES (session_id is endpoint-owned
opaque data per the relay privacy posture; see `pi_forward.rs` header). The
`authed_room != target_room` mismatch is the leak signal.

## Scope

- `relay/src/handlers/control.rs` — `room_meta_update` handler.
- Keep the existing unknown-`(peer,room)` WARN drop branch as-is.
- Add INFO on the accept branch (both empty-patch no-op and non-empty broadcast).

## Privacy posture (must preserve)

The relay treats `session_id` / `model` / `thinking` as endpoint-owned opaque
data and must NOT log their values (precedent: `pi_forward.rs` header — "does
not parse it, derive targets from it, log it"). Log only:

- `peer` = `self.actor.peer_short` (8-char tail, existing convention).
- `room` = `target_room` (room ids are not secrets — they already appear in
  INFO auth/disconnect lines: `peer.rs:104`, `peer.rs:207`).
- `authed_room` = `self.actor.room_id` (the room this connection authenticated
  in — same exposure level as `room`).
- `fields` = the set of patch fields present, as a short token list
  (`["session_id","working"]`), never the values. A field being PRESENT is
  protocol metadata (the patch declared it); its VALUE is opaque.

The `authed_room != room` comparison is the load-bearing signal: a sender
patching a room it didn't auth into is the cross-room leak signature.

## Design

In `room_meta_update` (`control.rs:143-171`), after `apply_patch` succeeds:

```rust
let cross_room = target_room != self.actor.room_id;
let fields: Vec<&str> = [
    frame.meta.model.as_ref().map(|_| "model"),
    frame.meta.thinking.as_ref().map(|_| "thinking"),
    frame.meta.session_id.as_ref().map(|_| "session_id"),
    frame.meta.working.map(|_| "working"),
].into_iter().flatten().collect();

if is_empty_patch {
    info!(
        peer = %self.actor.peer_short,
        room = %target_room,
        authed_room = %self.actor.room_id,
        cross_room,
        fields = ?fields,  // empty
        "room_meta_update no-op (empty patch)"
    );
} else {
    info!(
        peer = %self.actor.peer_short,
        room = %target_room,
        authed_room = %self.actor.room_id,
        cross_room,
        fields = ?fields,
        "room_meta_update applied"
    );
    // existing publish_room_meta_updated call unchanged
}
```

Notes:
- `fields` is `Vec<&str>`; `?fields` renders as the array debug form. Keep it
  short — only field names, never values.
- `cross_room: bool` makes `grep cross_room=true` the one-line triage query.
- The existing WARN drop for unknown `(peer, room)` already covers the
  reject path; optionally add `authed_room` + `cross_room` there too for
  symmetry, but it's not load-bearing (a drop can't leak).
- `info!` not `debug!`: the default `RUST_LOG` is `info` (`main.rs:110`), so
  INFO surfaces by default in the live container; DEBUG would require setting
  `RUST_LOG`. This is a triage signal that should be on without reconfiguring.

## Acceptance Criteria

- [ ] Every accepted `room_meta_update` (non-empty AND empty-patch) emits one
      INFO line with `peer`, `room`, `authed_room`, `cross_room`, `fields`.
- [ ] No patch field VALUE is ever logged (`session_id`/`model`/`thinking`
      values absent); only field-name presence in `fields`.
- [ ] `cross_room=true` when `target_room != self.actor.room_id`, else `false`.
- [ ] Existing WARN drop for unknown `(peer, room)` still fires and is
      unchanged in behavior (optionally augmented with `authed_room`/`cross_room`).
- [ ] Existing `room_meta_update_dispatches_through_typed_actor_handler` test
      (`control.rs:403`) still passes (behavior unchanged; the INFO line is
      side-effect-only and not asserted there).
- [ ] New unit test: a `room_meta_update` whose `room_id` differs from the
      actor's authenticated `room_id` produces an applied patch AND the INFO
      line carries `cross_room=true`. Assert on the observable effect
      (subscriber receives `room_meta_updated` for the target room) since
      there is no tracing-test dep to assert log text directly. Optionally
      assert the empty-patch no-op path does NOT broadcast.
- [ ] `cargo fmt --check && cargo clippy -- -D warnings && cargo test` green
      in `relay/`.
- [ ] Manual: rebuild the relay image, swap the container, reproduce a
      cross-room patch from a second Pi process (shared owner epk) and
      confirm `cross_room=true` appears in `docker logs remote-pi-relay`.

## Out of scope

- Changing the `room_meta_update` accept/reject policy (this only observes;
  the shared-peer_id cross-room accept is a separate decision tracked in Bug 2).
- Logging `session_history` or `agent_message` delivery (different paths;
  not the bottleneck for Bug 2).
- Adding a relay admin/state endpoint for live room inspection (larger;
  separate story).
- Backfilling the WARN drop branch with `authed_room` (optional, not load-bearing).

## References

- `relay/src/handlers/control.rs:143-171` — `room_meta_update` handler
  (accept branch silent; drop branch WARN at `:154`).
- `relay/src/handlers/connection_actor.rs:81-84` — `peer_id`, `peer_short`,
  `room_id`, `conn_id` available on the actor.
- `relay/src/protocol/generated/room.rs:29-34` — `RoomMetaPatch` fields
  (`model`, `thinking`, `session_id`, `working`).
- `relay/src/handlers/pi_forward.rs:1-14` — privacy posture: relay does not
  log endpoint-owned opaque values (session_id precedent).
- `relay/src/main.rs:110` — default `EnvFilter::new("info")`, so INFO surfaces
  in the live container without `RUST_LOG`.
- `relay/src/handlers/peer.rs:104,207` — precedent: room_id already appears
  in INFO auth/disconnect lines.
- `.work/active/stories/story-mobile-cross-session-history-leak.md` — Bug 2,
  the investigation this unblocks (the "refined open question" acceptance
  criterion).

## Implementation notes

- **Files changed**: `relay/src/handlers/control.rs` (single file).
- **Handler**: `room_meta_update` now computes `cross_room =
  target_room != self.actor.room_id` and a `fields: Vec<&str>` of present
  field names (never values) before `apply_patch`. The accept branch logs
  INFO on both the empty-patch no-op and the non-empty broadcast paths;
  the existing unknown-`(peer,room)` WARN drop was augmented with
  `authed_room` + `cross_room` for symmetry (cheap, and makes the grep
  uniform across both branches — the operator-flagged optional decision).
- **Import**: `use tracing::warn;` → `use tracing::{info, warn};`.
- **Tests added** (in `control.rs` mod tests):
  - `room_meta_update_targets_a_room_the_sender_did_not_auth_into` —
    models the shared-owner-epk topology (two `pi` connections in `main`
    and `other`), patches `other` from an actor authed in `main`, asserts
    the broadcast targets `other` (the observable proof of cross-room
    accept). The `cross_room=true` INFO line itself is not asserted (no
    `tracing-test` dep); verified by the manual criterion + source read.
  - `room_meta_update_empty_patch_does_not_broadcast` — asserts an empty
       patch does not broadcast `room_meta_updated` (the no-op half).
- **Discrepancies from design**: none. The design's optional
  "augment the WARN drop branch" was adopted (see handler note) for grep
  symmetry; all other fields/behavior match the spec exactly.
- **Adjacent issues parked**: none.
- **Verification**: `cargo fmt --check` ✓ (after applying fmt),
  `cargo clippy -- -D warnings` ✓ (0 warnings), `cargo test` ✓
  (116 unit + 19 rooms integration + others all pass, including the 2
  new tests).
- **Privacy**: confirmed no patch field VALUE is logged — only field-name
  presence in `fields`. `session_id`/`model`/`thinking` values are never
  emitted, consistent with `pi_forward.rs` posture. `room`/`authed_room`
  are room ids (already in INFO auth lines at `peer.rs:104,207`).
- **Manual criterion (not yet run)**: rebuild relay image, swap container,
  reproduce a cross-room patch from a second Pi process (shared owner epk),
  confirm `cross_room=true` in `docker logs`. Deferred to the operator/
  deploy step — the unit test proves the accept path; the manual step proves
  the live-container surfacing at default `RUST_LOG=info`.

## Review (2026-07-06)

**Verdict**: Approve - story verified by implement; fast-lane advance

**Blockers**: none
**Important**: none
**Nits**:
- The `cross_room=true` INFO line is asserted transitively (observable
  broadcast targets the patched room) rather than directly, because there
  is no `tracing-test` dep. Acceptable for a story; the manual acceptance
  criterion (rebuild + live repro) covers the live-container surfacing.

**Notes**: Substrate mode, fast lane (story item, green verification).
Independently re-verified `cargo fmt --check` + `cargo clippy -- -D warnings`
(0 warnings) + `cargo test` (116 unit + 19 rooms integration, all pass, incl.
2 new tests). Re-examined the two load-bearing claims rather than
rubber-stamping implement notes: (1) privacy — grep confirms only
field-name tokens emitted, no `session_id`/`model`/`thinking` values;
(2) cross-room test genuinely exercises the path (Fixture::actor hardcodes
room_id="main", patch targets "other", so cross_room is truly true).
Archived with body kept (retain-bodies convention), archived_atop=v0.6.0.
