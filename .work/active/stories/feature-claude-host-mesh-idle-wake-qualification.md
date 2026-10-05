---
id: feature-claude-host-mesh-idle-wake-qualification
kind: story
stage: done
tags: [pi-extension, workflow]
parent: feature-claude-host-mesh-idle-wake
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Live qualification: which wake lane actually starts an idle Claude turn?

Design element: Unit 1 of `feature-claude-host-mesh-idle-wake` (the trickiest
unit — everything downstream gates on this evidence). Protocol reshaped by
the Opus architect review (2026-10-04; adjudication in the feature body).

## Protocol

Run from this repo's session (this agent is a mesh peer and can drive sends);
record command + observation + timestamp into the feature body under
`## Qualification evidence`. Fix N and T for the pass criteria BEFORE
running.

- **Q0 launch-path census** — every session class needing wake on this box
  (cmux panes via `cmux claude-teams`, NextUp nxuC staging, daemons, resume
  recovery) with exact command + flags. Gates the fleet-delivery decision
  (wrapper-only vs moving cmux-bootstrap onto the wrapper).
- **Q1 enablement prerequisites** — Claude Code version; auth mode +
  org/channel policy for dev channels; startup consent dialog behavior
  (per launch / per `--resume` / non-TTY); exact argv grammar of the
  dev-channels flag (variadic? repeatable? last-wins?); `--allowedTools`
  naming for MCP tools (`mcp__<server>__<tool>`?).
- **Q2 wake semantics — scenario matrix** (each cell: does a turn start,
  latency, what the woken turn does):
  default-permissions vs skip-permissions; get_messages pre-approved or
  not; burst of N; broadcast; two woken Claude peers replying to each other
  (loop?); wake mid-typing / permission dialog open / plan mode /
  compaction / after `--resume`; does `notification()` ever reject with
  channels off.
- **Q3 server-alive paths** — `--mcp-config` spawn timing (process alive
  before first tool call?); lock-contention `_failLoud` exit (second session
  same cwd); no-config never-join path; per path: sender-visible ACK state.
- **Q4 parallel lane: background-task wake** — does a completed background
  Bash job re-invoke an idle Claude Code session on this build? Prototype
  `outpost-pi mesh-wait` (blocking exit-on-message) in a scratch copy.
- **Hooks premise** — does the `Notification` hook (or any hook output)
  start a turn on an idle session? Check, don't assert.
- **Cross-PC + cost** — relay-forwarded message wakes identically? (and
  should it, given the trust model?) Tokens per woken turn; daily-cost
  estimate at realistic rates.

Operator authorization: standing (2026-10-04). Scratch-folder sessions;
idle panes cost nothing, woken turns cost one roundtrip.

## Acceptance evidence

- Q0–Q4 + premise checks recorded with Claude Code version
- Lane decision (channel-notification / mesh-wait / both) against the
  pre-declared pass criteria (N/N wakes within T seconds across the matrix)
- Fleet-delivery decision surfaced to the operator with the census

## Ordering

No dependencies. Units 2 (`-toggle`) and 3 (`-nudge`) depend on this
story's lane decision.
