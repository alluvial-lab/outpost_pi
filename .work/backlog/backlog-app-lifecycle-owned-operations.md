---
id: backlog-app-lifecycle-owned-operations
created: 2026-07-23
updated: 2026-07-23
tags: [app, lifecycle]
---

# App lifecycle-owned operations (merged from 4 findings)

Merged by groom 2026-07-23 (cluster F5). All are app-side detached Futures
("discards the Future" fire-and-forget). One feature could establish the
shared generation/error/single-flight ownership policy. Absorbed item bodies
retained in `.work/archive/`.

1. **Periodic mesh poll discards `pullOnDemand()`** — `app/lib/data/mesh/mesh_sync_service.dart:545`.
2. **Foreground-resume mesh pull future unowned** — `app/lib/main.dart:100`.
3. **`reconcileOnAppResume()` discarded across lifecycle transitions** — `app/lib/main.dart:102`.
4. **Fallback `ConnectionManager.boot()` discarded after peer revocation** — `app/lib/ui/settings/viewmodels/settings_viewmodel.dart:126`.

Absorbed: `gate-refactor-lifecycle-mesh-poll-floating`,
`gate-refactor-lifecycle-resume-mesh-pull-floating`,
`gate-refactor-lifecycle-resume-reconcile-floating`,
`gate-refactor-lifecycle-settings-fallback-boot-floating`.
