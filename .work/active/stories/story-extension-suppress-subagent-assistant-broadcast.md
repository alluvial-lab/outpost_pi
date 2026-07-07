---
id: story-extension-suppress-subagent-assistant-broadcast
kind: story
stage: review
tags: [pi-extension, bug, transport, lifecycle]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-07
updated: 2026-07-07
---

# Suppress subagent assistant messages from the live broadcast + transcript replay

## Brief

When a session's main agent dispatches a subagent (the `subagent` tool from
`@gotgenes/pi-subagents`), the subagent's assistant messages fire top-level
`message_end` in the parent session and get broadcast to the phone as
`agent_message`, appearing in the mobile chat alongside the main agent's own
output. The operator reported this as "subagent messages / reports showing up
in chat" — a **correct-session, wrong-content** leak. It is a **blocking bug**
because it fires regardless of model (same-model subagents leak too).

This story implements the confirmed fork-local fix: a `tool_execution_start` /
`tool_execution_end` window gate that suppresses subagent-origin assistant
`message_end` broadcasts. Tracked under `feature-reconnect-reproduction` as the
primary resolution of the operator's reported symptom (see
`story-mobile-cross-session-history-leak` for the full investigation).

## Root cause (CONFIRMED 2026-07-07, two live captures)

The `subagent` tool (`@gotgenes/pi-subagents` v18.0.1, `name: "subagent"` at
`src/tools/agent-tool.ts:132`) runs **in-process** and creates a **child
`AgentSession`** via `createSubagentSession()`. Per
`src/lifecycle/create-subagent-session.ts:177` ("Children always load the
parent's extensions and skills"), the child calls `session.bindExtensions()`
(line 233), which **re-binds the parent's `remote-pi` extension**. So when the
subagent produces an assistant message, the **child** session's `message_end`
fires and our extension's handler is bound to it too — broadcasting the
subagent's text to the phone. The handler cannot distinguish child from parent:
`MessageEndEvent` / `AssistantMessage` / `ctx` carry no parent/child or
subagent marker (verified against SDK types).

Second live capture (`~/.pi/remote/debug-firings.jsonl`) confirmed the firing
order during a `gpt-5.3-codex-spark` subagent dispatch from the
`umans-glm-5.2` main session:

```
17:43:06 tool_execution_start subagent                     ← parent dispatches
17:43:07 session_start        startup  sess=ae1d9dfd        ← child session_start (SAME sessionId)
17:43:07 message_end          user                          ← subagent's user msg
17:43:09 message_end          assistant model=gpt-5.3-codex-spark  ← LEAK
17:43:09 tool_execution_end   subagent                      ← parent's end
17:43:09 message_end          toolResult                    ← folded result (correct)
```

The subagent's assistant `message_end` fires **between**
`tool_execution_start(subagent)` and `tool_execution_end(subagent)`. So a
window gate keyed on `toolName === "subagent"` suppresses the leak.
**Model-independent** — keys on the toolName, not the model, so same-model
subagents are caught too. Path #2 (session_start detection) was rejected: the
child fires `session_start` with `reason=startup` and the **same sessionId** as
the parent (no fresh id, no parent/child signal), so it reduces to path #1
with extra steps.

## The fix (fork-local, `pi-extension/src/index.ts`)

A module-level **depth counter** (not a boolean — subagents can nest):
`_subagentToolDepth: number`, init 0.

1. **`tool_execution_start`** (`index.ts:1267`): if
   `event.toolName === "subagent"`, increment `_subagentToolDepth` BEFORE the
   existing transcript/broadcast logic. (The existing `tool_request` broadcast
   for the `subagent` tool itself is fine — it shows "subagent running" in the
   app timeline and is not the leak.)
2. **`tool_execution_end`** (`index.ts:1288`): if
   `event.toolName === "subagent"`, decrement `_subagentToolDepth` (floor at
   0 — never go negative on a stray end without start).
3. **`message_end`** (`index.ts:1323`): when `_subagentToolDepth > 0`, skip the
   `_appendLegacySdkMessageToTranscript(m)` call for assistant messages (and
   the failed-turn forwarding block below it). This suppresses BOTH the live
   `agent_message` broadcast AND the `assistant_committed` transcript event
   (see open sub-question — currently leaning suppress-both, see below).

### Why suppress the transcript event too (the replay-leak sub-question)

`_appendLegacySdkMessageToTranscript` →
`SdkSessionProjection.appendLegacySdkMessageToTranscript`
(`sdk_session_projection.ts:355`) does two things for an assistant message:
(a) broadcasts a live `agent_message` (`:417`), and (b) appends an
`assistant_committed` transcript event (`:400`) to the in-memory
`TranscriptEventLog`. That log feeds `session_sync` / `session_history` replay
(`:495` `forSession(sessionId)`). So suppressing only (a) still leaks on
reconnect/replay — the subagent text re-surfaces when the phone rehydrates.
**To fully prevent the leak, the transcript event must be suppressed too.**
The cleanest implementation is to short-circuit at the `message_end` handler
in `index.ts` (skip the `_appendLegacySdkMessageToTranscript` call entirely
while the gate is open), so neither the broadcast nor the transcript event is
produced. This means the subagent's assistant text is never recorded for the
session — which is the intended behavior (it's not the main session's
conversation).

### What about user / toolResult messages during the subagent window?

The capture shows a `role=user` `message_end` (the dispatch prompt forwarded
as a user msg) and a `role=toolResult` (the folded result) also fire inside
the window. **Decision: suppress only `assistant` messages.** The `user` and
`toolResult` ones are not the reported leak (they don't render as agent chat
text), and the `toolResult` is the legitimate folded result the main agent
consumes. Suppressing them risks breaking the turn projection. Gate only
`assistant` to start; revisit if a follow-up leak is reported.

## Acceptance Criteria

- [ ] A module-level `_subagentToolDepth` counter is incremented on
      `tool_execution_start` where `toolName === "subagent"`, decremented on
      the matching `tool_execution_end` (floored at 0).
- [ ] In `message_end`, while `_subagentToolDepth > 0`, `assistant` messages
      are NOT passed to `_appendLegacySdkMessageToTranscript` (suppresses both
      the live `agent_message` broadcast AND the `assistant_committed`
      transcript event). `user` and `toolResult` messages are unaffected.
- [ ] The failed-turn forwarding block (`role === "assistant" && stopReason
      === "error"`) in `message_end` is also gated (a subagent provider error
      must not broadcast to the phone).
- [ ] Nested subagents: depth counter handles >1 concurrent open subagent
      dispatches without premature re-enable.
- [ ] Unit tests: (a) an assistant `message_end` inside an open
      `subagent` tool-execution window does NOT broadcast / record;
      (b) an assistant `message_end` outside the window DOES (regression);
      (c) nested open/close keeps the gate active until the outermost closes;
      (d) `tool_execution_end` without a matching start floors at 0 (no
      negative depth).
- [ ] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
      green in `pi-extension/`.
- [ ] Manual: rebuild `dist/`, restart pi, dispatch a subagent from the phone,
      confirm the subagent's assistant text no longer appears in mobile chat —
      including after a forced reconnect/replay (verify the transcript-event
      suppression holds).
- [ ] Inline comment citing `@gotgenes/pi-subagents` toolName `"subagent"` and
      the fork-local tradeoff (a different subagent tool/package with a
      different toolName would not be caught).

## Out of scope

- Cross-room session flip (Bug 2 #2) — CLOSED, ruled out by
  `cross_room=false`; not this story.
- Upstream SDK `source`/`subagent` field on `MessageEndEvent` — out of fork.
- The reorder-fix deploy / 77% inbound drop rate — separate, higher-urgency
  deploy step tracked on `story-fix-transport-active-room-reestablishment-on-reconnect`.
- Suppressing `user`/`toolResult` messages during the subagent window —
  deferred (see "What about user / toolResult" above).

## References

- Investigation: `.work/active/stories/story-mobile-cross-session-history-leak.md`
  (two live captures, SDK type verification, tool-provider identification,
  firing-order resolution).
- `pi-extension/src/index.ts:1267,1288,1323` — the three handlers to edit.
- `pi-extension/src/session/sdk_session_projection.ts:355,400,417,495` —
  `appendLegacySdkMessageToTranscript` (broadcast + transcript event + replay
  feed); explains why both must be suppressed.
- `@gotgenes/pi-subagents` source at
  `~/.pi/agent/npm/node_modules/@gotgenes/pi-subagents`:
  `src/tools/agent-tool.ts:132` (tool name `"subagent"`),
  `src/lifecycle/create-subagent-session.ts:177,233` (child re-binds parent
  extensions).
- SDK types: `MessageEndEvent` / `AssistantMessage` /
  `SessionStartEvent` carry no parent/child or subagent marker
  (`core/extensions/types.d.ts:405-411,517-524,550-553`;
  `@earendil-works/pi-ai/dist/types.d.ts:276-288`).
- Parent: `feature-reconnect-reproduction.md`.

## Implementation notes

- **Files changed**:
  - `pi-extension/src/session/subagent_gate.ts` (new) — pure `SubagentGate`
    class (depth counter with floor-at-0 + nesting), `SUBAGENT_TOOL_NAME`
    constant, and a process-singleton `subagentGate`. No SDK imports; fully
    unit-testable. Inline doc cites `@gotgenes/pi-subagents` provenance and
    the fork-local tradeoff.
  - `pi-extension/src/session/subagent_gate.test.ts` (new) — 9 unit tests
    covering active/inactive, non-subagent-tool no-op, nested subagents,
    floor-at-0 (stray exit + extra-exits), and reset.
  - `pi-extension/src/index.ts` — import `subagentGate`; `enter` call at the
    top of `tool_execution_start`, `exit` at the top of `tool_execution_end`;
    in `message_end` a `suppressForSubagent` flag (`role === "assistant" &&
    subagentGate.isActive()`) gates both the `_appendLegacySdkMessageToTranscript`
    call (suppresses live `agent_message` broadcast AND `assistant_committed`
    transcript event) and the failed-turn `provider_error` forwarding block.
    `user`/`toolResult` messages pass through unaffected.
- **Design decision (extraction)**: the gate is a pure module rather than
  inline module-level state in `index.ts`, because `index.ts`'s `pi.on`
  handlers have no direct test seam (the integration harness drives the full
  factory via MockRelay, not via `pi.on` event emission). Pure extraction
  follows ports/adapters (gate logic independent of the SDK harness) and
  makes the nesting/floor invariants directly unit-testable.
- **Replay-leak sub-question resolved**: suppress the transcript event too
  (not just the broadcast) — implemented by short-circuiting the
  `_appendLegacySdkMessageToTranscript` call entirely while the gate is
  active, so neither the live `agent_message` nor the `assistant_committed`
  transcript event (which feeds `session_sync`/`session_history` replay) is
  produced. The subagent's assistant text is never recorded for the session.
- **Discrepancies from design**: none.
- **Adjacent issues parked**: none.
- **Verification**: `corepack pnpm typecheck` ✓, `corepack pnpm build` ✓,
  `corepack pnpm test` ✓ (763 passed, 3 pre-existing skipped, 48 files —
  incl. the 9 new gate tests and the 171 extension integration tests, no
  regressions in the touched handlers).
- **Manual criterion (not yet run)**: rebuild `dist/` (done), restart pi,
  dispatch a subagent from the phone, confirm subagent assistant text no
  longer appears in mobile chat — including after a forced reconnect/replay.
  Deferred to the operator (the unit + integration tests prove the gate
  logic; the manual step proves the live-container surfacing).

## Implementation discovery (2026-07-07) — streaming leak path via `message_update`

The first implementation (gating only `message_end`) was insufficient. A live
capture with TEMP DEBUG instrumentation (file-append to
`~/.pi/remote/debug-leakfix.jsonl`, logging `message_update` + `message_end` +
`tool_execution_start`/`end` gate state) during a subagent dispatch revealed
the subagent's reply streams token-by-token via `message_update` (text_delta →
`agent_chunk` broadcast) **before** `message_end` fires:

```
19:04:22 tool_execution_start subagent  gate=true          ← gate ACTIVE (correct)
19:04:23 message_end user              gate=true           ← suppressed (correct)
19:04:24 message_update  delta="subagent probe ok" gate=true   ← LEAK (ungated streaming path)
19:04:24 message_end assistant model=gpt-5.3-codex-spark gate=true   ← suppressed (correct)
19:04:24 tool_execution_end subagent    gate=true→false
```

The `message_end` gate worked exactly as designed (`gate=true` throughout, the
subagent's assistant `message_end` suppressed). But the `message_update`
handler (`index.ts:1268`) broadcast `agent_chunk` deltas **with the gate
active** — I had not gated it. The phone received "subagent probe ok" via the
streaming path, one second before `message_end`.

**Fix applied**: added `if (subagentGate.isActive()) return;` to the
`message_update` handler, before the `_applyTurnAndPublish` /
`_owners.broadcast` calls. This suppresses the streaming `agent_chunk`
deltas during the subagent window, matching the `message_end` suppression.

The gate now covers both assistant-content broadcast paths:
- `message_update` → `agent_chunk` (streaming deltas) — gated
- `message_end` → `agent_message` (finalized text) + transcript event — gated

TEMP DEBUG instrumentation fully removed (src + dist); typecheck + build +
full test suite green (763 passed, 3 pre-existing skipped, 48 files).
