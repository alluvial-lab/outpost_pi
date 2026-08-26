---
id: feature-public-flip-branding-and-exposure
kind: feature
stage: done
tags: [branding, security, ops, release]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-14
updated: 2026-08-26
---

# Public flip: branding holdover cleanup + private-layer exposure remediation

Forensic audit 2026-08-14 (hash-compared against upstream main; image reads
unavailable this session — provenance established via git hash-object).

## A. Look-and-feel holdovers (all CONFIRMED upstream artifacts)

1. **Launcher icons are upstream's art, byte-identical**: Android adaptive
   set + iOS AppIcon set in `app/` hash-match `jacobaraujo7/remote_pi@main`.
   Cockpit macOS/Windows icons use the same 1024 source
   (`c7614537…`). The rebrand propagated upstream art, not new art.
2. **`app/lib/ui/core/themes/app_colors.dart` is byte-identical to
   upstream's** — the mobile app's whole color theme is upstream's.
3. **The documented brand palette (black/white/#4FC3F7, branding/README.md)
   is referenced by ZERO code** — it exists only in branding/ SVGs.
4. **Site art diverged**: `site/public/logo.svg` + `site/app/icon.svg` differ
   from `branding/logo-full.svg` (stale/PT-era variants, likely pre-rebrand).
5. **`branding/screenshot-app.png`** (used on site cockpit page) predates any
   re-rebrand; retake after new look lands.
6. Fonts: vestigial commented Schyler/Trajan Pro stanzas in app+cockpit
   pubspecs (upstream leftovers). Runtime fonts via google_fonts (fine).
7. Acceptable as-is: README MIT attribution, cockpit CHANGELOG historical
   "Remote Pi" entries (history), legacy-migration identifiers in tests.

## B. Private-layer exposure if repo goes public (the hard blocker)

- **957 tracked files** of private ops across `.work/` (session notes with
  incident detail), `.research/`, `.orchestration/`, `.claude/`, `review/`,
  `REPO-EVAL.md`, root `AGENTS.md`/`CLAUDE.md` (full deploy runbook with
  LAN/tailnet IPs, VM hostname, phone setup).
- **~1,397 commits of history touching `.work/` alone** — a public flip
  exposes ALL history, so tree cleanup alone is insufficient.
- Scattered: `scripts/herdr-setup.sh` comment (LAN IP), fixture hostname
  `dev-vm` (cosmetic). Site docs page tailscale mentions are benign links.

## Historical status: design locked 2026-08-14

Identity complete (see `.mockups/design-system/` + `branding/`):
- **World**: Phosphor Beacon — dark-native #0D1210 / light #F3F6F3, accent
  #74CC9C / #256E47, full status set AA-verified both modes.
- **Mark**: Constellation III, enlarged — block-cursor hub (phosphor) + two
  peer nodes (ink). Canonical SVGs in `branding/` (v2.0; upstream-derived
  logo-full.svg + banner.png removed). Share-icon neighbor-audited.
- **Type**: Console Mono — Space Mono everywhere; wordmark `outpost_pi` 700.
- **Contract**: `.mockups/design-system/tokens.css` (dual-mode, 8pt, radii).
- **PNG pipeline**: Pillow 11 on the VM rasterizes the mark natively
  (rects/circles/lines + supersample + LANCZOS) — no external SVG converter
  needed; banner wordmark text wants Space Mono present at export time.

The original remediation checkpoints were the icon regeneration sweep
(app/cockpit/site PNGs, hash-verify ≠ upstream), app+cockpit theme replacement,
and site logo sync. Those checkpoints completed in v0.5.0. The 2026-08-26
revalidation below separates their realized state from the remaining public-
exposure regression and stale screenshot prose.

## Licensing verdict (adversarial review, 2026-08-15 — gpt-5.6-sol cross-model)

**Source repo: CLEAR to flip public** after in-line fixes (all landed + pushed):
LicenseRef-proprietary stale markers (rp-s3 Cargo.toml, cockpit rpm/metainfo) → MIT;
identity package TODO license → real MIT; Runner.rc "All rights reserved" → MIT notice.
Clean bills: upstream MIT attribution chain, icon pack (vscode-material-icon-theme
5.35.0, MIT, LICENSE bundled in cockpit/assets/file_icons/), fonts (OFL via
google_fonts, banner rasterization exempt), no GPL/AGPL/SSPL/NC deps in any
subproject (per-direct-dep verified). Remaining licensing work is
binary-distribution-gated, not flip-gated: .work/backlog/backlog-licensing-binary-notices.md
(LGPL libmpv/FFmpeg notices + MPL dbus for cockpit binaries; licenses screen in both apps).

## Realized repository path

The earlier fresh-repository recommendation was superseded by the operator's
executed 2026-08-15 path: targeted `git filter-repo` redaction, upstream-history
truncation to one MIT import root, and a force-push before making
`alluvial-lab/outpost_pi` public. `.work` intentionally remains public; local
session notes and the full operator runbook remain ignored. LICENSE and NOTICE
continue to preserve Jacob Moura/`remote_pi` provenance.

## Child stories (tracked in .work/active/stories/)

1. `story-brand-icon-regen-sweep` — Pillow rasterizer → every launcher/favicon/
   banner PNG + site SVGs; hash-verify ≠ upstream; drop stale screenshot.
2. `story-brand-theme-replacement` — app_colors.dart (byte-identical to
   upstream) + cockpit theme → Phosphor Beacon; Space Mono via google_fonts;
   drop vestigial font stanzas. Depends on 1.
3. `story-brand-site-sync` — tokens → Tailwind vars, logo/favicon, wordmark,
   README hero, screenshot retake. Depends on 1 (screenshot on 2).

## Brand cascade implementation complete — 2026-08-15

The branding half is implemented and locally verified:

- `story-brand-icon-regen-sweep` — `done` (`99876cc0`): all app/cockpit/site
  assets regenerated from Constellation III, 33/33 upstream hashes differ.
- `story-brand-theme-replacement` — `done` (`970d74a`): mobile/Cockpit dual-mode
  tokens + Space Mono landed; analyzers green, app 874-test serialized suite and
  Cockpit 280-test concurrency-2 suite green. The concurrency-2 app suite still
  exposes an unrelated pre-existing sync-test isolation failure documented in
  the child body; its isolated test is green.
- `story-brand-site-sync` — `done` (`c07fa20`): Tailwind/CSS dual-mode tokens,
  Space Mono, canonical inline marks, README reference, lint and 18-route build
  green.

Bounded deviations are recorded in the child items: banner PNG uses the
approved Noto Sans Mono fallback because Space Mono is not installed on the VM;
the themed phone screenshot and device visual smoke await device UAT because no
phone is attached.

**Historical lifecycle boundary:** the feature stayed at `drafting` after the
brand cascade because public exposure and device proof still required operator
action. The public flip subsequently executed in v0.5.0. The 2026-08-26 design
pass advances the feature for the narrower regression closure described below.

Parked by operator 2026-08-14: components mockup layer
(.mockups/design-system/components.css + showcase) — run before any
redesigned-screen mocks, not needed for the asset/theme cascade.


## Verification (all stories)

- Hash-compare regenerated icons against upstream raw files (must differ).
- `git grep -lE "192\.168\.50|100\.106\.7|dev-vm|tailscale"` on exported
  tree → only benign hits (site docs links), zero infra.
- App + cockpit build/analyze green; site lint+build green.

## Design-time revalidation — 2026-08-26

### Scope map and evidence

Direct-read only was sufficient: the feature is a realized remediation audit,
not a new subsystem, and the remaining unknowns were answerable from public Git
refs, current files, and the shipped v0.5.0 child evidence. No exploratory
fanout was used.

- **Icons/themes fixed:** all 44 current app/Cockpit platform icon candidates
  compare different from `upstream/main`; the mobile theme hash differs from
  upstream; 37 runtime references use the Phosphor Beacon values.
- **Site mark fixed:** `site/public/logo.svg` and `site/src/app/icon.svg` are
  byte-identical to `branding/logo-full-dark.svg`.
- **Typography fixed:** Schyler/Trajan searches are empty and Space Mono remains
  wired across app, Cockpit, and site.
- **Stale image removed:** `branding/screenshot-app.png` and source references
  are absent. One sentence in `site/src/app/cockpit/page.tsx` still claims a
  screenshot appears above it; that is the only residual brand inconsistency.
- **Public flip executed:** GitHub reports `alluvial-lab/outpost_pi` as PUBLIC;
  public history has one root commit, `2226812b` (`Import from remote_pi at
  d6be6a4 (MIT) — see LICENSE/NOTICE`); LICENSE/NOTICE attribution checks pass;
  `AGENTS.local.md` and `.work/session-notes/**` are ignored and untracked.
- **Exposure regression found:** the scrubbed pre-flip sensitive commits are
  reachable only from intentionally retained private local branches, but
  `origin/main` contains one post-flip commit (pre-rewrite hash withheld —
  its content carried the literal
  tailnet relay address and the current active story still carries it. The
  separately published `feat/app-theme-system` head has no known address hit.

### Existing completed children — do not re-work

1. `story-brand-icon-regen-sweep` — done; canonical generator and all platform
   icon exports landed.
2. `story-brand-theme-replacement` — done; app/Cockpit Phosphor Beacon and Space
   Mono landed.
3. `story-brand-site-sync` — done; site tokens and canonical marks landed; stale
   imagery was removed.
4. `story-public-flip-shred-runbook` — done; the initial public-ref scrub and
   public visibility transition executed.

## Design decisions

- **Repository remediation path:** keep the established public repository and
  perform a narrow second rewrite of a fresh public-origin mirror after the
  current-tree fix — recreating the repository would discard public metadata,
  while tree-only redaction leaves a reachable committed value.
- **Public work tracking:** keep `.work`, `.research`, protocol contracts, and
  public agent guidance tracked; sanitize content and reject only declared
  local/private paths. Their existence is not itself evidence of exposure.
- **Screenshot closure:** do not manufacture or restore a marketing screenshot
  without a real current capture. Remove the false copy now; a future current
  capture is additive marketing work, not required to prove upstream imagery is
  gone.
- **Private archive isolation:** scan and rewrite only refs obtained from a fresh
  mirror of public `origin`; never include the deliberately retained local
  pre-scrub branches in a push plan.
- **Review posture:** effective review weight is `standard` (caller default):
  exactly one balanced fresh-context feature review after implementation. A
  separate design-time advisory pass was skipped because the remediation path
  is constrained by the already-executed scrub and independently checkable Git
  evidence; unavailable design review does not block this pass.

## Architectural choice

Three approaches were considered:

1. **Fresh public repository snapshot.** This maximizes history isolation but
   now sacrifices the established public URL's issues, releases, watchers, and
   clone continuity. It fit the pre-flip decision point, not the current state.
2. **Current-tree redaction only.** This is least disruptive but fails the
   feature's history-exposure contract because the address remains reachable in
   `origin/main` ancestry and provides no prevention.
3. **Guarded tree cleanup plus a targeted public-origin rewrite (chosen).** Add
   a tested recurring guard, land all current-tree corrections, then rewrite
   only public heads/tags in a disposable mirror and verify a fresh clone. This
   addresses cause and residue while preserving repository identity and the MIT
   import root.

The trickiest unit is the public-history rescrub: it is destructive, changes
post-regression SHAs, interacts with branch protection/tags/open clones, and can
accidentally publish private archive refs. It is therefore last and explicitly
operator-gated.

## Implementation Units

### Unit 1: Close residual brand evidence honestly

**File**: `site/src/app/cockpit/page.tsx`
**Story**: `feature-public-flip-branding-and-exposure-brand-evidence-closure`

```tsx
// Keep the mesh explanation, but remove the sentence claiming a missing
// screenshot exists. No replacement image is imported without a real capture.
export default function CockpitPage() {
  // Existing page body; only the false screenshot sentence changes.
}
```

**Implementation Notes**:
- Make the one prose correction; do not touch completed app/Cockpit themes,
  regenerate icons, or restore upstream imagery.
- Re-run hash/content anchors as verification evidence.

**Acceptance Criteria**:
- [ ] No tracked stale screenshot or false screenshot reference remains.
- [ ] Existing canonical mark, theme, and typography evidence remains green.
- [ ] Site lint and production build pass.

---

### Unit 2: Current-tree redaction and regression guard

**Files**: `.work/active/stories/backlog-ext-broker-no-reconnect-after-boot-tailscale-rebind.md`, `scripts/check-public-exposure.sh`, `scripts/check-public-exposure.test.sh`, `.github/workflows/ci.yml`
**Story**: `feature-public-flip-branding-and-exposure-public-tree-guard`

```bash
scan_tracked_paths() { local repo_root="$1"; }
scan_tree() { local repo_root="$1"; }
scan_history() { local repo_root="$1" revision_scope="$2"; }
main() { : "${1:---tree}"; }
```

**Implementation Notes**:
- Replace the literal URL with a semantic tailnet relay placeholder without
  weakening the reconnect incident's technical diagnosis.
- The scanner rejects known operator network literals and tracked local-only
  paths, supports tree/branch-history/public-mirror modes, and emits bounded
  path/commit identifiers rather than incident content.
- CI runs scanner fixtures plus the current-tree guard unconditionally on push
  and PR; a subproject path filter would recreate the `.work` blind spot. The
  history story enables branch-ancestry CI only after the known hit is removed,
  avoiding a deliberately red intermediate pipeline.
- Fixture tests construct forbidden values at runtime so the guard does not
  match its own checked-in tests.

**Acceptance Criteria**:
- [ ] Current tracked tree and branch ancestry pass the new guard.
- [ ] Negative fixtures prove forbidden path, tree-content, and history-only
  failures; a clean fixture passes.
- [ ] Tree-mode CI covers root work/docs/scripts changes as well as
  subprojects without failing on the not-yet-rewritten historical commit.

---

### Unit 3: Public-origin history rescrub and operator verification

**Files**: `.work/active/stories/feature-public-flip-branding-and-exposure-history-rescrub.md` (execution/ref-map record), `.github/workflows/ci.yml`; reuses `scripts/check-public-exposure.sh`
**Story**: `feature-public-flip-branding-and-exposure-history-rescrub`

```bash
# Disposable mirror only; exact mutation remains operator-controlled.
git clone --mirror git@github.com:alluvial-lab/outpost_pi.git <temp-mirror>
git -C <temp-mirror> filter-repo --replace-text <local-rules> --force
scripts/check-public-exposure.sh --all-public-refs <temp-mirror>
```

**Implementation Notes**:
- Inventory public heads/tags before rewriting and preserve an old→new ref map.
- Replace only the post-flip literal; do not remove `.work`, change author
  identity, or alter LICENSE/NOTICE provenance.
- Verify the mirror before preparing a force-push packet. Enable history-mode
  CI only on the clean rewritten tip. The operator owns branch-protection
  changes, remote mutation, clone coordination, and cached-object disposition;
  then a fresh public clone must pass the same checks.

**Acceptance Criteria**:
- [ ] No private local ref appears in the mirror or push plan.
- [ ] All public heads/tags, the one import root, and MIT provenance survive.
- [ ] Rewritten mirror and post-push fresh clone have zero forbidden tree/history
  hits and pass `git fsck --full`; post-rewrite CI checks both tree and ancestry.
- [ ] Without recorded operator execution and post-push verification, the story
  and feature remain active.

## Implementation Order

1. In parallel: `feature-public-flip-branding-and-exposure-brand-evidence-closure`
   (after completed `story-brand-site-sync`) and
   `feature-public-flip-branding-and-exposure-public-tree-guard` (after completed
   `story-public-flip-shred-runbook`).
2. `feature-public-flip-branding-and-exposure-history-rescrub` after both
   current-tree checkpoints.
3. Parent feature verification and one standard fresh-context review.

## Simplification

- Reuse the completed v0.5.0 icon/theme/site work; no duplicate brand stories,
  token registries, generators, or screenshot placeholders.
- Keep public work/research/contract surfaces rather than maintaining a second
  public-tree manifest; one executable exposure guard owns the policy.
- Use one disposable public-origin rewrite instead of touching the development
  checkout or recreating the public repository.
- Remove false screenshot prose rather than adding an unverified visual asset.

## Testing

- **Brand interface evidence:** upstream hash comparisons and canonical SVG
  equality protect the public identity contract; site lint/build protects the
  edited marketing surface.
- **Exposure regression tests:** temporary Git fixtures prove guard exit behavior
  for tracked-path, tree-content, and history-only leaks without weakening the
  patterns to make CI green.
- **Public-history verification:** mirror scan, ref map, `git fsck --full`, root
  commit check, LICENSE/NOTICE checks, and a fresh post-push clone protect against
  accidental ref loss, private-ref publication, corruption, or provenance loss.
- **No redundant Flutter suites:** no app/Cockpit source changes are planned;
  their shipped theme tests and direct hash/content checks are the relevant
  evidence. Any implementation deviation into those subprojects restores their
  prescribed analyze/test commands.

## Risks

- **Riskiest assumption:** a second targeted rewrite is operationally acceptable
  for the current public consumers. It changes every descendant SHA after the
  regression and may require branch-protection, tag, PR, and clone coordination.
- **Failure condition:** a mirror accidentally includes private local refs, a
  force-push omits a public ref, or a current-tree commit lands after the mirror
  snapshot and reintroduces the value.
- **Fallback:** the guard/current-tree fix remains safe and shippable while the
  history story stays active; rebuild the disposable mirror from the latest
  public origin and do not mutate remote state until its ref map and checks pass.
- **Cached objects:** even a successful rewrite may leave old-SHA access in GitHub
  caches. The operator must record either a support purge request or explicit
  acceptance of the bounded, non-routable address-disclosure risk.
- **Guard scope:** patterns that are too broad create noisy false positives;
  patterns that are too narrow miss new private coordinates. Start with the
  confirmed operator subnets/local paths and expand only from verified evidence.

## Review closure (2026-08-26)

Standard one pass; no re-review. Receiver adjudication confirmed and this wave
fixed all three findings:

- **Blocker:** the merge-only and binary-blob history content-scan gap was fixed
  by enumerating unique reachable blobs and scanning their contents directly.
  Pre-fix break-it proofs showed the old guard passed both fixtures; the fixed
  suite now fails closed on both.
- **Important:** diagnostics now redact network-pattern matches in identifiers,
  including path components. The pre-fix filename fixture showed the literal in
  output; the fixed fixture proves the output remains bounded. The history-story
  pending prose and acceptance evidence were reconciled against its execution
  record, with the one unsupported product/brand-content check left honestly
  unchecked.
- **Coverage-policy comment:** the existing
  `idea-public-exposure-broader-network-policy` backlog item remains parked; no
  new item was created. Its examples use semantic range wording so the current
  guard's tree and history checks remain clean.
- **Verification:** 11 fixture assertions pass; `--tree` passes; `--history
  HEAD` passes in `real 19.42s` (`time -p`); and a fresh 38-ref mirror clone of
  public origin passes `--all-public-refs` and `git fsck --full`.

Feature stage is `done`.
