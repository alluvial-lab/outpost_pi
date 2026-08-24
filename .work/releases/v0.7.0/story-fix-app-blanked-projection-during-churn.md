---
id: story-fix-app-blanked-projection-during-churn
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Blank chat during churn: dedup drops all replay while projection is unbuilt

## Symptom

Operator report (2026-08-23): blank-chat flakes persist on 0.5.1 (the
direct-cold-open variant was fixed in `b3cb6422`; this is a different
window). Capture `debug/ef5-…c9cc1cea9d20.bin`: in churn windows the
replay admission drops 60–330 replayed events with **0–1 accepted** (e.g.
05:14:18–05:21:00, 12:49:33–12:54:52, 13:14:25–13:16:27), while `route`
events fire 2–3× per second and some `roomSnapshot` rows carry no payload
at all (12:52:40, 12:54:14, 12:58:37).

## Root cause

The dedup decision already reads the canonical transcript event store, but
`_replayHistory` rebuilt the disposable `msgs` projection only when
`appendAll` reported a newly appended event. During churn the event log can be
complete while the route's disposable projection is empty/unbuilt. An
all-duplicate replay then correctly appends zero durable events but incorrectly
skips projection materialization, leaving chat blank until a genuinely new
event triggers another rewrite.

## Fix approach

Keep durable admission keyed to the canonical event store, but always derive
and reconcile the disposable message projection from that store after an
accepted replay boundary—even when every incoming event is already known.
Existing record-by-record equality keeps a healthy projection churn-free.

## Regression test

Unit: seen-set contains id, store does not, hydration replays id → row
admitted (chat non-empty). Fails-before evidence required. Live: the soak
blank-chat oracle + a churn-window route scenario (fault-scheduled
reconnect + immediate route) renders non-empty.

## Verification notes

- Evidence: capture windows above; `roomSnapshot` rows with empty payload
  during the same windows.
- Operator-perceived frequency: "quite a few flakes" — every churn burst
  with a route into the affected session is a candidate window.

## Implementation notes

- **Execution capability:** `sol/high`; this is a persistence/projection
  convergence defect sharing the replay boundary with the preceding story.
- **Files changed:** `app/lib/data/sync/sync_service.dart` and
  `app/test/data/sync/sync_service_test.dart`.
- **Failing regression:** `duplicate replay rebuilds a missing disposable
  projection` seeds the canonical event log, clears only the `msgs` box, and
  replays the same history. Before the fix the final rows were `[]` (expected
  `['restored']`); after the fix the projection rematerializes immediately.
- **No-churn guard:** `duplicate history replay through projection emits no
  Hive churn` remains green because reconciliation writes only differing rows.
- **Four-step confirmation:** focused regression and no-churn guard pass; full
  `sync_service_test.dart` passes; `flutter analyze` passes; full
  `flutter test --exclude-tags e2e --concurrency=2` passes (891 tests). The
  capture-shaped 60–330-drop windows now still dedup against durable truth but
  also reconstruct an empty routed projection, so no new event is required to
  make history visible.
- **Test-integrity repair:** the reconnect replay test was changed from a fixed
  delay to awaiting `debugApplyHistory`; the extra canonical rematerialization
  exposed its elapsed-time assumption under full-suite load.
- **Adjacent issues parked:** none.

## Bounded inline review

**Verdict: pass.** The fix changes only the replay-to-projection convergence
condition, preserves append-only event truth and duplicate admission, and keeps
healthy duplicate replay free of Hive writes. The regression reproduces the
blank projection directly rather than inferring it from a seen-set.
