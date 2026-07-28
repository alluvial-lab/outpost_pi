---
id: gate-security-debug-log-fallback-raw-exceptions
kind: story
stage: review
tags: [security, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-24
updated: 2026-07-28
---

# Debug-log fallback prints raw exceptions and stack traces

## Source
gate-security scan for v0.3.0 (2026-07-24). Severity: Low → parked per gate_finding_routing.

## Domain
Error Handling & Logging / Data Protection

## Location
`app/lib/data/debug/debug_log_impl.dart:121,320`

## Evidence
All logger failure paths interpolate raw exceptions into _safeLog; _safeLog prints that text and prints the full stack in debug builds. File and platform exceptions commonly include absolute sandbox paths and platform details, contradicting the method's scrubbed contract.

## Implementation notes

- Changed `app/lib/data/debug/debug_log_impl.dart`: fallback diagnostics now
  receive only fixed failure categories and never print exception text or stack
  traces.
- Changed `app/test/data/debug/debug_log_impl_test.dart`: added a
  `FileSystemException` fallback canary which exercises the file-I/O callers,
  asserts no exportable state, and proves diagnostics contain neither the path,
  runtime exception class, nor a stack frame.
- Verified: `flutter analyze` and
  `flutter test test/data/debug/debug_log_impl_test.dart --concurrency=1`.

## Remediation direction
Pass fixed failure categories — or at most an admitted runtime error class — to _safeLog, and never print stacks. Add a FileSystemException path canary covering every fallback route.
