---
id: backlog-cockpit-file-watch-reliability
kind: story
stage: drafting
tags: [cockpit, lifecycle]
parent: null
depends_on: []
release_binding: null
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
