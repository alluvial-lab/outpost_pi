---
id: story-dependabot-drain-resume
kind: story
stage: done
tags: [deps, ci, ops]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-14
updated: 2026-08-15
---

# Resume and finish the dependabot drain

## Outcome

The post-history-rewrite queue is drained: `gh pr list --state open` returned
no open PRs after every stale Dependabot branch was recreated from the current
`main`. Twenty-five PRs were merged after all checks on their fresh heads
completed with `success` or `skipped`; four incompatible/deferred PRs were
closed with explanatory comments.

The full CI matrix passed on the recreated actions PR, including the lanes that
path filtering normally skips. Every later dependency PR also passed its bumped
directory's relevant lane before merge. One duplicate app run on #3 exposed two
load-sensitive history-replay test failures; its required one-time rerun passed.

## Merged in the final drain (25)

- actions: #3 `actions/setup-node` 4→7; #42 `actions/checkout` 4→7.
- relay: #12 `sha2` 0.10.9→0.11.0; #44 `thiserror` 2.0.18→2.0.20;
  #60 `tokio-tungstenite` 0.29.0→0.30.0; #61 `serde` 1.0.228→1.0.229.
- pi-extension: #10 `vitest` 4.1.9→4.1.10; #45 `ws` 8.21.0→8.21.3;
  #49 `vite` 8.0.16→8.2.1; #62 `@types/node` 25.9.4→26.2.0;
  #63 `@noble/ciphers` 2.2.0→2.3.0.
- protocol: #54 `@noble/curves` 2.2.0→2.3.0; #57 `@noble/ciphers`
  2.2.0→2.3.0.
- site: #48 `tailwindcss` 4.3.0→4.3.3; #50 `@types/node`
  20.19.41→26.2.0; #52 `eslint-config-next` 16.2.11→16.3.0; #53 `next`
  16.2.11→16.3.0; #64 `@tailwindcss/postcss` 4.3.0→4.3.3.
- app: #36 `flutter_image_compress` 2.4.0→2.5.1; #58 `auto_injector`
  2.1.1→2.2.0; #66 `path_provider_platform_interface` 2.1.2→2.1.3;
  #67 `package_info_plus` 8.3.1→9.0.1.
- cockpit: #27 `media_kit_video` 1.3.1→2.0.1; #33 `window_manager`
  0.4.3→0.5.2; #65 `google_fonts` 6.3.3→8.2.1.

## Closed in the final drain (4)

- #9 `rand` 0.8.6→0.9.4: both fresh relay runs failed clippy because 0.9
  deprecates three `thread_rng` call sites. The major is ignored until that
  source migration is undertaken.
- #28 `shadcn_flutter` 0.0.52→0.0.53: both fresh cockpit runs failed analyze
  with 22 removed `showDialog`/`showPopover` APIs. Although semver-patch, the
  pre-1.0 release is source-breaking; exact version 0.0.53 is ignored while
  later releases remain eligible for testing.
- #31 `share_plus` 10.1.4→12.0.2: both fresh app runs failed analyze because
  `Share.shareXFiles` is deprecated in favor of `SharePlus.instance.share()`.
  The major is ignored until the settings sharing call is migrated.
- #56 `flutter_local_notifications` 18.0.1→22.3.0: the existing major-ignore
  config did not auto-close the stale PR within 15 minutes, so it was closed
  manually with a comment referencing the ignore rule and deferred v22 API
  migration.

## Security alerts

The public-repository Dependabot alerts API succeeded. The drain reduced the
open set from six to one; API state at completion was **1 open / 31 fixed**.
The remaining alert is #43, medium severity, `hono <4.12.34`: “Hono: ReDoS in
CORS middleware via Access-Control-Request-Headers.” No open dependency PR
remained for it.

## Deviations and repairs

- The first recreated actions PR ran every lane and exposed an unrelated
  `prefer_initializing_formals` cockpit lint on the rewritten `main`. The
  command value constructors were routed through one private initializing
  constructor, verified with cockpit analyze/tests, and committed as
  `93a50627` before #3 was recreated again.
- #3's unrelated app test failure was rerun once under the approved red-analysis
  rule; the rerun passed, and every exact-head check was green before merge.
- #28 was initially classified as a safe patch, but fresh relevant CI proved it
  source-breaking. It was closed rather than merged past red, and the exact
  broken version was ignored to prevent the same weekly loop.
- #56 required manual closure after the requested 15-minute config-sync window.

## Prior drain work (completed before the resume)

Green merges already completed in the first session were: actions #1, #2, #43;
relay #13, #18, #46; rp-s3 #6, #8; pi-extension #47, #51; protocol #55; site
#21; app #25, #29. Supporting changes were #41 (initial ignore rules) and #59
(cockpit `stateTurn` test repair). #10 was recreated and merged again after the
history rewrite.

## Operational gotchas retained

1. Resolve PRs against `alluvial-lab/outpost_pi`; `gh.repo` is set and the old
   upstream remote remains removed.
2. Dependabot may supersede an old-version PR with a new PR number. Always list
   the live queue rather than relying on a saved number set.
3. Path-filtered CI skips untouched directories, so use an actions/workflow
   change or the combined fresh relevant-lane evidence when validating all
   surfaces.
4. Billing failures are recognizable as zero executed steps plus BlobNotFound
   logs. They are infrastructure failures, not code failures.
5. Merge one PR per dependency directory at a time. A same-directory merge
   makes sibling lockfile PRs stale or DIRTY; comment `@dependabot recreate`
   because `rebase-strategy: "disabled"` makes `@dependabot rebase` inert.
6. Before merge, inspect the exact head SHA's check runs. A real failure in the
   bumped directory blocks the merge; rerun an unrelated or apparently stale
   failure once before adjudicating it.
