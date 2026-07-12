---
id: story-app-persistent-ring-log
status: superseded
superseded_by: story-app-debug-log-adapter, story-app-debug-toggle-ui, story-app-capture-routing
superseded_date: 2026-07-04
kind: story
stage: done
tags: [app, observability, bug]
parent: feature-cross-side-observability
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---

> **SUPERSEDED 2026-07-04.** Split into 3 stories under the debug-gated,
> app-global design revision (post design-review). See
> `.work/reviews/review-feature-cross-side-observability-design-2026-07-04.md`
> and the revised `feature-cross-side-observability` body.

# App: persistent debug ring log + in-app export

## Status

**Design landed 2026-07-04** (`feature-cross-side-observability` advanced to
`stage: implementing`). An earlier inline build attempt was reverted 2026-07-04
(it left the app non-compiling: `DebugLog` contract + `DebugLogImpl` adapter +
DI registration + viewmodel export methods were added without a producer or
consumer, and a dangling `_DebugSection` reference). The design pass wrote the
full unit breakdown into the feature body; this story implements Units 1-4
(the ring log) as a single stride. The relay-side companion
(`story-relay-retroactive-file-logging`) IS implemented and verified.

## Observed

The app's logging is `debugPrint(...)` → Android logcat ring buffer only
(`ws_transport.dart`, `sync_service.dart`). The buffer is bounded, wiped on
reboot, and rolled over by traffic. There is no file-based logger — the
`logging` package in `pubspec.lock` is not used for persistent capture, and
`path_provider`/`share_plus` are not in `pubspec.yaml`. So every intermittent
mobile bug noticed after the fact (reconnect cluster, swallowed messages,
no-echo timeouts) is **anecdotal** on the phone: by the time it's noticed, the
logcat is gone. `adb logcat -d` works only for USB-connected dev builds in
real time.

`idea-cross-side-logging-for-debug` (2026-06-29 survey) names the persistent
app-side ring log as the single highest-leverage piece — it converts
intermittent bugs from "lost" to "diagnosable after the fact." This is the
phone-side half of the cross-side observability gap; the relay half is
`story-relay-retroactive-file-logging`.

## Scope

1. **A bounded in-memory ring buffer** flushed to a file on device
   (`getApplicationDocumentsDirectory`), surviving reboot and buffer rollover.
   Size-capped (e.g. 512 KiB) with truncation/rotation so it doesn't grow
   unbounded.
2. **A thin `DebugLog` surface** that the existing `debugPrint` sites route
   through, preserving current logcat behavior AND persisting to the ring.
   Concentrated in `ws_transport.dart` (`[ws-in] …`) and `sync_service.dart`
   (`[msg-send]`, `[msg-echo]`, `[session-sync]`, send-timeout, session-gate
   rejections).
3. **Privacy scrubbing.** The persistent+shareable log must NOT contain
   message bodies or image data — only routing metadata + message ids + state
   transitions. Notably `[msg-send] id=$id text=${_preview(text, image)}`
   (`sync_service.dart:260`) includes a text preview; the persistent copy
   keeps `id` only and drops the preview. (logcat can keep the preview in dev
   builds; the persisted copy is the privacy-safe subset.)
4. **In-app "Export debug log" share-sheet action** in settings, reading the
   persisted file and sharing via `share_plus`.
5. **State-transition capture** that maps 1:1 to the shipped resilience fixes:
   `working` convergence, room snapshot adoption, reconnect hydration,
   send-failure surfacing, pending-send backstop, stale-session history
   guards, session-gate rejections (`missing_session_id`, `session_mismatch`,
   `active_session_unknown`).

## Acceptance criteria

- [ ] A bounded ring log persists to `getApplicationDocumentsDirectory()`,
  survives app restart, and is capped (no unbounded growth).
- [ ] The key state-transition lines from `ws_transport.dart` and
  `sync_service.dart` are captured (routing + ids + transitions), with
  message bodies/image previews scrubbed.
- [ ] An "Export debug log" action in settings shares the persisted log via
  the system share sheet.
- [ ] The shared log's lines correlate to the extension's
  `app user_message id=…` (`index.ts:3297`) and the relay's forward-path
  `debug!` id (`story-relay-retroactive-file-logging`) by message id.
- [ ] `flutter analyze` clean; `flutter test` green (new tests for the ring
  buffer cap + privacy scrubbing).
- [ ] No message text or image content reaches the persisted/shared log.

## Open decisions (RESOLVED 2026-07-04, operator-confirmed)

All four open decisions are closed in the parent feature's `## Design
decisions` section:
- **Release gating:** always-on, privacy-scrubbed subset.
- **Share format:** jsonl.
- **Retention:** 1 MiB cap, single file, ring-truncate, 48h coverage.
- **Capture surface:** the 15 `debugPrint` sites; scrub `[msg-send]` text preview.

No further design input needed — proceed to implementation.

## Out of scope

- The relay file logging (`story-relay-retroactive-file-logging`).
- Extension-side level toggle (separate, lower-leverage).
- Structured telemetry / crash reporting service (explicit non-goal per survey).
- Capturing message bodies or image data (privacy non-goal).

## References

- `app/lib/data/transport/ws_transport.dart:82-142` — `[ws-in]` debugPrint sites.
- `app/lib/data/sync/sync_service.dart:212,245,260,341,425,538,610` — `[msg-send]`/`[msg-echo]`/`[session-sync]` sites.
- `app/lib/ui/settings/settings_page.dart`, `settings_sheet.dart` — export action home.
- `app/lib/config/dependencies.dart` — DI/service registry.
- `app/pubspec.yaml` — add `path_provider`, `share_plus`.
- `.agents/skills/flutter-mobile/SKILL.md` — async UI safety, lifecycle.
- `idea-cross-side-logging-for-debug` — the survey grounding this.
