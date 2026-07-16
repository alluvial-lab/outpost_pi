---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data-tests
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

# Translate cockpit data test output and comments

## Scope

Translate Portuguese comments and human-facing test-runner prose in exactly
these files:

- `cockpit/test/data/git_status_reader_impl_test.dart`
- `cockpit/test/data/lsp_server_pool_test.dart`
- `cockpit/test/data/file_reader_impl_test.dart`
- `cockpit/test/data/lsp_formatter_test.dart`
- `cockpit/test/data/lsp_text_edit_test.dart`
- `cockpit/test/data/lsp_root_and_offsets_test.dart`
- `cockpit/test/data/file_system_mutator_impl_test.dart`
- `cockpit/test/data/worktree_manager_impl_test.dart`
- `cockpit/test/data/auto_updater_self_updater_test.dart`
- `cockpit/test/data/lsp_codec_test.dart`

Translate `group`/`test` descriptions, skip messages, assertion `reason` text,
and explanatory comments. Preserve fixtures, setup, actions, assertions,
timing, commands, JSON, offsets, and filesystem/branch names. In particular,
keep `café` and `olá 世界 🚀` unchanged because they are intentional multibyte
UTF-8 fixtures, not prose to normalize. Tests are Skip-tier for dartdoc.

## Acceptance criteria

- [ ] Test descriptions, skip/reason output, and explanatory comments are
      natural English in all ten files.
- [ ] Fixtures, actions, assertions, timing, and coverage are unchanged; no test
      is removed, skipped more broadly, or weakened.
- [ ] No dartdoc gap-fill is added to test helpers.
- [ ] Touched Dart files are formatted.
- [ ] All ten focused test files pass together using the repository Flutter
      binary and writable `PUB_CACHE` documented by the feature.
- [ ] The integrated feature can pass full `flutter analyze` and `flutter test`
      from `cockpit/`.

## Implementation notes

- Files changed: the ten scoped files under `cockpit/test/data/` listed above.
- Tests added: none; this story changes test-runner prose and comments only.
- Delivery mode: direct-read only. The fixed ten-file manifest and translation-only boundary made exploratory fan-out unnecessary.
- Verification: repository Dart formatter completed for all ten files; the focused ten-file Flutter run passed (66 tests); full `flutter analyze` passed with zero issues; full `flutter test` passed (241 tests); `git diff --check` passed.
- Language review: all test descriptions, skip messages, assertion reasons, and explanatory comments are natural English. Manual ASCII-token review found only preserved fixture data such as `novo`, `conteudo`, and `nao/existe`.
- Discrepancies from design: the literal accent grep cannot have zero matches while preserving the explicitly exempt `café` and `olá 世界 🚀` UTF-8 fixtures; its four matches are only those required fixture lines. No Portuguese prose remains.
- Adjacent issues parked: none.
