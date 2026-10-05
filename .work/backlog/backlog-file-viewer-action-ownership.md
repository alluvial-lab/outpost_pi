---
id: backlog-file-viewer-action-ownership
created: 2026-10-05
updated: 2026-10-05
tags: [cockpit, workflow]
---

# Own file-viewer save/format actions across invocation surfaces

Cockpit file-viewer `_save()`/`_format()` asynchronous actions need one owned rejection boundary whether invoked via keyboard shortcut (VoidCallback slot) or toolbar (owned rejection-observing adapter), with focus restoration preserved and both entry-point tests kept distinct. Folded from two gate-refactor lifecycle findings.

Consolidated 2026-10-05 by operator-confirmed groom merge from: gate-refactor-lifecycle-file-viewer-shortcut-promise, gate-refactor-lifecycle-file-viewer-toolbar-promise.
Scope-promote via /agile-workflow:scope when wanted.
