---
id: story-restart-loop-fresh-start-loud-relaunch
kind: story
stage: review
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

- [x] `--fresh-first` / `PI_RESTART_FRESH=1` launches the first iteration
      without `--continue`, subsequent iterations with it (harness test)
- [x] Lifecycle log persists across the loop's lifetime under
      `$OUTPOST_PI_HOME/logs/`, mode 0700, with per-exit and stop-reason
      records (harness test)
- [x] A fast-dying marker-authorized relaunch produces a
      `RELAUNCH-FAILED-FAST` record with exit code + elapsed (harness test)
- [x] Wrapper docs updated; typecheck + full vitest suite green (script
      change has no TS build surface beyond tests)

## Implementation notes (2026-10-06)

- Execution capability: inline (session; single wrapper script + tests).
  Review weight: standard (bounded inline pass, standalone-story lane).
- Files changed: `scripts/pi-restart-loop.sh` (fresh-first interception
  argv+env, persistent per-folder lifecycle log keyed by the cwd-lock room
  id, per-run elapsed + stop-reason records, RELAUNCH-FAILED-FAST detection
  on loop-stopping exits within `OUTPOST_PI_RELAUNCH_FAST_WINDOW` (default
  5s, env-tunable), 1 MiB single-generation rotation, best-effort logging
  that can never take the wrapper down),
  `pi-extension/src/pi_restart_loop.test.ts` (harness extended with
  wrapperArgs/envExtra; 4 new tests), `pi-extension/docs/daemon.md`
  (restart-wrapper mechanics section: handshake contract, fresh-first
  rationale incl. the pi-core `--continue` skills-replay caveat, log
  location + failed-fast semantics).
- Tests added: fresh-first argv form, fresh-first env form, lifecycle-log
  persistence + timestamp shape, RELAUNCH-FAILED-FAST on a fast-dying
  marker-authorized relaunch. 9/9 in the file.
- Simplification: none identified (additive surface, as scoped).
- Discrepancies from design: none. Crash safety unchanged — no auto-retry;
  the failed-fast record is observability only (the Sep-26 incident's
  diagnosis lane).
- Adjacent issues parked: `idea-pi-upstream-continue-skills-replay`
  (operator-gated upstream report for the pi-core replay behavior).
