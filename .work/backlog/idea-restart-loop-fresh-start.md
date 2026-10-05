---
id: idea-restart-loop-fresh-start
created: 2026-10-04
updated: 2026-10-04
tags: []
---

pi-restart-loop.sh needs an explicit fresh-start path for the first
iteration.

Fleet finding (2026-10-04 resident reboots, relayed by the projects
session): pi's hot-reload restart-with-`--continue` does NOT refresh the
skills section — a resumed session replays its stored system message, so
skill/package wiring changes only reach a session on a FRESH start (or
interactive `/reload`, unreachable for residents on orphaned PTYs).
Compounding it, the wrapper always prepends `--continue` on its first
iteration and pi rejects `--continue` combined with `--session-id`, so the
wrapper has no fresh-start path without a mobile `/new` (which today works
only via the EXIT_FRESH_SESSION=42 restart contract). Workaround used in
the field: stop the resident, create a fresh latest session via a one-shot
`pi --print`, then start the wrapper (its `--continue` adopts the fresh
session).

Candidate: honor an explicit fresh-start arg/env (e.g.
`PI_RESTART_FRESH=1` or `--fresh-first`) that drops `--continue` on the
first iteration only, then resumes the normal hot-reload `--continue`
cadence. Note: the system-message/skills replay on `--continue` is pi-core
behavior (worth an upstream pi report), while the fresh-start escape hatch
is wrapper-local and small.
