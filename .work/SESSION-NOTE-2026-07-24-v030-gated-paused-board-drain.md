# SESSION NOTE — 2026-07-24 — v0.3.0 gated + paused; board drain next (RESUME HERE AFTER CONTEXT RESET)

**SUPERSEDED 2026-07-25: v0.3.0 SHIPPED.** Drain completed (29/29), gates
re-run on the drain delta (9 new bound blockers, all fixed same-day),
UAT passed (operator ack), tag `v0.3.0` cut on `fedf37f` (operator pushes),
release collapsed retain-bodies to `.work/releases/v0.3.0/`. Remaining:
component releases `app-v0.3.0` (3 active + 2 stubs), `cockpit-v0.3.0`
(4 active + 1 stub — includes the pair-code seam fix), `relay-0.3.0`
(5 relay stubs). Verify each bind with the attribution rule; the local
gather patch skips stamped husks. `extension-0.3.0` stays skipped;
`backlog-piext-extension-test-19-failures` stays unbound. The deployed
stack is live: extension dist rebuilt + full Pi restart done, app
0.3.0+2 debug APK sideloaded, relay 0.2.0 container unchanged (no v0.3.0
relay changes). This note is kept for the deploy/cutover reference below;
delete at next substrate groom.

---

Transient handoff note. Delete when superseded. **This is the master
resumption point** — supersedes
`SESSION-NOTE-2026-07-23-release-v030-handoff.md` (deleted).

## TL;DR — where we are

`release-deploy v0.3.0` ran bind → all 6 gates → readiness, then the
operator **paused the release cycle to drain the board first**. The drain
is now complete (29/29 done). **Next action: drain the 29 bound
blocking items via `/agile-workflow:implement-orchestrator`, then re-run
`/agile-workflow:release-deploy v0.3.0`** (idempotent — resumes at
readiness → changelog → UAT checkpoint → local tag → collapse).

**Update 2026-07-24 (drain COMPLETE): all 29 bound blocking items are
`stage: done`.** Full record in
`.work/session-notes/2026-07-24-implement-orchestrator-v030-drain.md`.
**Next action: re-run `/agile-workflow:release-deploy v0.3.0`** (idempotent
— resumes at readiness → changelog → UAT checkpoint → local tag →
collapse). Notable drain outcomes beyond the item list: pair-code E2E seam
(`OUTPOST_PI_PAIR_CODE_FILE`) added to heal the e2e-lane regression from
the TUI-only security fix (harness 16/16 verified twice, incl. once by the
orchestrator); pnpm overrides live in `pnpm-workspace.yaml` (pnpm 11
ignores package.json `pnpm.overrides`); full-suite flutter on this VM wants
`--concurrency=2`.

~~**Update 2026-07-24 (pre-drain operator decisions, applied):**~~ the OPEN
OPERATOR DECISION below is resolved — both owner-transition security mediums
promoted + bound (drain queue: 27 → 29). The pairing-viewmodel overlap is
resolved — generation-fence item merged into the bound no-dispose item
(combined acceptance). Drain scope = the 29 bound items ONLY; the
reconnect/targeting epic arc (`feature-reconnect-reproduction` +
`epic-targeting-and-session-lifecycle-contracts`) is live-phone-repro work
and is explicitly NOT auto-drainable.

## Release state

- `.work/active/release-v0.3.0.md` at `stage: quality-gate`, full gate-run
  log + binding-consistency record in body.
- **Bound set: 24 original items + 28 gate items** (27 blocking at
  `implementing` + `gate-patterns-v0.3.0` done).
- Bind was 17 active + 7 done archived stubs. 16 other late-bound archive
  stubs were **unbound** (see "husk sweep" below).

## Gate results (all 6 ran 2026-07-24; findings committed as items)

| Gate | Findings | Bound blocking | Parked to backlog |
|---|---|---|---|
| security | 7 (2H/3M/2L) | 2 | 5 |
| tests | 6 (2C/4H) | 5 | 1 |
| cruft | 3 (1H/2M) | 1 | 2 |
| docs | 14 (all H) | 14 | 0 |
| patterns | 5 patterns + 3 inconsistencies | 1 (done) | 3 drafting stories |
| refactor | 14 (11H/3M; 4 libraries) | 5 | 9 |

- Patterns gate wrote 5 new patterns
  (`content-free-diagnostic-categories`, `frame-byte-bounded-admission`,
  `identity-scoped-monotonic-high-watermarks`,
  `recoverable-secure-channel-circuit-breakers`,
  `cross-language-known-answer-fixture-triangulation`), regenerated
  `.agents/skills/patterns/SKILL.md` (16 patterns) + `.agents/rules/patterns.md`
  digest. 3 inconsistency stories parked unbound at drafting.
- Refactor gate discovered a **4th** scan library (`scan-documentation`,
  findings-route: refactor) — CONVENTIONS prose still says 3; fix on next
  conventions touch.

## Drain queue (the 29 bound blocking items, all `stage: implementing`)

- **14 gate-docs** — E2E trust-model roll-forwards (VISION/DECISIONS/AGENTS/
  READMEs×4/rust-relay skill/4 pattern-skill anchor fixes). Mechanical,
  parallelizable; biggest readiness mass. Note: follow each item's
  "Required edit" — the docs scanners verified contradicting sources.
- **5 gate-tests** — `ci-lane-runs-env-dependent-e2e` (critical: ci.yml runs
  unfiltered `flutter test`; needs e2e tag exclusion), 3 e2e seam tests
  (lost-pair_ok recovery, 5-failure detach/reattach, real session-rotation
  replacement), 1 unit test (orphan msgs_v3 wipe).
- **5 gate-refactor** — pairing_viewmodel dispose/generation fence
  (absorbed the parked `gate-patterns-inconsistency-pairing-viewmodel-generation-fence`
  2026-07-24 — combined acceptance on the bound item), 2 protocol-contract
  discriminator-registry items, 2 secure-channel @throws dartdoc/JSDoc items.
- **4 gate-security** — `pairing-token-in-model-context` (QR bearer token
  reaches LLM context via pi.sendMessage → render TUI-only + regression),
  `high-severity-dependency-audit-failures` (next≥16.2.11, sharp≥0.35.0,
  fast-uri≥3.1.4, brace-expansion≥5.0.7; deps-audit lane red),
  `owner-transition-committed-before-durable-cleanup` (durable pending-
  transition record + boot-convergent cleanup; promoted 2026-07-24),
  `identity-store-fatal-read-rotates-owner-key` (generate only on null load;
  no silent rotation on fatal reads; promoted 2026-07-24).
- **1 gate-cruft** — conditional `isFiniteNumber` emit in protocol codegen.

~~**OPEN OPERATOR DECISION**~~ **RESOLVED 2026-07-24**: both owner-transition
MEDIUM security findings promoted to release-blocking and bound at
implementing (`gate-security-owner-transition-committed-before-durable-cleanup`,
`gate-security-identity-store-fatal-read-rotates-owner-key` — moved from
`.work/backlog/` to `active/stories/`).

**Unbound backlog rollups (genuine consolidated work, post-v0.3.0 drain
candidates)**: `backlog-cruft-removal-batch` (8),
`backlog-app-lifecycle-owned-operations` (4),
`backlog-cockpit-file-watch-reliability` (3),
`gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward`, plus ~20 parked
medium/low findings from this cycle.

## The husk sweep (root-caused + fixed locally)

The archived-stub late-binding gather swept 16 retired husks (9 groom
merge-absorbed, 3 duplicates — 2 fold targets shipped in extension-0.2.0,
4 superseded/resolved). Zero genuine work. All 16 unbound + stamped
(`status: superseded|duplicate` + pointer). Fixes:

- **CONVENTIONS.md** gained "Archive-tier semantics": retired husks must be
  stamped at retirement; grooms must stamp at merge; incomplete work belongs
  in backlog, not archive.
- **Local stopgap patch** in the skills repo
  (`~/.pi/agent/git/github.com/nklisch/skills`, branch
  `agile-workflow/archive-husk-gather-skip`, 2 commits): gather skips
  status-stamped + non-done archive files; groom stamp rule. **This patch is
  live for our next release run.**
- **Upstream PR NOT opened.** Adversarial review (Sol/high) said "rework":
  guard/gather predicate split, retirement≠eligibility conflation,
  SPEC/convert/review foundation drift, hand-rolled YAML parsing, missing
  version bump. Full rework scope parked as
  `.work/backlog/release-deploy-archive-eligibility-contract.md` IN THE
  SKILLS REPO on that branch (3rd commit, pushed). Path: upstream issue
  first (maintainer picks eligibility vocabulary), then contract PR.
  If upstream picks different vocabulary, migrate our stamps then.

## Remaining release plan (post-drain)

1. Re-run `/agile-workflow:release-deploy v0.3.0` → readiness (27 items
   done) → changelog draft (CHANGELOG.md exists, keep the v0.2.0 format;
   draft covers the security arc + note the paired cutover) → **UAT manual
   checkpoint** (operator runs `docs/release-uat.md`, acks) → local tag
   `v0.3.0` (operator pushes) → collapse retain-bodies.
2. Then component releases in order: `app-v0.3.0` (3 active + 2 stubs),
   `cockpit-v0.3.0` (4 active + 1 stub), `relay-0.3.0` (5 relay stubs).
   **Verify each bind with the attribution rule** — the gather is now
   patched locally, but the relay/app stub sets include groom-merge husks
   that are stamped, so they should skip cleanly. `extension-0.3.0` stays
   skipped; `backlog-piext-extension-test-19-failures` stays unbound.
3. Deploy reminders (unchanged from 2026-07-23 note): paired cutover =
   rebuild extension dist → FULL Pi restart (not /reload) → sideload app;
   pre-E2E pairings re-pair once; relay deploy whenever convenient (first
   if deployed with the others). App APK: cap Gradle heap 3G + tmpdir off
   tmpfs; bump app/pubspec.yaml manually.

## Environment notes

- `gh` is NOT authenticated on the VM (skills-repo PR must be opened from
  the operator's machine; branch is pushed).
- The skills-repo checkout has an untracked `package-lock.json` — left alone.
- main is ~90 commits ahead of origin; nothing pushed (push is external).

---

**Update 2026-07-27 (component releases COMPLETE):** app-v0.3.0 (tag
46a888c) and cockpit-v0.3.0 (tag 530cf7b) shipped, collapsed
retain-bodies. relay-0.3.0 SKIPPED as empty: of the 5 expected stubs, 4
are stamped retired husks (gather skips) and 1 was already bound to
v0.1.0; no relay code changed this cycle. 3 unfinished cruft items moved
archive→backlog per archive-tier semantics. Release family complete:
v0.3.0 + app-v0.3.0 + cockpit-v0.3.0; extension-0.3.0 and relay-0.3.0
both skipped. Push: git push origin main v0.3.0 app-v0.3.0 cockpit-v0.3.0.
