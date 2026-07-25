---
id: gate-tests-ci-lane-runs-env-dependent-e2e
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: tests
created: 2026-07-24
updated: 2026-07-24
---

# App CI lane invokes environment-dependent E2E tests without the required harness

## Priority
Critical

## Value evidence
Item: `feature-ci-verification-matrix`. The feature requires all six lanes green, but `.github/workflows/ci.yml:158-160` runs unfiltered `flutter test`. Pairing tests construct `HarnessEndpoints` and fail when E2E_PI_HOST_URL/E2E_RELAY_URL/E2E_TOXIPROXY_URL are absent (`app/test/e2e/support/harness_endpoints.dart:9-18`); multiple bundle verification records confirm 6 consistent pairing-endpoint failures under unfiltered `flutter test`. The separate e2e-pairing.yml owns the Docker harness.

## Gap type
important-interface

## Suggested test
```yaml
# Mark harness-dependent tests explicitly and prove the ordinary CI command
# exits zero in a clean environment with no E2E_* defines.
- run: flutter test --exclude-tags e2e
# Separately assert e2e/run-pairing.sh selects the tagged E2E suite with
# its injected Docker/Toxiproxy endpoints.
```

## Test location (suggested)
`.github/workflows/ci.yml`

## Implementation notes

- Tagged every harness-backed `app/test/e2e/*_test.dart` suite with the library-level `e2e` tag and changed the ordinary app CI lane to `flutter test --exclude-tags e2e`. The dedicated pairing workflow still selects `test/e2e/` through `e2e/run-pairing.sh`, so harness coverage remains in its Docker/Toxiproxy-owned lane.
- Verification: in a detached clean worktree containing only this item patch, ran `flutter pub get`, then ran `env -u E2E_PI_HOST_URL -u E2E_RELAY_URL -u E2E_TOXIPROXY_URL -u E2E_COMPOSE_PROJECT -u E2E_COMPOSE_FILE -u E2E_REDACTION_CANARY_FILE flutter test --no-pub --exclude-tags e2e`; the rerun exited zero with 839 tests passed and no harness endpoint defines. The first clean invocation hit the existing timing-sensitive `sync_service_test.dart` no-echo assertion and the immediate identical rerun passed. The Docker harness was not executed for this CI-routing item.

## Review

Bounded inline review (orchestrator, 2026-07-24): all six harness suites
carry @Tags(['e2e']); ci.yml runs `flutter test --exclude-tags e2e`.
Orchestrator-verified on the integrated tree: `flutter test --exclude-tags
e2e` exits zero with no E2E_* defines — 842 tests passed. Approved -> done.
