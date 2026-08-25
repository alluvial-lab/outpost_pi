---
id: gate-refactor-documentation-transcript-store-errors
kind: story
stage: implementing
tags: [refactor]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: refactor
created: 2026-08-25
updated: 2026-08-25
---

# Document transcript store validation and read failures

## Library
documentation

## Rule
service-contract

## Confidence
High

## Location
`app/lib/domain/contracts/transcript_event_store.dart:49`

## Issue
The domain store contract describes append/read operations but omits their failure behavior, while `HiveTranscriptEventStore` throws on session-key mismatch and malformed or cross-session stored records.

## Impact
Sync callers cannot distinguish recoverable persistence degradation from a contract violation or corrupt durable state without reading the adapter.

## Fix
Add dartdoc to the interface describing append validation, storage failure propagation, and corrupt-read behavior; let the Hive override inherit or refine that contract.
