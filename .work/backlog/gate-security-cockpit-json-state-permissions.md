---
id: gate-security-cockpit-json-state-permissions
kind: story
tags: [cockpit, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-08-26
updated: 2026-08-26
---

# Cockpit JSON state files inherit ambient filesystem permissions

## Severity
Low

## Domain
Data Protection

## Location
`cockpit/lib/app/core/data/storage/json_state_store.dart:311`

## Evidence
```dart
await file.parent.create(recursive: true);
final temporary = File('${file.path}.tmp');
final output = await temporary.open(mode: FileMode.write);
```

The new JSON backend does not establish owner-only permissions on the state directory, temporary file, committed file, or quarantine copies. On POSIX systems the files therefore inherit the process umask (commonly producing mode `0644`). The documents contain absolute project paths (`cockpit/lib/app/cockpit/data/repositories/json_project_repository.dart:47-54`) and persisted file/session paths (`cockpit/lib/app/cockpit/domain/entities/workspace_layout_codec.dart:74-112`), which can disclose local workspace structure to another account when parent-directory traversal permits it.

## Remediation direction
Create and harden the state directory and every JSON/temp/quarantine file with owner-only permissions on POSIX, tighten pre-existing files during open/migration, and add platform-aware mode tests. Preserve the atomic same-directory rename behavior and define the corresponding Windows ACL posture rather than assuming Unix mode bits there.
