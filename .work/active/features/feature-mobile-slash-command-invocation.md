---
id: feature-mobile-slash-command-invocation
kind: feature
stage: drafting
tags: [app, pi-extension, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# Mobile command invocation (dedicated-ops model)

## Brief

Let the mobile app invoke the pi commands it actually needs — via **dedicated
operations per command** (the Pi ecosystem's own pattern), NOT a general
slash-command invoke (which the SDK does not provide) and NOT the fragile
editor-seam (rejected on design review). Core deliverable: **`/new` works from
mobile** by extending the daemon's restart-fresh approach to interactive agents.
Plus a verify-first look at invoking the extension's own commands from mobile.
Upstream host-operation API tracked as the long-term clean general solution.

## How we got here (the editor-seam detour, recorded so it's not retried)

1. Origin: the `/new` bug — `newSession unavailable (no command ctx yet)`
   (`.work/backlog/backlog-mobile-new-button-newsession-no-command-ctx.md`).
2. Confirmed root cause: the mobile app can't issue slash commands — `sendMessage`
   → `_wakeAgent` prompt-injects, bypassing pi's command parser.
3. A spike found an editor-seam (`setEditorComponent` + `editor.onSubmit`) that
   reaches pi's parser programmatically.
4. A `gpt-5.6-sol` design review **killed the editor-seam**: not a transparent
   proxy (history lost across `/reload`), `onSubmit` is a user-event callback
   whose programmatic invoke can **clobber a TUI draft being composed**, no robust
   ack, composer `/`-routing unsafe (unknown commands become model prompts).
5. The operator's push ("surely others issue commands programmatically") led to
   the real model: **dedicated operations per command** — the cockpit does exactly
   this (`agent_composer.dart:470`: "Route a pure built-in (/new, /compact)
   through its dedicated RPC"). The SDK gates session-control (`newSession`/
   `fork`/`switch`/`reload`) behind `ExtensionCommandContext` — *"only safe in
   user-initiated commands"* — while safe ops (`compact`/`abort`/`shutdown`) sit
   on the base `ExtensionContext`. **That's why `compact` works from mobile but
   `/new` doesn't: `compact()` is base-context; `newSession()` is command-gated
   by design.** No general command-invoke API exists.

## Rescoped direction

Drop "arbitrary slash commands, both modes." Deliver the commands mobile needs
through the right dedicated path each:

| Need | Path | Story |
|---|---|---|
| **`/new`** (the original bug) | **restart-fresh**: interactive `session_new` (no command-ctx) acks + resets + exits with the fresh-session code; the process manager restarts **without `--continue`** (the daemon `EXIT_DAEMON_FRESH_SESSION` pattern, extended to interactive) | `…-restart-fresh-*` (core) |
| **Extension commands** (`/outpost-pi …`) | the extension owns those handlers — verify whether they're callable from mobile without the command-context gate | `…-extension-command-invocation` (verify-first) |
| Native safe ops (`/compact`, set_model, …) | already work via existing actions | n/a |
| Arbitrary unknown commands | none, and unsafe | out of scope |
| General durable solution | upstream host-operation API in `@earendil-works/pi-coding-agent` | tracked, not blocking |

## Child stories

- `story-new-session-restart-fresh-extension-exit` — interactive `session_new`
  with no command-context → ack + reset + `process.exit(EXIT_FRESH_SESSION)`
  (mirror the daemon path at `index.ts:2981`). `depends_on: []`.
- `story-new-session-restart-fresh-restart-mechanism` — the process manager
  restarts **without `--continue`** on that exit code: `pi-restart-loop.sh`
  enhancement (outpost) **+** a mechanism for the 11 herdr-managed agents.
  `depends_on: [extension-exit]`. **Key design risk** (below).
- `story-mobile-extension-command-invocation` — verify-first whether the
  extension's own commands can be invoked from mobile without the command-context
  gate (per-command check of what context the handlers use). `depends_on: []`.

## Key design risk (the restart-mechanism story)

The daemon auto-restarts via its supervisor; **herdr-managed agents do NOT
auto-restart on exit** (a SIGTERM'd agent sits at a bash pane until manually
re-launched), and `herdr agent start -- …` resumes with `--continue`. So
restart-fresh for the 11 herdr agents needs a real mechanism — candidates:
- run **all 12 agents under the `pi-restart-loop` wrapper** (today only `outpost`
  is), with the wrapper restarting without `--continue` on the fresh-session code;
  or
- a "fresh-session-requested" marker the next launch reads + drops `--continue`.
This is the open design point for that story; resolve before implementing.

## Out of scope (rejected)

- The editor-seam (`setEditorComponent` + `onSubmit`) — killed by design review
  (draft-clobber hazard, not a transparent proxy, no robust ack, unsafe composer
  routing).
- "Arbitrary slash commands / both modes" — the cockpit doesn't even do this;
  the SDK has no general command-invoke API.
- Retiring `session_new` — the daemon path + deploy-compat + the durable protocol
  depend on it; keep it (the fix changes its interactive implementation, not its
  wire contract).
- Upstream host-operation API — tracked as the long-term clean general solution,
  not blocked on.

## Verification (per story at implement time)

- `/new` from mobile → fresh session (new `session_start reason=new`), no
  `newSession unavailable` error; works for the wrapper agent AND herdr-managed
  agents; `--continue`-resumed agents correctly go fresh on `/new`.
- Extension tests (`corepack pnpm test`); the daemon `EXIT_DAEMON_FRESH_SESSION`
  path unchanged (no regression).
- Extension-command invocation (if the verify pans out): relevant `flutter test`
  + a round-trip of an `/outpost-pi …` command from mobile.
