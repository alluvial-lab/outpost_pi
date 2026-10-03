---
id: story-claude-launcher-safe-local-qualification
kind: story
stage: review
tags: [pi-extension, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-03
updated: 2026-10-03
---

# Safe Claude launcher and local polling qualification

## Brief

Requirements intake from the nextup resident agent, relaying operator direction
(mesh message `01a103e3-53a6-775e-919e-e52418edc2b0`). Nextup runs a Pi
orchestrator at its checkout root and an interactive Claude Code orchestrator;
the immediate consumer use is cross-cwd unicast to coordinate file claims and
report when messages are actually ingested during a repair round.

Qualify the existing optional Claude mesh adapter, not a new mobile harness
target. Scope is one bounded extension CLI change plus local integration
verification. R1 and R2 are prerequisites for the consumer's first real use.

## Requirements and acceptance

- [x] **R1 — safe launch authority (required).** The wrapper no longer injects
  `--dangerously-skip-permissions` (or any `--dangerously-*` flag). Permission
  bypass is an operator opt-in via normal claude-flag passthrough; no duplicate
  permission configuration was added. Regression tests pin the default argv.
- [x] **R2 — local polling path (required).** The wrapper no longer injects
  `--dangerously-load-development-channels`; a polling-only launch needs no
  dangerous flag, and channels remain available as explicit passthrough. Live
  interactive smoke completed (evidence below).
- [x] **R4 — subdirectory confirmation (required).** Confirmed by source and by
  live smoke (evidence below). No change requested in the singleton lock or
  folder-scoped broadcast semantics.
- [x] Launcher usage docs updated to the actual safe defaults (help text,
  `pi-extension/README.md`, site tutorial `site/src/app/tutorials/claude-mesh`).
- [x] Extension typecheck/tests/build green; site lint/build green; bounded
  standalone-story review passed.

**R3 — optional stretch (completed with caveat):** headless `claude -p` +
channels qualification. The launcher itself works headless (see evidence);
MCP tool calls are blocked by Claude's permission system in `-p` mode, so
unattended headless use additionally needs an explicit
`--allowedTools "mcp__outpost-pi-mesh__*"` (or an allow rule in settings) —
an opt-in, consistent with R1's posture. No further change commissioned.

## Implementation notes

- Execution capability: inline implement (single cohesive story, one owner);
  host session on the orchestrator provider, no implementation subagents.
- Review weight: `standard` (default) — standalone story, bounded inline pass.
- Files changed:
  - `pi-extension/src/extension/command_surface/standalone_cli.ts` — extracted
    `splitClaudeCliArgs` / `buildClaudeLaunchArgs` pure helpers; removed both
    injected `--dangerously-*` flags; safe-default help text; headless wizard
    TTY guard.
  - `pi-extension/src/extension/command_surface/standalone_cli.test.ts` — new:
    cwd/passthrough splitting (incl. flag-value-not-cwd), argv construction
    with/without packaged skill, and a safe-default regression guard asserting
    no `--dangerously-*` flag is ever injected.
  - `pi-extension/README.md` — new "Claude Code on the mesh" section (safe
    defaults, opt-in passthrough incantation).
  - `site/src/app/tutorials/claude-mesh/page.tsx` — rewritten "What it wires
    in" (ephemeral `--mcp-config`, `--append-system-prompt-file`; the page
    still described the retired `mcp add -s local` + `~/.claude/skills`
    deployment), polling-by-default delivery section, and an "opt-in flags"
    section replacing "the wrapper sets these".
- Discovered defect fixed in passing (fail-fast boundary): headless
  `outpost-pi claude -p` with no folder config hung on the wizard's readline
  (unsettled top-level await, Node exit 13). Now exits 1 immediately with the
  two real options (run interactively once, or pre-create
  `<cwd>/.pi/outpost-pi/config.json` — the documented scripted path).
- Simplification: two injected flags and their ordering deleted; no new
  config surface, no permission-policy subsystem — plain passthrough.
- Discrepancies from design: none.
- Adjacent issues parked (observations, not blockers):
  - Pi→Claude bodies sent as objects by this Pi runtime arrived at the Claude
    MCP inbox as a JSON-encoded **string** (double serialization somewhere on
    the send path). Legal per envelope contract (body is free-form) and
    parseable; worth a look if structured bodies matter to mesh consumers.
  - `scripts/cmux-bootstrap-agents.sh` (legacy cmux surface, not the
    `outpost-pi claude` launcher) still hardcodes
    `--dangerously-skip-permissions` for its own panes; out of scope here.

## Verification evidence

Code (baseline `9cca09b59` → this branch):

- `corepack pnpm typecheck` ✓; targeted suite (226 tests) ✓; full suite
  **66 files, 1163 passed / 3 skipped** ✓; `corepack pnpm build` ✓ (run again
  after the TTY guard; tests predate only the guard, which no test exercises).
- `site`: `pnpm lint` + `pnpm build` ✓ (tutorial page compiles, route listed).

Live R2 interactive smoke (2026-10-03, this box; Pi peer = this session at
`/home/agent/projects/outpost_pi@outpost_pi`; scratch cwd
`debug/claude-mesh-smoke` — gitignored, removed after capture):

- Revision: working tree over `9cca09b59`, built `dist/` (post-change).
  Claude Code **2.1.284** (Opus 5.5, Claude Max). Invocation (non-secret):
  `node pi-extension/dist/index.js claude /home/agent/projects/outpost_pi/debug/claude-mesh-smoke`
  — no channels flag, no permission bypass. Claude's own TUI default showed
  "auto mode on" (its local default, not wrapper-injected).
- Wizard ran in the child dir (exact-cwd config lookup confirmed;
  `.pi/outpost-pi/config.json` with `agent_name: claude-smoke` created);
  folder-trust dialog answered by the operator side.
- MCP registered without channels: transcript shows
  "Called outpost-pi-mesh 2 times"; no `--dangerously-*` flag on argv
  (pinned by unit tests).
- `list_peers` returned the full local mesh verbatim, including
  `/home/agent/projects/outpost_pi@outpost_pi`.
- Claude→Pi unicast ACK verbatim:
  `Delivered to /home/agent/projects/outpost_pi@outpost_pi`; the message was
  delivered into the Pi turn (this session) — transport ACK ≠ ingestion;
  ingestion observed here on the Pi side.
- Pi→Claude: the reply sat in the Claude inbox until the next prompted turn;
  `get_messages` drained it (from/re/id verbatim in transcript); a second
  `get_messages` returned `(no messages)` — turn-boundary polling confirmed,
  immediate wake not used.
- `re`-correlation round-trip both directions: Claude's step-2 reply arrived
  at the Pi peer with `re=` set to the Pi send's id; Claude's drain echoed the
  Pi reply's `re` pointing at its own step-1 id.

R4 (live): launcher targeting a child dir of the checkout worked end to end —
identity/lock on the child cwd (no conflict with the root Pi agent), packaged
MCP + skill resolved from package paths, ephemeral MCP config per process.
Parent-tree access from the child cwd: Claude read
`/home/agent/projects/outpost_pi/README.md` through its sandboxed shell with
**no permission prompt** (sandbox permits reads outside cwd); parent-tree
writes/exec remain governed by Claude's permission gates — the cwd split is
mesh identity, not filesystem isolation. The launcher's one persisted side
effect (legacy `claude mcp remove outpost-pi-mesh -s local` cleanup) still
applies in shared checkouts.

R3 (headless, optional): `claude -p` + passthrough channels flag, pre-created
config: launcher exited 0 within timeout, MCP registered; `list_peers` /
`get_messages` were **permission-blocked** in `-p` mode (no TTY to approve) —
Claude's own guidance: allow `mcp__outpost-pi-mesh__*` for unattended use.
First attempt (no config) surfaced the wizard hang, now fail-fast (exit 1).

## Boundaries kept

Singleton per-cwd lock, folder-scoped local broadcast, cross-PC transport,
and consumer worktree policy untouched. No nextup files touched; scratch
folder was in this repo's gitignored `debug/` and was removed after capture.
No relay, app, or dormant cockpit changes.
