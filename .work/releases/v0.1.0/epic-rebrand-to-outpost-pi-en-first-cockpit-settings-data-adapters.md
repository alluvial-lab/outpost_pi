---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-settings-data-adapters
kind: story
stage: done
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-settings
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Translate settings data-adapter documentation

## Scope

Translate Portuguese comment/dartdoc prose to English in these owned files:

- `cockpit/lib/app/settings/data/daemon/supervisor_client_impl.dart`
- `cockpit/lib/app/settings/data/daemon/win_named_pipe.dart`
- `cockpit/lib/app/settings/data/relay/relay_gateway_impl.dart`

Preserve commands, paths, JSON keys, URLs, timeouts, error strings, Win32 calls,
process/socket order, line framing, and `Result` behavior. Translate adapter-
specific IO/lifecycle rationale in context.

## Documentation boundary

`SupervisorClientImpl` and `RelayGatewayImpl` inherit their public contracts
from domain ports. Do not duplicate dartdoc on every override. Retain and
translate class-level adapter behavior plus useful private-helper docs.
`supervisorPipeName` and `winPipeTransact` already satisfy the Always tier and
only need their existing docs translated.

## Acceptance criteria

- [x] All three files contain EN-only comment/dartdoc prose.
- [x] Adapter-specific platform, lifecycle, framing, and failure rationale is
      preserved rather than replaced with generic contract restatement.
- [x] Natural-language error strings are reviewed and remain unchanged when
      already English.
- [x] No executable token, command, path, key, timeout, FFI call, error mapping,
      process/socket behavior, or public signature changes.
- [x] Scoped PT scan and dart format check pass; parent integration runs the
      full settings and Cockpit gates.

## Implementation notes

- Files changed: `cockpit/lib/app/settings/data/daemon/supervisor_client_impl.dart`, `cockpit/lib/app/settings/data/daemon/win_named_pipe.dart`, `cockpit/lib/app/settings/data/relay/relay_gateway_impl.dart`.
- Tests added: none; this was a comment/dartdoc-only change with no behavior change.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Documentation rationale: kept adapter overrides undocumented because their contracts are inherited from the domain ports; translated and gap-filled the adapter class and existing helper docs instead. Described `_call` as using the supervisor transport rather than only the UDS because the same helper delegates to a Windows named pipe.
- Verification: scoped EN/PT grep found no accented or sampled unaccented Portuguese; `dart format --output=none --set-exit-if-changed` passed for all three owned files; `flutter analyze` passed with zero issues; full `flutter test` passed (241 tests). Existing natural-language error literals were reviewed and left unchanged.
