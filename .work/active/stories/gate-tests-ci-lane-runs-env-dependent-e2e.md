---
id: gate-tests-ci-lane-runs-env-dependent-e2e
kind: story
stage: implementing
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
