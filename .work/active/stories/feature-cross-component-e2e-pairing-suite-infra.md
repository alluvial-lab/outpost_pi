---
id: feature-cross-component-e2e-pairing-suite-infra
kind: story
stage: done
tags: [e2e-test, testing]
parent: feature-cross-component-e2e-pairing-suite
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-19
updated: 2026-07-18
---

# Scaffold the cross-component pairing e2e stack

## Checkpoint

Create the top-level Compose/runner/CI surface and the narrow Pi-host, Flutter,
secure-storage, Toxiproxy, readiness, and teardown helpers specified by Unit 1
of the parent design. The stack runs the real relay image, the real extension
factory through the installed Pi SDK runtime, and app production adapters. The
Pi host is the only custom service substitute and exposes command input plus
user-visible TUI/status output—never raw envelope injection.

## Ordering

This checkpoint blocks every lifecycle case. Keep one feature owner for the
bundle; this story records infrastructure readiness rather than a separate
worker assignment.

## Acceptance evidence

- [ ] `e2e/run-pairing.sh` starts relay, Pi host, and pinned Toxiproxy with healthchecks and dynamic host ports, then tears down containers and volumes on every exit.
- [ ] Pi host uses a fresh HOME/cwd, the installed SDK runner, production extension factory, realistic `session_start` context without message actions, and process restart for isolation.
- [ ] Flutter support uses real `PairingStorage`, app transport/channel/connection/sync adapters, real temp Hive, and only a scoped secure-storage platform fixture.
- [ ] Readiness and event waits are bounded predicates with privacy-safe phase diagnostics; no arbitrary startup sleeps.
- [ ] `.github/workflows/e2e-pairing.yml` runs the same local entrypoint without an APK, emulator, model provider, or secrets.

## Test integrity

If this harness exposes a production bug, park it in this repo and land the
honest failing test as a linked skip with a one-line reason; do not weaken the
invariant. Fix stale fixtures, drifted assertions, and harness defects
in-session. Never game an assertion, assert mock calls as product evidence, or
replace real sockets with in-process mocks merely to obtain green.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for the cross-component architecture).
- Review weight: `standard` (caller).
- Files changed: `e2e/docker-compose.test.yml`, `e2e/services/pi-host.Dockerfile`, `e2e/run-pairing.sh`, `e2e/README.md`, `e2e/tsconfig.pi-host.json`, `pi-extension/test/support/e2e_pi_host_{runtime,server}.ts`, and `app/test/e2e/support/` endpoint/readiness/storage/proxy clients.
- Tests added: infrastructure smoke through the same runner; installed-SDK host typecheck and Flutter support analysis.
- Simplification: one HTTP command/status/event boundary and one bounded polling helper; process restart remains the only extension reset.
- Discrepancies from design: `.github/workflows/e2e-pairing.yml` is not written because the caller's allowed write scope excludes `.github/`; the local/CI-compatible entrypoint is complete for a later workflow-only follow-up.
- Adjacent issues parked: none.
- Verification: `node_modules/.bin/tsc -p ../e2e/tsconfig.pi-host.json`; Flutter analyze of `test/e2e/support`; `E2E_INFRA_ONLY=1 e2e/run-pairing.sh` (relay, Pi host, and Toxiproxy healthy; cleanup passed).
