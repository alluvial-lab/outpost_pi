---
id: feature-cockpit-typed-rpc-boundaries
kind: feature
stage: drafting
tags: [cockpit, refactor, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-16
---

# Cockpit: typed value objects at RPC domain boundaries

## Brief

Two gate findings in the Cockpit domain layer describe RPC payloads crossing
into domain events as raw `Map<String, dynamic>` blobs, navigated by string
keys deep in business logic — the ad-hoc-map-at-a-boundary anti-pattern the
`.agents/rules/code-design.md` fail-fast rule targets. This feature replaces
them with typed value objects parsed at the boundary:

- `gate-refactor-boundaries-ambiguous-map-rpc-event` — `RpcToolStart.args` and `RpcMeshRevoked.details` carry untyped wire blobs into domain events
- `gate-refactor-boundaries-ambiguous-map-rpc-gateway-respondui` — `RpcProcessGateway.respondUi` requires callers to pass a raw `{value|confirmed|cancelled}` map in a domain port

## Simplification opportunity

Define typed DTOs/value objects at the RPC→domain boundary; parse once, pass
typed objects downstream. Reduces the drift surface and moves validation to the
edge. No public-surface behavior change beyond stricter typing.

## Source

Promoted from backlog by `scope` (2026-07-15). 2
`gate-refactor-boundaries-ambiguous-map-rpc-*` findings from the v0.6.0 release
`gate-refactor` (boundaries library).
