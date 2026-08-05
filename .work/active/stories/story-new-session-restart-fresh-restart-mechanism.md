---
id: story-new-session-restart-fresh-restart-mechanism
kind: story
stage: drafting
tags: [pi-extension, workflow]
parent: feature-mobile-slash-command-invocation
depends_on: [story-new-session-restart-fresh-extension-exit]
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# /new from mobile: restart-without-continue mechanism (wrapper + herdr)

The other half of `/new`-via-restart-fresh. Once the extension exits with the
fresh-session code (the sibling extension-exit story), the **process manager must
restart the agent WITHOUT `--continue`** so a fresh session starts (today
restarts resume the old session).

## The design risk (resolve before implementing)

- **The daemon** auto-restarts via its supervisor — already works.
- **`outpost`** runs under `pi-restart-loop.sh` — but the wrapper restarts WITH
  `--continue`; it needs to restart WITHOUT `--continue` once on the fresh-session
  exit code, then resume `--continue` for later restarts.
- **The 11 herdr-managed agents** do NOT auto-restart on exit (a killed agent
  sits at a bash pane), and `herdr agent start -- …` resumes with `--continue`.
  So restart-fresh needs a real mechanism here.

Candidate mechanisms (pick during design):
1. Run **all 12 agents under the `pi-restart-loop` wrapper** (today only `outpost`
   is — see `scripts/herdr-start-agents.sh`), with the wrapper handling the
   fresh-session code by restarting without `--continue` once.
2. A **"fresh-session-requested" marker** the extension writes before exiting;
   the next launch reads it + drops `--continue`.

## Change (once the mechanism is chosen)

- `scripts/pi-restart-loop.sh` — on the fresh-session exit code, relaunch `pi`
  WITHOUT `--continue` once (fresh session), then resume normal `--continue`
  behavior for subsequent exits.
- `scripts/herdr-start-agents.sh` (and/or a per-agent wrapper) — whichever
  mechanism puts all agents under a launcher that honors the fresh-session code.
- The existing `scripts/herdr-restart-agents.sh` (extension-reload restarts)
  should keep using `--continue` (those are reloads, not fresh sessions) — don't
  conflate.

## Acceptance

- [ ] `/new` from mobile on a herdr-managed agent → the agent restarts WITHOUT
      `--continue` → fresh session; not left at a bash pane.
- [ ] `/new` on the `outpost` (wrapper) agent → fresh session.
- [ ] Extension-reload restarts (hot-reload) still resume with `--continue`
      (no regression to the reload path).

## Ordering

`depends_on: [story-new-session-restart-fresh-extension-exit]` (keys on its exit
code). Resolve the herdr-mechanism design question before implementing.
