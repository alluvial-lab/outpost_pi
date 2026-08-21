# Release UAT / smoke gate

A release tag is not cut until an operator has run and acknowledged a live
end-to-end smoke against the deployed release candidate. This is the human
backstop that would have caught the `v0.6.0` non-functional ship (the
`/outpost-pi pair` flow was broken by three integration bugs that all passed
the automated gate suite).

This is a **manual checkpoint**, not an entry in `gates_for_release`. The
agile-workflow `release-deploy` skill invokes each `gates_for_release` entry as
`Skill(skill="agile-workflow:gate-<name>")`; there is no `gate-uat` skill, so a
`uat` slot there would fail to resolve and halt the release. Instead,
`release-deploy` pauses for user action after the automated gates pass and
before tag creation (its "mapping requires user action → pause and prompt"
path), and the operator runs this runbook at that pause.

The durable automation that catches integration regressions going forward is
`feature-cross-component-e2e-pairing-suite`; this manual runbook is the
independent, sooner backstop.

## Verification posture

**Trust relay logs over the footer/UI for connection truth.** Across all three
`v0.6.0` bugs, the relay debug log (`RUST_LOG=info,relay=debug`,
`OUTPOSTPI_RELAY_LOG_DIR=/data/logs`) was the decisive diagnostic signal — the
TUI footer and app UI reported success while the wire path was broken. A green
footer is not acceptance; an `authenticated` line in the relay log is.

## App↔Pi release smoke (the common case)

For a release that touches the app↔Pi path, the smoke exercises the pairing →
session-hydrate lifecycle end to end on a real deploy:

1. **Relay up** — container `outpost-pi-relay` running; `docker logs
   outpost-pi-relay` shows `authenticated` for a real peer, not just `Up`.
2. **Pi extension up** — `/outpost-pi` footer shows 🟢 connected.
3. **`/outpost-pi pair` renders the QR** in the TUI (the actual QR glyph, not
   just the "QR ready" notify).
4. **App scans → `pair_ok` returns** (no 30s timeout).
5. **Session transcript hydrates** in the app — messages stream both
   directions; an outbound user message produces an agent response on the app.
6. **Scanner boundary smoke** (mobile_scanner v7 native
   boundary; added 2026-08-16, first executable at next phone-attached
   checkpoint): on the local emulator `scripts/emulator-scanner-smoke.sh` (boot line + prereqs in story-ci-android-emulator-test-job); on a real phone `cd app && flutter test integration_test/mobile_scanner_boundary_test.dart -d <android-or-ios-device> --tags e2e`.
7. **Phosphor Beacon visual smoke on a real device** (dark + light modes;
   pending since v0.5.0 — themed screenshot retake for the site is tracked by
   `feature-public-flip-branding-and-exposure`): verify app theme renders the
   dual-mode tokens and Space Mono on-device, both appearance modes.

Each step must actually occur; a silent skip is a failure. If any step fails,
do not cut the tag — triage via the relay debug log + the delivery-path debug
log (`OUTPOST_PI_DEBUG_LOG=1` → `~/.pi/remote/debug/delivery.log`), fix, redeploy,
and re-run.

## Other-component releases

For releases touching other components, run the equivalent live capability for
that component:

- **cockpit** — launch the desktop build, connect to a running pi session, and
  exercise the control surface (settings create/rename, control commands).
- **relay-only** — confirm `authenticated` peers, cross-PC forward path, and
  room/presence state via the relay log.
- **site** — `pnpm build` green + the production route renders.

## Acknowledgment

The operator records the ack (a checked item / a recorded `--accept` on the
`release-deploy` resume) before the tag is created. No ack → no tag.

## See also

- [`.work/CONVENTIONS.md`](../.work/CONVENTIONS.md) — `release_uat` convention.
- [`feature-cross-component-e2e-pairing-suite`](../.work/active/features/feature-cross-component-e2e-pairing-suite.md) — the durable automated form of this smoke.
- [AGENTS.md — Deployment and running](../AGENTS.md) — component locations and the paired wire-change deploy order.
