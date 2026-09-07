---
id: feature-mobile-session-context-telemetry-extension-sampler
kind: story
stage: implementing
tags: [pi-extension, protocol]
parent: feature-mobile-session-context-telemetry
depends_on: [feature-mobile-session-context-telemetry-schema-codegen]
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Extension sampler: getContextUsage + git branch → edge-gated room-meta patches

Design element: Unit 2 of the feature body — read the feature's
"Implementation Units / Unit 2" for the full design (SessionTelemetryPublisher
signature, sampling points, value-gating, git timeout→null, the stale-ctx
latest-slot accessor discipline, hello room_meta inclusion, and the
`_publishRoomMetaPatch` type-derivation cleanup).

## Acceptance evidence

- Unit tests with injected usage/branch sources: delta-only publishes, no
  republish on unchanged values, compaction null-clear, git timeout →
  null-clear once, reset forgets state.
- Wiring test: agent_settled triggers a sample; a stale-throwing usage
  source yields undefined without propagating (the
  `story-new-wedge-bare-pi-reopen` defect class must stay closed).
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  green.
- Live spot-check on one restarted pi: published ctx_percent matches the
  TUI footer at settle (validates the freshness assumption; if stale,
  record the finding + fall back to message_end sampling per the feature's
  Risks section).

## Ordering constraints

Depends on the schema-codegen story (wire fields must exist first). Note:
pis only load extension changes at process restart (ESM) — the live
spot-check requires one pi restart.
