---
kind: story
release_binding: v0.2.0
parent: feature-finish-generated-protocol-adoption
stage: done
id: gate-refactor-protocol-handwritten-control-type-strings
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# Control handler repeats generated frame type strings

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
Medium

## Location
relay/src/handlers/control.rs:68

## Issue
The generated RelayControlFrame match already identifies the control variant, but the handler repeats discriminator strings for labels/limits (subscribe_presence, presence_check, rooms_check, etc.; also lines 86, 97, 100, 112, 123, 134, 137). These can drift from the generated protocol source.

## Fix
needs analysis: derive the label from the generated enum/registry or centralize a single generated-backed variant-to-wire-type helper.

## Implementation
- Execution capability: delegated feature implementer; the Rust generator and handler adoption were one bounded discriminator projection.
- Generated `RelayControlFrame::wire_type()` from the same variant sequence as `RELAY_CONTROL_FRAME_TYPES`.
- Routed peer-bound and rate-limit labels through the generated method instead of repeating six discriminator strings in production handlers.
- Extended dispatch coverage to assert every generated inbound variant's label belongs to the generated registry.
- Verification: generator syntax + deterministic Rust check, relay fmt, strict clippy, and all relay tests (180 total across unit/integration suites) passed.
- Discrepancies from design: none.
