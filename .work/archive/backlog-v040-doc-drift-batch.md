---
id: backlog-v040-doc-drift-batch
created: 2026-08-11
updated: 2026-08-26
tags: [pi-extension, docs]
status: folded
folded_into: feature-doc-drift-repair (groom 2026-08-26)
---

# v0.4.0 doc/comment drift batch

## Origin
gate-cruft C5, gate-docs D4+D5+D6+D8 (v0.4.0). Lower-stakes drift; batched.

## Findings
- composition_root.ts:112-116 — comment says SIGKILL/SIGTERM skips session_shutdown; the hot-reload path uses graceful SIGTERM (index.ts:2890) and a session_shutdown hook is registered. Limit the statement to ungraceful SIGKILL.
- pi-extension/README.md:136 — New session documented only as ctx.newSession(); omits the restart-managed EXIT_FRESH_SESSION path that relaunches without --continue. Document both in-process and restart-fresh paths.
- .agents/skills/pi-extension-typescript/SKILL.md:99-107,169 — omits the agent_settled hook now in use; names EXIT_DAEMON_FRESH_SESSION while the impl exports EXIT_FRESH_SESSION (rpc_child.ts:45). Update.
- index.ts:2168-2170 — router comment attributes all tool broadcasts to SDK handlers; _deliverMeshMessageToAgent also broadcasts tool_request/tool_result (2128-2136). Clarify.
- AGENTS.md:311-313 — says arm is a no-op when disabled, but hot-reload.sh:69-72 returns status 1. Clarify TUI warns / shell helper exits nonzero.
