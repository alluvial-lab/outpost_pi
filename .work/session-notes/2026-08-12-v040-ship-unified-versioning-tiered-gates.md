# 2026-08-12 — v0.4.0 ship: unified versioning, tiered-gate trial, tag reclamation

## What shipped

- **`v0.4.0`** (tag `31c3b00`, on origin) — **66 items** collapsed into
  `.work/releases/v0.4.0/` (retain-bodies). First release under unified
  product versioning.
  - 13 features/fixes that had passed review but were never release-bound
    (canonical-transcript-ordering arc, extension-hot-reload-via-process-restart,
    new-session-restart, working-flag/onConnected fixes, mesh-reconciliation,
    protocol-contract discriminator registry, boundary typed decoders, etc.).
  - 47 prior gate findings (security/tests/cruft/docs/patterns/refactor) completed
    since v0.3.0 but never bound.
  - 6 gate-finding fixes driven to done by this release's own tiered gate +
    Phase 8 (see below).
- **Deployed live:** pi-extension (dist/ rebuilt + Pi restarted during UAT),
  relay (`outpost-pi-relay:0.4.0`, healthy), app (sideloaded APK v0.4.0+4).
  Cockpit intentionally **not** deployed (unused surface; fixes are in source).

## Key decisions (durable — don't relitigate)

### 1. Unified product versioning (CONVENTIONS change, commit `67f2036`)

Retired per-component semver (`app-v`/`cockpit-v`/`extension-`/`relay-`/repo `v`)
in favor of **one product `vX.Y.Z`**. Rationale: single-operator product, components
are wire-paired and co-deployed (they move in lockstep), so independent component
versions were ceremony without independence — cross-cutting work forced a repo-level
release *alongside* component cuts, and we'd been cutting both. Component tags
survive as **artifact identifiers** (`outpost-pi-relay:0.4`, app `versionName`) —
deploy details, not substrate releases. Per-component semver would only regain value
if components gained independent external consumers. Historical per-component
releases under `.work/releases/` remain as record.

### 2. Tiered release-gate model (trial; formalization parked → `backlog-idea-evaluate-tiered-release-gates`)

Instead of "all 6 gates over the whole bundle," split **2-dimensionally**:
- **Feature work** (non-`gate_origin` items) → run **all 6 gates** (new code
  deserves full hygiene + bug-catch).
- **Gate-origin work** (prior gate outputs) → run **security only** (regression
  sweep). Re-running cruft/docs/patterns on items that ARE such findings is circular.

**Verdict: it worked.** Caught 2 real regressions of prior security fixes
(broker audit-log oversized-predecessor; launchd plist not unlinked) + real
lifecycle/doc bugs in genuinely-new code; confirmed 12/14 prior fixes held; the
hygiene gates caught *actively-false* comments (the "single-clock" invariant, the
"recoverable delivery" contract). The 5-high timestamp cluster it surfaced
independently rediscovered the problem the in-flight `canonical-transcript-timestamp-ownership`
arc exists to fix — routed there, NOT bound to v0.4.0.

**Cost was heavy:** ~2.5M codex tokens across 11 subagent runs (7 scanners + drain
+ Phase 8 + fixes); several scanners near/over the 272K 2x-billing line. The
security-regression + 3 bug-catchers are inherently heavy. Weigh this when
formalizing.

## Gotchas / incidents

- **3 "done" gate findings weren't actually done.** A completion sweep (gpt-5.6-sol)
  of all 60 done items against source found: `gate-security-ci-mutable-action-refs`
  was deliberately scoped (ci.yml only; deps-audit/e2e-pairing deferred — but the
  follow-up was never re-tracked); `gate-security-combined-app-verification-flaky`
  was honestly still `drafting`; `gate-security-local-ipc-permissions` had POSIX
  landed but the **Windows named-pipe ACL** it explicitly required was unimplemented.
  Fix: amended the done item honestly (POSIX scope; Windows deferred) + opened
  backlog follow-ups (`backlog-piext-windows-named-pipe-acl`,
  `backlog-ci-pin-deps-audit-e2e-pairing-refs`). Lesson: `stage: done` is trustworthy
  but verify scope against the finding's own remediation text.

- **Phase 8 caught 2 gaps in the drain's own fixes.** The fresh-context completion
  review (standard weight, one pass) found the marker-race fix had hardened the
  wrapper to require `0600` markers but `refresh-dist.sh` still created `0644`
  (would break the multi-agent refresh), and the launchd fix deleted the plist but
  suppressed deactivation failures (old supervisor could keep running). Both fixed
  + verified. Validates the fresh-context pass even on small test-verified fixes.

- **Tag collision: pre-rebrand v0.4.0/v0.5.0/v0.6.0 on origin.** The post-rebrand
  series (reset to v0.1.0) was climbing back into occupied tag space. CONVENTIONS
  *said* those tags were deleted, but they weren't (all 3 on origin, in main's
  ancestry). **Resolution (option B):** deleted the 3 dead pre-rebrand tags on
  origin (`git push origin :refs/tags/v0.4.0 :refs/tags/v0.5.0 :refs/tags/v0.6.0`),
  reclaiming the version space — matches the stated rebrand intent and clears the
  whole collision class for v0.5.0/v0.6.0 too. This was a git-tag collision only;
  pre-rebrand *bindings* were correctly relocated to `releases-pre-rebrand/` so
  work-view was unaffected.

- **`git mv -q` unsupported** on this git (unknown switch). Use `git mv ... >/dev/null`.

## Where it stands

- origin/main at `31c3b00` (v0.4.0 ship); v0.4.0 tag on origin. **1 local commit
  unpushed**: `deploy: align relay/app/cockpit artifact versions to v0.4.0` (the
  Cargo.toml/pubspec bumps made after the tag during deploy). Land with
  `git push origin main` when convenient (deployed artifacts already carry 0.4.0).
- Board: 66 items retired to `releases/v0.4.0/`; **11 active items** — all
  genuinely in-flight (the `canonical-transcript-timestamp-ownership` arc, 5
  implementing + 6 drafting). Backlog grew with deferred findings + pattern candidates.

## Parked / next

- **Tiered-gate formalization** → `backlog-idea-evaluate-tiered-release-gates`
  (trial validated; decide whether to make it the default posture).
- **Timestamp-ownership arc** (5 implementing, in `active/`) — the natural next
  major work; closes the 5-high cluster the gates independently rediscovered.
- **Deferred findings** in backlog: `/new` teardown redesign, recoverable-delivery
  contract, hot-reload arm-path tests, herdr/cockpit hardening, broker audit
  mem ceiling, doc-drift batch, codegen Dart-IR-from-schema, + 4 pattern candidates.
- **App forward-compat:** Flutter warned the Android build will break in a future
  Flutter version (Kotlin-Gradle-Plugin usage in several plugins). Not a v0.4.0
  issue; park a migration item when convenient.
