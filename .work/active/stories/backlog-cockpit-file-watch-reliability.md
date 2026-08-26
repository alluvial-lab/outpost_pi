---
id: backlog-cockpit-file-watch-reliability
kind: story
stage: done
tags: [cockpit, lifecycle]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-07-23
updated: 2026-08-26
---

# Cockpit file-watch reliability (merged from 3 findings)

Merged by groom 2026-07-23 (cluster F4). One surface — cockpit file-watch/LSP
async work is unobserved and unowned. Absorbed item bodies retained in
`.work/archive/`.

1. **File-watcher failures swallowed** — empty error handler discards every
   file-watch failure — `cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart:457`.
2. **File-watch reload debounce unowned** — reload has no explicit async
   ownership boundary — `cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart:445`.
3. **File-viewer LSP debounce unowned** — discarded debounce future;
   unexpected async LSP failure is unobserved — `cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:240`.

Absorbed: `gate-cruft-file-watcher-errors-swallowed`,
`gate-refactor-lifecycle-workspace-file-watch-debounce-floating`,
`gate-refactor-lifecycle-file-viewer-lsp-debounce-floating`.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-luna` xhigh, inline; bounded
  cockpit lifecycle work with direct ownership and verification.
- Review weight: standard (source: default).
- Files changed: `cockpit/lib/app/cockpit/data/filesystem/file_reader_impl.dart`,
  `cockpit/lib/app/cockpit/domain/contracts/file_reader.dart`,
  `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`,
  `cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart`,
  `cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart`, and
  `cockpit/test/ui/workspace_projection_test.dart`.
- Tests added: projection coverage now asserts watcher-stream failures and
  reload failures reach the owner; the existing watcher debounce/disposal
  coverage remains in place.
- Simplification: watcher reload now has one owned async method, and LSP
  debounce cancellation is centralized for edit, retarget, and dispose paths.
- Discrepancies from design: failures are surfaced through the existing
  Cockpit recovery banner via a required projection-owner callback; no new UI
  surface or storage change was introduced.
- Adjacent issues parked: none.

## Review

- Verdict: pass — bounded inline standalone-story review.
- Watch stream errors and synchronous watch setup failures reach the required
  projection-owner callback; reload read failures are also surfaced instead of
  being discarded.
- File-watch reload futures are explicitly owned with `ownAsync`, stale paths
  are rejected, and debounce timers are canceled when watchers are replaced or
  tabs close.
- LSP debounce futures are explicitly owned with `ownAsync`; the timer is
  canceled on edits, viewer retargets, and disposal, with path/text captured
  for the intended document update.
- Verification: `flutter analyze && flutter test` passed from `cockpit/` (288
  tests).
