---
id: feature-contract-gap-audit
kind: feature
stage: review
tags: [pi-extension, app, relay, docs]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on:
  - feature-cross-side-observability
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-19
---

# Contract gap audit (evidence-sourced, static tracks unblocked)

## Brief

**Demoted and renamed** from the original "targeting & delivery contract" and
"session-lifecycle contract" features. The 2026-07-04 adversarial review
showed that the original contract-first framing (a) over-aggregated confirmed
code defects and unreproduced hypotheses, (b) duplicated work already
shipped by the released bold-refactor epics, and (c) risked canonizing
unverified assumptions as current-state truth. This feature is now a narrow,
evidence-sourced **audit** that consumes/amends the released bold outputs and
harvests invariants from already-fixed stories — NOT a parallel
contract-design pass.

## Scope

### A. Targeting facts missing from `PROTOCOL.md`
`docs/ARCHITECTURE.md` already pins canonical `session_id`, relay-opaque
routing, room-targeted cross-PC, and fail-closed app session gates. The
genuine gap is narrower than the original draft claimed:
- `owner_pk` is per-machine, not per-Pi-process (the App pairs with a machine).
- `room_id` is per-`(cwd, assigned-name)`; the cwd-lock disambiguates; two
  same-named pis in one room is a lock violation, not a supported topology.
- Relay forwarding is fanout to every conn at `(owner_pk, room)` (intentional
  for multi-device owners).
- A `user_message` targets one Pi session via `session_id`.

Audit against code (`relay/src/peers/connections.rs:send_to_room`,
`registry.rs:30-45`, `pi-extension/src/rooms.ts`, `pairing/storage.ts`), don't
invent. Cross-reference with `docs/ARCHITECTURE.md` rather than duplicating.

### B. Typed error-code spike (feasibility, not confirmed scope)
Disambiguate the single `session_mismatch` into `session_superseded` (phone's
session_id is stale → re-sync) vs `not_my_session` (message was for a
different pi → silent drop). BUT `story-foreign-session-user-message-tolerance`
shows the extension **cannot** distinguish duplicate-delivery from legitimate
stale re-sync without cross-process sibling state. So:
- Run this as a **feasibility spike**: can the extension's session parent-chain
  distinguish "predecessor of my current session" from "unrelated session id"
  within one process? Does that suffice under multi-connection fanout?
- Tests for both cases (wrong-pi duplicate delivery does not render an error;
  legitimate stale session still triggers re-sync) gate any wire change.
- If parent-chain/sibling state is unavailable, prefer an app-side handling
  rule scoped to `user_message` replies plus `session_sync` behavior rather
  than a premature wire change.

### C. Session-lifecycle / transcript-identity invariants (harvested after review)
Harvest from already-fixed stories **after** their review lands — record the
discovered invariant, don't pre-write it:
- `story-fix-stale-ctx-wrapactionctx-crash` (done in v0.1.0) — harvest the
  discovered rule for guarded reads from session-scoped SDK contexts.
- `story-mobile-chat-blank-on-pair-after-pre-pair-work` (done in v0.1.0) —
  harvest the durable-SDK-source / typed-replay-log invariant.
- `story-mobile-assistant-message-duplicated-live-replay` (done and live-
  verified in v0.1.0) — harvest the canonical transcript-event identity rule
  established by its extension, app, and replay tests.

### D. SDK stale-context seam (from the harness, not prose)
The harness established that plain `session_start` context does not carry
`sendUserMessage`; message delivery belongs to the factory `ExtensionAPI` or a
`ReplacedSessionContext`. The later real-SDK investigation in
`story-fix-stale-ctx-messageapi-rearm-on-reload` (done in v0.1.0) found the
actual bug was process-global ownership: child session factories could replace
the parent's live API. `OutpostPiRuntimeCoordinator` now admits one phone-facing
owner lease and treats child factories as satellites. Record that discovered
seam; do not retain the superseded "SDK-blocked" premise.

### E. `docs/ARCHITECTURE.md` bold-DAG drift
`docs/ARCHITECTURE.md` calls the bold refactor DAG "in-flight," but the four
overlapping epics are `stage: done` in `.work/releases/v0.6.0/`. Rewrite that
section current-state (rolling-foundation) as part of this audit.

## Consumed outcomes

Both formerly downstream fixes are already done in v0.1.0:

- `story-foreign-session-user-message-tolerance` shipped the app-side
  convergence rule retained by Track B.
- `story-fix-stale-ctx-messageapi-rearm-on-reload` shipped the runtime ownership
  coordinator consumed by Track D.

## Out of scope

- The observability infrastructure (`feature-cross-side-observability`).
- The reconnect cluster attribution (`feature-reconnect-reproduction`).
- Re-designing what the released bold epics already shipped — consume/amend,
  not duplicate.
- The `#2` stale-error repro (separate observe-and-diagnose task).

## Residual decisions

- Typed mismatch subcodes are not feasible at the extension boundary; Track B
  retains the existing app-side convergence rule and makes no wire change.
- `session_started_at` still merits a separate design pass because the extension
  reports relay-start/reset time while the SDK exposes a session-header
  timestamp. Parked as `idea-session-started-at-sdk-header`; this audit does not
  choose new wire semantics.

## Seed material

`.work/drafts/draft-protocol-targeting.md` — retained as background for the
targeting audit. The "collision conditions" section is INVALIDATED per
operator Q2 (no cross-room collision occurred; the stale error was in `#2`'s
own session) and is not evidence for a durable contract claim.

## Split decision (2026-07-19)

The physical-phone dependency applied only to reconnect-derived attribution,
not to Tracks A–E. The feature-level dependency on
`feature-reconnect-reproduction` was removed so the static code/release audit
can proceed. The residual live-evidence pass is isolated as
`story-reconnect-derived-contract-claims-audit`, dependent on
`idea-mobile-drop-slow-recovery` and
`idea-mobile-outgoing-message-swallowed`.

Track B is the only implementation-sized static checkpoint and is tracked as
`story-contract-gap-session-error-feasibility`. It is a feasibility result plus
existing regression evidence; no wire change is presumed.

## Implementation

Execution used direct repository reads only. This is an evidence harvest over
bounded, named code and terminal release items; exploratory delegation would
have duplicated the already-reviewed evidence.

### Track A — targeting facts audited and pinned

Landed the missing current-state facts in the canonical root `PROTOCOL.md`,
with `docs/ARCHITECTURE.md` as the session-model cross-reference:

- **Machine-scoped pairing:** `pi-extension/src/pairing/storage.ts` stores Owner
  public keys in the machine-global `~/.pi/remote/peers.json`; processes do not
  own separate pairing rosters.
- **Room derivation and lock:** `pi-extension/src/rooms.ts::roomIdFor` hashes
  `(realpath(cwd), assigned-name)` while preserving the default-name legacy id.
  `pi-extension/src/session/cwd_lock.ts` delegates to the same derivation, so a
  same-cwd/same-assigned-name process is a lock conflict rather than a supported
  duplicate room.
- **Exact-room fanout:** `relay/src/peers/connections.rs::send_to_room` selects
  one `(peer_id, room_id)` vector and `deliver` copies to each live entry;
  `relay/src/peers/registry.rs` documents this as `(owner_pk, room_id)` delivery
  with sender skipping for multi-device Owners.
- **One session per prompt:** `pi-extension/src/session/session_gate.ts` rejects
  a `user_message` whose `session_id` is missing or differs from the active SDK
  session before delivery. The relay remains session-opaque.

No collision claim from `.work/drafts/draft-protocol-targeting.md` was carried
forward.

### Track B — typed error feasibility rejected

`story-contract-gap-session-error-feasibility` records the static trace and is
done. The installed SDK exposes only an optional parent session *path* in the
current header; normal Outpost-Pi `session_new` does not populate it, and even
fork lineage cannot reveal a different process at the same relay fanout key.
The extension therefore cannot reliably classify predecessor vs unrelated
session ids in the general case.

No `session_superseded` / `not_my_session` codes were added. The already-shipped
app-side rule remains correct: foreign mismatch replies fail the app session
gate, accepted mismatches are non-transcript control, and canonical room
metadata rotation triggers resync. The two required cases are covered in
`app/test/data/sync/sync_service_test.dart`'s `session_mismatch tolerance`
group; extension fail-closed rejection remains covered by
`pi-extension/src/session/session_gate.test.ts`.

### Track C — reviewed lifecycle and transcript invariants harvested

The three v0.1.0 stories establish these rules:

1. **SDK context reads are session-scoped operations.** Guard property reads as
   well as calls; a stale getter can throw synchronously. The current
   `SdkSessionProjection.wrapActionCtx` and `remote_session.ts` resolver degrade
   stale bindings without crashing the relay router.
2. **The SDK session is durable truth; the extension log is a typed replay
   adapter.** `bindSessionContext` backfills from
   `sessionManager.buildSessionContext()`, maps through the shared transcript
   mapper, and dedupes into the append-only log. Resume history does not depend
   on live `message_end` hooks having observed the original turn.
3. **One logical transcript event has one deterministic identity across live
   and replay.** The `message_end` path emits stable `ts` / `message_id` facts;
   app live and history paths derive the same event key. Legacy duplicate
   broadcasts/stream-buffer commits are removed or guarded.

The durable current-state form landed in `docs/ARCHITECTURE.md`; implementation
history remains in the released stories and pattern references.

### Track D — SDK seam consumed from the real harness

`story-session-replacement-harness` proved plain `session_start` contexts lack
message delivery methods and that replaced contexts go stale. The subsequent
real-SDK runtime work in `story-fix-stale-ctx-messageapi-rearm-on-reload`
identified the operative seam: stock replacement creates a fresh factory API,
but same-process child factories could overwrite a module-global binding.

The shipped `OutpostPiRuntimeCoordinator` owns the solution: an approved
factory lease binds the phone-facing `ExtensionAPI` at `session_start`; child
factories remain satellites; only the active owner can tear down or replace
resources. `docs/ARCHITECTURE.md` now states that current ownership boundary
without preserving the superseded SDK-blocked explanation.

### Track E — rolling architecture drift removed

Rewrote `docs/ARCHITECTURE.md` from future/in-flight bold-refactor language to
current architecture. It no longer says canonical sessions are pending,
reachability is independently reimplemented, transcript replay replaces Hive
state, or nine DAG children are ready to design. The replacement section states
the shipped boundaries: generated protocol, canonical session, shared
reachability/turn contracts, append-only transcript replay, typed relay owners,
composed extension modules, runtime ownership, and cockpit projection.

### Reproduction-dependent split

No reconnect-derived claim was inferred from the VM. The remaining physical-
phone evidence pass is `story-reconnect-derived-contract-claims-audit`, blocked
on `idea-mobile-drop-slow-recovery` and
`idea-mobile-outgoing-message-swallowed`. It will amend durable docs only if the
joined live trace proves a genuine invariant gap.

### Follow-up parked

`idea-session-started-at-sdk-header` captures the separate design question of
whether SDK header time should replace relay-start/reset time as
`session_started_at`. It is not required to close this evidence audit.
