---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-typed-rpc-boundaries
stage: done
id: gate-refactor-boundaries-ambiguous-map-rpc-gateway-respondui
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# RPC UI responses are exposed as raw maps in a domain port

## Library
boundaries

## Rule
ambiguous-map-to-domain

## Confidence
Medium

## Location
cockpit/lib/app/cockpit/domain/contracts/rpc_process_gateway.dart:62

## Issue
RpcProcessGateway.respondUi requires callers to pass a raw {value|confirmed|cancelled} Map<String, dynamic>, leaking wire shape into the domain/UI boundary.

## Fix
Needs analysis: replace the map with a typed RpcUiResponse sealed/value type and serialize it only in PiRpcProcess.

## Implementation

Added sealed `RpcUiResponse` variants for value, confirmation, and cancellation
responses. Threaded the response through the gateway, process controller,
session, and transcript UI, while keeping wire-key serialization centralized in
`PiRpcProcess`. Added exact serialization coverage for all response variants
and updated the four gateway fakes mechanically.

Verification: `flutter analyze lib test` and focused response/session/workspace
tests passed.
