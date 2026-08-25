---
id: story-canonical-transcript-timestamp-ownership-app-consume-cleanup
kind: story
stage: done
tags: [app, bug]
parent: feature-canonical-transcript-timestamp-ownership
depends_on: [story-canonical-transcript-timestamp-ownership-extension-producer-ts, story-canonical-transcript-timestamp-ownership-error-frame-ts]
release_binding: v0.8.0
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# App consume + fallback cleanup (close the app-side residuals)

Unit D of `feature-canonical-transcript-timestamp-ownership`. Now that every
producer carries server `ts` (Units A–C), close the app-side residuals so no
authoritative event stamps `DateTime.now()` when the wire carries `ts`.

## Change (`app/lib/data/sync/sync_service.dart`)

- Buffered tool fallback narration: derive ONE `requestTs` from the wire `ts`
  (legacy `DateTime.now()` fallback) and use it for BOTH the fallback
  `AssistantMessageCommitted` and the `ToolRequested` — not an independent
  `DateTime.now()` for the narration.
- Sweep every authoritative producer (`UserMessageConfirmed`,
  `AssistantMessageCommitted`, `ToolRequested`/`ToolFinished`,
  `CompactionRecorded`, error diagnostic): confirm it consumes wire `ts`;
  `DateTime.now()` ONLY for genuinely-missing fields.

## F1/F2 reconciliation (2026-08-25)

- F1/F2 now make delivery/execution hooks durable timestamp owners; the app
  remains compatibility-tolerant rather than deleting fallbacks. Missing `ts`
  still uses phone time for genuinely mixed-era/pre-durable frames.
- The identity-capability heuristics for dropped `agent_message(ts)` frames are
  not timestamp compensations and remain necessary for reconnect dedupe; this
  cleanup therefore narrows to independent timestamp creation only.
- `AgentDone` and error terminal facts are non-rendered boundaries, but they now
  share the producer-derived timestamp too so the event log itself preserves the
  single-clock contract. Correlated pending-send failures likewise consume an
  available error-frame timestamp.

## Acceptance

- [ ] No authoritative app event stamps `DateTime.now()` when the wire carries
  `ts` (producer-connected app tests asserting real wire-`ts` flow, not injected).
- [ ] The (updated) enumeration table shows ZERO remaining authoritative
  phone-`ts` paths — the single-clock invariant finally holds.
- [ ] `flutter test --exclude-tags e2e test/domain test/data test/ui/chat`
  green; the 3 `streaming`-convergence guards green; `flutter analyze` clean.

## Ordering

`depends_on: [extension-producer-ts, error-frame-ts]` (needs all producers
carrying server `ts`). This is the closing unit of the feature.

## Implementation

- Execution capability: `sol/high`.
- Derived one `requestTs` per tool-request frame and reused it for both legacy
  buffered narration and `ToolRequested`; fixed the test ingress adapter so it
  no longer discarded tool timestamps.
- Reused `AgentDone.ts` for its buffered assistant commit and terminal fact, and
  propagated `ErrorMessage.ts` into correlated pending-send failures.
- Preserved all old-extension fallbacks and added mixed-era coverage proving
  timestamped and ts-less histories remain renderable together.
- Verification: focused producer-consumption tests passed; final feature-level
  Flutter analyze/full non-e2e suite and extension suites are recorded in the
  feature implementation summary.
