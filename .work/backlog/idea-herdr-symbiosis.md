---
id: idea-herdr-symbiosis
created: 2026-07-31
updated: 2026-07-31
tags: [pi-extension, workflow]
---

# Explore Herdr + outpost-pi symbiosis

## Context
Explored during the 2026-07-31 hot-reload session. Herdr (v0.7.5) is an agent-aware terminal multiplexer — "tmux for coding agents." Installed at `~/.local/bin/herdr`, repo cloned at `/home/agent/projects/herdr-src`.

## What Herdr already provides for pi
- **First-class pi support**: `src/detect/manifests/pi.toml` — detects pi via "Working..." literal, supports `herdr agent start --kind pi`
- **Agent state sidebar**: working/blocked/done at a glance across all pi sessions (the state visibility currently missing — we dig through relay logs)
- **Socket API**: `agent.list`, `agent.wait`, `agent.prompt`, `pane.send_text`, `pane.read` — a programmatic control surface
- **Remote reattach**: `herdr --remote <ssh-target>` — terminal access from phone without code-server
- **Session persistence**: server model keeps agents alive on detach

## The gap
- **No auto-restart/respawn**: Herdr doesn't relaunch agents on exit. The wrapper (`pi-restart-loop.sh`) is still needed for the hot-reload restart loop.

## The most promising integration point
`pane.send_text` can inject slash commands into a pi pane from outside:
1. **Replace the `ensureStarted` auto-start fix**: `herdr agent wait <pane> --until idle` then `herdr pane send_text <pane> "/outpost-pi\n"` — inject the relay-start command from outside pi, instead of the code-level `_state` check
2. **Replace the bash-tool arm discovery**: `herdr pane send_text <pane> "/outpost-pi hot-reload arm\n"` — arm the hot-reload from any pane, no ancestor-chain PID discovery needed
3. **Publish custom state**: `pane.report_agent` / `pane.report_metadata` — tell Herdr about hot-reload status, relay state, session info

## Symbiosis architecture
- Herdr: session persistence, state visibility, remote terminal, pane management
- Wrapper (`pi-restart-loop.sh`): restart loop inside a Herdr pane (still needed — Herdr doesn't respawn)
- Extension: hot-reload logic (agent_settled, quiescing gate, PID-scoped state) — transport-agnostic
- Relay + Flutter app: mobile chat interface (coexists with Herdr's terminal reattach — different purpose)

## What to explore when picking this up
1. Does `pane.send_text` reliably deliver slash commands to pi's TUI (timing, focus, raw-mode interaction)?
2. Can a Herdr plugin or hook auto-start the relay when pi is detected (`agent.start` completion → `pane.send_text "/outpost-pi"`)?
3. Can the outpost extension publish state to Herdr via the socket API (hot-reload armed/pending, relay connected/disconnected)?
4. Does running the wrapper inside a Herdr pane work cleanly (foreground pi, Herdr's terminal management)?
5. Can `herdr agent wait --until idle` replace or augment the `agent_settled` boundary for the hot-reload trigger?
6. AGPL-3.0 license — check compatibility with outpost-pi's shipping model (note: README says Apache-2.0; the GitHub page shows AGPL — verify)
