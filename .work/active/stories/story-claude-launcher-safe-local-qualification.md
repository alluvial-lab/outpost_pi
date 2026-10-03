---
id: story-claude-launcher-safe-local-qualification
kind: story
stage: implementing
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
verification. R1 and R2 are prerequisites for the consumer's first real use;
this item is requirements intake, not an instruction to launch an unrestricted
Claude session or edit the consumer checkout. Implementation has not begun.

## Requirements and acceptance

- [ ] **R1 — safe launch authority (required).** Stop injecting
  `--dangerously-skip-permissions` by default. Permission bypass must require
  an explicit operator opt-in. Prefer existing Claude flag passthrough over a
  duplicate persistent permission configuration. Ordinary launch preserves
  Claude's configured permission policy; the wrapper must not silently widen
  it. Regression-test default argv and explicit opt-in, along with leading
  cwd and flag-value passthrough.
- [ ] **R2 — local polling path (required).** Make the launcher usable without
  `--dangerously-load-development-channels`, which is also currently injected
  unconditionally. Channels and permission bypass must be independent choices;
  a polling-only launch must not require either dangerous flag. Preserve an
  explicit channels opt-in rather than deleting the optional capability.
- [ ] Run a real interactive Claude smoke through the built launcher with
  channels disabled and without permission bypass. Record revision/build,
  Claude version, exact non-secret invocation, permission approvals, and the
  distinction between transport ACK and agent ingestion. Establish: MCP
  registers; `list_peers` discovers a live Pi peer at another cwd; unicast gets
  a received ACK; a Pi-to-Claude envelope waits in the inbox until the next
  prompted turn; `get_messages` returns the envelope and a subsequent drain is
  empty; Claude replies with the received envelope id as `re`, and the Pi peer
  observes that correlation. Immediate wake is not required. Do not present a
  direct MCP client test or `claude -p` run as interactive qualification.
- [ ] **R4 — subdirectory confirmation (required).** Record source-backed cwd
  behavior and live-smoke observations for a dedicated child directory under a
  checkout. Check inherited MCP overrides, config lookup, identity/lock,
  package-relative skill resolution, generated MCP config, and normal Claude
  permissions for parent-tree access. Parent-file operations may require
  explicit Claude approval/additional-directory configuration; the cwd split
  is not a filesystem isolation boundary. Use an owned scratch checkout, not
  nextup's live repair files.
- [ ] Update the owning launcher usage/docs for the actual safe defaults,
  explicit opt-ins, and turn-boundary polling limitation. Run extension
  typecheck/tests/build and a bounded standalone-story review. If interactive
  auth/TTY/operator approval is unavailable, report the precise unmet
  prerequisite and leave R2 unqualified rather than weakening acceptance.

**R3 — optional stretch, not completion-blocking:** headless `claude -p` with
channels on this box, only if cheap after the required path. Keep its evidence
separate; skip with a reason if it requires significant setup or authority.

## Source grounding

Direct-read only; no exploratory fan-out needed. Baseline `9cca09b59`:

- `pi-extension/src/extension/command_surface/standalone_cli.ts`:
  `launchClaudeCli` accepts only a leading positional cwd and forwards later
  arguments; spawns Claude in the resolved target directory. It unconditionally
  appends both dangerous flags today. It also invokes
  `claude mcp remove outpost-pi-mesh -s local` in that directory before creating
  a temporary MCP configuration; qualification must account for this persisted
  legacy-registration cleanup, rather than claim launch is wholly side-effect
  free.
- The MCP executable and optional appended `skills/agent-network/SKILL.md`
  resolve from the package entrypoint, not the consumer cwd. Generated MCP
  configuration has an absolute executable path and no baked `--cwd`.
- `pi-extension/src/mcp/mesh_server.ts` uses its inherited `process.cwd()`, not
  `CLAUDE_PROJECT_DIR`; `OUTPOST_PI_MCP_CWD` and explicit `--cwd` can override
  it. It canonicalizes mesh identity and calls `acquireCwdLock(_cwd)` without
  a name argument. Do not generalize that Claude call into a statement that
  all current Pi lock users are cwd-only: the lock helper supports names.
- `pi-extension/src/session/local_config.ts` checks the exact cwd's
  `.pi/outpost-pi/config.json` (or `OUTPOST_PI_DIRECT_CONFIG`), not an ancestor's
  config. A new child directory normally triggers the launcher setup wizard.
- The MCP server enqueues incoming envelopes before attempting an optional
  channel notification. `get_messages` drains via `inbox.splice(0)`; the
  instructions require a call at each turn start. This supports a polling
  path in source but is not yet live Claude-host qualification.

## Boundaries and simplification

Keep the current Claude adapter's singleton behavior, folder-scoped local
broadcast, cross-PC transport, and consumer worktree policy unchanged. No
nextup edits; no relay, app, or dormant cockpit changes. No global Claude
permission changes or restarts of existing agents for this smoke.

Remove implicit dangerous launch options rather than adding a parallel
permission-policy subsystem. Prefer native passthrough flags and small
behavioral regression tests. Fix only documentation assertions touched by this
slice; broader product-positioning changes are not commissioned.

## Execution status

Scoped only. No live Claude process launched, code changed, or smoke tests run.
No dependencies; no release binding. R1/R2 implementation and qualification
remain outstanding. Optional R3 does not delay the consumer handoff.
