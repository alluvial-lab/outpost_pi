---
id: backlog-protocol-codegen-dart-ir-from-schema
created: 2026-08-11
updated: 2026-08-11
tags: [pi-extension, app]
---

# Dart wire IR should be generated from the canonical schema

## Origin
gate-refactor R5 (Medium), v0.4.0.

## Location
tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json:676-749.

## Issue
The Dart generation IR independently re-declares tool_request and tool_result fields (including optional ts) already defined in protocol/schema/app-pi-server.schema.json:160-186. The ordering work required both sources edited manually and describes the fixture as maintained "in lockstep", so schema changes are not mechanically propagated to Dart.

## Work
Generate the Dart IR directly from the canonical JSON schema, or make one canonical intermediate representation generate both schema-facing TypeScript and Dart projections.
