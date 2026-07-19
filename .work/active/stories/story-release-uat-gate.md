---
id: story-release-uat-gate
kind: story
stage: done
tags: [workflow, release]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-02
updated: 2026-07-18
---

# Add a release UAT / smoke gate before tags ship

## Brief

`v0.6.0` shipped non-functional: the `/remote-pi pair` flow was broken by three
integration bugs that all passed the automated gate suite. The current release
config (`.work/CONVENTIONS.md`) is

```
gates_for_release: [security, tests, cruft, docs, patterns, refactor]
```

— every gate is automated and derives pass/fail from code/artifacts. There is no
manual verification step between "all gates green" and "tag created," so a green
gate bundle does not actually mean the system works end to end. This story adds a
human user-acceptance / smoke gate to `release-deploy` so an operator must confirm
a live end-to-end smoke (the pairing arc, on a real relay + extension + app)
before a release tag is cut.

This is the human backstop that would have caught the v0.6.0 gap *today*. The
durable automation that catches it going forward is the companion feature
`feature-cross-component-e2e-pairing-suite` — no dependency between them; the UAT
gate is valuable independently and sooner.

## What counts as "acceptance" (the smoke runbook)

The gate is a documented, operator-run smoke that exercises the release's
headline capability end to end on a real deploy, not a re-run of unit tests. For
a release that touches the app↔Pi path (the common case), the smoke is:

1. Relay up (container `remote-pi-relay`, authenticated — `docker logs` shows
   `authenticated`, not just `Up`).
2. Pi extension up (`/remote-pi` footer 🟢 connected).
3. `/remote-pi pair` renders the QR in the TUI (not just the "QR ready" notify).
4. App scans → `pair_ok` returns (no 30s timeout).
5. Session transcript hydrates in the app (messages stream both directions).

For releases touching other components (cockpit, relay-only, site), the smoke is
the equivalent live capability for that component. The runbook lives in a
durable artifact (not `.work/`) — candidate: a section in the repo-root
`AGENTS.md` "Deployment and running" area, or a dedicated `docs/release-uat.md`,
referenced by `CONVENTIONS.md`'s gate config. The operator signs off (a checked
item / a recorded `--accept` ack) before the tag is created.

## Scope of this story

- Add a `uat` (or `manual-acceptance`) slot to `gates_for_release` in
  `.work/CONVENTIONS.md`, positioned **last** (after all automated gates), so the
  tag is not cut until the operator has run and acknowledged the smoke.
- Author the smoke runbook in a durable location and cross-reference it from
  `CONVENTIONS.md`.
- This is a process + docs change, not a code change. If during implementation
  "what UAT means" turns out to need a real design pass (e.g. per-component
  smoke matrices, automated capture of the ack), promote to a feature — but lean
  story-first.

## Out of scope

- The cross-component e2e *automation* — that is
  `feature-cross-component-e2e-pairing-suite`. This story is the manual gate; it
  can later reference the e2e suite as the automated form of the smoke once that
  exists, but does not depend on it.

## Verification

- `release-deploy <version>` on a future release pauses at the `uat` gate until
  the operator acknowledges the smoke run.
- The runbook is durable (in `docs/` or `AGENTS.md`, not `.work/`) and
  current-state (no progress-log prose).

## Context

- `v0.6.0` non-functional ship is the motivating incident; debugging arc in
  `.work/SESSION-NOTE-2026-07-02-paired-deploy-debugging.md`.
- The `relay` debug log (`RUST_LOG=relay=debug`) was the decisive diagnostic
  signal across all three bugs — the runbook should call out "trust relay logs
  over the footer/UI for connection truth" as the verification posture.

## Implementation (inline, 2026-07-19)

Implemented inline via the `implement` skill's no-coordination path (process +
docs, no subproject code).

**Design deviation from the brief (logged per autopilot caller-note judgment):**
the brief's "Scope" proposed adding a `uat` slot to `gates_for_release`. That is
not safely implementable as written: `release-deploy` invokes each
`gates_for_release` entry via `Skill(skill="agile-workflow:gate-<name>")`, and
the agile-workflow plugin ships only `gate-{cruft,docs,patterns,refactor,
security,tests}` — there is no `gate-uat` skill. A `uat` slot would fail to
resolve at Phase 4 of `release-deploy` and halt the release.

The story's *intent* (operator must acknowledge a live e2e smoke before a tag
is cut) is preserved by the alternative the brief itself anticipated ("if ...
needs a real design pass ... promote to a feature — but lean story-first"):

- `docs/release-uat.md` — the durable smoke runbook (app↔Pi pairing arc +
  other-component variants + the ack requirement + the "trust relay logs over
  the footer/UI" verification posture that was decisive in the v0.6.0 incident).
- `.work/CONVENTIONS.md` — `release_uat: manual-checkpoint` convention, with
  the rationale that it rides `release-deploy`'s built-in user-action pause
  (not a `gates_for_release` slot) and points at the runbook. The e2e
  automation feature is cross-referenced as the durable follow-up.

No subproject code changed.

## Verification

- `release-deploy <version>` pauses for operator action after the automated
  gates pass and before tag creation; the operator runs the smoke runbook and
  records the ack. (The pause is `release-deploy`'s existing "mapping requires
  user action → pause and prompt" path; no `gate-uat` skill is invoked.)
- The runbook is durable (`docs/release-uat.md`, referenced from
  `CONVENTIONS.md`) and current-state (no progress-log prose).
- `CONVENTIONS.md` carries `release_uat: manual-checkpoint` with the
  not-a-gates-slot rationale, so a future agent does not re-attempt the
  breaking `gates_for_release: [..., uat]` form.

## Review (bounded inline, standalone story)

Standalone story (`parent: null`) → bounded inline review, no fresh-context
reviewer spawn (per `review` skill routing). Checked:

- The deviation from the brief is the only safe implementation given the
  plugin's gate registry; the intent is preserved and the rationale is durable.
- The runbook matches the documented deploy shape (container name
  `outpost-pi-relay`, debug-log env vars, `/remote-pi` footer) in `AGENTS.md`.
- The convention note defends itself inline against the rejected alternative.

No material blockers. Advanced to `done`.
