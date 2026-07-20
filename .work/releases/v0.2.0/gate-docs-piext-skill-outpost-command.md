---
id: gate-docs-piext-skill-outpost-command
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Pi-extension reference skill names retired remote-pi commands

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/pi-extension-typescript/SKILL.md:17,127`
- Contradicting source: `pi-extension/src/extension/command_surface/commands.ts:24-34`

## Current doc text
> Any change involving `/remote-pi` ... `src/index.ts` — extension factory, `/remote-pi` commands ...

## Contradiction
The registered command surface is `outpost-pi`, including all subcommands. The canonical implementation reference would route future agents to a retired command name.

## Required edit
Replace command references with `/outpost-pi` and update the important-files description to the current command-surface ownership. Preserve the skill's scope and lifecycle guidance.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.

## Implementation notes
- **Execution:** Bounded inline reference repair; the command-surface adapter is the direct ownership source.
- **Change:** Renamed slash-command references to `/outpost-pi` and split the important-files guidance between the `src/index.ts` composition entrypoint and `src/extension/command_surface/commands.ts` registration owner.
- **Verification:** Confirmed the descriptions match `registerOutpostPiCommands` and no retired slash-command reference remains. No automated test applies to this prose-only correction.
- **Bounded inline review:** Pass — lifecycle scope is preserved while command ownership is current.
