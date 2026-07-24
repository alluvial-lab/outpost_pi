# SESSION NOTE — 2026-07-23 — v0.3.0 release handoff (RESUME HERE AFTER CONTEXT RESET)

Transient handoff note. Delete when superseded. **This is the master
resumption point** — the day's earlier notes
(`session-note-2026-07-23-drain-standalone-stories.md`,
`session-note-2026-07-23-late-privacy-hardening-done.md`,
`session-note-2026-07-23-late2-owner-identity-transition-done.md`) are
superseded by this one.

## TL;DR — where we are

Everything shippable is **done and reviewed**. The operator confirmed the
release plan below; the very next action is
`/agile-workflow:release-deploy v0.3.0` (repo-level first), then the three
component releases in order. `main` is 85 commits ahead of origin, **nothing
pushed** (push is external — operator runs from their machine).

## Confirmed release plan (operator-approved 2026-07-23)

Run FOUR releases, in this order, per the CONVENTIONS attribution rule
(exactly one component tag → component release; multiple/none → repo):

1. **`v0.3.0`** (repo) — 16 active + 16 archived stubs. The security arc:
   `feature-owner-message-e2e-authentication` (+5 stories),
   `feature-diagnostic-privacy-hardening` (+ its standalone drain stories),
   `feature-owner-identity-transition` (+2 stories),
   `feature-replacement-session-wake-confirmation`,
   `feature-ci-verification-matrix` (+2 stories),
   `story-e2e-session-replacement-case`,
   `story-mobile-stuck-message-after-new-session-replacement`.
2. **`app-v0.3.0`** — 3 active + 1 stub (`gate-security-owner-reset-retains-transcripts`,
   `gate-security-mobile-failure-detail-logged`,
   `app-owner-key-version-rollback-hardening`).
3. **`cockpit-v0.3.0`** — 4 active + 1 stub (the 4 cockpit diagnostic-privacy
   stories).
4. **`relay-0.3.0`** — 0 active + 5 relay-tagged archived stubs.

**Skip `extension-0.3.0`** — no extension single-tag items (extension changes
ride in multi-tag repo items). **No component items remain unbound after these
four — verify at bind time with the attribution rule.**

Per release (release-deploy skill): bind → 6 gates (`security, tests, cruft,
docs, patterns, refactor` per CONVENTIONS) → drive critical/high gate findings
to done (release-blocking; medium/low park to backlog per
`gate_finding_routing`) → draft CHANGELOG entry (operator confirms) → **UAT
manual checkpoint** (operator runs `docs/release-uat.md`, acks) → local tag
(operator pushes) → collapse (`retain-bodies`: bodies move to
`.work/releases/<version>/`). `binding_guard: warn`. Idempotent — safe to
re-run/resume any release at any phase.

## What shipped this session (all on local main)

- **Drain run**: 3 standalone stories done (`8bb4927` legacy-box finally-close,
  `8214f86` placeholder-test deletion, `a84cd8f` `agentMessageWireType` const +
  drift guard; reviews `6b98e12`/`177aeb2`/`b08b6c1`). 7 parented stories were
  design-blocked → led to the two features below.
- **`feature-diagnostic-privacy-hardening`** — done (`d6b47d2`). Adopted the
  0.2.0 content-free-by-construction policy; 5 stories + follow-ups; standard
  review (Sol) fixed legacy-JSONL egress + resend `$err` + constructor
  admission (`82ddbb9`); parked
  `idea-privacy-canaries-production-boundary-coverage`.
- **`feature-owner-identity-transition`** — done (`8f30e85`). Operator picked
  Option A (wipe transcripts on owner-key replacement). Durable per-owner mesh
  high-water mark + self-latching boot-convergent wipe. Standard review found
  3 concurrency blockers → corrective worker (Sol/high) fixed all in `f9c416d`
  (watermark context serialization, self-latching wipe, writer-exclusion
  gate).
- **Reconnect cluster triage** — ENVIRONMENT GATE, not design gate.
  `story-mobile-stuck-message-after-new-session-replacement` reconciled → done
  (`07ccf7f`; landed + live-verified via
  `feature-replacement-session-wake-confirmation`). The other 4 reconnect
  items await the operator's next physical-phone session (drop protocol is in
  `feature-reconnect-reproduction`'s body). Parked
  `idea-mobile-new-session-red-timeout-affordance`.

## Operational reminders for deploy time (post-tag)

- **Paired cutover (owner-channel E2E, app ↔ extension)**: rebuild extension
  `dist/` (`cd pi-extension && corepack pnpm build`; sandbox needs
  `COREPACK_HOME=<writable>` + `--store-dir <writable>`), then **FULL Pi
  process restart — NOT `/reload`** (stale module otherwise), then sideload
  the app APK. Pre-E2E pairings must re-pair once. Relay untouched by E2E
  (relay-0.3.0 is stub-only housekeeping; deploy it whenever convenient —
  relay first if it IS deployed with the others).
- **App APK on the VM**: cap Gradle heap to 3G + tmpdir off tmpfs (see
  AGENTS.md); `flutter build apk --release`; bump `app/pubspec.yaml` version
  MANUALLY before building (release-deploy doesn't). Phone is on a
  workstation: `scp` the APK there, `adb install -r`.
- **Flutter verification on VM**: `export PATH="$HOME/projects/outpost_pi/.tools/flutter/bin:$PATH"`;
  6 e2e tests fail from missing pairing-endpoint env (known baseline); if
  pub-cache RO errors: `PUB_CACHE=<repo>/.pub-cache flutter test --no-pub`.
- Baseline test counts after this session: app 832 passed, cockpit 261 passed,
  extension 884 passed.

## Board state after the four releases

- All active features done. Only the phone-gated reconnect cluster remains
  (`feature-reconnect-reproduction` + 4 drafting items +
  `story-reconnect-derived-contract-claims-audit` blocked on them).
- After v0.3.0 family ships: `feature-contract-gap-audit` stays blocked on
  reconnect evidence; next feature-level work is the phone drop-test session.
- Backlog: 42 items (41 + newly parked canary-strengthening idea).
