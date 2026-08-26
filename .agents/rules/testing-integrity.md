# Testing Integrity

Tests are evidence. Do not make them green by weakening what they prove.

## No gaming tests

Never use patterns such as:

- `expect(true).toBe(true)`;
- asserting whatever the current implementation happens to return;
- deleting a failing test without root cause;
- broadening mocks until behavior is no longer tested;
- snapshot updates that hide behavior changes;
- disabling lint/tests without a linked reason and follow-up.

A failing test with an honest skip/xfail-equivalent reason tied to a tracked bug is better than a dishonest green test.

## Failure triage

When a test fails, classify it before fixing:

- **Product bug** — real behavior is wrong. Track it in this repo's `.work/` queue unless it is the task you are explicitly fixing.
- **Test drift/debt** — stale fixture, broken mock, outdated assertion, fragile timing. Fix it in-session so the suite remains useful.
- **Environment issue** — missing service, dependency, simulator, browser, or secret. Report the exact prerequisite; do not fake the test.

Do not silently fix unrelated product bugs mid-test-pass unless the user asked for broad cleanup and the bug is small enough to verify fully.

## Agent-reported test results

Subagent pass/fail self-reports are claims, not evidence (2026-06-30
false-failure incidents; full history in
`.work/archive/backlog-piext-agents-false-uds-failure-claims`):

- The orchestrator independently re-runs the owning suite on high-risk
  stories (lifecycle, listeners, delivery, identity). Agent
  self-classification is never the sole gate.
- Environment-flake dismissal applies only to failures whose names or
  errors name the environment (bind EPERM, read-only socket paths, fixture
  leader-election races). Tests asserting behavior — listener counts,
  delivery counts, state transitions, exactly-once — are root-caused and
  fixed, never waived as flakes.
- Validate expectation changes against a clean checkout of HEAD; counts
  observed while debugging a dirty tree are not evidence.

## Verification by subproject

Use the owning subproject's commands.

### `pi-extension/`

```bash
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```

### `app/`

```bash
flutter analyze
flutter test --exclude-tags e2e
flutter build apk --debug   # or an appropriate platform build smoke
```

Run the dedicated cross-component E2E pairing harness from the repository root:

```bash
e2e/run-pairing.sh
```

On this VM, full-suite runs use `--concurrency=2` for load-sensitive timing tests.

### `relay/`

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
cargo build
```

### `cockpit/`

```bash
flutter analyze
flutter test
flutter build macos
```

### `site/`

```bash
pnpm lint
pnpm build
```

If a command is too expensive or unavailable in the current environment, say what was skipped and why, and run the nearest meaningful smaller check.

## Async and lifecycle tests

Remote Pi's highest-risk defects are lifecycle/state convergence bugs. Add or preserve tests for:

- stale Pi SDK context after session replacement;
- reconnect hydration after dropped relay/app updates;
- `working` state converging false after success, error, abort, compaction, and shutdown;
- daemon restart/session-new behavior;
- keyring fallback and identity preservation;
- WebSocket reconnect/teardown paths;
- Flutter async UI mounted guards.

Prefer deterministic timers/fake clocks where available over sleeps. Long-running manual smoke tests should be documented separately from unit tests.
