---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain-contracts
kind: story
stage: done
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Translate cockpit domain contracts to English

## Scope

Translate Portuguese comment prose to English in the 21 PT-bearing contract
files under `cockpit/lib/app/cockpit/domain/contracts/`:

- `app_launcher.dart`
- `dismissed_update_store.dart`
- `environment_installer.dart`
- `file_reader.dart`
- `file_searcher.dart`
- `file_system_mutator.dart`
- `file_system_reader.dart`
- `folder_lister.dart`
- `git_status_reader.dart`
- `notifier.dart`
- `project_repository.dart`
- `rpc_gateway_factory.dart`
- `rpc_process_gateway.dart`
- `self_updater.dart`
- `session_history.dart`
- `terminal_gateway.dart`
- `terminal_gateway_factory.dart`
- `update_checker.dart`
- `url_opener.dart`
- `workspace_layout_store.dart`
- `worktree_manager.dart`

Preserve every Dart declaration, type, runtime string, import, and contract
behavior. Translate each file deliberately rather than applying a blind global
replacement. Keep dartdoc references such as `[repoPath]`, code literals, error
semantics, lifecycle ownership, and `Result<T, E>` success/failure meaning
intact. Existing contract interfaces and every `Result`-returning method are
already dartdoc-covered; this story translates and quality-checks those docs
rather than adding speculative API surface.

## Acceptance criteria

- [ ] All Portuguese comment prose in the 21 listed files is idiomatic English dartdoc or English non-doc commentary.
- [ ] Contract intent, preconditions, side effects, error behavior, lifecycle notes, and `Result` semantics remain equivalent.
- [ ] No executable declaration, runtime string, import, or public signature changes.
- [ ] Every contract interface and every `Result`-returning method still has meaningful `///` documentation under `.agents/skills/documentation-conventions/SKILL.md`.
- [ ] A targeted accented-Latin grep reports no matches in the 21 files, and a manual lexical review catches unaccented Portuguese residue.
- [ ] `dart format` is run on the owned files; from `cockpit/`, `flutter analyze` and `flutter test` pass (or an exact environment failure is reported without weakening tests).

## Implementation notes

- Files changed: all 21 contract files listed in Scope under `cockpit/lib/app/cockpit/domain/contracts/`.
- Tests added: none; this was a comment-only translation and documentation-quality pass.
- Discrepancies from design: none. The story's audit found the required contract-interface and `Result` member docs already present, so no speculative member docs were added. The literal `~/.pi/agent/sessions/<cwd-codificado>/` remains unchanged despite its unaccented Portuguese placeholder because the story explicitly requires preserving code literals.
- Verification: `dart format` completed on all 21 files with no formatting changes; `flutter analyze` passed with zero issues; the full `flutter test` suite passed with 241 tests; the targeted accented-Latin grep returned no matches; executable code outside comments is byte-equivalent after whitespace normalization.
- Adjacent issues parked: none.
