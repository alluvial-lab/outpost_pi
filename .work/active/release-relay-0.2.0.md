---
id: release-relay-0.2.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: null
created: 2026-07-19
updated: 2026-07-19
---

# Release relay-0.2.0

First post-rebrand relay release. Binds the relay-attributed done work since
the `relay-0.1.0` rebrand reset: pre-auth resource bounds + the late
`gate-security` finding on pre-auth WebSocket size limits.

This release is paired with cross-component protocol changes bound elsewhere
(repo `v0.2.0`): `feature-typed-bounded-relay-decoding` and
`feature-finish-generated-protocol-adoption` touch relay + app + extension +
cockpit wire, so the components are not independently deployable. At the UAT
checkpoint this release deploys as part of a coordinated cut, not in
isolation.

## Bound items

### Active done items (2)

| id | title | kind | tags |
|----|-------|------|------|
| feature-relay-resource-bounds | Relay: bound unauthenticated/authenticated resource consumption and retained state | feature | relay, security |
| gate-security-preauth-websocket-size-limits | Pre-auth WebSocket frames and hello metadata lack explicit size limits | story | security, relay |

### Binding-consistency warnings

Guard run 2026-07-19 (`binding_guard: warn`, `epic_cohesion: phased`).
All findings are legitimate cross-component phased delivery, not true drift:

- **CONFLICT** — `feature-typed-bounded-relay-decoding` (parent of bound
  story `gate-security-preauth-websocket-size-limits`) is `done` + unbound.
  Its tags `[app, pi-extension, relay, security, protocol]` make it
  multi-component → repo-attributed; it binds to repo `v0.2.0`, not here.
  Legitimate cross-component phased delivery.
- **INCOMPLETE ×4** (informational under `phased`) — `feature-relay-resource-bounds`
  has 4 unbound children (`gate-security-pi-envelope-auth-scan-rate-limit`,
  `gate-security-auth-challenge-no-timeout`,
  `gate-security-unbounded-outbound-queues`,
  `gate-security-subscription-empty-target-retention`). All are `[security]`-only
  → repo-attributed; they bind to repo `v0.2.0`. No relay-attributed child is
  left behind.

## Gate runs

### gate-security (2026-07-20) — 4 High findings

The current delegated harness exposed no nested generic-subagent/scanner
adapter, so this gate used the skill's inline fallback with reduced isolation.
The bounded audit covered the two release items and their relay auth,
WebSocket, mesh-storage, routing, retained-state, logging, dependency, and
container controls; it did not implement fixes.

Release-blocking findings:

- `gate-security-preauth-large-message-allocation`
- `gate-security-rooms-dedup-cache-unbounded`
- `gate-security-mesh-owner-storage-unbounded`
- `gate-security-mesh-auth-distinct-key-scan-fanout`

### gate-tests (2026-07-19) — 2 High, 1 Medium

Inline scan, reduced isolation. The relay code surface has real test
coverage gaps around the new pre-auth/transport bounds.

Release-blocking findings:

- `gate-tests-handshake-step-timeout-seam`
- `gate-tests-preauth-transport-size-ceiling`

Non-blocking (backlog): `gate-tests-mesh-auth-cache-ttl` (Medium).

### gate-cruft (2026-07-19) — 1 Medium, 3 Low

No release blockers. All four routed unbound to `.work/backlog/`:
`gate-cruft-misnamed-bounded-test-mailbox-shim`,
`gate-cruft-unused-parse-hello-wrapper`,
`gate-cruft-relay-test-bool-assertions`,
`gate-cruft-relay-plan-era-comments`.

### gate-docs (2026-07-19) — 1 Medium

No release blockers. One repo-skill staleness finding unbound to backlog:
`gate-docs-formal-rigor-relay-backpressure` (`.agents/skills/formal-rigor-stack/SKILL.md`
still claims relay mailboxes are unbounded — now stale after
`feature-relay-resource-bounds`).

### gate-patterns (2026-07-19) — 1 pattern draft

No findings (not a pass/fail gate). Emitted one pattern draft
(`centralized-resource-policy`) as `gate-patterns-relay-0.2.0` at `stage: done`;
updated the pattern index + generated rules digest.

### gate-refactor (2026-07-19) — 0 new findings

Scanned against the three Remote-Pi scan-rule libraries (boundaries,
lifecycle, protocol-contract). 1 already-tracked Medium
(`gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward`,
`relay/src/handlers/pi_forward.rs:262`) skipped as a duplicate. No new items.

### Totals

**6 release-blocking findings** (4 security High + 2 tests High) must reach
`done` before ship; **8 non-blocking** findings are unbound backlog and do not
block.

## UAT checkpoint

Per `release_uat: manual-checkpoint` in `.work/CONVENTIONS.md`, the tag is
**not** cut until an operator runs the relay smoke runbook in
[`docs/release-uat.md`](../../docs/release-uat.md) and records an ack.
For a relay-only release the smoke is: confirm `authenticated` peers,
cross-PC forward path, and room/presence state via the relay debug log
(`RUST_LOG=info,relay=debug`, `OUTPOSTPI_RELAY_LOG_DIR=/data/logs`).
