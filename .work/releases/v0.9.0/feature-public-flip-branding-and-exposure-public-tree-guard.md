---
id: feature-public-flip-branding-and-exposure-public-tree-guard
kind: story
stage: done
tags: [security, ops, release]
parent: feature-public-flip-branding-and-exposure
depends_on: [story-public-flip-shred-runbook]
release_binding: v0.9.0
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

- [x] The current tracked tree has zero known operator LAN/tailnet literal
  address hits and zero tracked local-only paths.
- [x] The scanner exits non-zero for each generated negative fixture, exits
  zero for the clean fixture, and reports bounded path/commit identifiers only.
- [x] CI invokes the current-tree guard on `.work`, docs, scripts, and all
  subprojects for every push and pull request.
- [x] `bash -n scripts/check-public-exposure.sh scripts/check-public-exposure.test.sh`,
  the test script, and the tree scanner against the repository all pass.
- [x] `git diff --check` passes.

## Ordering constraint

The completed `story-public-flip-shred-runbook` is the policy baseline. Finish
this current-tree cleanup and prevention checkpoint before rewriting public
history, otherwise the replacement commit would immediately reintroduce the
same value.

## Implementation run

- Executed inline in the host because this harness exposes no implementation
  subagent adapter. The story's four-file product/policy write set stayed
  isolated from concurrent app, relay, extension, and substrate work.
- Worker capability: `openai-codex/gpt-5.6-sol`, `xhigh`, caller-selected for
  security/exposure remediation with public-history implications.

## Implementation notes

- Replaced the relay coordinate in the incident record with a semantic tailnet
  relay placeholder while preserving the transport-loss diagnosis.
- Added one content-free scanner policy in `scripts/check-public-exposure.sh`.
  Tree mode checks tracked working content and declared local-only paths;
  history mode checks path changes, blob-line changes, and commit messages for
  a selected ancestry; public-ref mode refuses non-mirror checkouts and scans
  only mirror heads and tags.
- Added runtime-constructed Git fixtures for clean tree/history, forbidden
  path, current-tree content, history-only content, and public-mirror failure.
  Negative assertions also prove the rejected content is absent from scanner
  diagnostics.
- Added an unconditional CI job for fixture tests plus tree mode. Ancestry mode
  remains intentionally disabled until the operator-gated rescrub removes the
  known precondition failure; this avoids installing a knowingly red pipeline.

## Verification evidence

- `bash -n scripts/check-public-exposure.sh scripts/check-public-exposure.test.sh`
  — PASS.
- `scripts/check-public-exposure.test.sh` — PASS across clean and negative Git
  fixtures, including mirror-only mode.
- `scripts/check-public-exposure.sh --tree` after staging every owned file —
  PASS, proving the guard also accepts its own checked-in implementation.
- Pre-rewrite `--history HEAD` probe — expected non-zero with content-free
  commit/path identifiers only; confirms the final checkpoint still has real
  work and CI history mode must wait.
- `.github/workflows/ci.yml` — exposure job has no path-filter dependency and
  therefore covers root work/docs/scripts changes and every subproject.
- `git diff --check` for the owned change set — PASS.
