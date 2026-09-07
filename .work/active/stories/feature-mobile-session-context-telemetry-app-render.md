---
id: feature-mobile-session-context-telemetry-app-render
kind: story
stage: implementing
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
