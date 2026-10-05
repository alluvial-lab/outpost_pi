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
land the chosen mechanism as a first-class (toggleable) launcher capability
of `outpost-pi claude`.

Origin: operator finding via the projects-root fleet session (2026-10-04,
fleet CHANGELOG); parked as `backlog-claude-host-mesh-delivery-pull-only`,
promoted same day.

## Strategic decisions (scoped 2026-10-04)

- **Mechanism: qualification-first, not pre-committed.** Empirically qualify
  the existing `notifications/claude/channel` wake end-to-end before building
  anything new; fall back to the MCP server→client sampling-request lane only
  if the dev channel proves unreliable. — The wake already exists server-side;
  the unknowns are qualification facts.
- **Default posture: wake ON for this fleet's Claude sessions** (operator:
  "I'd at least want it on here"), exposed as a wrapper toggle rather than a
  silent hard-wired default. — Pi hosts already wake by default; the box's
  operator-piloted sessions want parity. Public/default posture for other
  consumers is a design-time call informed by qualification (dev-channel
  stability risk).
- **rc-HTTP-nudge lane: out of scope here — handed to NextUp.** The
  remote-control HTTP channel is a NextUp-side surface; the candidate nudge
  lane was handed to the NextUp resident agent (mesh handoff 2026-10-04) and
  is parked there as `mesh-idle-wake-rc-nudge` (nextup commit 93f4ae2), with
  pickup conditions (this feature qualifies+lands; rc channel verified able
  to inject a turn noninteractively) and a void-if-covered condition (voids
  if the channel-notification path here fully covers idle wake). Their side
  will coordinate on-mesh before implementing — double-wake race (rc
  injection + channel notification) is the noted interaction to avoid.
  This feature stays single-repo (mesh-server + wrapper + skill + docs).

## Grounding (scoping evidence)

- The server side already fires the wake: `mesh_server.ts` pushes
  `notifications/claude/channel` on every inbound peer message (broker/system
  presence envelopes filtered out), with a no-op catch when channels aren't
  enabled. It works only when Claude Code is launched with
  `--dangerously-load-development-channels server:outpost-pi-mesh` — per
  current docs the ONLY known enablement path; the wrapper forwards such
  flags verbatim but never passes this one itself.
- The 2026-10-04 claude-nextup session ran the mesh MCP staged on **lazy
  spawn** — while idle the server process may not exist: nothing subscribes
  to the broker, nothing buffers, nothing can notify. At least two candidate
  causes for the observed pull-only behavior: flag absent, and/or server not
  alive while idle.
- Candidate directions from the operator finding: (a) MCP sampling request
  when a message lands (if Claude Code honors sampling, that starts a turn);
  (b) rc-HTTP nudge — deferred to NextUp per strategic decisions; (c) Claude
  Code hooks that force-check `get_messages`. Hooks cannot wake a truly idle
  session (no hook events fire while idle — they only cover turn boundaries,
  which the skill's turn-start discipline already covers): expect
  evaluate-and-drop unless qualification proves otherwise.
- Pi-side contrast: `_deliverMeshMessageToAgent` injects and triggers the
  turn, batching while busy (landed after the characterized interruption
  complaint, archived `backlog-mesh-message-wake-interrupts-agent`). Claude
  hosts have no equivalent.
- NextUp-side Claude sessions currently run with plugin disables (their
  project policy b561e12, expedience against bundled-CLI drift — operator:
  reversible, plugins can be toggled back on). No current wake lane needs a
  Claude-side plugin, but don't treat that policy as a hard constraint if a
  design lands there.
- Code surfaces (all this repo): `pi-extension/src/mcp/mesh_server.ts`,
  `pi-extension/src/extension/command_surface/standalone_cli.ts`
  (`outpost-pi claude` launcher + flag passthrough),
  `pi-extension/skills/agent-network/SKILL.md` (source; `~/.pi/remote` is the
  deployed copy), `site/src/app/tutorials/claude-mesh/page.tsx`,
  `pi-extension/README.md`.

## Qualification ladder (design inputs, not a plan)

1. Enumerate Claude Code enablement paths for the channel notification
   (flag is documented; settings.json/env equivalent — unknown, verify
   against current Claude Code).
2. Qualify the existing wake live: relaunch a Claude mesh session with the
   flag, send it a mesh message while idle, observe whether a turn starts;
   repeat with the MCP lazily-spawned vs already-running to pin the lazy-spawn
   interaction (does a down server mean dropped messages, or does the broker
   queue for absent peers?).
3. If the dev channel is unreliable: qualify the sampling-request lane
   (does Claude Code honor server-initiated sampling on this build? approval
   UX for operator-piloted sessions?).
4. Hooks lane: confirm the idle-no-events premise; expected evaluate-and-drop.

## Architectural choice

Three candidate architectures:

- **A. Wrapper toggle over the existing channel-notification lane** — the
  server already emits `notifications/claude/channel` on every inbound peer
  message; the only missing piece is launch-side enablement plus docs/tests.
  Optimizes for minimal new machinery and reuse of shipped code; sacrifices
  stability guarantees (rides a Claude Code development channel with no
  compatibility contract).
- **B. Server-initiated sampling-request lane as primary** — MCP-documented
  capability, potentially stabler than a dev channel; but each wake costs a
  model roundtrip with approval UX, and Claude Code's honoring of
  server-initiated sampling is unverified on this box.
- **C. Hooks lane** — dead on arrival for true idle: Claude Code fires no hook
  events in an idle session, so hooks only reinforce turn boundaries the
  skill's turn-start drain already covers.

**Chosen: A**, with B sketched as a conditional fallback unit that activates
only if qualification kills the dev-channel lane. This implements the locked
strategic decision (qualification-first) and keeps the landing single-repo.

## Design decisions

- **Toggle shape: wrapper-owned `--mesh-wake` flag** — intercepted by the
  wrapper (any position, filtered from passthrough) and expanded to
  `--dangerously-load-development-channels server:outpost-pi-mesh` on the
  claude argv. If the passthrough already carries that raw flag, skip
  expansion (dedupe). No env-var twin — one source of truth; fleet launch
  scripts can append a flag as easily as an env. — Minimal surface, explicit
  operator intent, composes with the existing verbatim passthrough.
- **Guarded-invariant change (explicit)**: `buildClaudeLaunchArgs`'s
  "never inject a `--dangerously-*` flag" regression guard narrows to
  "never inject `--dangerously-skip-permissions`; the dev-channels wake flag
  only via explicit `--mesh-wake`". The safe-default principle is about not
  silently widening Claude's *authority*; the wake flag starts turns but
  changes no permission policy — a woken Claude still faces its approval
  gate. Test + JSDoc updated together with this rationale in the landing
  story; the guard against authority-widening stays absolute.
- **Notification content becomes a nudge, not a payload** — on wake, emit
  `📨 mesh message from <from> arrived — call get_messages to read it and
  reply (echo its id via re)` instead of the current full-body dump. Keeps
  `get_messages` the single authoritative drain surface; a full-body channel
  message would let Claude reply without draining, leaving a stale duplicate
  in the inbox that resurfaces at the next turn boundary. — Single source of
  truth on the inbox.
- **Skill discipline unchanged**: turn-start `get_messages` drain stays in
  the agent-network skill even with wake on — it is the fallback when
  channels are disabled AND the authoritative drain; the skill gains a note
  that wake mode may deliver a nudge before/without a drain.
- **Lazy-spawn handling is qualification-gated, launch-side only** — if
  Claude Code lazy-spawns `--mcp-config` servers, a server-side fix is
  structurally impossible (nothing runs to subscribe). Options post-Q3:
  accept + document the from-launch gap (wake coverage begins after the
  first tool call spawns the server), or consume a spawn-timing knob if Q1
  finds one. The rc-nudge lane (NextUp) remains the recorded complement for
  true idle-from-start.

## Implementation Units

### Unit 1: Live qualification protocol (trickiest — designed first)
**File**: no product code; evidence lands in this feature body (`##
Qualification evidence`), driven from this repo's session via mesh tools
**Story**: `feature-claude-host-mesh-idle-wake-qualification`

Protocol (each step records command + observation + timestamp here):

1. **Q1 enablement paths** — against the Claude Code build on this box:
   `claude --help` flag inventory for development-channels; docs/settings
   surface check for a settings.json or env equivalent; record version
   string.
2. **Q2 wake semantics** — scratch folder with `outpost-pi claude <dir>
   --dangerously-load-development-channels server:outpost-pi-mesh` in a
   tmux pane; idle (no prompt); a Pi mesh peer (this session) sends a
   message; observe: does a turn start? does the channel input reach the
   model? what does the woken turn do with nudge vs payload? Repeat once
   while a turn is active (busy-wake behavior — coalescing need?).
3. **Q3 spawn timing** — same launch, fresh session: is the MCP server
   process alive before any tool call (ps + mesh peer list)? If not: send a
   message pre-first-spawn and record sender-side ACK status (peer absent →
   denied/timeout?) and post-spawn drain result — pins the from-launch gap.
4. **Q4 conditional** — only if Q2 fails: server-initiated sampling-request
   probe (one-line server experiment in a scratch copy, not the product
   tree), recording whether Claude Code surfaces an approval and starts a
   turn.

**Acceptance Criteria**:
- [ ] Q1–Q3 evidence recorded in this body with Claude Code version
- [ ] Lane decision recorded: channel-notification lands, or sampling
      fallback activates, with rationale
- [ ] Lazy-spawn verdict recorded (gap real / not real) and the docs stance
      chosen

### Unit 2: Wrapper `--mesh-wake` toggle
**File**: `pi-extension/src/extension/command_surface/standalone_cli.ts`
**Story**: `feature-claude-host-mesh-idle-wake-toggle` (depends on Unit 1's
lane decision)

```ts
/** Wrapper-owned wake opt-ins intercepted before verbatim passthrough. */
export const MESH_WAKE_FLAG = "--mesh-wake" as const;
export const CLAUDE_DEV_CHANNELS_EXPANSION =
  "--dangerously-load-development-channels=server:outpost-pi-mesh" as const;

export function splitClaudeCliArgs(args: readonly string[]): {
  targetCwd: string;
  meshWake: boolean;            // NEW: --mesh-wake seen (deduped vs raw flag)
  passthroughArgs: string[];    // --mesh-wake filtered out; raw dev-channels
                                // flag left verbatim (expansion skipped)
};

export function buildClaudeLaunchArgs(
  mcpConfigPath: string,
  skillPath: string | null,
  meshWake: boolean,            // NEW: appends CLAUDE_DEV_CHANNELS_EXPANSION
): string[];
```

**Implementation Notes**:
- Intercept `--mesh-wake` at any argv position; drop it from passthrough.
- Dedupe: if passthrough already contains the raw
  `--dangerously-load-development-channels` form (either `=` or space
  variant targeting `outpost-pi-mesh`), do not append the expansion.
- `--dangerously-skip-permissions` remains strictly verbatim-only; the
  invariant comment on `buildClaudeLaunchArgs` is rewritten to the narrowed
  authority principle (see Design decisions).
- JSDoc updates follow documentation-conventions (exported + tested =
  Always tier).

**Acceptance Criteria**:
- [ ] `--mesh-wake` anywhere in argv → claude argv gains the dev-channels
      expansion exactly once; flag removed from passthrough
- [ ] raw dev-channels flag in passthrough → no duplicate expansion
- [ ] regression guard rewritten: `--dangerously-skip-permissions` NEVER
      injected by the wrapper (absolute); dev-channels only via `--mesh-wake`
- [ ] README + site tutorial (`claude-mesh`) document the toggle and the
      narrowed safe-default statement

### Unit 3: Nudge-style wake notification
**File**: `pi-extension/src/mcp/mesh_server.ts`
**Story**: `feature-claude-host-mesh-idle-wake-nudge` (depends on Unit 1's
lane decision; voids if the channel lane dies)

```ts
/** Human/model-readable wake nudge for an inbound mesh message.
 *  Deliberately carries NO message body: get_messages stays the single
 *  authoritative drain surface (a body here would let the model reply
 *  without draining, leaving a stale inbox duplicate). */
export function wakeNudgeContent(from: string): string {
  return `📨 mesh message from ${from} arrived — call get_messages to read it and reply (echo its id via re)`;
}
```

Extracted from the inline template so it is unit-testable (the script's
module-load side effects otherwise resist import); the `onMessage` handler
calls it. The notification catch stays no-op (fallback comment updated to
  name the nudge contract).

**Acceptance Criteria**:
- [ ] `wakeNudgeContent` unit test: contains sender address, names
      `get_messages`, contains no body payload
- [ ] handler emits nudge content (asserted via the extracted helper's use —
      wiring verified live in Unit 1's protocol)
- [ ] agent-network skill (repo source) documents wake mode: nudge may
      arrive without a drain; turn-start drain stays mandatory

---

## Implementation Order
1. `feature-claude-host-mesh-idle-wake-qualification` (Unit 1)
2. `feature-claude-host-mesh-idle-wake-toggle` (Unit 2) and
   `feature-claude-host-mesh-idle-wake-nudge` (Unit 3) — parallelizable
   after 1

## Simplification
- The tutorial's conflation of the two `--dangerously-*` flags under one
  warning simplifies to: authority flag stays verbatim opt-in; wake flag
  gains a first-class toggle — the "safe defaults" section gets sharper, not
  longer.
- No deletions identified; the no-op catch and polling fallback are
  retained deliberately (non-wake consumers remain supported).

## Testing
- Wrapper: extend `standalone_cli.test.ts` — toggle interception,
  expansion, dedupe, and the narrowed regression guard (each protects the
  launch-contract invariant this repo relies on).
- Nudge: new focused unit test for `wakeNudgeContent` (protects the
  single-drain-surface contract).
- Qualification: evidence recorded in the feature body, not automated —
  live Claude Code behavior; an e2e lane is out of scope here.

## Risks
- **Riskiest assumption**: a channel notification actually starts a turn in
  current Claude Code builds rather than only rendering — front-loaded as
  protocol step Q2; if it fails, Unit 3 voids and the sampling fallback
  activates.
- **Dev-channel drift**: no compatibility contract across Claude Code
  updates — the wake can silently break. Mitigation: cheap toggle,
  `get_messages` fallback always present, qualification evidence records
  the Claude Code version so future breakage is diagnosable.
- **Lazy-spawn gap**: if `--mcp-config` servers spawn lazily, wake coverage
  begins only after the first tool call. Q3 pins it; the gap is documented,
  not papered over; rc-nudge (NextUp) is the recorded complement.
- **Double-wake race** with a future NextUp rc-nudge landing — coordination
  note already exchanged on-mesh (void/pickup conditions recorded).
- **Quota/cost**: qualification spawns a real Claude Code session; idle
  panes cost nothing, woken turns cost one roundtrip — operator already
  authorized enabling the wake on this box.

## Simplification opportunity

If a wake lands as the primary delivery path, the agent-network skill's
every-turn `get_messages` discipline demotes from primary mechanism to
fallback (skill-doc simplification; the tool itself stays — it remains the
drain/replay surface and the no-wake default for consumers who don't opt in).
The `mesh_server.ts` no-op catch comment ("channels not enabled — get_messages
polling covers it") would then describe the fallback, not the norm. Nothing
identified for outright deletion.
