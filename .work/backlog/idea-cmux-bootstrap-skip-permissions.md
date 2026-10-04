---
id: idea-cmux-bootstrap-skip-permissions
created: 2026-10-03
updated: 2026-10-03
tags: []
---

Legacy cmux bootstrap scripts still hardcode `--dangerously-skip-permissions`.

`scripts/cmux-bootstrap-agents.sh:170` launches every pane with
`cmux claude-teams --model sonnet --dangerously-skip-permissions`, and the
header comments document the flag as a passthrough feature. This is the same
authority concern the launcher fix just resolved for `outpost-pi claude`
(story `story-claude-launcher-safe-local-qualification`): an orchestrator-grade
Claude in a shared repo should not get blanket permission bypass by default.

Distinct surface, so it was out of scope there: these panes belong to the old
cmux orchestration setup (root `CLAUDE.md` workflow), not the mesh launcher.
When touched, decide the safe default + explicit opt-in the same way the
launcher now does (plain flag opt-in, no injected bypass), or retire the
scripts if the cmux surface is dead.
