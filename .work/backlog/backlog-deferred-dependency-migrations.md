---
id: backlog-deferred-dependency-migrations
created: 2026-08-15
updated: 2026-08-15
tags: [deps, pi-extension, relay, app]
---

# Deferred dependency migrations (evidence recorded during the 2026-08-15 drain)

Dependabot majors closed as incompatible during the post-flip drain, with the
failing evidence + bounded ignore rules landed (commit 61cec4e). Each line
needs a real code migration before the ignore rule comes off:

1. **pi-coding-agent SDK 0.80.7–0.84.x** (pi-extension; PRs #77 #89 #96–#100) —
   upstream SDK removed `AuthStorage`, `ModelRegistry.create`, changed the
   `pi-ai` OAuth export surface. Biggest item: our extension is pinned to an
   aging SDK; a deliberate upgrade story (not a bump). Check upstream release
   notes per minor when taking this on.
2. **axum 0.8** (relay; #73) — WebSocket `Utf8Bytes` type migration in the
   WS routing layer.
3. **rand 0.9** (relay; #9) — `thread_rng` call sites deprecated; mechanical.
4. **shadcn_flutter 0.0.53** (cockpit; #28) — removes 22 dialog/popover APIs;
   audit call sites before bumping.
5. **share_plus 12** (app; #31) — `SharePlus.instance.share()` API migration.
6. **flutter_secure_storage 10** (app; #84) — `AppleOptions` migration.
7. **ed25519-dalek 3** (relay? #72) — `CryptoRng` bounds incompatibility.
8. **flutter_local_notifications 22** (cockpit; ignore rule) — v22 named-params
   API in local_notifier.dart:27,36 + system_permissions_impl.dart:66,72.

State after drain: 0 open PRs, 0 open dependabot alerts (35 fixed), main green.
