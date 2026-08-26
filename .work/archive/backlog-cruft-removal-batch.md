---
id: backlog-cruft-removal-batch
created: 2026-07-23
updated: 2026-08-26
tags: [cleanup, refactor, app, relay]
status: folded
folded_into: feature-cruft-consolidated-cleanup (groom 2026-08-26)
---

# Cruft-removal batch (merged from 8 gate-cruft findings)

Merged by groom 2026-07-23 (cluster F3). All are behavior-preserving
removals/cleanups — route together through one `[refactor]` pass. Absorbed
item bodies retained in `.work/archive/`.

1. **Legacy sync/turn compatibility wrappers** — `app/lib/data/sync/sync_service.dart:129-134`; `app/lib/domain/transcript/transcript_projection.dart:7`.
2. **Misnamed unbounded-channel test mailbox shim** — `relay/src/lib.rs:13-22`.
3. **`PresenceTransitions` single-impl pass-through trait** — `relay/src/peers/registry.rs:64`.
4. **Plan-era relay comments** → rewrite as current-state contracts — `relay/src/lib.rs:51-53`; `relay/src/handlers/pi_forward.rs:1`.
5. **Boolean equality assertions in relay tests** (clippy-rejected) — `relay/src/peers/registry.rs:1233,1248,1263,1294`.
6. **Unused `ActorDispatch::Close` variant** behind `#[allow(dead_code)]` — `relay/src/handlers/connection_actor.rs:28`.
7. **Test-only `parse_hello` passthrough wrapper** — `relay/src/auth/challenge.rs:67-69`.
8. **Unused Settings relay-URL compatibility projection** — `app/lib/ui/settings/viewmodels/settings_viewmodel.dart:65`.

Absorbed: `gate-cruft-legacy-sync-turn-compat-shims`,
`gate-cruft-misnamed-bounded-test-mailbox-shim`,
`gate-cruft-presencetransitions-single-impl-trait`,
`gate-cruft-relay-plan-era-comments`, `gate-cruft-relay-test-bool-assertions`,
`gate-cruft-unused-actordispatch-close`, `gate-cruft-unused-parse-hello-wrapper`,
`gate-cruft-unused-settings-relay-url-compatibility`.
