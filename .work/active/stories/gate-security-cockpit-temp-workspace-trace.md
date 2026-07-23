---
id: gate-security-cockpit-temp-workspace-trace
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

# Production workspace flow writes paths to a predictable temp trace

## Severity
Low

## Domain
Error Handling & Logging / Data Protection

## Relevance
Release-relevant

## Location
`cockpit/lib/app/cockpit/ui/cockpit_page.dart:124`

## Evidence
```dart
File(
  '${Directory.systemTemp.path}/ck_trace.log',
).writeAsStringSync('$m\n', mode: FileMode.append, flush: true);
```

## Issue
The production Create Workspace flow unconditionally calls this temporary crash marker. In particular, `cockpit_page.dart:140` records `picker:done path=$path mounted=$mounted`, exposing the selected workspace's absolute path in a fixed shared-temp filename. The trace is not debug-mode gated, is never removed or rotated, and follows normal platform file-creation permissions. Anyone who receives or can read that temp file learns local account/project layout; a stale file also survives after the one Windows crash investigation that motivated it. The data is local path metadata rather than file contents or credentials, so severity is Low.

## Remediation direction
Remove the temporary marker now that it has served its investigation, or replace it with a debug-only, content-free diagnostic under an application-private directory with bounded retention. Never write selected workspace paths or dialog result objects to a predictable shared-temp file.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.
