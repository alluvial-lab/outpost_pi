---
id: feature-public-flip-branding-and-exposure-history-rescrub
kind: story
stage: implementing
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

- [ ] The rewrite input is a mirror clone of
  `git@github.com:alluvial-lab/outpost_pi.git`, not this checkout or any local
  archive branch.
- [ ] Every public head and tag is accounted for before and after the rewrite;
  no private local ref appears in the push plan.
- [ ] The post-rewrite mirror and a fresh post-push public clone have zero
  forbidden history/tree hits and pass `git fsck --full`.
- [ ] CI scans both the current tree and branch ancestry after the rewritten
  tip is public; no intermediate committed configuration intentionally fails
  on the known pre-rewrite hit.
- [ ] The single import root, LICENSE, NOTICE, product name, and canonical brand
  assets survive unchanged in content.
- [ ] The operator records the force-push/public-clone verification and the
  cached-object disposition in this item body. Without that operator action,
  this checkpoint and its parent feature remain active.

## Ordering constraint

Run only after both current-tree checkpoints are done. This is the feature's
last implementation checkpoint because any later commit containing the old
literal would invalidate the rewritten public history.
