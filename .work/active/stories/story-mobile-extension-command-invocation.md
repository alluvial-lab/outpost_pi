---
id: story-mobile-extension-command-invocation
kind: story
stage: drafting
tags: [app, pi-extension, research]
parent: feature-mobile-slash-command-invocation
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-26
research_dials:
  scope_authority: pre-registered
  verification_rigor: standard
  intent: verify the Pi SDK surface for invoking extension/host operations from mobile (verify-first, feeds parent feature design)
  output_kind: findings recorded in this item body, consumed by parent feature design
---

# Extension-command invocation from mobile (verify-first)

A verify-first item under `feature-mobile-slash-command-invocation`. The
extension **owns** its registered commands (`/outpost-pi …` via
`createCommandSurface`/`registerOutpostPiCommands`) — unlike pi-native
session-control ops, the handler logic lives in the extension. Question: can
those commands be invoked from mobile **without** the `ExtensionCommandContext`
gate (i.e., without needing a pre-existing slash-command to arm the context)?

## Verify (read-first; produce a finding before any implementation)

1. Read the extension's command handlers (`pi-extension/src/extension/command_surface/**`)
   — for each `/outpost-pi` command, what context does its handler actually use?
   Base-`ExtensionContext` methods (available from `session_start`), or
   `ExtensionCommandContext`-only methods (`newSession`/`fork`/`reload`/`waitForIdle`)?
2. If a command's handler uses only base-context methods → it's callable from the
   mobile path without the gate (the extension invokes its own handler with the
   event/session context). If it uses command-context-only methods → it's gated
   (same class of problem as `/new`).
3. Produce a per-command table: `{command, ctx-required, mobile-invokeable?}`.

## Change (only if the verify shows a clean path)

- A wire action (e.g. `extension_command { command, args }`) the app sends; the
  extension dispatches to its own handler with the available (base) context for
  commands that don't need the command-context.
- App: a way to issue extension commands (picker entry, or quick-actions).

## Acceptance

- [ ] Per-command verify table recorded in this body.
- [ ] If a clean path exists for some commands: a wire action + app entry +
      round-trip test for at least one; if not: documented why (gated), parked.

## Ordering

`depends_on: []` (independent verify). May yield a clean capability for a subset
of extension commands, or confirm they're gated (park).
