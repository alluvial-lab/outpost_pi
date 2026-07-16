---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data-runtime-adapters
kind: story
stage: done
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Translate cockpit data runtime and RPC adapters

## Scope

Translate Portuguese comment/dartdoc prose to idiomatic English in exactly
these files:

- `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`
- `cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart`
- `cockpit/lib/app/cockpit/data/rpc/pi_process_registry.dart`
- `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart`
- `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process_factory.dart`
- `cockpit/lib/app/cockpit/data/terminal/pty_terminal_gateway.dart`
- `cockpit/lib/app/cockpit/data/terminal/pty_terminal_gateway_factory.dart`
- `cockpit/lib/app/cockpit/data/setup/environment_installer_impl.dart`
- `cockpit/lib/app/cockpit/data/notifications/local_notifier.dart`

Preserve process lifecycle, serialized stdin, response correlation, typed wire
mapping, unknown-event fallback, PID cleanup, PTY shell/environment behavior,
installer commands, and notification configuration. Production changes are
comment-only: do not alter imports, signatures, JSON/discriminator strings,
commands, environment variables, error strings, or control flow.

`pty_terminal_gateway_factory.dart` contains ASCII-only Portuguese missed by
the original accent baseline and is deliberately included. Do not add dartdoc
to the `@visibleForTesting` `schemaControlPromptForTesting` forwarding seam;
it is Skip-tier. Adapter overrides inherit domain-port contracts, while the
existing class docs own infrastructure-specific behavior.

## Acceptance criteria

- [x] All nine files contain natural English comments/dartdoc with lifecycle,
      failure, and boundary semantics preserved.
- [x] Every public adapter/service class retains meaningful `///` documentation.
- [x] RPC keys/discriminators, process arguments, commands, environment values,
      runtime strings, and executable behavior are unchanged.
- [x] Normal and word-diff review shows production edits are comment-only.
- [x] Touched Dart files are formatted and the integrated feature can pass
      `flutter analyze` and `flutter test` from `cockpit/`.

## Implementation notes

- Files changed: `rpc_data_mapper.dart`, `rpc_event_mapper.dart`,
  `pi_process_registry.dart`, `pi_rpc_process.dart`,
  `pi_rpc_process_factory.dart`, `pty_terminal_gateway.dart`,
  `pty_terminal_gateway_factory.dart`, `environment_installer_impl.dart`, and
  `local_notifier.dart` in the story-owned cockpit data adapter paths.
- Tests added: none; production changes are documentation-only.
- Discrepancies from design: none. The existing public adapter/service class
  docs were translated and strengthened around infrastructure-specific wire,
  process, PTY, install, and notification behavior. Inherited port methods and
  the `schemaControlPromptForTesting` test seam remain undocumented as designed.
- Translation boundary decision: preserved the quoted runtime literals
  `erro desconhecido`, `Abrir`, and `Agente terminou` because the story forbids
  runtime-string changes; all comment and dartdoc prose in the nine files is
  English.
- Dispatch rationale: direct-read only; the exact nine-file manifest and
  comment-only boundary made exploratory fan-out unnecessary.
- Verification: the nine files pass `dart format` with no changes; executable
  prefixes are unchanged in the diff; accented-Latin and Portuguese-token
  comment scans return no matches; `flutter analyze` reports no issues; all 241
  `flutter test` tests pass.
- Adjacent issues parked: none.
