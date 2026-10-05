---
id: feature-claude-host-mesh-idle-wake
kind: feature
stage: implementing
tags: [pi-extension, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Claude-host mesh idle wake — reliable inbound-message delivery to idle Claude sessions

## Brief

On Pi hosts, inbound mesh peer→agent messages are delivered into the agent's
turn (with busy-batching, flush at `agent_settled`). On Claude hosts the
agent-network skill surfaces messages via the `get_messages` MCP tool —
pull-only — so an idle Claude session never sees inbound mesh messages until
the operator starts a turn to jostle it. Cross-app coordination stalls
whenever the Claude side is idle (observed 2026-10-04, claude-nextup session).

This feature closes that gap: qualify a wake mechanism that makes inbound
mesh messages reach an idle Claude Code session without human jostling, and
land the chosen mechanism as a first-class (toggleable) capability.

Origin: operator finding via the projects-root fleet session (2026-10-04,
fleet CHANGELOG); parked as `backlog-claude-host-mesh-delivery-pull-only`,
promoted same day.

## Strategic decisions (scoped 2026-10-04)

- **Mechanism: qualification-first, not pre-committed.** Empirically qualify
  candidate wake lanes end-to-end before landing one. — The unknowns are
  qualification facts.
- **Default posture: wake ON for this fleet's Claude sessions** (operator:
  "I'd at least want it on here"), exposed as an explicit toggle rather than
  a silent hard-wired default. — Pi hosts already wake by default; the box's
  operator-piloted sessions want parity. Public/default posture for other
  consumers is a design-time call informed by qualification.
- **rc-HTTP-nudge lane: out of scope here — handed to NextUp.** Parked there
  as `mesh-idle-wake-rc-nudge` (nextup commit 93f4ae2) with pickup/void
  conditions; double-wake race is the noted interaction. This feature stays
  single-repo (mesh-server + wrapper + skill + docs).

## Review adjudication (Opus 5.5 architect lane, 2026-10-04, claude -p)

Review artifact: `~/.claude/plans/you-are-the-architect-lane-compiled-blossom.md`.
Verified load-bearing claims against the tree before folding in (cmux
launch line, cwd-detection argv, sampling semantics). Disposition:

- **Accepted, design-changing**: P1 fleet launch path never sees the wrapper
  toggle (cmux claude-teams); P2 the invariant narrows the wrong thing (wake
  changes *who can start a turn*, not permissions — "initiative" is its own
  authority class); P3 no storm/loop control → server-side edge-triggered
  coalescing + rate cap; P4 nudge stalls on get_messages approval → pair
  with --allowedTools pre-approval; P5 --mesh-wake placement breaks cwd
  detection → filter before cwd detection; P6 sampling is not a wake
  mechanism (returns completion to server, not a session turn) → fallback
  replaced with background-task wake and PTY/cmux injection candidates,
  qualified in parallel; P7 lazy-spawn likely misdiagnosis → demoted, lock
  contention + no-config silent killers elevated; P8 the no-op catch
  detects nothing; P9 dev-channels flag argv grammar unverified; P12
  research-preview prerequisites (auth mode, org policy, startup consent
  dialog) enter Q1.
- **Accepted, protocol-level**: launch-path census (Q0); Q2 becomes a
  scenario matrix (permissions × pre-approval × burst × broadcast ×
  two-peer loop × mid-typing/dialog/plan-mode/compaction/resume); Q3 adds
  lock-contention and no-config paths with sender-visible ACK states; pass
  criteria (N/N wakes within T seconds) so "unreliable" is defined;
  cross-PC wake question (trust model); measured cost per woken turn;
  hooks premise weakened (Notification hook fires on idle — check, don't
  assert); P11 delivered-semantics wording (received = buffered, not
  handled; inbox is in-memory and dies with the MCP process).
- **Partially accepted**: P7 — lazy-spawn narrative demoted but Q3 still
  measures spawn timing (cheap, and the fleet's nxuC staging is a different
  mechanism whose lazy behavior was real in the CHANGELOG's terms).

## Architectural choice

Candidate architectures (post-review):

- **A. Channel-notification lane + wrapper toggle** — the server already
  emits `notifications/claude/channel`; missing pieces are launch-side
  enablement, coalescing, pre-approval pairing, and docs/tests. Rides a
  research-preview development channel with no compatibility contract, a
  startup consent dialog, and auth-mode prerequisites.
- **B. Background-task wake** — a blocking `outpost-pi mesh-wait` command
  the agent runs as a background Bash job; Claude Code re-invokes the
  session when a background task completes; the skill re-arms it each turn.
  Uses supported surfaces, no dev channel; costs one always-running
  background job per session and adds a re-arm discipline to the skill.
- **C. PTY/cmux injection** — the orchestrator (or a wrapper-owned PTY)
  types a "check get_messages" line into the idle session. No Claude Code
  surface dependency at all; orchestrator-side, overlapping with NextUp's
  rc-nudge lane.
- **D. Hooks** — weakened premise: the `Notification` hook fires on idle
  prompts; whether any hook output can START a turn is a qualification
  question, not an assumption. Evaluate-and-drop unless it surprises.

**Chosen: qualify A and B in parallel** (B replaces the dead sampling
fallback — MCP `sampling/createMessage` returns a completion to the server,
it cannot inject a session turn, so the original fallback could never wake
anything). C stays recorded as the orchestrator-side lane; D is a premise
check. Landing picks the lane that passes the pass-criteria; A is preferred
if both pass (no re-arm discipline needed), B is the supported-surface
fallback.

## Design decisions

- **Toggle: wrapper-owned `--outpost-mesh-wake`** (namespaced so a future
  Claude Code flag of the same short name can't be silently swallowed by
  the wrapper's interception). Intercepted at any argv position and
  filtered out **before cwd detection** (P5: `splitClaudeCliArgs` treats
  only a leading non-flag token as cwd; filtering after would mis-launch
  and pass the path to claude as a prompt). Expands to
  `--dangerously-load-development-channels=server:outpost-pi-mesh` (canonical
  `=`-form; exact argv grammar — variadic/repeatable/last-wins — recorded
  in Q1 before dedupe logic is finalized). Dedupe against a raw
  dev-channels flag already present in passthrough.
- **Two guards, not one narrowed guard (P2)**: (1) *authority* — the
  wrapper never injects `--dangerously-skip-permissions` (absolute);
  (2) *initiative* — the dev-channels flag only via `--outpost-mesh-wake`,
  documented as **"lets mesh peers start turns"**. Initiative is its own
  authority class: today only the operator can start a turn; with wake, any
  mesh peer can — including cross-PC peers whose relay traffic is not
  end-to-end encrypted. The tutorial warns specifically about combining
  both flags, which is the fleet's real configuration
  (cmux claude-teams runs skip-permissions).
- **Fleet delivery path — per-surface flag, not wrapper migration (P1,
  corrected 2026-10-04 after ground-truthing the live launches)**: three
  launch surfaces exist. (a) The bespoke claude-nextup launch
  (`claude-rc --remote-control` + hand-written ephemeral `--mcp-config` +
  skill append, `nxuC` via env) — gains the wake flag by editing its tmux
  launch line, zero code. (b) `scripts/cmux-bootstrap-agents.sh` →
  `cmux claude-teams` dispatch panes — the script appends the flag when
  wake is wanted; migrating these onto `outpost-pi claude` was considered
  and REJECTED: the wrapper invokes plain `claude`, which would drop the
  `claude-teams` hooks the cmux orchestrator's `agent.hook.*` events depend
  on. (c) The product wrapper gets the `--outpost-mesh-wake` toggle for
  everyone else. Q0's census records each surface's exact command.
- **Local-only wake by default (trust simplification 2026-10-04)**: the
  live mesh has zero cross-PC peers — every peer is a local session this
  operator runs, so peer-initiated turns among them are the feature, not a
  threat. Designed default: local peers wake; a cross-PC message (`<pc>:`
  prefix on `from`) lands in the inbox WITHOUT waking — visible at the next
  turn drain. The relay's cross-PC traffic is not E2E, so remote-initiated
  unattended turns stay opt-in forever rather than becoming an ambush the
  day a second PC peers.
- **Notification is edge-triggered and coalesced in the server (P3)**:
  notify only on the inbox's empty→non-empty transition; re-arm when
  `get_messages` drains it. A burst or broadcast becomes one wake. Backstop:
  a global wake rate cap (e.g. notify at most once per N seconds) against
  two woken peers ping-ponging — the cap does not drop inbox messages, only
  additional wakes.
- **Nudge pairs with pre-approval (P4)**: when `--outpost-mesh-wake` is set
  the wrapper also passes
  `--allowedTools mcp__outpost-pi-mesh__get_messages` (exact flag/tool-name
  grammar verified in Q1) so the woken session can drain without an
  approval dialog — otherwise an unattended wake stalls on the very tool
  call the nudge requests. `from` and any preview content are treated as
  untrusted input (escaped/quoted; no raw body in the nudge).
- **Nudge carries no payload**: `get_messages` stays the single
  authoritative drain surface; a full-body channel message would let the
  model reply without draining, leaving a stale inbox duplicate.
- **No wake-state detection exists (P8)**: an un-opted client silently
  ignores the custom notification — the `.catch` fires only on transport
  errors. The server cannot know whether wake is active; the comment and
  any adaptive behavior must not pretend otherwise.
- **Skill discipline**: turn-start `get_messages` drain stays mandatory
  (fallback + authoritative surface); the skill documents wake mode (nudge
  may arrive before/without a drain) and corrects delivery semantics
  (received = buffered by the peer's MCP process, not handled; the inbox is
  in-memory and dies with the process — SKILL.md's "Delivery is reliable"
  line gains this precision).

## Qualification evidence (2026-10-05, story -qualification; Claude Code 2.1.289, Opus 5.5 · Claude Max, auth = claude.ai OAuth)

Scratch cell: `/tmp/wakequal` via `outpost-pi claude <dir> <flag>` in tmux;
sender = this repo's Pi session on the mesh; pane observed via capture-pane.

**Q2 core — channel-notification wake: PASS 3/3 within 15s** (declared
criteria N=3/T=15s), launched with
`--dangerously-load-development-channels server:outpost-pi-mesh`:

- Wake 1 (single): turn started ~6–8s after ACK. The channel notification
  renders as a session input (`← outpost-pi-mesh: 📨 Message from …`),
  the turn runs with no typed text. Woken turn: 13s, ~350–1000 tokens.
- Wake 2 (single): turn started ~4–6s; 7s total (tools already loaded).
- Burst (3a+3c simultaneous, 3b +6s after sender-side error): 3a+3c
  **coalesced into ONE turn client-side** (same-timestamp inputs); 3b got
  its own turn. ⇒ Claude Code merges simultaneous notifications; messages
  straddling turn boundaries each wake — server-side edge-triggered
  coalescing still adds value, and the rate cap remains the loop backstop.
- Permission mode: this box's default is "auto mode" — **no approval
  stalls** on MCP tool calls. Strict default-perms cell NOT run (public-
  consumer concern only; the --allowedTools pairing is designed anyway).
  P4 stall remains unconfirmed-but-plausible for gated modes.
- Woken-session self-report: full message text arrives inline but without
  the message id (nudge redesign notes the id must come from the drain).

**Q1 enablement paths:**

- `--dangerously-load-development-channels server:<name>` — space form
  parses; **consent dialog every launch** (default option 1 = proceed; one
  Enter). Hidden from `claude --help`.
- `--channels server:<name>` — accepted, **no dialog, but silent no-op**:
  session idles, message buffers in inbox (pull intact), NO wake. The
  "approved channels" registration surface is unknown — open follow-up if
  the dangerous flag ever needs replacing.
- `--allowedTools` grammar: space/comma-separated variadic list
  (`--allowedTools mcp__outpost-pi-mesh__get_messages` shape; exact MCP
  tool naming to confirm at landing).

**Q3 server-alive paths:**

- Spawn timing: MCP process spawns **eagerly at session start** (no lazy
  process spawn for --mcp-config on 2.1.289); one early respawn observed
  then stable. Tool **schemas** lazy-load — the first wake costs one extra
  tool-search call (this is the real "lazy" the fleet CHANGELOG named).
- Lock contention (second session, same cwd): second MCP retry-then-
  `failLoud`-exits; main TUI looks normal; `/mcp` shows `✘ outpost-pi-mesh`
  (visible if checked, not proactive). Folder-keyed address ⇒ sender still
  gets "Delivered" — to the lock holder. Silent-wake-death risk confirmed
  as designed-for.
- No-config path: not live-tested (wizard gates it on the wrapper);
  code-level analysis stands (stays connected, never joins, tools report
  why).

**Q4 background-task wake: PASS** — idle session with a background
`sleep 25` started a new turn on task completion
(`● Background command … completed (exit code 0)` → `✻ Brewed for 1s`).
**Lane B (`outpost-pi mesh-wait` as a background task) is viable** on
supported surfaces with no dev channel.

**Hooks premise:** not live-tested (both lanes passed; deprioritized).
`Notification`-hook-can-start-a-turn remains an open footnote.

**Cross-PC:** no `<pc>:` peers exist today — untestable; local-only-wake
default stands as designed.

**Cost:** woken turns 3–13s wall, ~350–1000 tokens each. Negligible at
current fleet message rates.

**Lane decision: Lane A lands** (channel notification via the dangerous
flag + consent-Enter). It passed 3/3 + burst; consent dialog is the one
operational wrinkle — per-launch one Enter (operator or launch script
send-keys). Lane B is confirmed viable and stays the documented fallback
if the dev channel drifts or the consent burden becomes a problem.
Fleet wake-on = append the flag to the claude-nextup tmux launch line
(per-surface delivery decision, already recorded).

## Implementation Units

### Unit 1: Live qualification protocol (trickiest — designed first)
**File**: no product code; evidence lands in this feature body (`##
Qualification evidence`), driven from this repo's session via mesh tools
**Story**: `feature-claude-host-mesh-idle-wake-qualification`

- **Q0 launch-path census** — every session class that needs wake on this
  box (cmux panes, NextUp nxuC staging, daemons, resume recovery) and the
  exact command + flags each launches with. Gates the fleet-delivery
  decision.
- **Q1 enablement prerequisites** — Claude Code version; auth mode (claude.ai
  vs API key) and org/channel policy for development channels; startup
  consent dialog behavior (per launch, per `--resume`, non-TTY); exact argv
  grammar of the dev-channels flag; `--allowedTools` tool-name grammar for
  MCP tools.
- **Q2 wake semantics — scenario matrix** — for each cell, does a turn
  start, within what latency, and what does the woken turn do:
  default-permissions vs skip-permissions; get_messages pre-approved or
  not; burst of N messages (how many turns?); broadcast; two woken Claude
  peers replying to each other (loop?); wake while operator mid-typing /
  permission dialog open / plan mode / compaction / after `--resume`;
  whether `notification()` ever rejects with channels off (P8 check).
- **Q3 server-alive paths** — spawn timing of `--mcp-config` servers
  (process alive before first tool call?); lock-contention exit (second
  session, same cwd → `_failLoud`); no-config never-join path; for each:
  what the SENDER's ACK reports (received/timeout/denied) so silent
  wake-death is visible from the other side.
- **Q4 parallel lane: background-task wake** — does a completed background
  Bash job re-invoke an idle Claude Code session on this build? Prototype
  `outpost-pi mesh-wait` (blocking exit-on-message) in a scratch copy; if
  the re-invoke behavior holds, B is live.
- **Hooks premise** — does the `Notification` hook (or any hook output)
  start a turn on an idle session? Check, don't assert.
- **Cross-PC + cost** — does a relay-forwarded message wake identically
  (and should it, given the trust model?); tokens per woken turn measured;
  rough daily-cost estimate at realistic message rates.
- **Pass criteria**: N/N wakes within T seconds across the Q2 matrix (N, T
  fixed before running) — this defines "unreliable", the lane-switch
  trigger.

**Acceptance Criteria**:
- [ ] Q0–Q4 + premise checks recorded with Claude Code version
- [ ] Lane decision (A / B / both) with rationale against pass criteria
- [ ] Fleet-delivery decision surfaced to the operator with the census

### Unit 2: Wrapper `--outpost-mesh-wake` toggle
**File**: `pi-extension/src/extension/command_surface/standalone_cli.ts`
**Story**: `feature-claude-host-mesh-idle-wake-toggle` (depends on Unit 1's
lane decision)

```ts
/** Wrapper-owned wake opt-in, namespaced against future claude flags. */
export const MESH_WAKE_FLAG = "--outpost-mesh-wake" as const;

export function splitClaudeCliArgs(args: readonly string[]): {
  targetCwd: string;             // detected AFTER MESH_WAKE_FLAG is filtered
  meshWake: boolean;
  passthroughArgs: string[];     // MESH_WAKE_FLAG removed; raw dev-channels
                                 // flag left verbatim (expansion skipped)
};

export function buildClaudeLaunchArgs(
  mcpConfigPath: string,
  skillPath: string | null,
  meshWake: boolean,             // appends dev-channels expansion +
): string[];                     // get_messages --allowedTools pre-approval
```

**Implementation Notes**:
- Filter `--outpost-mesh-wake` BEFORE cwd detection (P5 regression test:
  `["--outpost-mesh-wake", "/tmp/proj"]` → cwd `/tmp/proj`, no prompt
  positional in passthrough).
- Two-guard invariant comment + test rewrite (authority absolute;
  initiative only via the toggle). JSDoc per documentation-conventions.
- Dedupe logic finalized against Q1's recorded argv grammar.
- README + site tutorial: toggle docs, initiative framing, explicit warning
  on combining wake with skip-permissions.

**Acceptance Criteria**:
- [ ] flag at any position → exactly one expansion + pre-approval flag;
      cwd detection unaffected (regression test for the leading-flag case)
- [ ] raw dev-channels flag present → no duplicate/clobber
- [ ] `--dangerously-skip-permissions` never injected (absolute guard)
- [ ] README/tutorial updated with the two-guard framing

### Unit 3: Edge-triggered coalesced wake notification
**File**: `pi-extension/src/mcp/mesh_server.ts`
**Story**: `feature-claude-host-mesh-idle-wake-nudge` (depends on Unit 1's
lane decision; voids if the channel lane dies)

```ts
/** Human/model-readable wake nudge. Carries NO message body — get_messages
 *  stays the single authoritative drain surface — and treats `from` as
 *  untrusted input (escaped). */
export function wakeNudgeContent(from: string): string;

/** True when the inbox transitioned empty→non-empty (edge trigger). */
export function shouldWake(inboxLengthBefore: number): boolean;
```

**Implementation Notes**:
- Notify only on empty→non-empty; re-arm when `get_messages` drains to
  empty. Burst/broadcast → one wake.
- Global wake rate cap (floor on notification frequency) as the loop
  backstop; inbox itself never drops messages.
- Replace the misleading `.catch` comment: no wake-state detection exists
  (P8) — the catch covers transport errors only.

**Acceptance Criteria**:
- [ ] unit tests: nudge content (sender escaped, names get_messages, no
      body); edge-trigger logic (burst → one wake; drain re-arms)
- [ ] rate-cap behavior tested
- [ ] agent-network skill (repo source): wake-mode note + delivered-
      semantics precision (received = buffered, in-memory inbox)
- [ ] typecheck + test + build green

---

## Implementation Order
1. `feature-claude-host-mesh-idle-wake-qualification` (Unit 1)
2. `-toggle` (Unit 2) and `-nudge` (Unit 3) — parallelizable after 1

## Simplification
- Tutorial's two-flag conflation simplifies into the two-guard framing
  (authority vs initiative) — sharper, not longer.
- No deletions; no-op catch + polling fallback retained deliberately.

## Testing
- Wrapper: interception/expansion/dedupe/cwd-ordering + narrowed-guard
  regression (launch-contract invariants).
- Server: nudge content + edge-trigger + rate-cap units (extracted pure
  helpers; the script's module-load side effects resist direct import).
- Qualification: evidence in the feature body; automated e2e out of scope.

## Risks
- **Riskiest assumption**: a channel notification starts a turn at all —
  front-loaded in the Q2 matrix with defined pass criteria; B runs in
  parallel so a dead A doesn't restart design from zero.
- **Initiative + skip-permissions (cmux dispatch panes' config)**: wake
  lets mesh peers start turns that then run with no approval gate in panes
  launched with skip-permissions. Untrusted-input handling + the tutorial
  warning are designed in; the piloted claude-nextup session does NOT run
  skip-permissions (woken turns there still face the approval gate), and
  local-only wake bounds the exposure to this box's own sessions.
- **Dev-channel drift**: research-preview surface, consent dialog, auth
  prerequisites — version-stamped evidence keeps future breakage
  diagnosable; B is the supported-surface exit.
- **Silent wake-death**: lock contention / no-config paths kill the MCP
  join without wake-specific signal — Q3 records sender-visible ACK states
  so the other side sees it.
- **Double-wake race** with NextUp rc-nudge — coordination on-mesh,
  conditions recorded.
- **Quota/cost**: measured per woken turn in qualification; rate cap bounds
  loop burn.

## Grounding (scoping evidence, retained)

- The server side already fires the wake: `mesh_server.ts` pushes
  `notifications/claude/channel` on every inbound peer message (presence
  envelopes filtered), no-op catch when channels aren't enabled. Works only
  with `--dangerously-load-development-channels server:outpost-pi-mesh` —
  per current docs the only known enablement path.
- The 2026-10-04 claude-nextup session staged the mesh MCP as `nxuC` on
  lazy spawn (NextUp's own staging, not the wrapper) — spawn-timing
  behavior may differ from `--mcp-config`; Q3 measures ours.
- Pi-side contrast: `_deliverMeshMessageToAgent` injects and triggers the
  turn, batching while busy (post-complaint hardening, archived
  `backlog-mesh-message-wake-interrupts-agent`).
- Launch surfaces ground-truthed 2026-10-04 (ps + tmux): the live
  claude-nextup session is a bespoke `claude-rc --remote-control` launch
  (hand-written ephemeral --mcp-config + skill append, nxuC via env, no
  skip-permissions); the cmux 4-pane dispatch fleet (claude-teams,
  skip-permissions, hooks for orchestrator events) is not currently
  running; the product wrapper has no live sessions on this box.
- NextUp-side Claude sessions run with plugin disables (their policy
  b561e12, expedience — operator: reversible). No current wake lane needs
  a Claude-side plugin.
- Code surfaces (all this repo): `pi-extension/src/mcp/mesh_server.ts`,
  `pi-extension/src/extension/command_surface/standalone_cli.ts` (+test),
  `pi-extension/skills/agent-network/SKILL.md`, site claude-mesh tutorial,
  `pi-extension/README.md`, `scripts/cmux-bootstrap-agents.sh`.
