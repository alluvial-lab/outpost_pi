# Session note: 2026-07-07 — relay logging shipped, Bug 2 mechanism fully traced, subagent-leak fix incomplete (third broadcast path)

## TL;DR

This session resolved Bug 2's *investigation* completely but the *fix* is
**incomplete and still leaking**. The subagent's "subagent probe ok" text still
appears in mobile chat after two fix attempts. The next session must find the
remaining ungated broadcast path.

## What shipped (committed, green)

1. **`story-relay-log-room-meta-update-accept-and-drop`** (ARCHIVED, stage:done)
   — relay INFO logging for `room_meta_update` accept/drop with `cross_room`
   flag. Deployed to the live relay container (`remote-pi-relay:0.2.0`
   rebuilt+swapped). This is the artifact that *resolved* Bug 2's cross-room
   hypothesis: `cross_room=false` everywhere → the session flip is the 7ADky
   Pi's own rotation, NOT a sibling overwrite. Review passed (fast-lane).

2. **Fork-posture docs** (commit `644512e`) — rewrote `AGENTS.md` +
   `.agents/rules/agent-discipline.md` to hard-fork / fork-local-default
   reality (rebrand to Outpost-Pi pending in `epic-rebrand-to-outpost-pi`).

## Bug 2 investigation — COMPLETE (mechanism fully traced)

Full chain in `story-mobile-cross-session-history-leak.md`:

- **The `subagent` tool** is `@gotgenes/pi-subagents` v18.0.1 (NOT pi-native,
  NOT our extension). Tool name `"subagent"`
  (`~/.pi/agent/npm/node_modules/@gotgenes/pi-subagents/src/tools/agent-tool.ts:132`).
- **In-process child session**: `createSubagentSession()` creates a child
  `AgentSession`, and line 177 "Children always load the parent's extensions
  and skills" + `session.bindExtensions()` (line 233) **re-binds our
  `remote-pi` extension** to the child. So the child's `message_end` fires
  with our handler bound → broadcasts subagent text to the phone.
- **SDK exposes no subagent/source marker**: `MessageEndEvent`,
  `AssistantMessage`, `AgentStartEvent`, `SessionStartEvent` carry no
  parent/child or subagent field (verified against SDK type defs). So the
  extension cannot filter on metadata.
- **Cross-room leak RULED OUT**: `cross_room=false` in live relay logs →
  the session flip is the 7ADky Pi's own rotation (h1), not a sibling
  overwrite (h2). The `cross_room` logging earned its keep here.
- **Firing order confirmed** (second capture, `debug-firings.jsonl`): the
  subagent's `assistant` `message_end` fires **between**
  `tool_execution_start("subagent")` and `tool_execution_end("subagent")`.
  So a tool-execution-window gate works and is model-independent.

## Bug 2 fix — INCOMPLETE (still leaking)

**Story**: `story-extension-suppress-subagent-assistant-broadcast`
(stage: review, but **DO NOT advance to done** — the live repro still leaks).

### Fix shipped (commit `1cb8cf0`, dist rebuilt, pi restarted)

- New pure module `pi-extension/src/session/subagent_gate.ts`:
  `SubagentGate` depth counter (floor-at-0, nesting-safe), keyed on
  `toolName === "subagent"`. Process singleton `subagentGate`. 9 unit tests.
- Wired into `index.ts`: `enter`/`exit` in `tool_execution_start`/`end`;
  `suppressForSubagent` flag gates `message_end` (both the
  `_appendLegacySdkMessageToTranscript` call AND the failed-turn
  `provider_error` forwarding).
- **Second fix** (commit `1cb8cf0`): added
  `if (subagentGate.isActive()) return;` to `message_update` (the streaming
  `agent_chunk` path), which the first fix missed.

### Why it's still leaking (confirmed live 2026-07-07 ~19:06 UTC)

Operator restarted pi with the latest dist (both `message_update` AND
`message_end` gated — confirmed in `dist/index.js`: 2
`subagentGate.isActive` refs, 0 debug refs). Dispatched a subagent.
**"subagent probe ok" STILL appeared in mobile chat.**

The debug capture (before it was removed) proved the gate IS active and
correct during the subagent window — both `message_end` and `message_update`
fired with `gate=true`. So the leak is coming from a **third broadcast path**
that neither handler gates.

### The remaining broadcast paths (NOT yet gated)

`_owners.broadcast` is called from ~13 sites in `index.ts` (grep
`_owners.broadcast`). The gated ones are:
- `:1267` `message_update` → `agent_chunk` (gated)
- `message_end` → via `_appendLegacySdkMessageToTranscript` → projection
  `broadcast` callback at `:1176`/`:1516` (gated via `suppressForSubagent`)

**Ungated candidate paths** (likely culprits — the subagent's content could
reach the phone through any of these):
- `:1225` `message_start`? → `user_input` broadcast (the `input` handler)
- `:1288` `tool_execution_start` → `tool_request` broadcast (this is fine —
  shows "subagent running", not the leak text)
- `:1322` `_owners.broadcast(msg)` — need to read context (line ~1322)
- `:1374` `_owners.broadcast(errMsg)` — error forwarding
- `:1394` `agent_end` → `agent_done` broadcast
- `:1451` `compaction`
- `:1980`, `:1988` `tool_result`
- `:2060`, `:2130`

### NEXT STEP (for the fresh session) — instrument `_owners.broadcast` directly

Stop gating individual handler call sites. Instead, **instrument
`_owners.broadcast` itself** to log every message `type` that goes out during
a subagent dispatch. This finds the exact remaining path in one capture.

Concrete plan:
1. In `index.ts`, wrap or log at the `_owners.broadcast` definition (or the
   `broadcast:` callback at `:1176`/`:1516`). Simplest: add a TEMP DEBUG
   `appendFileSync` at the top of the `broadcast:` callback
   (`:1176`) logging `{ ts, type: message.type, gateActive: subagentGate.isActive() }`.
   ALSO instrument `_owners.broadcast` call sites directly if the projection
   callback isn't the path — but the callback at `:1176` is the projection's
   output channel, so start there.
2. Rebuild, restart pi, dispatch a subagent, read the log.
3. Whichever `type` (e.g. `agent_chunk`, `agent_message`, `agent_done`,
   `tool_result`) appears with `gateActive=true` during the subagent window
   AND carries subagent content → that's the ungated path.
4. Gate it.
5. **Cleanest eventual fix**: rather than gate N call sites, gate at the
   source — make `_owners.broadcast` (or the projection output) check
   `subagentGate.isActive()` and drop assistant-content messages. But this
   risks suppressing legitimate `agent_done`/`tool_result` for the main
   agent's turn that wraps the subagent — needs the capture to know which
   types to drop.

## Other open items (parked, lower priority)

- **Reorder-fix deploy** (HIGHEST severity, deferred): the 77% inbound drop
  rate (8640 room-mismatch / 2534 enqueue). Fix `ca555be` in source
  (`story-fix-transport-active-room-reestablishment-on-reconnect`,
  stage:review), NOT deployed. This silently discards most agent output and
  is the primary driver of the degraded chat experience. Deploy =
  rebuild+sideload the app. Elevated-urgency evidence on the story
  (commit `f8891ef`).
- **Bug 1** (`story-mobile-send-timeout-relay-room-main-mismatch`): the
  relay-drop mechanism was discredited by re-inspection (directionality
  backwards; zero phone-originated drops). Still needs the actual failure
  path re-confirmed (app-transport-stuck vs Pi-didn't-echo) via extension
  debug log at a fresh repro. Lower priority than the reorder deploy.
- **Rebrand epic** `epic-rebrand-to-outpost-pi` (backlog) — operational,
  not a defect.

## Files / state for the next session

- **The fix story**: `.work/active/stories/story-extension-suppress-subagent-assistant-broadcast.md`
  (stage: review — **do not advance**; has full implementation-discovery
  notes including the streaming-path finding).
- **The gate module**: `pi-extension/src/session/subagent_gate.ts` +
  `subagent_gate.test.ts` (committed, correct, 9 tests green).
- **The investigation story**: `.work/active/stories/story-mobile-cross-session-history-leak.md`
  (stage: drafting, has the full mechanism trace, SDK findings, and the
  resolved/ruled-out hypotheses).
- **`dist/` is rebuilt** with the two-gate fix (commit `1cb8cf0`) but the
  leak persists — so the next instrumentation must be added on top.
- **Throwaway debug logs** (safe to delete): `~/.pi/remote/debug-leakfix.jsonl`,
  `~/.pi/remote/debug-firings.jsonl`, `~/.pi/remote/debug-message-end.jsonl`.
- **Ring logs** in `debug/` (gitignored): `a35-11f1-...bin` is the latest
  capture (includes the still-leaking repro).
- **Relay container** `remote-pi-relay:0.2.0` has the `cross_room` logging
  live (from the archived story).

## Key commands for the next session

```bash
# verify the gate is in the loaded dist
grep -c "subagentGate.isActive" pi-extension/dist/index.js   # expect 2

# build after adding instrumentation
cd pi-extension
export PNPM_HOME=~/projects/remote_pi/.pnpm-store
export npm_config_cache=~/projects/remote_pi/.npm-cache
export XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache
corepack pnpm typecheck && corepack pnpm build && corepack pnpm test

# relay cross_room grep (for any cross-room question)
docker logs remote-pi-relay 2>&1 | grep "cross_room=true"
```

## Lesson for the next session

Don't gate individual handler call sites one at a time — there are ~13
`_owners.broadcast` sites. Instrument the broadcast *sink* once to find all
leaking types, then gate at the right layer. The streaming-path miss
(`message_update`) was avoidable: the SDK fires `message_update` for every
token, which is obvious in hindsight, but I only discovered it via live
capture. A sink-level instrument would have caught it in one pass.
