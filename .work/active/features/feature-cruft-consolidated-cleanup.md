---
id: feature-cruft-consolidated-cleanup
kind: feature
stage: drafting
tags: [refactor, cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Consolidated cruft cleanup (one behavior-preserving [refactor] pass)

## Brief

Formed by groom 2026-08-26 from three cruft batches that are all
behavior-preserving removals/cleanups — route together through one
`[refactor]` design pass rather than three separate ones.

Sources (bodies retained in `.work/archive/`):
- `backlog-cruft-removal-batch` (8 gate-cruft findings, merged 2026-07-23)
- `backlog-hot-reload-cruft-batch` (gate-cruft C1 + gate-tests T5, v0.4.0)
- `gate-cruft-v050-dead-code-sweep` (2 verified instances, post-hoc v0.5.0)

## Findings (carried forward)

**app/relay batch** (all behavior-preserving):
1. Legacy sync/turn compatibility wrappers — `app/lib/data/sync/sync_service.dart:129-134`; `app/lib/domain/transcript/transcript_projection.dart:7`.
2. Misnamed unbounded-channel test mailbox shim — `relay/src/lib.rs:13-22`.
3. `PresenceTransitions` single-impl pass-through trait — `relay/src/peers/registry.rs:64`.
4. Plan-era relay comments → rewrite as current-state contracts — `relay/src/lib.rs:51-53`; `relay/src/handlers/pi_forward.rs:1`.
5. Boolean equality assertions in relay tests (clippy-rejected) — `relay/src/peers/registry.rs:1233,1248,1263,1294`.
6. Unused `ActorDispatch::Close` variant behind `#[allow(dead_code)]` — `relay/src/handlers/connection_actor.rs:28`.
7. Test-only `parse_hello` passthrough wrapper — `relay/src/auth/challenge.rs:67-69`.
8. Unused Settings relay-URL compatibility projection — `app/lib/ui/settings/viewmodels/settings_viewmodel.dart:65`.

**pi-extension dead code**: `_hotReloadEnabledPath()` / `_runtimeIdentityPath()`
no call sites (`index.ts` ~2671-2685 / ~2695-2707 depending on revision).
⚠️ Verify at design time: the helper removal may already have shipped as
`gate-cruft-unused-hot-reload-path-helpers` (v0.8.0,
`.work/releases/v0.8.0/`) — exclude if gone.

**pi-extension expiry test**: armed-request 5-minute expiry untested
(`index.ts:2842-2847` region) — fake clock just below/above the boundary;
assert no claim, marker, quiescing, or SIGTERM when expired, plus stale-file
cleanup.

**app EPK no-op**: empty conditional `if (out != b64) {}` —
`app/lib/data/transport/epk_encoding.dart:30`. Remove, preserve behavior.

## Verification

Per subproject owning the touched files (pi-extension: typecheck+test+build;
relay: fmt+clippy+test; app: analyze+test). All changes behavior-preserving —
suites must stay green with no assertion changes.
