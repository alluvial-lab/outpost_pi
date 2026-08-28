---
id: backlog-deferred-dependency-migrations
created: 2026-08-15
updated: 2026-08-28
tags: [deps, pi-extension, relay, app]
---

# Deferred dependency migrations (evidence recorded during the 2026-08-15 drain)

Updated 2026-08-28 after the v0.10.0 stack program + pertinence sweep:
two majors below were absorbed by the program and are no longer deferred
(kept as record with pointers). The remainder still need real code
migrations before the ignore rule comes off.

1. **pi-coding-agent SDK 0.80.7–0.84.x** — **ABSORBED 2026-08-27** by the
   stack program: `story-upgrade-pi-sdk-and-node-floor` landed 0.84.3 with
   the full adapter migration (AuthStorage/`ModelRegistry.create` removal,
   async `ModelRuntime`+`refresh()`, `session_compact_failed` convergence,
   abort-before-replacement, scoped models; Node floor corrected to
   >=22.19). Standing posture is now ordinary stack-currency: check SDK
   release notes per minor when bumping.
2. **axum 0.8** (relay; #73) — WebSocket `Utf8Bytes` type migration in the
   WS routing layer. Still deferred (pinned 0.7.9).
3. **rand 0.9** (relay; #9) — `thread_rng` call sites deprecated; mechanical.
   Still deferred (pinned 0.8).
4. **shadcn_flutter 0.0.53** (cockpit; #28) — removes 22 dialog/popover APIs;
   audit call sites before bumping. Dormant with cockpit (freeze-with-guard
   posture; revisit only on revival).
5. **share_plus 12** — **ABSORBED 2026-08-27**: the built-in-Kotlin story
   (`story-upgrade-plus-plugins-built-in-kotlin`) took share_plus
   10.1.4→13.3.0, crossing the v12 API break with the
   `SharePlus.instance.share` migration. No outstanding work.
6. **flutter_secure_storage 10** (app; #84) — `AppleOptions` migration.
   Still deferred (pinned ^9.0.0).
7. **ed25519-dalek 3** (relay? #72) — `CryptoRng` bounds incompatibility.
   Still deferred (pinned 2.2.0).
8. **flutter_local_notifications 22** (cockpit; ignore rule) — v22 named-params
   API. Dormant with cockpit.

State after drain: 0 open PRs, 0 open dependabot alerts (35 fixed), main green.
