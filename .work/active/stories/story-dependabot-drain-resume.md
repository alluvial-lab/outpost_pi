---
id: story-dependabot-drain-resume
kind: story
stage: implementing
tags: [deps, ci, ops]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-14
updated: 2026-08-14
---

# Resume and finish the dependabot drain (blocked on Actions billing)

## Where this stands

Session of 2026-08-14 drained most of the dependabot queue, then hit a hard
blocker: **GitHub Actions minutes exhausted** ("The job was not started
because recent account payments have failed or your spending limit needs to
be increased"). Jobs that "fail" with zero executed steps + BlobNotFound logs
are billing failures, NOT code failures. Operator must buy minutes / raise
the spending limit before CI runs again.

## Already merged (16 PRs; all had green CI before minutes ran out)

actions: #1 upload-artifact v7, #2 download-artifact v8, #43 setup-java v5
relay: #13 thiserror 2.0.19, #18 tokio 1.53.1, #46 futures-util 0.3.34
rp-s3: #6 tokio 1.53.1, #8 tower-http 0.7.0 (major, passed fmt+clippy+test)
pi-extension: #10 vitest 4.1.10, #47 tsx 4.23.12, #51 typebox 1.3.12
protocol: #55 tsx 4.23.12
site: #21 react 19.2.8
app: #25 gpt_markdown 1.1.8, #29 image_picker 1.2.3
Plus: #41 dependabot.yml ignore rules (typescript majors in /site + /protocol,
app_settings majors in /app), #59 cockpit stateTurn test fix (un-blocked
cockpit analyze; was path-skipped on main and silently red — see below).

## Remaining open (verify against live `gh pr list` — dependabot rebases churn heads)

- Safe minors/patches, expect green, merge per-directory one at a time:
  #3 setup-node 4→7 (its earlier RED was the stale cockpit tree, not the bump),
  #10-recheck if reopened, #36 flutter_image_compress (rebased after conflict),
  #44 thiserror 2.0.20, #45 ws 8.21.3, #48 tailwindcss 4.3.3, #49 vite 8.2.1,
  #52 eslint-config-next 16.3.0, #53 next 16.3.0, #54 @noble/curves 2.3.0,
  #57 @noble/ciphers 2.3.0, #58 auto_injector 2.2.0, #28 shadcn 0.0.53,
  #42 checkout 4→7 (new), + any fresh ones dependabot opens (limit 5/dir).
- Majors to judge on fresh CI, then close+ignore if red: #9 rand 0.9 (relay),
  #12 sha2 0.11 (relay), #27 media_kit_video 2.0.1, #31 share_plus 12,
  #33 window_manager 0.5.2, #50 @types/node 26 (site), #56
  flutter_local_notifications 22.3.0 (KNOWN broken: v22 API requires
  settings/id named params in local_notifier.dart:27,36 +
  system_permissions_impl.dart:66,72 — mechanical 2-file migration if we
  ever want it). When closing majors, append ignore rules to
  .github/dependabot.yml (same pattern as #41) or they return weekly.

## Gotchas learned (do not relearn)

1. `gh` resolved PR numbers against upstream remote before; `gh.repo`
   default is now set + upstream remote removed — leave it that way.
2. Dependabot supersession: it closes old-version PRs and opens newer ones
   (e.g. #38→#53 next 16.3.0). PR numbers churn; always list live.
3. Path-filtered CI lanes SKIP untouched directories on main — a lane can
   be red on main invisibly (that's how the cockpit stateTurn break hid).
4. Billing failures look like: failing check with zero steps run and
   BlobNotFound logs. Check annotations before believing a "failure".
5. Merge one PR per directory at a time; lockfile conflicts go DIRTY →
   `@dependabot rebase` and move on to another directory meanwhile.
6. No branch protection (private repo): RED does not block merging, but
   don't merge past red without understanding it (rule 4 first).

## Finish line

- All remaining safe bumps merged, majors adjudicated (merge or close+ignore).
- Full main CI green including previously-skipped lanes.
- Consider the 6 open dependabot security alerts (5 moderate, 1 low) —
  https://github.com/alluvial-lab/outpost_pi/security/dependabot
