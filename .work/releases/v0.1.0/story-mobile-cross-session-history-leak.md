---
id: story-mobile-cross-session-history-leak
kind: story
stage: done
tags: [app, pi-extension, relay, bug, transport, session]
parent: feature-reconnect-reproduction
depends_on:
  - story-verify-mobile-dup-and-reorder-reconnect-repro
release_binding: v0.1.0
gate_origin: null
created: 2026-07-06
updated: 2026-07-08
reinvestigated: 2026-07-06
review_addressed: 2026-07-08
closed_as_superseded: 2026-07-08
resolved_by:
  - story-extension-suppress-subagent-assistant-broadcast
  - story-extension-subagent-child-session-start-wipes-mobile-chat
---

# Mobile chat receives `session_history` from non-active Pi sessions (cross-room leak)

## Observed (2026-07-06, ring log `949-11f1-9243-4d82c1bdd26a.bin`)

Operator reports that **skills/ and starmods/ sessions appear as messages in
the mobile chat** — i.e. the phone is rendering transcript content from Pi
sessions that are NOT the active chat session. The ring log confirms: in the
`14:40–14:43` window (active room `7ADky8889NJy`, active session
`...f05f3343`), **3 distinct sessions** replayed through the app's
`_replayHistory` path:

```
replayDedup sessionIds (last 8) in 14:40-14:43 window:
  c12db9c7: 30 events   (14:40:21)
  06c8acbf: 30 events   (spans 07:17 → 14:41)
  f05f3343: 30 events   (the active session)

### Operator clarification (2026-07-06) — the symptom is subagent traffic, not cross-room session content

The operator clarified the report is NOT (primarily) about sibling cwd-room
sessions leaking in. It is: **when a session's main agent dispatches a
subagent (in skills/ and starmods/), the subagent's messages and its
report back to the main agent showed up in the mobile chat.** This is a
transcript-message delivery issue, not a `room_meta` session-flip.

### Mechanism finding (2026-07-06 static trace)

The SDK fires `message_end` for subagent assistant turns *within the parent
session* — subagent dispatch is NOT a `session_start` reason (SDK reasons are
only `startup | reload | new | resume | fork`; `extensions.md:395`). The
extension's `message_end` handler (`sdk_session_projection.ts:387-425`)
broadcasts every assistant text block as `agent_message` stamped with
`sessionId = this.currentRemoteSessionId()` (the parent/main session id),
gating only on `message.role === "assistant"` and `block.type === "text"` —
no source/subagent discrimination. So the subagent's report-back is an
assistant message in the main session, projected as `agent_message` and
fanout-broadcast to the phone, appearing in chat alongside the main agent's
own messages.

This is a **correct-session, wrong-content** leak: the session id is right
(the parent), but the content is subagent-internal traffic the operator does
not want surfaced in the mobile chat. The relay `cross_room` logging deployed
in `story-relay-log-room-meta-update-accept-and-drop` does NOT catch this —
it targets the wrong layer (room-meta routing, not transcript broadcast).

### SDK message-shape verification (2026-07-06) — no subagent/source field exists

Checked the SDK type definitions (source of truth, since `extensions.md`
doesn't document one):

- `MessageEndEvent` (`core/extensions/types.d.ts:550-553`) carries only
  `{ type, message }`. `message` is `AgentMessage` (a union).
- `AssistantMessage` (`@earendil-works/pi-ai/dist/types.d.ts:276-288`) fields:
  `role`, `content`, `api`, `provider`, `model`, `responseModel?`,
  `responseId?`, `diagnostics?`, `usage`, `stopReason`, `errorMessage?`,
  `timestamp`. **No `subagent`, `source`, `origin`, or `parentMessageId`
  field.**
- `AgentStartEvent` is `{ type: "agent_start" }` and `AgentEndEvent` is
  `{ type: "agent_end", messages }` (`types.d.ts:517-524`) — **no subagent
  id, no parent ref, no flag** distinguishing a subagent run from the main
  agent.
- The "subagent" concept is entirely internal to the Task tool and is
  **invisible at the extension event boundary**. There is no field on
  `event.message`, `event`, or `ctx` that the projection can filter on.

### Tool provider identification (2026-07-07) — @gotgenes/pi-subagents, in-process child session

The `subagent` tool is **neither pi-native nor part of our `remote-pi`
extension**. It is provided by the **`@gotgenes/pi-subagents`** package
(v18.0.1, registered in `~/.pi/agent/settings.json` under `packages`).
Key findings from its source (`~/.pi/agent/npm/node_modules/@gotgenes/pi-subagents`):

- The tool name is `"subagent"` (`src/tools/agent-tool.ts:132`,
  `name: "subagent" as const`).
- The package is described as "A focused, **in-process** sub-agent core for
  pi" — the subagent runs **in-process**, sharing the pi process.
- Critically: `createSubagentSession()` (`src/lifecycle/create-subagent-session.ts`)
  creates a **child `AgentSession`** via `deps.io.createSession()`, and line 177
  states **"Children always load the parent's extensions and skills."** The
  child session calls `session.bindExtensions()` (line 233), which **re-binds
  the parent's extensions — including our `remote-pi` extension.**

**This is the leak mechanism, fully traced:** when the subagent produces an
assistant message, the **child** session's `message_end` fires, and our
`remote-pi` extension's `message_end` handler is bound to the *child* session
too (because the child inherits the parent's extensions). The handler has no
way to know it's bound to a child session — `event`/`event.message`/`ctx`
carry no parent/child or subagent marker (verified above). So it broadcasts
the subagent's assistant text as `agent_message` to the phone.

### Implication for the fix — model-mismatch gate is NOT sufficient (blocking bug)

The operator confirmed they **don't always dispatch cross-model subagents** —
a same-model subagent would pass a `model`-mismatch gate and still leak. So the
`model`-proxy gate is a partial mitigation at best, NOT a real fix. This makes
the leak a **blocking bug**: the extension cannot distinguish subagent-origin
assistant messages from main-agent ones using any SDK-provided field.

Three real fix paths, in increasing order of cleanness:

1. **`tool_execution_start`/`tool_execution_end` window gate** (extension-side,
   fork-local, model-independent). The extension ALREADY has a
   `tool_execution_start` handler (`index.ts:1267`) that fires for every tool
   with `event.toolName`. When `toolName === "subagent"`, set a flag for the
   duration of the tool execution; in `message_end`, suppress `agent_message`
   broadcast while that flag is set. Caveat: this depends on the SDK firing
   `tool_execution_start` for the `subagent` tool AND on the subagent's
   `message_end` events firing *between* `tool_execution_start` and
   `tool_execution_end` for that toolCall — the latter is UNVERIFIED (the
   subagent runs in a child `AgentSession`, so its `message_end` events may
   not nest inside the parent's `tool_execution` window). Needs a live
   verification with `tool_execution_*` + `message_end` ordering captured.
2. **Detect child-session binding** (extension-side, fork-local). The
   extension's `session_start` handler fires for the child session too
   (because `bindExtensions` fires `session_start`). If `session_start` can
   detect it's a child (e.g. via a `parentSession` reason or ctx field), set a
   process-global `inSubagentSession` flag and suppress all broadcasts while
   it's set. Needs verifying whether `session_start` carries a parent/child
   signal in the subagent case.
3. **Upstream**: request `@gotgenes/pi-subagents` or pi-core expose a
   `parentSessionId`/`subagent` marker on `MessageEndEvent`/`AgentStartEvent`.
   Cleanest but out-of-fork.

**Open before implementing**: verify the SDK firing order — does the
subagent's `message_end` fire *between* the parent's
`tool_execution_start("subagent")` and `tool_execution_end("subagent")`?
If yes, fix path #1 works and is fork-local. If no (child-session events
fire outside the parent's tool_execution window), path #2 is needed. The
TEMP DEBUG instrumentation captured `message_end` only; a second capture
adding `tool_execution_start`/`tool_execution_end` + `session_start` would
settle both #1 and #2.

### Second capture resolution (2026-07-07) — fix path #1 CONFIRMED, fork-local, model-independent

A second live capture (TEMP DEBUG instrumentation writing to
`~/.pi/remote/debug-firings.jsonl`, logging `session_start` +
`tool_execution_start` + `tool_execution_end` + `message_end` ordering)
during a `gpt-5.3-codex-spark` subagent dispatch from the `umans-glm-5.2`
main session. Full firing sequence around the dispatch:

```
17:43:06 tool_execution_start subagent                          ← parent dispatches subagent
17:43:07 session_start        startup                  sess=06075b43  ← CHILD session_start fires
17:43:07 message_end          user                                  ← subagent's user msg
17:43:09 message_end          assistant  model=gpt-5.3-codex-spark    ← LEAK: subagent reply
17:43:09 tool_execution_end   subagent                              ← parent's tool_execution_end
17:43:09 message_end          toolResult                            ← folded result (correct)
```

**Fix path #1 (tool-execution window gate) CONFIRMED.** The subagent's
`message_end` (the leak) fires *between* `tool_execution_start subagent`
and `tool_execution_end subagent`. So a flag set on `tool_execution_start`
for `toolName === "subagent"` and cleared on `tool_execution_end` would
suppress the `agent_message` broadcast in `message_end`. **Model-
independent** — works for same-model subagents too (the gate keys on the
toolName, not the model).

**Fix path #2 (session_start detection) is viable but redundant and weaker.**
The child fires `session_start` with `reason=startup` and the **same
sessionId `06075b43`** as the parent — NOT a fresh id. So there is no
sessionId-change signal to detect mid-execution; path #2 reduces to
"a second `session_start` fired while a `subagent` tool_execution is open,"
which is just path #1 with extra steps. Path #1 is strictly better.

**DECIDED fix (fork-local, in `pi-extension/src/index.ts`):**
- Add a module-level `_inSubagentToolExecution: boolean` flag (or a
  depth counter, to handle nested subagents).
- In `tool_execution_start`: if `event.toolName === "subagent"`, set the
  flag (increment the counter).
- In `tool_execution_end`: if `event.toolName === "subagent"`, clear the
  flag (decrement).
- In `message_end`: when the flag is set (counter > 0), suppress the
  `agent_message` broadcast (and the `assistant_committed` transcript
  event?) for assistant messages. **Open sub-question**: should the
  transcript event also be suppressed, or only the live broadcast? The
  `session_history`/`session_sync` replay path would re-surface the
  subagent's assistant text on reconnect if the transcript event is kept —
  so to fully prevent the leak, the transcript event must be suppressed too
  (or the app's replay must filter it). Decide at implementation.
- Caveat: keys on the literal `toolName === "subagent"` from the
  `@gotgenes/pi-subagents` package. If a different subagent tool is ever
  used (different package, different toolName), the gate won't catch it —
  but that's an acceptable fork-local tradeoff documented inline.

### Two distinct failure modes now in scope

1. **Subagent-content leak (the operator's actual report)** — extension
   `message_end` broadcasts subagent assistant text to the phone. Needs an
   extension-side gate (suppress broadcast for subagent-origin assistant
   messages, or the SDK needs a source/subagent field the projection can
   filter on). Whether the SDK message carries any subagent/source metadata
   is UNVERIFIED — the `extensions.md` message shape does not document one,
   but the runtime `event.message` may carry a field worth checking.
2. **Cross-room session flip (the original h1/h2 ambiguity, lower priority)**
   — the `_activeRef` rotation captured in the ring log. May be unrelated to
   the operator's report; may be a real but separate bug. Keep the refined
   open question (does the extension send `room_meta_update` for a sibling
   room?) but treat it as secondary to #1.

### Live repro resolution (2026-07-07 ring log `9c1-11f1-8bca-c9ed4620e936.bin` + relay cross_room logs)

A live repro during subagent dispatch (my own subagent dispatch from the
remote_pi session, ~05:04 UTC) captured the session flip in the ring log,
AND the relay `cross_room` logging (deployed in
`story-relay-log-room-meta-update-accept-and-drop`) was live to witness it.

**The cross-room leak hypothesis (h2) is RULED OUT.** Ring-log timeline
(2026-07-07 05:04 UTC):

- 05:03:54 — burst of envelopes + replayDedup for session `...06075b43`.
- 05:04:04.885-904 — four `room_meta_updated` controls for room
  `7ADky8889NJy` arrive at the phone.
- 05:04:04.902 — session gate REJECTS `user_input` for session `...24d99f47`
  with `session_mismatch`. The active session flipped `06075b43` →
  `24d99f47`.
- 05:04:09 → 05:06:05 — `24d99f47` is now the active session (11
  replayDedup events).

Relay `cross_room` logs for the SAME window:

```
05:04:03.898  room_meta_update applied peer=l2X/dUc= room=7ADky8889NJy
              authed_room=7ADky8889NJy cross_room=false fields=["session_id"]
```

**`cross_room=false`** — the `session_id` patch for room `7ADky` came from a
sender authenticated in room `7ADky` itself (the 7ADky Pi's own process),
NOT a sibling. And across the entire recent window, **every** `cross_room`
line is `false` (zero `cross_room=true`). So h2 (sibling overwriting
`7ADky`'s session via the shared owner epk) is definitively ruled out.

**Confirmed: h1 (the 7ADky Pi's own session rotating).** The `fields=[
"session_id"]` patch is the 7ADky Pi publishing a new session_id for its own
room. The rotation happened during my subagent dispatch (the subagent runs in
this pi session = room `7ADky`). The session flip is the pi process's own
lifecycle event — a `/new`, session replacement, or the subagent tool's own
session boundary — NOT a cross-room sibling overwrite.

### What this means for the operator's reported symptom

The subagent-content leak (#1 above) and the session flip (#2) are **two
different things**, and the live repro confirms #2 is the 7ADky Pi's own
rotation (correct-ish), not a leak. The operator's report of subagent
messages appearing in chat is #1 — the `message_end` broadcast of subagent
assistant text — which the relay `cross_room` logging does NOT and cannot
catch (it's a correct-session, wrong-content issue at the extension
projection layer, not a room-routing issue).

### Revised open questions

- **(RESOLVED 2026-07-07) #1 subagent-content leak — CONFIRMED**: a
  subagent dispatch fires top-level `message_end` for the subagent's
  assistant reply, which the extension broadcasts as `agent_message` to the
  phone. Live capture via TEMP DEBUG instrumentation (file append to
  `~/.pi/remote/debug-message-end.jsonl`) during a `gpt-5.3-codex-spark`
  subagent dispatch from the `umans-glm-5.2` main session:
  ```
  17:20:17  assistant  umans-glm-5.2      toolUse  text,toolCall   ← main dispatches subagent (toolCall)
  17:20:17  user       -                   -        text             ← dispatch prompt as user msg
  17:20:19  assistant  gpt-5.3-codex-spark  stop     text             ← LEAK: subagent reply → top-level message_end
  17:20:19  toolResult -                   -        text             ← subagent result also folded into toolResult
  17:20:29  assistant  umans-glm-5.2      toolUse  text,toolCall   ← main agent continues
  ```
  The subagent's reply fires **twice**: once as a top-level `assistant`
  `message_end` (broadcast to phone — the leak), once as a `toolResult`
  (correct, already filtered by `role === "assistant"`).
  **The distinguisher is `message.model`**: the subagent ran on
  `gpt-5.3-codex-spark`, different from the main `umans-glm-5.2`. So a
  fix is possible WITHOUT an upstream SDK change — the extension's
  `message_end` handler can compare `message.model` against the session's
  active/expected model and suppress broadcast when they differ. Caveat:
  `model` is a proxy, not a true subagent flag — it breaks if a subagent is
  dispatched on the SAME model as the parent, or if the user manually
  switches the main session's model mid-turn. The clean fix remains an
  upstream SDK `source`/`subagent` field, but the `model`-mismatch gate is
  a viable fork-local mitigation.
- **(closed) #2 cross-room session flip**: RULED OUT by `cross_room=false`.
  The session rotation is the 7ADky Pi's own (h1). Whether that rotation is
  *expected* (subagent tool creates a child session?) is a separate question
  for the SDK, but it is NOT a cross-room leak.
```

`replayDedup` only fires inside `_replayHistory` (`sync_service.dart:1199`),
which only runs AFTER the session gate accepts the `SessionHistory` frame
(`sync_service.dart:569`, `sync_service.dart:844-846`). So the gate ACCEPTED
`session_history` frames for 3 different sessions — meaning `_activeRef.sessionId`
matched all 3 at some point, OR the gate is being bypassed.

Across the full ring log, **7 distinct sessions** replayed (390+300+90+60+60+
30+30 events). The phone sees a firehose of cross-session transcript content.

## Root cause (PARTIALLY CONFIRMED 2026-07-06 — deeper trace needed before fixing)

**Confirmed:** the active session (`_activeRef.sessionId`) changed 5 times in
3 minutes while `_activeRoomId` stayed `7ADky8889NJy`. The session gate is
correct; `_activeRef` is being mutated by room-metadata events.

**NOT confirmed:** the EXACT mutation path. A focused static trace found that
NONE of the 3 room handlers (`RoomAnnounced`/`RoomMetaUpdated`/`RoomsSnapshot`)
can mutate room `7ADky`'s `sessionId` from a sibling room's announcement —
they all key by `roomId` and only touch the announced room's entry. The relay
keys rooms by `(peer_epk, room_id)` and does not mis-route
`room_meta_updated` across rooms. So a sibling Pi's metadata for
`SF_DCbXsmreE` cannot flip `7ADky`'s `sessionId`.

### NEW structural fact (2026-07-06 live relay inspection)

All 4 dev-VM Pi processes authenticate under the **SAME owner epk** `l2X/dUc=`
— rooms `SF_DCbXsmreE` (02:35), `7ADky8889NJy` (02:36/03:19/17:53),
`zuMPC-YTtdUD` (07:03), `k0H-7lFh371e` (07:04/17:10). They share one owner
keyring (the dev VM's `~/.pi/agent`). The phone (`MD/tL3E=`) is in
`room=main` only. Two relay-structural consequences the prior traces missed:

1. **`room_meta_update` keys by `(peer_id, room_id)` and drops unknown pairs**
   (`control.rs:143-167`, `rooms.rs:apply_patch`). A sibling Pi sending
   `room_meta_update` for room `7ADky` resolves to key `(l2X/dUc=, 7ADky)` —
   which EXISTS (the 7ADky Pi registered it). So a sibling could stamp a new
   session_id onto the `7ADky` room entry via the shared peer_id. This is a
   **candidate leak path the prior static trace missed**: does the extension
   ever send `room_meta_update` for a room it did NOT register (a sibling
   room id)? The relay would accept it under the shared peer_id.
2. **`RoomManager.subscribe` is keyed by peer_id, not room** (`rooms.rs:56`).
   `subscribers_of("l2X/dUc=")` returns the phone for ALL of that peer's
   rooms. So the phone RECEIVES `room_meta_updated` frames for all 4 sibling
   rooms under the one shared peer_id. The app's `RoomMetaUpdated` handler
   must not auto-activate to a sibling's session from these. This is the
   delivery-side precondition for the h2 leak.

### The 7ADky Pi did NOT re-auth during the repro window

The `7ADky` Pi's connections authenticated at 02:36:31 and 03:19:38, then
NOT AGAIN until 17:53:34 — so no reconnect rotation during 14:40-14:43.
Any session rotation in that window came via `room_meta_update` frames, not
re-auth. The relay doesn't log `room_meta_update` at INFO, so relay logs
alone cannot confirm whether `7ADky`'s session_id was rotated by the 7ADky
Pi's own process (h1, correct) or overwritten by a sibling via the
shared-peer_id path (h2-leak-variant).

**Two remaining hypotheses:**

1. **The `7ADky` Pi's OWN session rotated multiple times** (via `/new`/
   `/resume` during the operator's autopilot/review work). Each rotation
   publishes `room_meta_updated` with a new `session_id` for room `7ADky`.
   The app correctly tracks it (`RoomMetaUpdated` → `RoomInfo.sessionId` →
   `_onRoomsChanged` → `activate()`). The replayed sessions (`c12db9c7`,
   `06c8acbf`, `96bc2b30`) are PRIOR sessions of the SAME `7ADky` Pi. This
   is CORRECT behavior — the app hydrates each rotated session's history on
   reconnect. The operator may have mistaken the agent's own skills/starmods
   discussion content for sibling-Pi content.
2. **Cross-room leak via the phone being in `room=main`.** The sibling Pis
   (in `SF_DCbXsmreE`/`zuMPC`/`k0H-7l`) broadcast to the phone at
   `room=main` (the phone's registered room) — `OwnerMultiplexer.broadcast`
   has no room filter, and the relay delivers `(phone_epk, main)` to the
   phone. The sibling's `session_history` carries the sibling's `session_id`.
   For the gate to accept it, `_activeRef.sessionId` must have flipped to the
   sibling's — but the static trace shows no path for that. UNLESS the
   sibling's `session_history` is being accepted via a DIFFERENT gate path,
   or `_activeRef` is null (the `active_session_unknown` gate rejection at
   14:40:17.636 suggests `_activeRef` was briefly null right after reconnect).

### What the evidence supports

- The relay shows only ONE Pi process in room `7ADky` (2 auths, both from
  the dev VM). The 4 Pis are in 4 different rooms.
- The current pi session (`019f3570-42c7-...`) does NOT appear in the
  replayDedup sessionIds — so the replays are NOT the current session's
  history. They are prior/sibling sessions.
- Hypothesis (1) is consistent with the operator running autopilot/reviews
  (which rotate sessions via `/new`). Hypothesis (2) is consistent with the
  operator's report of sibling-Pi content appearing.

### Why this is parked, not fixed

The root cause is genuinely ambiguous between (1) correct session-rotation
tracking and (2) a cross-room leak. Implementing a fix on the wrong
hypothesis risks breaking correct reconnect-hydration behavior (1) or
missing the actual leak (2). The ring log does not decode `room_meta_updated`
payloads or `session_history` wire `session_id` fields, so it can't
distinguish them.

**Needed before fixing:**
- A live repro with the ring log decoding `room_meta_updated` room +
  session_id, AND the `session_history` wire `session_id` — so we can see
  whether the flipped sessions are the `7ADky` Pi's own rotations or sibling
  Pis' sessions.
- OR: a check whether the operator was running autopilot/`/new` on the
  `7ADky` Pi during the 14:40-14:43 window (which would confirm hypothesis 1).

## The fix (TBD — depends on confirmed hypothesis)

- If (1): no fix needed — the app is correctly tracking session rotations.
  The operator's report may be a misread.
- If (2): app-side — `_onRoomsChanged` must not `activate()` to a sibling
  session; extension-side — `OwnerMultiplexer.broadcast` must filter by
  room (requires per-owner room tracking).

## Acceptance Criteria

- [x] Static trace: does `_activeRef` change when a `RoomAnnounced` for a
      SIBLING room arrives while a different chat is open? **NO direct path**
      — the 3 room handlers key by `roomId` and can't mutate a sibling room's
      `sessionId`.
- [x] Static trace: does the extension broadcast `session_history` to ALL
      attached owners, or only those in the Pi's cwd-room? **ALL** —
      `OwnerMultiplexer.broadcast` (`owner_multiplexer.ts:450-454`) has no
      room filter.
- [x] Confirm via the ring log: the active session changed 5 times in 3 min
      while the room stayed `7ADky`.
- [x] **RELAY (2026-07-06 live)**: all 4 dev-VM Pis share one owner epk
      `l2X/dUc=`; `room_meta_update` keys by `(peer_id, room_id)` and would
      accept a sibling's patch for room `7ADky` under the shared peer_id;
      `subscribe` is peer-keyed so the phone receives all 4 rooms' meta. The
      7ADky Pi did not re-auth during the 14:40-14:43 window.
- [ ] **OPEN (refined)**: does the extension ever send `room_meta_update`
      for a room the process did NOT register (a sibling room id)? If yes,
      the shared-peer_id path overwrites `7ADky`'s session_id — that is the
      h2 leak mechanism. If no, the rotation is the 7ADky Pi's own (h1).
      Needs the extension's debug log for the 14:40-14:43 window, OR a decoded
      ring-log `room_meta_updated` carrying room + session_id + peer.
- [ ] Decide fix path after the open question is resolved.
- [ ] A regression test once the root cause is confirmed.

## Out of scope

- The send-timeout / `room=main` outbound bug — separate story
  (`story-mobile-send-timeout-relay-room-main-mismatch`), likely same root.
- The dup/reorder identity fixes (landed).

## Supersession decision (2026-07-08) — close as resolved-by-supersession

This story's two threads were both resolved by other work, and the remaining
open ACs are answered by that work, not by code written here:

1. **Subagent-content leak (the operator's actual report) — RESOLVED by
   `story-extension-suppress-subagent-assistant-broadcast` (done, verified
   live 2026-07-08).** That story implemented fix path #1 (the
   `tool_execution_start`/`tool_execution_end` window gate for
   `toolName === "subagent"`) which this story's investigation traced and
   confirmed as the viable fork-local, model-independent fix. The leak is
   closed at the extension projection layer (suppress both the live
   `agent_message` broadcast and the `assistant_committed` transcript event
   while a subagent tool execution is open).
2. **Cross-room session flip (h2) — RULED OUT as a leak.** The relay
   `cross_room` logging (deployed in `story-relay-log-room-meta-update-
   accept-and-drop`) confirmed `cross_room=false` for every `room_meta_update`
   in the repro window: the `7ADky` session_id patches came from the 7ADky
   Pi's own process (h1 — its own session rotation), NOT a sibling
   overwriting via the shared owner epk. There is no cross-room leak to fix.
   The own-process rotation in the subagent case was itself a real bug — a
   child subagent `session_start` publishing a child `session_id` for the
   parent's room, which wiped the mobile chatlog — and that is resolved by
   `story-extension-subagent-child-session-start-wipes-mobile-chat` (done,
   operator-confirmed fixed). So thread #2's supersession chain is: relay
   logging rules out the cross-room sibling overwrite (h2), and the child-
   session wipe story fixes the genuine own-process rotation symptom the
   operator saw.

**Remaining open ACs:**
- "does the extension send `room_meta_update` for a sibling room?" — answered
  NO by the `cross_room=false` evidence (a sibling patch would have shown
  `cross_room=true`); it is the 7ADky Pi's own.
- "decide fix path" — decided: no code fix needed here. The reported symptom
  routes to the subagent story (done); the cross-room hypothesis is closed.
- "regression test" — covered by the subagent story's tests.

This item is at `stage: review` for a review pass to confirm the
supersession reasoning before advancing to `done`. No code change is in this
story's diff — it is a closeout decision grounded in the two done stories'
evidence.

## References

- Ring log: `debug/949-11f1-9243-4d82c1bdd26a.bin` — 7 sessions replayed,
  3 in the `14:40-14:43` window alone.
- Relay logs: 4 Pi auths from `l2X/dUc=` in 4 cwd-rooms
  (`7ADky8889NJy`, `SF_DCbXsmreE`, `zuMPC-YTtdUD`, `k0H-7lFh371e`).
- `app/lib/data/sync/sync_service.dart:569` — the session gate;
  `:844-846` — `SessionHistory` → `_replayHistory`;
  `:1199` — `replayDedup` (only fires after gate accepts).
- `app/lib/data/transport/connection_manager.dart:643` — `RoomAnnounced`
  handler; `:1012` — `_learnSessionFromPairOk`.
- `pi-extension/src/extension/owner_multiplexer.ts:450` — `broadcast` (all
  owners, no room filter).
- `pi-extension/src/session/sdk_session_projection.ts:638` —
  `maybeSendLateAttachSessionSync` (late-attach targets).
- `story-mobile-send-timeout-relay-room-main-mismatch` — likely same root
  (phone in `room=main`, Pis in cwd-rooms).
