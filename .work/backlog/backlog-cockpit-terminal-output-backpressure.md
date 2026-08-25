---
id: backlog-cockpit-terminal-output-backpressure
created: 2026-08-15
updated: 2026-08-15
tags: [cockpit, bug, performance]
---

# Cockpit terminal output backpressure / coalescing (sustained-output freeze)

Upstream `23d95446` (#120) + `1ddbbb03`: sustained TUI output (agent
transcripts!) can freeze the UI. Ours streams every PTY chunk straight into
`terminal.write` (`cockpit/lib/app/cockpit/ui/session/terminal_session.dart:36-41`)
and starts the PTY without `ackRead` (`pty_terminal_gateway.dart:20-27`) —
the vulnerable shape. Full upstream scheduler (their
`pty_output_scheduler.dart`) is built against their absorbed-terminal stack;
estimated **L** against our kyroon_pty/xterm-4.0 stack; the narrower
`1ddbbb03` coalescer/backpressure variant is **M**.

## Why parked, and promote trigger

Freeze not yet reproduced locally on our stack (different terminal engine
than upstream's). **Promote to active** the first time sustained agent
output visibly stutters or freezes a cockpit session — under the
cockpit-in-use posture, expect this to promote soon; check after any long
agent turn in a cockpit terminal.
