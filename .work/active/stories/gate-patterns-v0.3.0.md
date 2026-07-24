---
id: gate-patterns-v0.3.0
kind: story
stage: done
tags: [patterns]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: patterns
created: 2026-07-24
updated: 2026-07-24
---

# Patterns extracted for v0.3.0

## New patterns codified
- `content-free-diagnostic-categories` — closed reason codes + bounded metadata at logging boundaries (the diagnostic-privacy arc's recurring shape)
- `frame-byte-bounded-admission` — dual count+byte budgets before enqueueing burst-controlled work
- `identity-scoped-monotonic-high-watermarks` — owner/key-generation-fenced monotonic watermarks under serialization
- `recoverable-secure-channel-circuit-breakers` — bounded invalid-frame streak → detach, retain keys, reattach + resync
- `cross-language-known-answer-fixture-triangulation` — one independent deterministic KAT fixture, reproduced byte-for-byte in Dart + TS

## Inconsistencies flagged
- `generation-fenced-async-ownership` ← pairing_viewmodel.dart async-gap channel install without generation check → `gate-patterns-inconsistency-pairing-viewmodel-generation-fence`
- `stale-capability-eviction` ← pairing_coordinator listDevices dereferences captured ctx.ui after await → `gate-patterns-inconsistency-pairing-coordinator-stale-capability`
- `typed-wire-decoders` ← pair_request_flow.dart raw jsonDecode of untrusted pairing response → `gate-patterns-inconsistency-pair-request-flow-typed-decoder`

## Pattern files written
- `.agents/skills/patterns/content-free-diagnostic-categories.md`
- `.agents/skills/patterns/frame-byte-bounded-admission.md`
- `.agents/skills/patterns/identity-scoped-monotonic-high-watermarks.md`
- `.agents/skills/patterns/recoverable-secure-channel-circuit-breakers.md`
- `.agents/skills/patterns/cross-language-known-answer-fixture-triangulation.md`
- `.agents/skills/patterns/SKILL.md` (updated index, 16 patterns)
- `.agents/rules/patterns.md` (regenerated digest, src-sha256=a07b66c9)
