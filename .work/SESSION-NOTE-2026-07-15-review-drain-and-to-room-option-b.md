# Session note — 2026-07-15 — review backlog drained + to_room Option B implemented

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## TL;DR

Two things done this session, both operator priorities:

1. **Drained the entire review backlog.** Started with 34 stories + 14 features
   + 2 epics at `review`; ended with 0. The 34 stories were a routing smell
   (child stories never enter review — green verification advances them to
   done). The 14 features + 2 epics got cross-model fresh-context review
   (`openai-codex/gpt-5.6-sol`); 9 findings fixed, 1 rejected (diff-range
   confounding), 1 parked. Both rebrand epics are now `done`.

2. **Implemented `story-to-room-sender-side-room-targeting` (Option B).** The
   operator's stated priority #2 from the 07-14 note. Cross-PC `pi_envelope`
   delivery now targets the sibling's actual live room instead of the hardcoded
   `"main"` (which reached no live room and silently broke cross-PC mesh
   delivery). Story is `done` (standalone-story bounded inline review).

Nothing is pushed — 226 commits ahead of `origin/main`, all local on `main`.

## The review backlog drain

### Routing fix first (the smell)

34 stories at `review` were all **child stories** (every one had a `parent:`
pointing to a feature). Per the agile-workflow review principles, child stories
never enter review — green verification advances them directly to `done`. The
real review unit is the **feature**. Batch-normalized all 34 `review → done`
(commit `b4a4186`) after confirming each carried genuine verification evidence
(flutter analyze/test green, cargo test/clippy, dart format, PT-scan clean).
This collapsed the backlog from 34 stories + 14 features down to 14 features.

### 14 feature reviews → all done

Fanned out 5 parallel cross-model reviewers (`openai-codex/gpt-5.6-sol`,
thinking high), grouped by surface/risk. 4 commits:

| Commit | Features | Findings |
|---|---|---|
| `f47876e` | 4 EN-first (app/site/relay/prose) | 3 fixed: tautological site JSDoc, relay `parse_hello` doc, missed `cockpit.desktop` PT |
| `bbcfd23` | 3 external-surfaces | 1 fixed: docs pointed at removed `/outpost-pi config` |
| `771d817` | 1 EN-first pi-extension | 3 fixed: residual ASCII PT (`Fase`/`nome`/`reescrito`), `RemoteState` JSDoc, contract re-scope |
| `7e55047` | 5 EN-first cockpit | 1 Nit fixed (`flutter_pty`→`kyroon_pty`); 1 Important **rejected** (diff-range confounding) |

The rejected finding: the reviewer flagged `update_checker_impl.dart`'s
`manifestUrl` nullable change as contradicting cockpit-data's comments-only
contract. Verified via per-commit attribution that the behavior change came
from retire-rp-s3 commit `f90a74e` (already reviewed/done), not the cockpit-data
EN-first feature. The integrated diff range `376fa38..HEAD` conflated sibling
features. **Lesson: when a reviewer flags "not comments-only" at epic scope,
check per-commit attribution before accepting — the diff range spans sibling
features.**

### 2 epic aggregate reviews → both done

The epic-level reviews earned their keep — both caught cross-feature integration
gaps invisible at feature scope:

- `epic-rebrand-external-surfaces` (`f9f1adb`): caught a **Blocker** — the
  onboarding docs claimed the wizard's "Use the relay?" step connects the relay,
  but after no-default-relay the extension refuses without an explicit
  `set-relay` URL. Fixed across the tutorial + both READMEs. Plus an Important:
  `site/CLAUDE.md` referenced a deleted `push-docker.sh`.
- `epic-rebrand-to-outpost-pi-en-first` (`87dcd4e`): caught 10 residual `Fase`
  remnants in app code (the app feature's accented-only scan missed ASCII PT —
  same gap the pi-extension feature had), a SKILL.md typo (`Split`→`Skip`),
  missing `documentation-conventions` in the AGENTS.md reference list, and
  parked the legacy `.orchestration/contracts/` PT translation as a backlog
  item.

**Lesson: the accented-only PT scan is a recurring gap.** Three features
(pi-extension, app, and the epic-wide sweep) all missed ASCII PT (`Fase`,
`nome`, `reescrito`) that only an ASCII-word scan catches. The
documentation-conventions skill should prescribe an ASCII PT-word scan, not
just accented-character scan. Filed as part of the epic review.

### Verification

All green: relay (fmt+clippy+20 tests), site (lint+build), pi-extension
(typecheck + 830/841 tests — 8 failures are the documented pre-existing
`acquireCwdLock` EROFS environmental flake on read-only
`~/.pi/remote/locks/`), cockpit (analyze clean + 241 tests), app (21/21 home
tests; 228 analyze errors pre-existing in `outpost_pi_identity/` plugin).

## to_room Option B implemented

### Context (from 07-14 note)

The relay half of the `to_room` wire change shipped in relay-0.2.0: cross-PC
`pi_envelope` now carries a required `to_room`, the relay routes via
`send_to_room(to_pc, to_room)`, empty `to_room` → `bad_envelope`. But the
**sender half was left as a temporary `"main"` default** at
`broker_remote.ts:378,487,552`. Since each Pi's MeshNode joins
`roomIdFor(cwd, sessionName)` (a real 12-char id, NOT `"main"`), a
`to_room: "main"` envelope reached no live sibling room → cross-PC mesh
delivery was non-functional.

The 07-14 session did the design analysis (why the original "roster
derivation" is unsound for multi-Pi-per-PC) and the operator chose **Option B**
(relay as authoritative room source via `subscribe_rooms` + `rooms_check`)
over Option A (`leader_room` bolted on `peers_update`). The story body
described Option A; it needed updating to Option B before implementation.

### What I did

1. **Updated the story to Option B** (`3e3459c`): rewrote the design section,
   acceptance criteria, and implementation notes to the relay-authoritative
   shape. Key difference from Option A: no new wire field on `PeersUpdateBody`
   (relay is the single room truth); `BrokerRemote` maintains a `siblingRooms`
   cache from relay push events, not from a peer-announced field. Extension-only
   change (no relay/schema/app edit). Advanced `drafting → implementing`.

2. **Implemented** (`b466eab`) across 3 files:
   - `pi_forward_client.ts`: threads `to_room` on the `envelope` event (Site 2
     ACK); emits validated `rooms`/`room_announced`/`room_ended` control events;
     exposes `sendRoomControl` for `subscribe_rooms`/`rooms_check`.
   - `broker_remote.ts`: `siblingRooms` cache from relay push events;
     `pickRoom()` targets a live room (Sites 1 & 3); cold-cache `rooms_check`
     bootstrap + bounded `peers_request` fanout; `subscribe_rooms` on sibling
     add; leader heuristic (oldest `started_at` first); `detach` removes all
     new listeners.
   - `broker_remote.test.ts`: 41 tests (updated `"main"` assertions + new
     cold-cache/ACK/room-event/bootstrap/convergence tests).

3. **Reviewed** (`b41c9c2`): standalone-story bounded inline review (parent
   epic shipped in v0.6.0). All lenses pass: no `"main"` literal,
   `PeersUpdateBody` unchanged, lifecycle clean, cold-cache safe (no fabricated
   room), ACK threads `to_room`, anti-spoof intact, subscribe idempotent.

### Design notes (load-bearing)

- **Why relay-authoritative, not peer-announced**: the relay already maintains
  authoritative room state (`RoomManager`, `RoomMeta`, the
  `registry_event_publisher` push path) and already exposes `subscribe_rooms`
  + `rooms_check` + `room_announced`/`room_ended`/`room_meta_updated` events.
  Option A would duplicate that state into a peer-announced `leader_room`
  field that can drift from relay truth; Option B reuses the relay's existing
  API with no new wire field and no second source of room truth.
- **Cold-cache behavior**: when `pickRoom()` returns `undefined` (empty cache),
  the envelope is NOT sent to a fabricated room (correct — avoids the relay
  returning `offline` for a bogus room). `rooms_check` is triggered to warm the
  cache. `tryRouteOutbound` returns `true` so the broker's ACK-timeout
  contract holds (sender's pending map times out — the existing behavior for a
  non-delivered envelope). The next send after the snapshot warms targets the
  real room.
- **Leader heuristic**: `_replaceOrderedRooms` sorts by `started_at` (oldest
  first = leader registers first), deterministic tie-break by `room_id`. In
  practice only the leader's room has a `PiForwardClient` listener, so
  targeting any live room is safe (follower rooms silently drop).
- **Relay reconnect**: `subscribe_rooms` is per-WS-connection. The existing
  relay-transport reconnect path re-runs bridge attach, which re-fires
  `setSiblings` → `_subscribeToRooms`. (Not yet explicitly tested for the
  reconnect case — the acceptance criteria list it; the test suite covers
  `setSiblings` re-subscribe but not a full relay reconnect cycle. Park as a
  follow-up if live testing reveals a gap.)

## Board state

- **0 items at review** (was 34 stories + 14 features + 2 epics)
- 2 rebrand epics **done**; 15 features done, 5 drafting; 56 stories done, 2
  implementing, 7 drafting
- 1 backlog item parked (`idea-translate-legacy-orchestration-contracts`)
- `story-to-room-sender-side-room-targeting` **done**

## Resume priority

1. **Cut a release** bundling the two rebrand follow-up epics (v0.1.1 or
   v0.2.0). They're done and verified; a release-deploy would collapse them
   into a release record and run the gates. The rebrand arc is shippable.
2. **Drain the 2 implementing stories** — `story-document-deferred-relay-volume-cutover`,
   `story-refresh-current-protocol-security-docs` (the third,
   `story-wire-protocol-codegen-tests-into-check`, may already be done —
   check).
3. **Triage the 73 gate findings** in the backlog (security/refactor/tests/docs
   from v0.1.0) — decide which are real follow-up work vs. already-addressed
   vs. won't-fix.
4. **Live-test cross-PC mesh delivery** now that `to_room` sender-side is
   implemented — the relay reconnect re-subscribe path is the one untested
   edge.

## Process notes (for future me)

- **The 4-concurrent-subagent gate is real.** Fanning out 5 reviewers meant 1
  queued until a slot freed. Plan for 4-wide parallelism, not 5.
- **pnpm in this sandbox needs the full env incantation**: `COREPACK_HOME` +
  `PNPM_HOME` + `npm_config_cache` + `XDG_CACHE_HOME` (all under
  `outpost_pi/.`), plus `CI=true` to skip the deps-status RO-cache check that
  aborts on no-TTY. Bare `pnpm` is not on PATH. Documented in AGENTS.md but
  easy to forget mid-session.
- **`/tmp` is read-only in this sandbox** (tmpfs). Redirect logs to
  `outpost_pi/.xdg-cache/` instead.
- **The `acquireCwdLock` EROFS flake is permanent in this sandbox.**
  `~/.pi/remote/locks/` is read-only, so `cwd_lock.test.ts` (7) +
  `extension.test.ts` (1, the same-name-join test) always fail. Don't
  re-investigate; it's documented in the v0.1.0 release notes. 830/841 is the
  real green.
