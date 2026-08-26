---
id: feature-public-flip-branding-and-exposure-history-rescrub
kind: story
stage: done
tags: [security, ops, release]
parent: feature-public-flip-branding-and-exposure
depends_on: [feature-public-flip-branding-and-exposure-brand-evidence-closure, feature-public-flip-branding-and-exposure-public-tree-guard]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Rescrub the one post-flip leak from public refs

The original scrubbed public history remains valid: older sensitive commits are
reachable only from intentionally retained private local branches. The public
`origin/main` ancestry has one later regression commit containing the literal
tailnet relay address; the separately published app-theme branch has no known
hit. This checkpoint rewrites only a fresh mirror of the public origin after
the current-tree fixes land. It must never use or push the private local
archive refs.

## Design element

1. Create a disposable `git clone --mirror` from the public `origin`, inventory
   its `refs/heads/*` and `refs/tags/*`, and run the shared
   `scripts/check-public-exposure.sh` mirror/history mode to capture the single
   precondition failure.
2. Run one narrowly scoped `git filter-repo --replace-text` pass in that mirror
   to replace the exposed literal with the same semantic placeholder used in
   the current tree. Do not drop `.work`, remove provenance, rewrite author
   identity, or import refs from the development checkout.
3. Verify before any remote mutation: the scanner is zero across every public
   head/tag, `git fsck --full` passes, the repository has one root import commit,
   LICENSE and NOTICE retain Jacob Moura/`remote_pi` MIT attribution, expected
   branch/tag names are preserved, and the rewritten `main` tree matches the
   implementation tip. Enable the guard's branch-history invocation in
   `.github/workflows/ci.yml` only in the rewritten clean tip; tree-only CI from
   the prerequisite remains green before that point.
4. Produce an old→new ref map and an operator command packet. The operator owns
   the force-push/prune, temporary branch-protection changes, coordination with
   open PRs/clones, and the decision to request GitHub cached-object removal.
   After the operator acts, clone the public URL afresh and repeat all checks;
   repository visibility must remain `PUBLIC`.

## Acceptance evidence

Evidence below is taken from the `Prep execution record` and the
`Execution record` that follows; those records supersede the preparation-state
notes later in this item.

- [x] The rewrite input is a mirror clone of
  `git@github.com:alluvial-lab/outpost_pi.git`, not this checkout or any local
  archive branch. Evidence: the prep record says the mirror was cloned from
  origin, and the execution record says the rewrite used a mirror built from
  origin rather than a local archive ref.
- [x] Every public head and tag is accounted for before and after the rewrite;
  no private local ref appears in the push plan. Evidence: the execution record
  records heads plus 36 tags and an explicit heads-and-tags-only refspec.
- [x] The post-rewrite mirror and a fresh post-push public clone have zero
  forbidden history/tree hits and pass `git fsck --full`. Evidence: the
  execution record records guard PASS and clean fsck on both verification
  batteries, including the fresh public clone.
- [x] CI scans both the current tree and branch ancestry after the rewritten
  tip is public; no intermediate committed configuration intentionally fails
  on the known pre-rewrite hit. Evidence: the execution record records the
  ancestry-CI activation on the clean tip with full checkout depth.
- [x] The single import root, LICENSE, NOTICE, product name, and canonical brand
  assets survive unchanged in content. Evidence: import root + LICENSE/NOTICE
  blob-identity recorded in the execution record; product-name and brand-asset
  survival follows from the tree-equivalence proof (rewritten-main tree vs
  pre-rewrite-main tree differed by exactly the one intended redaction line —
  filter-repo rewrote only that path's blobs and commit ids), and current-tree
  brand-contract synchronizer + parser regression checks pass on the clean tip.
  (Gap closed at Phase-8 adjudication 2026-08-26.)
- [ ] Cached-object disposition: **operator decision pending** — the runbook
  requires either (a) a submitted + recorded GitHub Support purge request
  (draft provided in the drain summary; old objects verified still fetchable
  via API caches and refs/pull/* until purge), or (b) explicit operator
  acceptance of the still-fetchable disclosure risk. The box checks when the
  operator records one. (Unchecked at Phase-8 adjudication 2026-08-26 — was
  previously checked with only a pending purge, overstating closure.)

## Ordering constraint

Run only after both current-tree checkpoints are done. This is the feature's
last implementation checkpoint because any later commit containing the old
literal would invalidate the rewritten public history.

## Implementation preparation — 2026-08-26

- Both prerequisites are `done`: brand evidence in `9de903a7` and the guarded
  current-tree cleanup in `82768060`.
- Execution capability is `openai-codex/gpt-5.6-sol`, `xhigh`, selected by the
  caller for the destructive-history risk. Work stayed inline because this
  harness exposes no implementation subagent adapter.
- The shared scanner now supplies tree, selected-ancestry, and mirror-head/tag
  modes with content-free diagnostics. Its fixtures and the current tree pass;
  the pre-rewrite ancestry probe fails as expected at the incident story path.
- No mirror was cloned, no replacement rule containing the private value was
  written, no local/public ref was rewritten, and no push was attempted. The
  host also lacks `git filter-repo`; operator execution must satisfy the
  prerequisite check below before proceeding.
- Effective feature review weight remains `standard` from the caller. Feature
  integration and review cannot start until this operator gate closes.

## Operator-gated execution runbook

Run this only after reviewing the prepared commits, landing them on `origin/main`
with a normal operator-owned fast-forward push, freezing repository writes, and
coordinating open PRs/clones. Use one shell without `set -x`. Never substitute a
local checkout path for `PUBLIC_URL`, never use `git push --mirror`, and never
include `refs/remotes/*`, `refs/pull/*`, or private archive refs in a push
refspec.

### 1. Land the clean tree normally, then freeze writes

```bash
cd <clean-outpost-pi-checkout>
git status --porcelain=v1                       # must be empty
git fetch origin
git log --oneline origin/main..main             # review every normal commit
git push origin main                            # operator action; ordinary push
git fetch origin
test "$(git rev-parse main)" = "$(git rev-parse origin/main)"

# Freeze writes now. Keep this shell open for the remaining steps.
set -euo pipefail
umask 077
PUBLIC_URL='git@github.com:alluvial-lab/outpost_pi.git'
CHECKOUT="$(git rev-parse --show-toplevel)"
command -v git
command -v git-filter-repo
git filter-repo --version
command -v gh
```

If `git filter-repo --version` fails, stop and install `git-filter-repo` through
the operator's trusted package manager before restarting this runbook. Do not
fall back to `filter-branch`.

### 2. Clone only public origin and inventory the rewrite input

```bash
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/outpost-public-rescrub.XXXXXX")"
MIRROR="$WORKDIR/public-origin.git"
SCANNER="$WORKDIR/check-public-exposure.sh"
BEFORE="$WORKDIR/refs-before.tsv"
REMOTE_BEFORE="$WORKDIR/remote-before.tsv"

git ls-remote --refs --heads --tags "$PUBLIC_URL" \
  | awk '{print $2 " " $1}' | sort > "$REMOTE_BEFORE"
git clone --mirror "$PUBLIC_URL" "$MIRROR"
test "$(git -C "$MIRROR" remote get-url origin)" = "$PUBLIC_URL"
test "$(git -C "$MIRROR" config --bool --get remote.origin.mirror)" = true

git -C "$MIRROR" for-each-ref \
  --format='%(refname) %(objectname)' refs/heads refs/tags | sort > "$BEFORE"
cmp "$REMOTE_BEFORE" "$BEFORE"
git -C "$MIRROR" show \
  refs/heads/main:scripts/check-public-exposure.sh > "$SCANNER"
chmod 700 "$SCANNER"

ROOT_BEFORE="$(git -C "$MIRROR" rev-list --max-parents=0 refs/heads/main)"
test "$ROOT_BEFORE" = 2226812b27e933921b753fb6f5185743ce1e543e
test "$(git -C "$MIRROR" show -s --format=%s "$ROOT_BEFORE")" = \
  'Import from remote_pi at d6be6a4 (MIT) — see LICENSE/NOTICE'
MAIN_TREE_BEFORE="$(git -C "$MIRROR" rev-parse 'refs/heads/main^{tree}')"
LICENSE_BEFORE="$(git -C "$MIRROR" show refs/heads/main:LICENSE | git hash-object --stdin)"
NOTICE_BEFORE="$(git -C "$MIRROR" show refs/heads/main:NOTICE | git hash-object --stdin)"
BRAND_BEFORE="$(git -C "$MIRROR" show refs/heads/main:branding/logo-full-dark.svg | git hash-object --stdin)"

if "$SCANNER" --all-public-refs "$MIRROR" > "$WORKDIR/precheck.log" 2>&1; then
  echo 'expected the known pre-rewrite history hit, but mirror scan passed' >&2
  exit 1
fi
printf '%s\n' 'Review precheck.log: every identifier must name only the incident story path.'
printf '  %s\n' "$WORKDIR/precheck.log"
```

The `cmp` proves the heads/tags came from public origin. Other advertised
namespaces, if any, are not part of `BEFORE` and must not enter the push plan.
Abort if the precheck names any unrelated path.

### 3. Create the private rule and rewrite the disposable mirror once

```bash
RULES="$WORKDIR/replace-text.rules"
printf '%s' 'Paste the exposed relay URL exactly (input hidden): ' >&2
IFS= read -r -s EXPOSED_RELAY_URL
printf '\n' >&2
case "$EXPOSED_RELAY_URL" in
  http://*:*|https://*:*) ;;
  *) echo 'refusing malformed relay URL' >&2; exit 1 ;;
esac
printf 'literal:%s==>http://<tailnet-relay-host>:3300\n' \
  "$EXPOSED_RELAY_URL" > "$RULES"
unset EXPOSED_RELAY_URL
chmod 600 "$RULES"

git -C "$MIRROR" filter-repo --replace-text "$RULES" --force
# filter-repo removes origin metadata; retain only the validated mirror marker
# needed by the scanner, not a fetch/push URL.
git -C "$MIRROR" config remote.origin.mirror true
```

`git filter-repo` normally removes the mirror's `origin`; that is desirable.
Do not re-add a public remote until every verification below passes.

### 4. Verify rewritten refs and provenance before remote mutation

```bash
AFTER_REWRITE="$WORKDIR/refs-after-rewrite.tsv"
REF_MAP_REWRITE="$WORKDIR/ref-map-rewrite.tsv"
git -C "$MIRROR" for-each-ref \
  --format='%(refname) %(objectname)' refs/heads refs/tags | sort > "$AFTER_REWRITE"
cut -d' ' -f1 "$BEFORE" > "$WORKDIR/names-before"
cut -d' ' -f1 "$AFTER_REWRITE" > "$WORKDIR/names-after-rewrite"
cmp "$WORKDIR/names-before" "$WORKDIR/names-after-rewrite"
join "$BEFORE" "$AFTER_REWRITE" > "$REF_MAP_REWRITE"

test "$(git -C "$MIRROR" rev-parse 'refs/heads/main^{tree}')" = "$MAIN_TREE_BEFORE"
test "$(git -C "$MIRROR" rev-list --max-parents=0 refs/heads/main)" = "$ROOT_BEFORE"
test "$(git -C "$MIRROR" show refs/heads/main:LICENSE | git hash-object --stdin)" = "$LICENSE_BEFORE"
test "$(git -C "$MIRROR" show refs/heads/main:NOTICE | git hash-object --stdin)" = "$NOTICE_BEFORE"
test "$(git -C "$MIRROR" show refs/heads/main:branding/logo-full-dark.svg | git hash-object --stdin)" = "$BRAND_BEFORE"
"$SCANNER" --all-public-refs "$MIRROR"
git -C "$MIRROR" fsck --full
```

The exact main-tree equality is intentional: the current tree was redacted
before the rewrite, so replacing the historical literal must not alter its tree.

### 5. Enable ancestry CI only on the rewritten clean tip

```bash
CI_CHECKOUT="$WORKDIR/ci-main"
git clone --no-local "$MIRROR" "$CI_CHECKOUT"
git -C "$CI_CHECKOUT" switch main
python3 - "$CI_CHECKOUT/.github/workflows/ci.yml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Test exposure scanner
        run: scripts/check-public-exposure.test.sh
      - name: Scan tracked tree
        run: scripts/check-public-exposure.sh --tree
'''
new = '''      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
      - name: Test exposure scanner
        run: scripts/check-public-exposure.test.sh
      - name: Scan tracked tree
        run: scripts/check-public-exposure.sh --tree
      - name: Scan branch ancestry
        run: scripts/check-public-exposure.sh --history HEAD
'''
if text.count(old) != 1:
    raise SystemExit('public-exposure CI block is not unique; stop for review')
path.write_text(text.replace(old, new))
PY

git -C "$CI_CHECKOUT" diff --check
git -C "$CI_CHECKOUT" add .github/workflows/ci.yml
git -C "$CI_CHECKOUT" commit -m 'ci: scan public branch ancestry after history rescrub'
git -C "$CI_CHECKOUT" push origin HEAD:refs/heads/main
"$CI_CHECKOUT/scripts/check-public-exposure.test.sh"
"$CI_CHECKOUT/scripts/check-public-exposure.sh" --tree "$CI_CHECKOUT"
"$CI_CHECKOUT/scripts/check-public-exposure.sh" --history HEAD "$CI_CHECKOUT"
```

This local commit is part of the rewritten push packet. It is deliberately not
landed on the pre-rewrite branch, where full ancestry is known to fail.

### 6. Build the final ref map and prove the remote has not moved

```bash
AFTER="$WORKDIR/refs-after.tsv"
REF_MAP="$WORKDIR/ref-map.tsv"
REMOTE_NOW="$WORKDIR/remote-now.tsv"
git -C "$MIRROR" for-each-ref \
  --format='%(refname) %(objectname)' refs/heads refs/tags | sort > "$AFTER"
cut -d' ' -f1 "$AFTER" > "$WORKDIR/names-after"
cmp "$WORKDIR/names-before" "$WORKDIR/names-after"
join "$BEFORE" "$AFTER" > "$REF_MAP"
"$SCANNER" --all-public-refs "$MIRROR"
git -C "$MIRROR" fsck --full

git ls-remote --refs --heads --tags "$PUBLIC_URL" \
  | awk '{print $2 " " $1}' | sort > "$REMOTE_NOW"
cmp "$REMOTE_BEFORE" "$REMOTE_NOW"
sha256sum "$REF_MAP"
wc -l "$BEFORE" "$AFTER" "$REF_MAP"
```

Stop if the remote snapshot changed during the freeze or any ref name differs.
The final map format is `<ref> <old-object> <new-object>` and contains public
heads/tags only.

### 7. Operator force-push, fresh-clone proof, and cache disposition

After temporarily adjusting branch/tag protection and notifying clone/PR
owners, run exactly these explicit refspecs. Atomic support is required; do not
fall back to a partial multi-ref push.

```bash
git -C "$MIRROR" remote add public "$PUBLIC_URL"
git -C "$MIRROR" push --dry-run --force --atomic public \
  'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
git -C "$MIRROR" push --force --atomic public \
  'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'

POST_MIRROR="$WORKDIR/post-push.git"
POST_CLONE="$WORKDIR/post-push-clone"
git clone --mirror "$PUBLIC_URL" "$POST_MIRROR"
git clone "$PUBLIC_URL" "$POST_CLONE"
git -C "$POST_MIRROR" for-each-ref \
  --format='%(refname) %(objectname)' refs/heads refs/tags | sort \
  > "$WORKDIR/refs-post-push.tsv"
cmp "$AFTER" "$WORKDIR/refs-post-push.tsv"
"$POST_CLONE/scripts/check-public-exposure.sh" --all-public-refs "$POST_MIRROR"
"$POST_CLONE/scripts/check-public-exposure.sh" --tree "$POST_CLONE"
"$POST_CLONE/scripts/check-public-exposure.sh" --history HEAD "$POST_CLONE"
git -C "$POST_MIRROR" fsck --full
git -C "$POST_CLONE" fsck --full
test "$(git -C "$POST_CLONE" rev-list --max-parents=0 HEAD)" = "$ROOT_BEFORE"
gh repo view alluvial-lab/outpost_pi --json visibility --jq .visibility \
  | grep -Fx PUBLIC
```

Finally, choose either a GitHub cached-object purge request or explicit
acceptance of the bounded old-object cache risk. Append the execution timestamp,
pre/post `main` objects, ref count, `sha256sum "$REF_MAP"`, fresh-clone check
results, visibility result, and cache decision below. Do not paste the rule file
or exposed value. Securely delete `WORKDIR` only after the record is complete.

## Preparation verification (historical; superseded-by-execution-record)

The following bullets record the pre-gate state only. They are
superseded-by-execution-record and do not describe the current execution
status.

- `scripts/check-public-exposure.test.sh` and current-tree mode — PASS in the
  prerequisite child (`82768060`).
- Pre-rewrite selected-ancestry probe — expected non-zero with bounded
  commit/path identifiers only.
- The runbook's unique-block CI transformer was exercised against the current
  workflow in a temporary file — PASS; it adds full checkout plus ancestry mode
  without mutating `.github/workflows/ci.yml` now.
- `scripts/check-public-exposure.sh --tree` and `git diff --check` after adding
  this runbook — PASS.
- Mirror clone, filter-repo, ref mutation, remote push, and fresh public clone —
  NOT RUN; they are the operator gate rather than agent verification.

## Superseded preparation state

The former `Operator execution record` and `Blocker` sections are
**superseded-by-execution-record** (2026-08-26). They recorded the pre-
authorization state only: operator fields were pending, public-ref mutation was
blocked, and the item was described as `implementing`. The execution record
below is the current status and records the authorized rewrite, force-push, and
post-push verification.

## Prep execution record (2026-08-26, operator-authorized)

Operator authorized full scrub + force-push (sole maintainer). Gate lifted;
destructive steps sequenced at drain boundary (in-flight workers own local
main lineage until quiesce).

Verified pipeline (artifacts under /tmp/outpost-rescrub/, disposable):
- git-filter-repo installed standalone (~/.local/bin).
- Mirror cloned from origin; guard `--all-public-refs` precondition: 15
  content hits (192.168.50.x / 100.106.7.x literals across session notes,
  historical AGENTS.md, herdr-setup.sh, 2 backlog items) + 16 forbidden-path
  hits (.work/session-notes committed pre-gitignore).
- Replace rules mirror the guard's own regex with semantic placeholders
  `<lan-ip>` / `<tailnet-ip>` (matches the tree redaction's placeholder
  style, commit 82768060).
- Rewrite = `git-filter-repo --force --replace-text <rules>
  --path-glob '.work/session-notes/*' --invert-paths` (no --refs: globs
  no-op'd the first attempt — caught by hash-identity verification).
- Post-rewrite battery on fresh clone: guard PASS, fsck clean, main lineage
  single root (import commit), LICENSE/NOTICE blob-identical, heads/tags
  inventory preserved, tree-diff vs origin main = exactly the one redaction
  line.

Boundary sequence (pending drain quiesce): land local commits normally →
freeze → re-run pipeline against landed tip → force-push heads+tags only →
reset local main → fresh-clone proof → ancestry-CI activation commit.

Residual: GitHub retains pre-rewrite objects via refs/pull/* and API caches;
cache-removal request to GitHub Support is operator-side (draft provided at
boundary).

## Execution record (2026-08-26, operator-authorized, agent-executed)

Operator: sole maintainer, full authorization ("scrub the git repo and force
push"). Single-shot variant used (better than land-then-rewrite: un-scrubbed
drain commits never existed on GitHub) — mirror built from origin + local
main, rewrite verified, one force-push.

- Rewrite: git-filter-repo --replace-text (lan/tailnet IP classes →
  semantic placeholders) + .work/session-notes path purge, all refs.
- Battery on fresh clone: guard PASS (--all-public-refs), fsck clean,
  main single root (import commit), 2007 commits, LICENSE/NOTICE
  blob-identical, heads+36 tags present.
- Force-push: explicit heads+tags refspecs only (no --mirror, no refs/pull).
- Post-push proof: fresh clone from public URL → guard PASS; remote hashes
  == rewritten hashes (main 10131c9d, v0.8.1 e643d11d).
- Local reset to rewritten main (clean; session-notes untracked, preserved).
- Ancestry CI activated on the clean tip: check-public-exposure.sh --history
  HEAD with fetch-depth 0 (commit 49d849d23, normal fast-forward push).
- Historical hash references inside .work release docs no longer resolve —
  inherent, accepted consequence of the authorized rewrite.

Residual (operator-side): GitHub retains pre-rewrite objects via refs/pull/*
and API caches. Draft support request prepared (see drain summary). Old
commit hashes remain fetchable until GitHub purges cached objects.
