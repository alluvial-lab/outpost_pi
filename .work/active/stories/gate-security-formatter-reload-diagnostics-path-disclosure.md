---
id: gate-security-formatter-reload-diagnostics-path-disclosure
kind: story
stage: implementing
tags: [cockpit, security]
parent: feature-diagnostic-privacy-hardening
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-20
updated: 2026-07-23
---

# Formatter reload diagnostics disclose local paths and stack traces

## Severity
Low

## Domain
Error Handling & Logging

## Relevance
Release-relevant

## Location
`cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:383`

## Evidence
```dart
} catch (e, st) {
  // Non-invasive signal only: preserve the prior fallback (no buffer change)
  // so a formatter/read failure does not silently mask as success.
  debugPrint('[file-viewer] _reloadFromDisk failed: $e\n$st');
}
```

## Issue
The release replaces a silent formatter-reload fallback with a debug message that interpolates the raw file exception and full stack trace. `FileSystemException` diagnostics include the selected file's absolute path, and the stack trace can include additional local source/build paths. This exposes workstation and project metadata to any consumer of the process console or collected debug output even though reload recovery needs only a content-free failure signal. The exposure is local and does not include file contents by itself, so this is defense-in-depth rather than a release blocker.

## Remediation direction
Emit a fixed, content-free formatter-reload failure category (or at most a normalized error class) without the raw exception, absolute path, or stack trace. If raw diagnostics remain necessary for troubleshooting, require an explicit debug-only opt-in and document the sensitive metadata it can expose.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.
