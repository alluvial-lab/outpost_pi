---
id: feature-mobile-session-context-telemetry-schema-codegen
kind: story
stage: implementing
tags: [pi-extension, app, relay, protocol]
parent: feature-mobile-session-context-telemetry
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Wire contract: branch/ctx_percent/ctx_max additive room-meta + nullableIntegers codegen

Design element: Unit 1 of the feature body — read the feature's
"Implementation Units / Unit 1" for the full design (schema fields,
merge categories, codegen emitter sites with line anchors, relay merge
hand-edits mirroring d13b85fec's exact touched lines, SPEC.md doc line).

## Acceptance evidence

- Codegen suite green with updated goldens + `protocol/fixtures/relay/
  relay-control.jsonl` rows covering set / clear / preserve for `branch`,
  `ctx_percent`, `ctx_max`.
- Relay merge test proving the null-clear path (post-compaction stale
  percent must not survive) plus absent-preserve.
- `cargo fmt --check && cargo clippy -- -D warnings && cargo test` green;
  codegen vitest green; TS + Dart generated files committed from the run.
- SPEC.md room-meta contract line gains the three fields in the same
  commit set (code-first timing).

## Ordering constraints

None — this is the foundation story; the extension-sampler and app-render
stories depend on it.
