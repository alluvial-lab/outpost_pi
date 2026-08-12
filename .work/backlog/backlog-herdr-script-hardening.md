---
id: backlog-herdr-script-hardening
created: 2026-08-11
updated: 2026-08-11
tags: [workflow, security]
---

# herdr operational script hardening

## Origin
gate-security S2 + S3 (v0.4.0), both Medium.

## Findings
- scripts/herdr-restart-agents.sh:120 — escalation SIGKILLs based on numeric-PID liveness (os.kill(pid,0)) without revalidating process identity; PID reuse could kill the wrong process. Use a pidfd or PID+starttime, revalidate before escalation.
- scripts/herdr-start-agents.sh:30 (same sink herdr-restart-agents.sh:156) — pane cwd is interpolated unquoted into a shell command (f"cd {cwd} && bash {WRAPPER}"). shlex.quote cwd/paths, or use an API supplying cwd + argv separately.
