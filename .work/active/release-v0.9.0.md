---
id: release-v0.9.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Release v0.9.0

Feature-lane minor cut: the 2026-08-26 autopilot drain (8 features, 22
standalone stories) + one late-bound archived stub. Includes the
operator-authorized public-history rescrub (cache residual accepted).

## Bound items

40 active done items (drain output; research child excluded as input) + 1
late-bound archived stub (gate-tests-fakesession-buildcontext-duplicate-
projection, done, never claimed by a prior release).

## Gate runs

### Gate runs
- **gate-tests** (2026-08-26) — 3 findings (High=1 bound: relay-failover production-seam interface coverage; Medium=2 backlog: brand-parser rejection matrix, cockpit fail-once commit recovery). Inline scanner, reduced isolation. Commit 0ceb8417.
