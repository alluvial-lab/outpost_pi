---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data-filesystem
kind: story
stage: review
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate cockpit data filesystem adapters

## Scope

Translate Portuguese comment/dartdoc prose to idiomatic English in exactly
these files:

- `cockpit/lib/app/cockpit/data/filesystem/app_launcher_impl.dart`
- `cockpit/lib/app/cockpit/data/filesystem/file_reader_impl.dart`
- `cockpit/lib/app/cockpit/data/filesystem/file_searcher_impl.dart`
- `cockpit/lib/app/cockpit/data/filesystem/file_system_mutator_impl.dart`
- `cockpit/lib/app/cockpit/data/filesystem/file_system_reader_impl.dart`
- `cockpit/lib/app/cockpit/data/filesystem/folder_lister_impl.dart`
- `cockpit/lib/app/cockpit/data/filesystem/git_status_reader_impl.dart`
- `cockpit/lib/app/cockpit/data/filesystem/session_history_impl.dart`
- `cockpit/lib/app/cockpit/data/filesystem/worktree_manager_impl.dart`

Preserve platform fallbacks, executable candidates, file classification,
bounded search/cache/ranking, Finder Trash and AppleScript behavior, hidden/VCS
filters, git porcelain parsing, session-path encoding, and worktree add/remove
ordering. Production changes are comment-only; domain ports remain the source
of truth for public method and `Result` contracts.

`folder_lister_impl.dart` contains ASCII-only Portuguese missed by the original
accent baseline and is deliberately included. The private `_Candidate`,
`_WinCandidate`, `_LinuxCandidate`, `_Cache`, and `_Ranked` helpers are
Skip-tier; do not add obvious-description dartdoc to them.

## Acceptance criteria

- [ ] All nine files contain natural English prose with platform, error, and
      lifecycle meaning unchanged.
- [ ] Public adapter classes retain meaningful adapter-specific `///` docs;
      inherited override contracts are not duplicated.
- [ ] Paths, commands, AppleScript, runtime errors, storage/wire values,
      signatures, and behavior are unchanged.
- [ ] Normal and word-diff review shows production edits are comment-only.
- [ ] Touched Dart files are formatted and the integrated feature can pass
      `flutter analyze` and `flutter test` from `cockpit/`.

## Implementation notes

- Files changed: all nine scoped adapters under
  `cockpit/lib/app/cockpit/data/filesystem/`.
- Tests added: none; production changes are documentation-only.
- Verification: touched files formatted; `flutter analyze` passed with zero
  issues; full `flutter test` passed (241 tests); accented-Portuguese grep
  returned no matches in the owned directory; normal and word-diff review
  confirmed executable code, runtime strings, commands, paths, and signatures
  are unchanged.
- Discrepancies from design: none. The Always-tier audit matched the feature
  design: each public adapter already had adapter-specific class dartdoc, so the
  work translated and clarified those docs without duplicating inherited port
  contracts. Private candidate/cache/ranking helpers remained undocumented.
- Adjacent issues parked: none.
