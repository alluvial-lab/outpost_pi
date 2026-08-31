---
id: gate-docs-session-new-fail-closed-contract
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.11.1
gate_origin: docs
created: 2026-08-29
updated: 2026-08-29
---

# Session-new documentation omits the bare-process fail-closed path

## Drift category
foundation-doc-assertion

## Location
- Doc: `PROTOCOL.md:261-270`; `scripts/pi-restart-loop.sh:28-29`
- Contradicting source: `pi-extension/src/index.ts:3288-3298,3346-3370`

## Current doc text
> `session_new` has two execution paths. In an in-process command context,
> `ctx.newSession()` replaces the SDK session and the extension re-captures fresh
> session capabilities before continuing. In daemon/restart-wrapper mode, where
> the command-only SDK capability is unavailable, the extension installs a
> synchronous restart fence ... and exits with `EXIT_FRESH_SESSION` (`42`).
>
> The wrapper comment says: “This is the extension's safety gate: only this
> wrapper and the daemon supervisor are allowed to turn a mobile /new request
> into process exit.”

## Contradiction
The release adds a third outcome for `session_new`: when no fresh command
context exists and neither daemon nor restart-wrapper mode owns the process, the
extension now exits with `EXIT_FRESH_SESSION` (`42`) rather than returning an
unavailable-action error. The command-capable path still performs an in-process
replacement, and the managed path still performs the fenced drain and restart.
Therefore the protocol's exhaustive “two execution paths” assertion is stale,
and the wrapper comment's claim that only managed owners can cause a mobile
`/new` process exit is false. The bare exit is the fail-closed side of the
room-bound-or-exited invariant; it has no wrapper to relaunch the process.

## Required edit
Roll the session-new contract forward to describe all three outcomes: fresh
command context uses in-process replacement; daemon/restart-wrapper ownership
uses the managed fence, drain, reset, and exit/relaunch path; and a bare
no-context process exits with `EXIT_FRESH_SESSION` as the fail-closed terminal
fallback. Update the wrapper comment to distinguish its relaunch-owned path
from the bare process's terminal fail-closed exit. Keep the room/session
convergence and durable delivery caveats current; do not add historical prose.
