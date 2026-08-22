---
id: idea-app-sync-service-suite-flakes
created: 2026-08-22
updated: 2026-08-22
tags: [app, testing]
---

# Stabilize sync-service assertions under the full Flutter suite

During reconnect-churn verification, two consecutive
`flutter test --exclude-tags e2e --concurrency=2` runs failed different
`app/test/data/sync/sync_service_test.dart` assertions while the complete file
passed immediately with `--concurrency=1` (96/96). The first full run failed
session-index assertions in `two session ids on the same room use different
boxes and index keys` and `foreign session_history is dropped before rows or
index mutate`; the second failed `server error clears pending chunk flush so
chat does not stay working` because the awaited runtime projection was still
null. This points to load-sensitive async/test isolation rather than one stable
product failure. Preserve the behavioral assertions; replace elapsed-time
settling with explicit completion barriers or otherwise isolate shared Hive
state without weakening coverage.
