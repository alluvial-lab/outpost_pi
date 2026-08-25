---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data
kind: feature
stage: done
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# EN-first + dartdoc gap-fill — cockpit module: data layer

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit module's **data layer** (`cockpit/lib/app/cockpit/data/`):
adapters, filesystem, notifications, repositories, rpc, setup, terminal.
21 PT-bearing Dart files. This layer holds the infrastructure adapters
(ports-and-adapters edge) — repository implementations, RPC clients, terminal
PTY, filesystem access.

PT is comment prose. Gap-fill scope is the Always tier: service-layer
functions, adapter classes with non-obvious contracts, `Result`-returning
functions. Repository implementations that merely satisfy a domain contract
are Skip tier for gap-fill (the contract is documented at the port, not the
adapter) — the design pass should distinguish adapter-specific behavior worth
documenting from contract restatement.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: one of three layer-slices of the cockpit module. Sibling
  slices: `...-cockpit-domain`, `...-cockpit-cockpit-ui`. No `depends_on`
  between the three layers — disjoint file sets, shared build gate. Can run
  in parallel.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format;
  Always tier (service-layer functions) vs Skip tier (DTOs/contract
  restatement).
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- `.agents/rules/code-design.md` — Ports and Adapters; the data layer is the
  adapter edge, so document adapter-specific behavior, not the port contract.

## What this feature does NOT cover
- The cockpit module's `domain/` and `ui/` layers — sibling features.
- Wire-stable identifiers — owned by the first rebrand epic.
- `scripts/` shell comments — out of scope.
- Generated/vendored state.

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
## Test files in scope

10 cockpit data test files carry PT: `cockpit/test/data/`
(`git_status_reader_impl_test.dart`, `lsp_server_pool_test.dart`,
`file_reader_impl_test.dart`, `lsp_formatter_test.dart`,
`lsp_text_edit_test.dart`, `lsp_root_and_offsets_test.dart`,
`file_system_mutator_impl_test.dart`, `worktree_manager_impl_test.dart`,
`auto_updater_self_updater_test.dart`, `lsp_codec_test.dart`). Tests are
Skip-tier for gap-fill (per the doc convention); the only work is PT→EN
translation of comments and test descriptions (the latter are user-facing in
test output and need translation-review, not sed).

Plus a grep confirming zero PT (accented Latin) in
`cockpit/lib/app/cockpit/data/` and `cockpit/test/data/`.

## Design decisions

- **What is the real translation boundary?**: Own the complete
  `cockpit/lib/app/cockpit/data/` directory, not only the 21 files found by the
  accented-Latin baseline. Direct inspection found four additional files with
  unaccented Portuguese prose: `folder_lister_impl.dart`,
  `hive_workspace_layout_store.dart`, `pty_terminal_gateway_factory.dart`, and
  `url_opener_impl.dart`. The implementation manifest is therefore 25
  production files plus the 10 already-named tests. This is consistent with the
  EN-first goal and does not cross the feature boundary.
- **What may translation change?**: Production edits are comment/dartdoc only.
  In tests, translate comments plus human-facing `group`/`test`/`reason`/skip
  messages, but preserve fixture data such as `café`, `olá 世界 🚀`, path names,
  JSON, commands, identifiers, and expected values when those values exercise
  Unicode, filesystem, or protocol behavior.
- **Where does the adapter contract live?**: Domain ports remain the source of
  truth for method contracts. Do not duplicate their prose on every `@override`;
  retain and translate class-level adapter docs only where they explain
  platform behavior, lifecycle, wire parsing, persistence, or failure mapping
  specific to the implementation.
- **What does the dartdoc gap audit require?**: No new Always-tier docs are
  needed in this slice. All 25 public adapter/service classes already have
  meaningful class-level `///` docs, while `Result`-returning overrides inherit
  documented domain-port contracts. The five syntax-level undocumented helper
  classes (`_Candidate`, `_WinCandidate`, `_LinuxCandidate`, `_Cache`,
  `_Ranked`) are private/trivial and Skip-tier. The public
  `schemaControlPromptForTesting` forwarder is a test-only seam and also
  Skip-tier. Implementation must re-run this audit after translation rather
  than adding type-restating filler.
- **How is implementation parallelized?**: Use four disjoint ownership stories:
  runtime/RPC adapters, filesystem adapters, persistence/update adapters, and
  test-output prose. They have no dependency edges and can use the raised
  worker tier in parallel; only the integrated cockpit gate is shared.

## Mapping and dispatch rationale

Direct-read mapping was sufficient. The boundary is one fixed adapter layer,
all source and test paths are known, and representative reads covered the
highest-risk process lifecycle, RPC decoding, PTY environment, filesystem
`Result` mapping, git/worktree behavior, Hive persistence, updater lifecycle,
and test fixtures. Exploratory fan-out would duplicate this bounded evidence.
Cross-model advisory review was skipped because the choices are reversible,
behavior-preserving documentation boundaries rather than large or risky
architecture decisions.

## UI alignment

No UI surface is introduced or redesigned. Test descriptions only affect test
runner output; no production copy, layout, component, or flow changes, so
feature-level fallback mockups do not apply.

## Architectural choice

### Options considered

1. **Translate only the 21 accent-bearing production files.** This follows the
   original mechanical measurement but knowingly leaves four Portuguese docs
   behind because ASCII-only prose evades the detector.
2. **One monolithic 35-file pass.** This guarantees one owner but produces a
   large mixed diff spanning process lifecycle, filesystem, persistence, update
   adapters, and tests.
3. **Manifest-driven four-story pass (chosen).** Translate all 25 production
   files and 10 tests with disjoint ownership by adapter concern, then run one
   integrated language/doc/build gate. This optimizes reviewability and uses the
   raised implementation tier without changing module boundaries.

The chosen design preserves Ports & Adapters: domain contracts remain canonical,
data-layer comments describe only adapter-specific behavior, and no executable
contract, persistence shape, or wire value changes.

## Tricky unit first: runtime and RPC semantics

The runtime/RPC unit is the riskiest prose surface. Its comments encode process
ownership, orphan cleanup, stdin request serialization, timeout/error mapping,
typed wire decoding, PTY capability overrides, and updater-independent setup
behavior. Translate with the implementation visible; preserve code references,
command names, environment variables, lifecycle ordering, and the distinction
between returned `Result` failures and thrown private `_request` errors.

## Implementation units

### Unit 1: Runtime, RPC, terminal, setup, and notification adapters

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data-runtime-adapters`

Representative signatures remain unchanged:

```dart
class RpcEventMapper {
  RpcEvent fromJson(Map<String, dynamic> json);
}

class PiRpcProcess implements RpcProcessGateway {
  Future<Result<void, RpcError>> spawn({
    required String workingDirectory,
    Map<String, String>? environment,
    String? sessionId,
  });
  Future<Result<void, RpcError>> sendControl(PiControlCommand command);
}

class PtyTerminalGateway implements TerminalGateway {
  void start({required String workingDirectory, int rows = 25, int columns = 80});
  Future<void> kill();
}
```

| Exact file | Per-file translation/review plan |
|---|---|
| `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart` | Translate request/response payload ownership, compatibility projection, and canonical transcript-event mapping; preserve wire keys and event IDs. |
| `cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart` | Translate typed-boundary, unknown-event, custom-message, UI-request, and safe-coercion prose; preserve event discriminators and fallback behavior. |
| `cockpit/lib/app/cockpit/data/rpc/pi_process_registry.dart` | Translate PID registry/PPID scan/orphan cleanup lifecycle and signal rationale; preserve process names, paths, and cleanup order. |
| `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart` | Translate process ownership, serialized stdin, response correlation, timeout/error, graceful kill, and pending-request cleanup prose; preserve commands and `Result` behavior. |
| `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process_factory.dart` | Translate one-process-per-agent factory intent. |
| `cockpit/lib/app/cockpit/data/terminal/pty_terminal_gateway.dart` | Translate PTY lifecycle, shell selection, login-shell PATH rationale, and `TERM`/`COLORTERM` capability docs; preserve environment values and platform branches. |
| `cockpit/lib/app/cockpit/data/terminal/pty_terminal_gateway_factory.dart` | Translate one-gateway-per-terminal factory intent (ASCII-only PT discovered during design). |
| `cockpit/lib/app/cockpit/data/setup/environment_installer_impl.dart` | Translate best-effort install and truncated error-output prose; preserve executable arguments and runtime error strings. |
| `cockpit/lib/app/cockpit/data/notifications/local_notifier.dart` | Translate foreground native-notification initialization rationale; preserve plugin settings and payloads. |

**Acceptance criteria**:

- [ ] All nine files contain idiomatic EN comments/dartdoc with lifecycle and
      boundary meaning unchanged.
- [ ] RPC discriminators, JSON keys, command strings, environment variables,
      process arguments, and error behavior are unchanged.
- [ ] Existing adapter class docs remain meaningful; no inherited port contract
      is redundantly copied onto overrides.

### Unit 2: Filesystem and git/worktree adapters

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data-filesystem`

Representative signatures remain unchanged:

```dart
class FileSystemMutatorImpl implements FileSystemMutator {
  Future<Result<void, String>> createFile(String path);
  Future<Result<void, String>> moveToTrash(String path);
}

class WorktreeManagerImpl implements WorktreeManager {
  Future<Result<Worktree, WorktreeOpError>> add(String repoPath, String name);
  Future<Result<void, WorktreeOpError>> remove(
    String repoPath,
    String worktreePath,
    String branch,
  );
}
```

| Exact file | Per-file translation/review plan |
|---|---|
| `cockpit/lib/app/cockpit/data/filesystem/app_launcher_impl.dart` | Translate OS candidate ordering, executable discovery, default-app fallback, icon extraction/cache, and detached-launch prose; preserve paths and commands. |
| `cockpit/lib/app/cockpit/data/filesystem/file_reader_impl.dart` | Translate file classification, size/UTF-8/binary heuristics, SVG handling, write/watch behavior, and silent stream-end rationale. |
| `cockpit/lib/app/cockpit/data/filesystem/file_searcher_impl.dart` | Translate bounded walk, ignored-directory, TTL cache, ranking, and permission-failure prose; keep private cache/ranking helpers undocumented. |
| `cockpit/lib/app/cockpit/data/filesystem/file_system_mutator_impl.dart` | Translate Finder Trash vs permanent-delete behavior, idempotence, test switch, and AppleScript escaping; preserve all `Result` branches/messages. |
| `cockpit/lib/app/cockpit/data/filesystem/file_system_reader_impl.dart` | Translate folders-first ordering, hidden-file policy, and VCS exclusion semantics. |
| `cockpit/lib/app/cockpit/data/filesystem/folder_lister_impl.dart` | Translate hidden-subfolder filtering intent (ASCII-only PT discovered during design). |
| `cockpit/lib/app/cockpit/data/filesystem/git_status_reader_impl.dart` | Translate executable resolution, porcelain `-z` parsing, rename/copy handling, collapsed ignored/untracked roots, status precedence, and ahead/behind prose. |
| `cockpit/lib/app/cockpit/data/filesystem/session_history_impl.dart` | Translate Pi session-path encoding, first-user-message title extraction, corrupt-file fallback, and cross-platform separators. |
| `cockpit/lib/app/cockpit/data/filesystem/worktree_manager_impl.dart` | Translate git discovery, branch/worktree add-remove ordering, native-path return, merged safety fallback, and porcelain parsing. |

**Acceptance criteria**:

- [ ] All nine files contain natural EN prose with platform and failure
      semantics preserved.
- [ ] Commands, filesystem paths, executable candidates, AppleScript, runtime
      errors, branch logic, and `Result` behavior are unchanged.
- [ ] The five private candidate/cache/ranking declarations remain Skip-tier,
      avoiding obvious-description dartdoc.

### Unit 3: Repositories and update adapters

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data-persistence-update`

Representative signatures remain unchanged:

```dart
class HiveWorkspaceLayoutStore implements WorkspaceLayoutStore {
  Future<Map<String, dynamic>?> load(String projectId);
  Future<void> save(String projectId, Map<String, dynamic> document);
}

class AutoUpdaterSelfUpdater with UpdaterListener implements SelfUpdater {
  Future<void> initialize();
  Future<void> checkForUpdates({bool inBackground = true});
  Future<void> applyDownloadedUpdate();
  void dispose();
}
```

| Exact file | Per-file translation/review plan |
|---|---|
| `cockpit/lib/app/cockpit/data/repositories/hive_dismissed_update_store.dart` | Translate the single-key dismissed-version persistence behavior; do not restate the port methods. |
| `cockpit/lib/app/cockpit/data/repositories/hive_project_repository.dart` | Translate primitive-map persistence, reserved selected-project key, manual ordering fallback, and legacy-data defaults; preserve Hive keys/shapes. |
| `cockpit/lib/app/cockpit/data/repositories/hive_workspace_layout_store.dart` | Translate JSON-string storage/cast/corruption fallback rationale (ASCII-only PT discovered during design); preserve box name and blob shape. |
| `cockpit/lib/app/cockpit/data/update/auto_updater_self_updater.dart` | Translate Sparkle/WinSparkle state mapping, silent scheduled checks, downloaded-update apply/restart lifecycle, and native-UI limitation. |
| `cockpit/lib/app/cockpit/data/update/noop_self_updater.dart` | Translate unsupported-platform no-op/manual-download behavior. |
| `cockpit/lib/app/cockpit/data/update/update_checker_impl.dart` | Translate short-timeout manifest fetch and null-on-network/HTTP/JSON/schema failure behavior; preserve URL and parser branches. |
| `cockpit/lib/app/cockpit/data/update/url_opener_impl.dart` | Translate external-handler adapter intent (ASCII-only PT discovered during design); preserve URI validation and boolean failure behavior. |

**Acceptance criteria**:

- [ ] All seven files contain idiomatic EN adapter prose.
- [ ] Hive keys, stored JSON shape, update phases, appcast URLs, plugin calls,
      timeout values, and failure behavior are unchanged.
- [ ] Repository overrides receive no contract-restating comments; their
      translated class docs retain only adapter-specific persistence details.

### Unit 4: Test descriptions and comment prose

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data-tests`

The test structure remains unchanged:

```dart
group('English behavior description', () {
  test('English expected behavior', () async {
    // Existing setup, action, and assertions remain behaviorally identical.
  });
});
```

| Exact file | Per-file translation/review plan |
|---|---|
| `cockpit/test/data/git_status_reader_impl_test.dart` | Translate test/skip/reason/comment prose for clean, dirty, spaced, collapsed, ignored, and ahead/behind cases; preserve git setup and path fixtures. |
| `cockpit/test/data/lsp_server_pool_test.dart` | Translate fake-client docs and open/restart/status descriptions; preserve lifecycle assertions. |
| `cockpit/test/data/file_reader_impl_test.dart` | Translate A/V/image/SVG/text/read-write descriptions and reasons; preserve extension matrices and nonexistent-path setup. |
| `cockpit/test/data/lsp_formatter_test.dart` | Translate placeholder/empty-command/success/failure descriptions and comments; preserve commands and exit-code expectations. |
| `cockpit/test/data/lsp_text_edit_test.dart` | Translate parse/range/multiline/clamp descriptions and comments; preserve edit offsets/text fixtures. |
| `cockpit/test/data/lsp_root_and_offsets_test.dart` | Translate offset/root-selection descriptions and comments; preserve code-unit, marker, and filesystem fixtures. |
| `cockpit/test/data/file_system_mutator_impl_test.dart` | Translate create/rename/trash descriptions and comments; preserve fixture paths and assertions. |
| `cockpit/test/data/worktree_manager_impl_test.dart` | Translate skip/test/comment prose for add/list/remove/merged behavior; preserve branch/path fixtures and git commands. |
| `cockpit/test/data/auto_updater_self_updater_test.dart` | Translate updater-state descriptions and comments; preserve emitted states and plugin-test setup. |
| `cockpit/test/data/lsp_codec_test.dart` | Translate framing/fragmentation/invalid-JSON descriptions and comments; preserve `café`/`olá 世界 🚀` multibyte fixtures exactly. |

**Acceptance criteria**:

- [ ] All test-runner descriptions, skip/reason messages, and explanatory
      comments in the ten files are English.
- [ ] Test fixtures, actions, assertions, timing, and coverage are unchanged;
      tests are neither weakened nor given dartdoc gap-fill.
- [ ] The ten focused test files pass together before the integrated suite.

## Implementation order

The four stories all have `depends_on: []` and disjoint write ownership, so the
raised-tier orchestrator may run them in parallel:

1. `...-data-runtime-adapters` — nine runtime/RPC/terminal/setup/notification files.
2. `...-data-filesystem` — nine filesystem/git/worktree files.
3. `...-data-persistence-update` — seven repository/update files.
4. `...-data-tests` — ten test files.
5. After integration, run the complete translation/doc self-check and cockpit
   analyze/test gate once on the combined tree.

## Testing and verification

### Per-story structural checks

- Review normal and `git diff --word-diff` output. Reject production changes to
  imports, identifiers, signatures, control flow, runtime strings, constants,
  commands, storage/wire keys, or platform branches.
- Format only touched Dart files using the repository Dart/Flutter toolchain.
- Apply `.agents/skills/scan-documentation/SKILL.md`: every public adapter class
  retains meaningful EN `///`; private helpers, test files, test-only seams,
  and inherited adapter overrides remain Skip-tier.
- Run both an accented-Latin scan and a Portuguese-token/manual review over all
  35 manifest files. A green accent grep alone is insufficient.

### Focused test gate

From `cockpit/`:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter test \
  test/data/git_status_reader_impl_test.dart \
  test/data/lsp_server_pool_test.dart \
  test/data/file_reader_impl_test.dart \
  test/data/lsp_formatter_test.dart \
  test/data/lsp_text_edit_test.dart \
  test/data/lsp_root_and_offsets_test.dart \
  test/data/file_system_mutator_impl_test.dart \
  test/data/worktree_manager_impl_test.dart \
  test/data/auto_updater_self_updater_test.dart \
  test/data/lsp_codec_test.dart
```

### Integrated parent gate

```bash
cd cockpit
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter analyze
~/projects/remote_pi/.tools/flutter/bin/flutter test

grep -RInE '[À-ÖØ-öø-ÿ]' lib/app/cockpit/data test/data
```

The grep must return no matches, followed by a manual/ASCII-token review of all
25 production files and ten tests. Intentional multibyte fixture payloads in
`lsp_codec_test.dart` are explicitly exempt from the language scan and must not
be “fixed.” No new behavioral test is required for production comment-only
changes; the focused ten-file run plus the full suite prove that test-label
translation did not alter behavior.

## Risks and pre-mortem

- **Riskiest assumption — language detection equals accent detection.** It
  already failed on four production files. The 25+10 manifest and manual
  ASCII-token review are the fallback and completion criterion.
- **Failure mode — lifecycle/contract prose changes meaning.** Translate with
  code visible and preserve ownership, ordering, null/error, platform-fallback,
  and `Result` semantics rather than translating isolated sentences.
- **Failure mode — fixture translation weakens tests.** Keep Unicode payloads,
  path/branch names, commands, JSON, and expected values intact; only runner
  labels, skip/reason messages, and explanatory comments are prose.
- **Failure mode — dartdoc gap-fill becomes duplicate noise.** The audit is
  intentionally empty: adapter class docs already cover infrastructure-specific
  intent, while domain ports own method contracts. Re-open the tier decision if
  implementation finds a genuinely public adapter-specific service seam, but do
  not document private/trivial helpers or overrides by syntax alone.
- **Failure mode — parallel diffs hide executable edits.** Ownership is
  disjoint; each story performs word-diff review, and the orchestrator runs the
  integrated formatter/analyze/test gate.
- **Fallback.** If verification fails, isolate by story, retain comment-only
  changes, and revert any test-output/fixture hunk before changing product code
  or test strength.

No foundation document update is required: this feature applies the already
landed EN-first/native-dartdoc policy without changing product behavior,
architecture, protocol, or persistence.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- cockpit/lib/app/cockpit/data/ cockpit/test/data/`).

### Findings (adjudicated)
- **Important — "diff not comments-only" — REJECTED (diff-range confounding).** The reviewer flagged `update_checker_impl.dart` (manifestUrl nullable), `rpc_event_mapper.dart:189`, `app_launcher_impl.dart:242`, `local_notifier.dart:25,38` as non-comments-only changes contradicting the feature's comments-only contract. Verified against per-commit history: the `manifestUrl` nullable behavior change came from commit `f90a74e` (the **retire-rp-s3** feature's `runtime-update-noop` story — already reviewed and done in the external-surfaces batch), NOT from the cockpit-data EN-first feature. The cockpit-data feature's commit `76877c9` touched the same file but only for PT→EN comment/dartdoc translation. The reviewer itself flagged this possibility ("either provide a feature-only baseline excluding sibling commit `f90a74e`..."). The integrated diff range `376fa38..HEAD` conflates sibling features; per-commit attribution confirms the cockpit-data feature's changes are comments-only as claimed. **No fix required.**
- No other findings; translation complete (only intentional `café`/`olá 世界 🚀` UTF-8 fixtures remain), wire values unchanged, dartdoc tier-correct.

### Verification
- `flutter analyze` clean; `flutter test` (241) green (reproduced by reviewer and re-verified).

### Verdict
Approve. Advanced `review → done`.
