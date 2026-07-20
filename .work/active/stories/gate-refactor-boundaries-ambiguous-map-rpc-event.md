---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-typed-rpc-boundaries
stage: done
id: gate-refactor-boundaries-ambiguous-map-rpc-event
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# RPC domain events carry untyped wire blobs

## Library
boundaries

## Rule
ambiguous-map-to-domain

## Confidence
Medium

## Location
cockpit/lib/app/cockpit/domain/entities/rpc_event.dart:68,269

## Issue
RpcToolStart.args and RpcMeshRevoked.details move Map<String, dynamic> payloads into domain events instead of narrowing them at the adapter boundary.

## Fix
Needs analysis: introduce typed DTOs or an explicit opaque JsonObject value object and have RpcEventMapper produce that boundary type.

## Implementation

Introduced `RpcJsonObject` as the opaque RPC object value object and carried it
through live and replayed tool transcript events into projected tool messages.
`RpcEventMapper` preserves string-key coercion and the existing empty/null
fallbacks for tool args and mesh-revoked details. Tool-card JSON still encodes
the wrapper's values, and the projection immutability test now inspects the
wrapped values.

Verification: `flutter analyze lib test` and focused RPC mapper/transcript tests
passed.
