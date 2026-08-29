---
id: gate-docs-dual-execution-path-pattern
created: 2026-08-29
updated: 2026-08-29
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Dual-execution-path pattern examples omit the session-new fail-closed outcome

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/dual-execution-path-contract-documentation.md:38-46,56-74`
- Contradicting source: `pi-extension/src/index.ts:3288-3298,3346-3370`; `PROTOCOL.md:261-270`

## Current doc text
> `session_new` has two execution paths. In an in-process command context,
> `ctx.newSession()` replaces the SDK session ... In daemon/restart-wrapper mode
> ... the extension installs a synchronous restart fence ... and exits with
> `EXIT_FRESH_SESSION` (`42`) ... without `--continue`.
>
> The user and agent examples describe only the in-process and
> daemon/restart-managed paths.

## Contradiction
The pattern's examples are presented as the current contract for the
protocol, user documentation, and agent reference, but the current
`session_new` implementation also has a bare no-context branch. When no command
context, daemon mode, or restart-wrapper owner is present, it exits with
`EXIT_FRESH_SESSION` (`42`) to avoid leaving a detached live process. The
examples' exhaustive “two paths” wording no longer describes the shipped
contract, even though the two primary execution paths remain valid.

## Required edit
Update the pattern examples and explanatory text to include the bare
no-context fail-closed terminal outcome, distinguish it from the managed
restart/relaunch path, and retain the in-process fresh-context and durable
recovery rules. Keep the pattern general enough for operations with only two
paths; do not describe the bare fallback as a universal requirement.
