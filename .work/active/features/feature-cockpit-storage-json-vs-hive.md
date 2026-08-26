---
id: feature-cockpit-storage-json-vs-hive
kind: feature
stage: drafting
tags: [cockpit]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Cockpit storage: evaluate JSON stores vs Hive (upstream 0802539b)

## Brief

Formed by groom 2026-08-26 from `backlog-cockpit-hive-json-store-migration`
(body retained in `.work/archive/`). Operator direction 2026-08-26: **defer
to upstream and evaluate in a vacuum** — the operator does not use the
cockpit yet, so there is no local-corruption pressure; decide on merits, not
on a promote trigger. The original item's "promote on first unrecoverable
corruption / before public Windows builds" gating is lifted by this
promotion.

## Context

Upstream `0802539b` replaced Hive with atomic JSON stores to fix Windows
crash classes (locked boxes, OneDrive-location corruption, dirty-shutdown
damage). Ours opens Hive synchronously at `cockpit/lib/main.dart:21-63` with
Hive repositories throughout. Their `json_state_store.dart` (tolerant read,
atomic write) is the workable target design.

## Work

1. Evaluate adopt-migrate-upstream-wholesale vs keep-Hive (with the bounded
   open-retry bandage from `story-harvest-cockpit-crash-class-ports` already
   landed) — operator leans upstream when the delta is reasonable.
2. If migrating: port `json_state_store` semantics, migrate persisted state,
   keep repository seams so the store swap stays behind one boundary.
3. Coordinate with `story-identity-boot-restore-race` if identity storage is
   touched — same-storage overlap.

Independent and NOT gated on this evaluation:
`gate-review-cockpit-bootstrap-wiring-test` (standalone story) lands the
bootstrap wiring test now — its retry/error-widget boundary is store-agnostic
and must hold under either backend.
