---
id: feature-public-flip-branding-and-exposure-public-tree-guard
kind: story
stage: implementing
tags: [security, ops, release]
parent: feature-public-flip-branding-and-exposure
depends_on: [story-public-flip-shred-runbook]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Redact the post-flip exposure regression and add a public-tree guard

The 2026-08-15 scrub succeeded for the public refs that existed then, but a
later work item committed the operator's literal tailnet relay address to
`origin/main`. Public work tracking remains allowed; incident-specific network
coordinates do not. This checkpoint cleans the current tree and adds the guard
that the first scrub lacked.

## Design element

- Replace the literal relay URL in
  `.work/active/stories/backlog-ext-broker-no-reconnect-after-boot-tailscale-rebind.md`
  with a semantic placeholder while retaining the transport-loss diagnosis.
- Add `scripts/check-public-exposure.sh`, with explicit
  `scan_tracked_paths(repo_root)`, `scan_tree(repo_root)`, and
  `scan_history(repo_root, revision_scope)` functions. The default checks the
  tracked tree; `--history` scans the selected branch ancestry; a mirror mode
  scans all public heads and tags. Fail closed with file/commit locations but
  never print surrounding incident content.
- Reject tracked local-only paths (`AGENTS.local.md`,
  `.work/session-notes/**`, `.env*`, key/PEM files) and the known operator LAN
  and tailnet literal-address patterns. Keep ordinary public examples and
  benign Tailscale documentation allowed.
- Add `scripts/check-public-exposure.test.sh`. Build temporary Git repositories
  at runtime and prove clean-tree success plus failures for a forbidden path,
  a current-tree address, and an address introduced only in history. Construct
  fixture values from fragments so the test source does not itself contain a
  forbidden literal.
- Add an unconditional `public-exposure` job to `.github/workflows/ci.yml`.
  Run the scanner tests and current-tree scan on every push and pull request;
  do not hide it behind the subproject path filter. The dependent history-
  rescrub checkpoint enables the branch-history invocation only after the
  known historical hit is removed, so this checkpoint does not deliberately
  land a permanently red CI job.

## Acceptance evidence

- [ ] The current tracked tree has zero known operator LAN/tailnet literal
  address hits and zero tracked local-only paths.
- [ ] The scanner exits non-zero for each generated negative fixture, exits
  zero for the clean fixture, and reports bounded path/commit identifiers only.
- [ ] CI invokes the current-tree guard on `.work`, docs, scripts, and all
  subprojects for every push and pull request.
- [ ] `bash -n scripts/check-public-exposure.sh scripts/check-public-exposure.test.sh`,
  the test script, and the tree scanner against the repository all pass.
- [ ] `git diff --check` passes.

## Ordering constraint

The completed `story-public-flip-shred-runbook` is the policy baseline. Finish
this current-tree cleanup and prevention checkpoint before rewriting public
history, otherwise the replacement commit would immediately reintroduce the
same value.
