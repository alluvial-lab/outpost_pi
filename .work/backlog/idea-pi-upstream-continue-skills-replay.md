---
id: idea-pi-upstream-continue-skills-replay
created: 2026-10-06
updated: 2026-10-06
tags: [workflow, docs]
---

# Upstream pi report candidate: `--continue` replays stored system message (no skills refresh)

Fleet finding (2026-10-04 resident reboots, folded out of the restart-loop
pair): pi's hot-reload restart-with-`--continue` does NOT refresh the
skills section — a resumed session replays its stored system message, so
skill/package wiring changes only reach a session on a FRESH start. This is
pi-core behavior (`@earendil-works/pi-coding-agent`), not wrapper-local.

Candidate: file an upstream report with the observed repro (skills added to
a package while a session runs do not appear on `--continue` resumes; a
fresh start or interactive `/reload` picks them up). External posts need
operator alignment first — park until the operator green-lights the
upstream issue.

Local mitigation already shipped: `pi-restart-loop.sh --fresh-first` /
`PI_RESTART_FRESH=1` (story-restart-loop-fresh-start-loud-relaunch).
