---
id: feature-claude-host-mesh-idle-wake-toggle
kind: story
stage: done
tags: [pi-extension, workflow]
parent: feature-claude-host-mesh-idle-wake
depends_on: [feature-claude-host-mesh-idle-wake-qualification]
release_binding: v0.13.0
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Wrapper `--outpost-mesh-wake` toggle

Design element: Unit 2 of `feature-claude-host-mesh-idle-wake`. Reshaped by
the Opus review: namespaced flag, cwd-detection ordering, get_messages
pre-approval pairing, two-guard invariant.

## Work

`pi-extension/src/extension/command_surface/standalone_cli.ts`:

- `MESH_WAKE_FLAG = "--outpost-mesh-wake"`, filtered out **before** cwd
  detection (regression: `["--outpost-mesh-wake", "/tmp/proj"]` → cwd
  `/tmp/proj`, nothing leaked to claude as a prompt positional).
- `buildClaudeLaunchArgs(..., meshWake)` appends, when set:
  `--dangerously-load-development-channels=server:outpost-pi-mesh` (canonical
  `=`-form; grammar per Q1 evidence) AND the get_messages pre-approval
  (`--allowedTools mcp__outpost-pi-mesh__get_messages`, exact grammar per
  Q1) so an unattended woken session can drain without stalling on an
  approval dialog.
- Dedupe vs a raw dev-channels flag already in passthrough (both forms,
  per Q1 grammar — avoid clobbering an operator-passed channel for another
  server).
- **Two-guard invariant** replaces the narrowed one: (1) authority —
  never inject `--dangerously-skip-permissions` (absolute); (2) initiative
  — dev-channels only via `--outpost-mesh-wake`, documented as "lets mesh
  peers start turns". JSDoc + regression-guard test rewritten together
  with this rationale.
- README + site claude-mesh tutorial: toggle docs, initiative framing,
  explicit warning on combining wake with skip-permissions (the fleet's
  real configuration).

## Acceptance evidence

- `standalone_cli.test.ts`: interception at any position; single expansion;
  pre-approval flag present iff wake; cwd-ordering regression; dedupe;
  authority guard still absolute
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
- README/tutorial updated

## Implementation notes (2026-10-05)

- `MESH_WAKE_FLAG` filtered in `splitClaudeCliArgs` BEFORE cwd detection;
  `meshWake` returned alongside cwd + passthrough.
- Expansion uses the `=` argv forms (`--dangerously-load-development-channels=server:outpost-pi-mesh`,
  `--allowedTools=mcp__outpost-pi-mesh__get_messages`) — `=` forms cannot
  swallow a trailing positional prompt the way variadic space forms can
  (review P9). Dedupe recognizes BOTH operator forms (space token + `=`).
- Two-guard JSDoc written into `buildClaudeLaunchArgs`; help text mentions
  the toggle.
- Tests: 13 in standalone_cli.test.ts — cwd-detection regression with
  leading wake flag, expansion iff wake, dedupe both forms, authority guard
  absolute (asserted across wake configurations), wake-off injects neither
  dangerous nor allowedTools flags.
- Docs: README two-opt-in section rewritten; site tutorial "Safe defaults"
  section now authority/initiative with the combination warning.
