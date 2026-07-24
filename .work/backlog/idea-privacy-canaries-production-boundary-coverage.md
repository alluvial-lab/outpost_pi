---
id: idea-privacy-canaries-production-boundary-coverage
kind: idea
stage: backlog
tags: [testing, security, app, cockpit]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-07-23
---

# Strengthen privacy canaries to exercise production capture boundaries

Parked from the `standard`-weight cross-model review of
`feature-diagnostic-privacy-hardening` (2026-07-23, Important — below blocker
bar). Three canaries assert the content-free helper/projection but do not drive
the production branch that emits it, so reverting the production call site to
raw logging would keep the test green:

1. `cockpit/test/ui/file_viewer_session_test.dart:15` tests only
   `fileViewerReloadFailureDiagnostic`; the catch at
   `cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:390` could revert to
   `$e\n$st` unnoticed. Needs a widget-level failed-reload drive.
2. `app/test/data/debug/debug_capture_routing_test.dart:795-813` injects a
   verbose session-sync error but asserts only event keys; restoring `$err` at
   `app/lib/data/sync/sync_service.dart:635` stays green. Needs a console
   capture assertion.
3. `cockpit/test/data/lsp_client_impl_test.dart:17-72` covers stderr lines but
   never triggers the stream `onError` branch at
   `cockpit/lib/app/core/data/lsp/lsp_client_impl.dart:344`. Needs a
   stream-error injection.

Risk rationale (why parked): all three production call sites are currently
fixed strings with no interpolation — the exposure requires a future edit to
RE-introduce interpolation, and the feature's other canaries (app wire→diagnostic,
resend-failure console, LSP subprocess, legacy-egress) already cover the
shared pattern. These are defense-in-depth gaps on individual branches, not
present exposures.
