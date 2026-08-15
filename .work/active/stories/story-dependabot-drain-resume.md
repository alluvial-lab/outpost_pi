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
`main`. Forty-six PRs were merged after all checks on their fresh heads
completed with `success` or `skipped`; fourteen incompatible/deferred/no-op PRs
were closed with explanatory comments. This includes the additional PRs
#68–98 opened by completion-time Dependabot config syncs as directory limits
freed.

The full CI matrix passed on the recreated actions PR, including the lanes that
path filtering normally skips. Every later dependency PR also passed its bumped
directory's relevant lane before merge. One duplicate app run on #3 exposed two
load-sensitive history-replay test failures; its required one-time rerun passed.

## Merged from the original resume queue (25)

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

## Closed from the original resume queue (4)

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

## Merged from the config-sync follow-on queue (16)

- relay: #68 `base64` 0.22.1→0.23.1; #69 `anyhow` 1.0.102→1.0.104;
  #70 `rusqlite` 0.32.1→0.40.2.
- pi-extension: #71 `@noble/curves` 2.2.0→2.3.0; #74 `typebox`
  1.3.12→1.3.13; #75 `typescript` 6.0.3→7.0.2; #78
  `@modelcontextprotocol/sdk` 1.29.0→1.30.0.
- site: #76 `react-dom` 19.2.6→19.2.8 and `@types/react-dom`
  19.2.3→19.2.4.
- app: #79 `path_provider` 2.1.5→2.1.6; #80 `lucide_icons_flutter`
  3.1.14+2→3.1.15; #82 `mobile_scanner` 5.2.3→7.4.0; #85 `dio`
  5.9.2→5.11.0.
- cockpit: #81 `desktop_drop` 0.5.0→0.7.1; #83 `xterm` git ref
  `6ef92b9`→published 4.0.0; #86 `package_info_plus` 8.3.1→9.0.1;
  #87 `pasteboard` 0.4.0→0.5.0.

## Closed from the config-sync follow-on queue (4)

- #72 `ed25519-dalek` 2.2.0→3.0.0: both relay runs failed tests because the
  existing `rand::ThreadRng` no longer satisfies the v3 `CryptoRng` bound in
  shared and forwarding/rooms key generation.
- #73 `axum` 0.7.9→0.8.9: both relay runs failed clippy across the WebSocket
  adapters because axum 0.8 changes text frames from `String` to `Utf8Bytes`
  and exposes incompatible axum/tungstenite byte types.
- #77 `@earendil-works/pi-coding-agent` 0.80.6→0.84.1: both pi-extension runs
  failed typecheck because 0.84.1 removes `AuthStorage` and
  `ModelRegistry.create`. Exact version 0.84.1 is ignored.
- #84 `flutter_secure_storage` 9.2.4→10.3.1: both app runs failed analyze with
  61 invalid storage overrides because v10 replaces iOS/macOS option types with
  `AppleOptions` across production and test-fixture APIs.

## Merged from the final config-sync queue (5)

- relay: #88 `hyper` 1.9.0→1.11.0; #90 `rand` 0.8.6→0.8.7; #91
  `serde_json` 1.0.149→1.0.151.
- app: #94 `google_fonts` 6.3.3→8.2.1; #95 `go_router` 14.8.1→17.5.0.

## Closed from the final config-sync queue (6)

- #89 `@earendil-works/pi-coding-agent` 0.80.6→0.84.0: the same fresh
  typecheck failures as #77 proved the incompatible API removal covers the
  0.84.x line, which is now ignored as a range.
- #92 grouped `flutter_secure_storage` 11, `package_info_plus`, and `share_plus`
  update: both app runs reproduced the 61 `AppleOptions` migration failures;
  all `flutter_secure_storage` majors are now deferred rather than only v10.
- #93 `xterm` git ref→4.0.0: closed as a zero-file no-op because Cockpit already
  declares 4.0.0 while intentionally resolving its block-glyph fork through a
  git override. Exact suggestion 4.0.0 is ignored while later versions remain
  eligible.
- #96 `@earendil-works/pi-coding-agent` 0.80.6→0.83.0: both pi-extension runs
  reproduced the #77/#89 API-removal failures.
- #97 `@earendil-works/pi-coding-agent` 0.80.6→0.82.1 and #98 0.80.6→0.81.1:
  both pairs of pi-extension runs reproduced the same failures, expanding the
  deferred range to the complete 0.81.x–0.84.x set.

## Security alerts

The public-repository Dependabot alerts API succeeded. The drain reduced the
open set from six to zero; API state at completion was **0 open / 35 fixed**.
The final medium-severity `hono <4.12.34` ReDoS alert (#43) changed to fixed
after the follow-on pi-extension dependency merges.

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
- Completion-time config syncs opened #68–98 as directory limits freed. The
  drain continued through every follow-on wave; incompatible releases gained
  bounded ignore rules before the final completion commit.

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
