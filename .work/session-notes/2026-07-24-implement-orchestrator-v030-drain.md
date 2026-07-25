# implement-orchestrator run notes — v0.3.0 bound-item drain (2026-07-24)

## Scope resolution

Natural-language scope: the 29 v0.3.0-bound blocking gate items at
`stage: implementing` (27 original + 2 operator-promoted security mediums,
bound 2026-07-24). Explicitly EXCLUDED: `feature-reconnect-reproduction` +
`epic-targeting-and-session-lifecycle-contracts` arc (live-phone-repro
gated, not auto-drainable — operator), unbound drafting stories, and parked
backlog.

All 29 items are standalone stories (parent: null) with empty depends_on —
one ready layer, no graph exclusions. Standalone-story lane: workers advance
`implementing → review`; orchestrator performs bounded inline review →
`done`. No feature/epic roll-ups apply. `review_weight`: standard (default)
— not consumed by standalone stories.

## Ownership topology (one wave; write sets verified disjoint)

| Worker | Items | Model / thinking | Write roots |
|---|---|---|---|
| W1 docs-foundation | 5 gate-docs (VISION, DECISIONS×3, AGENTS, PROTOCOL) | luna / medium | `AGENTS.md`, `docs/VISION.md`, `docs/DECISIONS.md`, `PROTOCOL.md` |
| W2 docs-readmes-skills | 5 gate-docs (README×4, rust-relay skill) | luna / medium | `README.md`, `pi-extension/README.md`, `relay/README.md`, `site/README.md`, `.agents/skills/rust-relay/SKILL.md` |
| W3 docs-pattern-anchors | 4 gate-docs pattern-anchor refreshes | luna / medium | `.agents/skills/patterns/{generation-fenced-async-ownership,stale-capability-eviction,subscription-unsubscribe-contract,typed-wire-decoders}.md` |
| W4 app-security-lifecycle | 2 gate-security (owner_identity_bridge), pairing-viewmodel dispose+generation-fence (merged item), dart secure-channel throws, orphan msgs_v3 wipe test | terra / high | `app/lib/pairing/`, `app/lib/ui/pairing/`, `app/lib/data/transport/secure_channel.dart`, `app/test/data/local/boxes_test.dart`, `app/test/{pairing,data}/**` |
| W5 app-e2e-ci | ci-lane e2e tag exclusion (critical), 3 e2e seam tests (lost-pair_ok, five-failure detach/reattach, real session-rotation) | sol / high | `.github/workflows/ci.yml`, `app/test/e2e/**`, `app/e2e/**` |
| W6 protocol-codegen | owner-multiplexer handwritten types, session-replay handwritten discriminators, cruft isFiniteNumber conditional emit | terra / high | `tools/protocol-codegen/**`, `pi-extension/src/protocol/generated/`, `pi-extension/src/extension/owner_multiplexer.ts`, `app/lib/data/sync/session_history_replay.dart` + Dart codegen output |
| W7 extension-security-docs | pairing-token-in-model-context (TUI-only render + regression), ts secure-channel @throws | terra / high | `pi-extension/src/extension/command_surface/`, `pi-extension/src/transport/secure_channel.ts`, related tests |
| W8 deps-audit (WAVE 2) | high-severity dependency audit (next/sharp/fast-uri/brace-expansion) | terra / medium | `site/package.json`, `site/pnpm-lock.yaml`, `pi-extension/pnpm-lock.yaml` |

W8 deferred to wave 2: it mutates `node_modules`/lockfiles in `site/` and
`pi-extension/` while W6/W7 verify with pnpm in the same packages — race
avoidance, not a dependency edge.

Model rationale: docs items are mechanical with scanner-verified required
edits (luna). App security/lifecycle items are same-file, failure-path
subtle (terra/high). E2E seam work needs harness design judgment (sol/high).
Protocol codegen is cross-language generated-contract work (terra/high).
Per AGENTS.md routing tiers; skill model matrix defers to stable project
convention.

## Concurrency contract (all workers)

Explicit-path `git add` only (never `-A`/`-am`); one `implement: <item-id>`
commit per item; preserve unrelated changes; standalone stories stop at
`review`; design-flaw escape hatch to `drafting`; test-integrity rule in
full; no nested delegation; no push.

## Wave outcomes (2026-07-24)

- W1/W2/W3 (14 gate-docs): all done after bounded inline review.
- W4: 4/5 done. `gate-security-owner-transition-committed-before-durable-cleanup`
  design-bounced (needs app/lib/routing scope) → W4b follow-up with expanded
  scope + orchestrator-found `_recheck()` unhandled-throw fix → done.
  W4b follow-up commit also fixed `_FakeStorage` hermeticity in
  test/ui/pairing/pairing_viewmodel_test.dart (MissngPluginException — W4b's
  boot() pending-marker check hit the platform channel; caught by
  orchestrator verification, not the workers).
- W6/W7/W8: all done. W8 review caught inert `package.json pnpm.overrides`
  (pnpm 11 reads pnpm-workspace.yaml only) → orchestrator follow-up moved
  overrides + fixed site allowBuilds placeholder.
- W5: ci-lane done (842-test clean-env run verified by orchestrator,
  `--concurrency=4` — default concurrency flakes on this loaded VM).
  Cross-item regression found: W7's TUI-only pair-code removal broke the
  e2e harness pair-code observation → entire e2e-pairing lane red.
  `session-replacement-real-rotation` bounced for harness scope.
- W5b (sol/high) dispatched: pair-code env-file seam
  (OUTPOST_PI_PAIR_CODE_FILE + pi-host endpoint), real-harness verification
  of lost-pair-ok + five-failure, session-replacement harness controls.
- W5b: all 3 items done. Seam `04550fc`; orchestrator independently re-ran
  `e2e/run-pairing.sh`: 16/16 + 20 redaction canaries. Extension 930
  passed/3 skipped + typecheck. App analyze clean; non-e2e 842/842 green
  at `--concurrency=2` (C=4 still flakes sync timing tests on this VM —
  every victim passes standalone; pre-existing suite characteristic).

## Final result: 29/29 bound blocking items done (2026-07-24)

v0.3.0 readiness is unblocked. Next: re-run
`/agile-workflow:release-deploy v0.3.0` (idempotent — resumes at
readiness → changelog → UAT checkpoint → local tag → collapse).

## Notes for release

- `backlog/app-sync-detached-transcript-degradation-regression.md`: did NOT
  reproduce on the integrated tree (107/107 sync tests green repeatedly) —
  cross-worker mid-flight contamination, annotated.
- Full-suite flutter runs on this VM need `--concurrency=2` for a
  reliable green (842 passed); higher concurrency under residual load
  produces non-deterministic sync timing-test failures (all pass
  standalone).
