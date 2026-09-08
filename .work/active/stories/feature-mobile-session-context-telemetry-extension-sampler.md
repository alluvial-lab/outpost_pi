---
id: feature-mobile-session-context-telemetry-extension-sampler
kind: story
stage: done
tags: [pi-extension, protocol]
parent: feature-mobile-session-context-telemetry
depends_on: [feature-mobile-session-context-telemetry-schema-codegen]
release_binding: v0.12.0
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

## Implementation notes

Implemented `SessionTelemetryPublisher` in
`pi-extension/src/extension/session_telemetry.ts` with injected context/git
sources, edge-gated delta patches, null clears after compaction, a 2-second
non-shell-interpolated git lookup, in-flight coalescing, reset generation
fencing, and hello-state projection. Wired the latest captured session context
accessor and lifecycle samples at session start, agent start, agent settled,
and session compaction. `_publishRoomMetaPatch` now derives its patch shape
from the generated room-meta update type.

Verification:

- `cd pi-extension && corepack pnpm typecheck` — passed.
- `cd pi-extension && corepack pnpm test` — passed (64 files, 1127 passed,
  3 skipped).
- `cd pi-extension && corepack pnpm build` — passed.
- Focused sampler/composition tests — passed (18 tests).
- Live spot-check was not run in this environment; the implementation samples
  `ctx.getContextUsage()` at `agent_settled`, the same SDK source used by the
  TUI footer, with stale-context errors treated as unavailable.

## Ordering constraints

Depends on the schema-codegen story (wire fields must exist first). Note:
pis only load extension changes at process restart (ESM) — the live
spot-check requires one pi restart.
