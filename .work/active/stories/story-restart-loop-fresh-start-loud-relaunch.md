---
id: story-restart-loop-fresh-start-loud-relaunch
kind: story
stage: implementing
tags: [pi-extension, workflow, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-06
updated: 2026-10-06
---

# Restart-loop: explicit fresh-start path + loud, persistent relaunch trace

## Brief

Fold of the restart-loop sibling pair (per the recorded sibling link):
`idea-restart-loop-fresh-start` (2026-10-04) and
`backlog-restart-loop-silent-relaunch-failure` (2026-10-07). Common thread:
restart-loop relaunch paths that fail or misbehave without a trace.

**Fresh-start lane.** pi's hot-reload restart-with-`--continue` does NOT
refresh the skills section — a resumed session replays its stored system
message, so skill/package wiring changes only reach a session on a FRESH
start (fleet finding 2026-10-04; tonight's fresh-sweep existed because of
it). The wrapper always prepends `--continue` on its first iteration and
pi rejects `--continue` combined with `--session-id`, so there is no
fresh-start path without a mobile `/new` (EXIT_FRESH_SESSION=42 contract).
Field workaround: stop the resident, create a fresh latest session via a
one-shot `pi --print`, then start the wrapper.

**Silent-relaunch lane.** During the outpost v0.13.0-era reboot, the ten
Sep-26-era orphaned-PTS wrappers all consumed their restart markers, then
their relaunches failed WITHOUT a trace — pi exited immediately on the
wrapper's `pi --continue` relaunch, the wrappers stopped (crash safety
held), and the output died with the PTYs. Root cause unknown (candidates:
stale env in the old wrappers, startup contention, PTS handling); the repro
is GONE — diagnosis would need synthetic reconstruction. The actionable fix
is observability: make every relaunch outcome land in a persistent,
survivable trace so the next occurrence is diagnosable.

## Design

**`--fresh-first` / `PI_RESTART_FRESH=1`.** The wrapper drops `--continue`
on the FIRST iteration only, then resumes the normal hot-reload
`--continue` cadence. The flag is intercepted during arg parsing (it is not
a directory, so it would otherwise pass through to pi as garbage); the env
form serves tmux/systemd launch lines. Startup echo records it.

**Persistent lifecycle log.** The wrapper appends its lifecycle lines to
`$OUTPOST_PI_HOME/logs/pi-restart-loop-<roomId>.log` (one log per folder,
roomId = the same `roomIdForCwd` hash the lock uses; dir mode 0700) in
addition to stdout. Lines: loop start (cwd, args, fresh-first state), each
pi exit (pid, exit code, timestamp — the current stdout echoes), relaunch
decisions and their reason (marker consumed / fresh-session / fresh-first),
and loop-stop reason. Each pi run's elapsed time is recorded; a
marker-authorized relaunch that dies within a short window (≤5 s) gets a
prominent `RELUNCH-FAILED-FAST` record (exit code, elapsed, marker, cwd,
pi path) — the exact evidence the Sep-26 incident lacked. Crash safety is
unchanged: no auto-retry. Simple size cap with one rotated generation.

**Docs.** The wrapper's mechanics section (README daemon-mode table +
wrapper header comment) documents the fresh-start escape hatch, the log
location, and the caveat that resumed sessions replay stored system
messages (skill/wiring changes need a fresh start). The pi-core
`--continue`/skills-replay behavior is parked separately as an upstream
report candidate.

## Simplification opportunity

None identified — additive wrapper surface; the field workarounds (manual
`pi --print` priming; blind post-mortems) are the things made unnecessary.

## Acceptance criteria

- [ ] `--fresh-first` / `PI_RESTART_FRESH=1` launches the first iteration
      without `--continue`, subsequent iterations with it (harness test)
- [ ] Lifecycle log persists across the loop's lifetime under
      `$OUTPOST_PI_HOME/logs/`, mode 0700, with per-exit and stop-reason
      records (harness test)
- [ ] A fast-dying marker-authorized relaunch produces a
      `RELUNCH-FAILED-FAST` record with exit code + elapsed (harness test)
- [ ] Wrapper docs updated; typecheck + full vitest suite green (script
      change has no TS build surface beyond tests)
