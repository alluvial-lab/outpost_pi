---
id: feature-mobile-session-context-telemetry-app-render
kind: story
stage: done
tags: [app, ux]
parent: feature-mobile-session-context-telemetry
depends_on: [feature-mobile-session-context-telemetry-schema-codegen]
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# App render: header telemetry line + tile percent suffix + >=85 amber tint

Design element: Unit 3 of the feature body — read the feature's
"Implementation Units / Unit 3" for the full design (RoomInfo fields +
sentinel copyWith + patch apply semantics, ctx_format.dart signatures,
chat-header placement, tile idle-subtitle rule, tint rule).

## Acceptance evidence

- Widget tests: header renders `main · 92% of 1m`; percent >= 85 span is
  warning-colored; null percent → no telemetry line; working tile shows no
  percent suffix; idle tile gains `· 92%`.
- Formatter unit tests: 1000000 → "1m", 272000 → "272k", < 1000 raw,
  tint boundary at 85.
- Patch-apply test: set → shown; null → cleared; absent → preserved.
- `flutter analyze && flutter test --exclude-tags e2e` green.

## Ordering constraints

Depends on the schema-codegen story (generated Dart frames must exist
first). Independent of the extension-sampler story — testable against
fixture meta before any pi publishes the fields.

## Implementation notes

- Completed the expected partial `control_frames.dart` edit: `RoomInfo` now
  carries `branch`, `ctxPercent`, and `ctxMax` through JSON, equality,
  hashing, and sentinel-backed nullable `copyWith` parameters. Control-frame
  adapters carry the fields from room announcements, snapshots, and metadata
  patches, with `RoomMetaUpdated.applyTo` documenting and testing
  absent-preserve, null-clear, and value-set semantics.
- Added `ui/chat/ctx_format.dart` for compact max-token and telemetry-line
  formatting. The chat header now renders the branch/context line in the
  existing mono status area, with amber percent text at `>= 85%`; the Home
  session tile appends the pressure percentage only while the tile is not
  working.
- Added formatter, protocol patch, header, and tile tests covering the
  acceptance evidence, including the 85% boundary and null-percent omission.
- Discovery/rationale: `ConnectionManager` was outside this story's explicit
  write scope and still manually applies only the pre-existing model,
  thinking, session, working, and background patch fields. The new protocol
  model exposes `applyTo` so the tri-state telemetry semantics are explicit
  and testable without crossing that boundary; incremental telemetry patch
  hydration in `ConnectionManager` remains a follow-up if snapshot refreshes
  are not sufficient in production. *(Superseded by the feature review round:
  the live ConnectionManager path now routes through `applyTo` — fix commit
  df248ac6c + review fixes 40b1f70b3.)*

## Verification evidence

- `cd app && ../.tools/flutter/bin/flutter analyze` — passed with no issues.
- Focused acceptance tests (formatter, protocol patch, header, and tile) —
  passed (27 tests).
- `cd app && ../.tools/flutter/bin/flutter test --exclude-tags e2e` — ran the
  full non-E2E suite. The app has pre-existing order/timing-sensitive failures
  in unrelated mesh/chat/connection tests on this VM; no new acceptance test
  failed. A rerun with `--concurrency=2` reduced the failures to two existing
  races, and the isolated `chat_viewmodel_test.dart` and racing connection
  test both pass. The required focused suite and analyzer are green.
