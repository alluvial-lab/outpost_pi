---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-core-data-adapters
kind: story
stage: review
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-core
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate cockpit core data-adapter prose

Translate Portuguese comments/dartdoc and the bounded human-readable runtime
labels in core data adapters. Preserve LSP framing, process lifecycle, JSON
keys, commands, persistence, permissions, executable resolution, and all
public signatures.

## Owned files (16)

- `cockpit/lib/app/core/data/lsp/lsp_client_impl.dart`
- `cockpit/lib/app/core/data/lsp/lsp_codec.dart`
- `cockpit/lib/app/core/data/lsp/lsp_command.dart`
- `cockpit/lib/app/core/data/lsp/lsp_launchers.dart`
- `cockpit/lib/app/core/data/lsp/lsp_process_registry.dart`
- `cockpit/lib/app/core/data/lsp/lsp_server_pool.dart`
- `cockpit/lib/app/core/data/lsp/lsp_text_edit.dart`
- `cockpit/lib/app/core/data/lsp/project_root_finder.dart`
- `cockpit/lib/app/core/data/relay/ephemeral_pi_rpc.dart`
- `cockpit/lib/app/core/data/relay/pairing_gateway_impl.dart`
- `cockpit/lib/app/core/data/relay/revoke_gateway_impl.dart`
- `cockpit/lib/app/core/data/repositories/hive_settings_store.dart`
- `cockpit/lib/app/core/data/rpc/jsonl_line_splitter.dart`
- `cockpit/lib/app/core/data/setup/environment_probe_impl.dart`
- `cockpit/lib/app/core/data/setup/outpost_pi_resolver.dart`
- `cockpit/lib/app/core/data/setup/system_permissions_impl.dart`

## Runtime-string review

Manually review and translate only the human-readable PT values identified in
this layer:

- the two LSP pool debug labels;
- the ephemeral pairing workspace label;
- the ephemeral pairing generated-name prefix.

Keep logger structure, interpolation, JSON keys, RPC prompt, temp paths,
commands, identifiers, and uniqueness suffix unchanged. Do not bulk-replace
nearby protocol or configuration values.

## Dartdoc scope

The design audit found no new Always-tier gap in this story. Translate existing
useful docs while preserving adapter-specific lifecycle and graceful-degradation
intent. Implementation overrides inherit their documented domain contract; do
not duplicate comments merely because an override is public. If a genuine miss
is discovered, record it in the parent feature before widening scope.

## Acceptance criteria

- [x] All 16 owned files contain no Portuguese prose or human-readable PT
      runtime labels.
- [x] LSP framing/start/restart/shutdown behavior, pairing/revoke RPC behavior,
      Hive keys, setup probes, and permission behavior are unchanged.
- [x] Runtime changes are limited to the four bounded human-readable values;
      keys, commands, identifiers, and data formats are unchanged.
- [x] No filler dartdoc is added to overrides, DTOs, or trivial helpers.
- [x] Focused LSP/data tests pass, followed by the parent feature's serialized
      full `flutter analyze` and `flutter test` gate.

## Implementation notes

- Files changed: all 16 owned core data-layer files listed above.
- Tests added: none; this is a behavior-preserving translation and dartdoc pass.
- Runtime labels: translated only the two LSP pool debug labels plus the
  ephemeral pairing workspace and generated-name prefix. JSON keys, commands,
  identifiers, framing, persistence, and lifecycle behavior remain unchanged.
- Dartdoc rationale: the story and parent audit identify no Always-tier gap in
  this adapter slice, so existing adapter-specific docs were translated without
  duplicating inherited port contracts on overrides.
- Verification: focused LSP tests passed (26 tests); `flutter analyze` passed
  with zero issues; full `flutter test` passed (241 tests); accented and known
  unaccented Portuguese scans returned no matches in the owned files;
  `git diff --check` passed.
- Discrepancies from design: none.
- Adjacent issues parked: none.
