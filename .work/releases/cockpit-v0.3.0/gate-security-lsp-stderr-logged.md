---
id: gate-security-lsp-stderr-logged
kind: story
stage: done
tags: [cockpit, security]
parent: feature-diagnostic-privacy-hardening
depends_on: []
release_binding: cockpit-v0.3.0
gate_origin: security
created: 2026-07-20
updated: 2026-07-27
---

# Language-server stderr is logged verbatim

## Severity
Low

## Domain
Error Handling & Logging / Data Protection

## Relevance
Release-relevant

## Location
`cockpit/lib/app/core/data/lsp/lsp_client_impl.dart:332`

## Evidence
```dart
void _onStderrLine(String line) {
  if (line.trim().isEmpty) return;
  debugPrint('[lsp:${spec.languageId}][err] $line');
}
```

## Issue
Cockpit forwards every non-empty language-server stderr line to process diagnostics verbatim and similarly interpolates raw stream errors at line 336. Language servers commonly include absolute workspace paths, source excerpts, compiler arguments, environment-derived failures, or tool output in stderr. Those values therefore reach console/collected diagnostics outside the content-free RPC diagnostic boundary introduced by this release. The server is a local child and this does not create a remote read primitive by itself, so this is a Low-severity diagnostic disclosure.

## Remediation direction
Project LSP diagnostics to fixed categories and bounded structural metadata (language, exit code, failure phase) without retaining raw stderr or error strings. If raw server output remains necessary, make it an explicit local debug opt-in with private bounded storage and clear disclosure rather than unconditional `debugPrint` output.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.

## Implementation notes

- Non-empty stderr now increments a per-process counter and emits one fixed
  content-hidden category; stream errors likewise use a fixed category.
- Exit diagnostics retain only the exit code and `stderrLines` count.
- Added a subprocess-backed canary with path/token-bearing stderr, verifying
  raw lines never reach debug output while the count and exit code survive.
- Verification: `flutter test` passed (260 tests). `flutter analyze` retains
  the unrelated pre-existing `unnecessary_underscores` info at
  `lib/app/cockpit/data/rpc/pi_rpc_process.dart:470`.
