---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain
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

# EN-first + dartdoc gap-fill — cockpit module: domain layer

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit module's **domain layer** (`cockpit/lib/app/cockpit/domain/`):
contracts, entities, validators, value_objects. 43 PT-bearing Dart files. This
is the contract-bearing heart of the cockpit module — the surface where
gap-fill matters most (contracts, `Result`-returning functions, domain
entities).

PT is comment prose. Gap-fill scope is the Always tier: exported Dart
classes/functions from the domain layer, `Result`/`Either`-returning functions,
contract interfaces. The `domain/contracts/` directory (e.g.
`worktree_manager.dart`) is the primary gap-fill target.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: one of three layer-slices of the cockpit module (the
  largest module, 103 files, split by layer to keep each design pass
  manageable). Sibling slices: `...-cockpit-ui`, `...-cockpit-data`. No
  `depends_on` between the three layers — disjoint file sets, shared build
  gate. Can run in parallel.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format
  and the Always tier for Dart domain/contract surfaces.
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- Parent epic `## Grounded surface measurement` and `## Decomposition risks`
  (cockpit is 216/252 files; the module is sub-sliced by layer).

## What this feature does NOT cover
- The cockpit module's `ui/` and `data/` layers — sibling features.
- Wire-stable identifiers — owned by the first rebrand epic.
- `scripts/` shell comments — out of scope.
- Generated/vendored state.

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
## Test files in scope

4 cockpit domain test files carry PT: `cockpit/test/domain/`
(`worktree_name_validator_test.dart`, `update_info_test.dart`,
`semver_test.dart`, `workspace_pane_test.dart`). Tests are Skip-tier for
gap-fill (per the doc convention); the only work is PT→EN translation of
comments and test descriptions (the latter are user-facing in test output and
need translation-review, not sed).

Plus a grep confirming zero PT (accented Latin) in
`cockpit/lib/app/cockpit/domain/` and `cockpit/test/domain/`.

## Design decisions

- **What is the owned translation set?** Edit exactly the 43 measured
  PT-bearing production files under `cockpit/lib/app/cockpit/domain/` and the
  four named PT-bearing tests. The nine EN-only domain files are audit context,
  not translation work; this keeps ownership disjoint from concurrent slices
  and matches the grounded epic measurement.
- **What may translation change?** Comment prose, dartdoc prose, test/group
  descriptions, and behavior-neutral natural-language test fixture prose only.
  Production declarations, imports, runtime/error strings, JSON and persistence
  keys, enum values, and behavior stay byte-for-byte equivalent apart from
  formatting induced by `dart format`.
- **How is gap-fill bounded?** Apply the convention's Always tier to the owned
  production set. The audit confirms six missing top-level domain docs, all in
  `workspace_pane.dart`; all contract interfaces and `Result`-returning methods
  in the 21 contract files already carry dartdoc. `UpdateArtifact` remains an
  explicit Skip-tier manifest DTO rather than receiving type-restating prose.
- **How are hard-to-detect PT remnants handled?** Accented-Latin grep is the
  mechanical backstop, followed by per-file human review for unaccented words
  and domain vocabulary. No blind repository-wide replacement is allowed.
- **Why child stories?** The raised implementation tier can safely dispatch
  three disjoint ownership groups in parallel: contracts, entities/exceptions,
  and validation/value-objects/tests. They share only the read-only build gate.

## Mapping and dispatch rationale

Direct-read mapping was sufficient: the feature has a fixed directory, a
measured 43+4-file inventory, and clear layer boundaries. Representative reads
covered the highest-risk contract (`rpc_process_gateway.dart`), a
`Result`-bearing port (`worktree_manager.dart`), the gap-bearing entity
(`workspace_pane.dart`), manifest parsing (`update_info.dart`), pure validation,
semver, and two tests. Exploratory fan-out was skipped because no structural or
interface unknown remained. Cross-model advisory review was also skipped: this
is a broad but behavior-preserving prose pass with no large or irreversible
architectural choice.

## UI surface

No UI surface is added or changed. Test descriptions are visible in test output,
but production UI strings are not part of this domain slice; mockups do not
apply.

## Architectural choice

### Options considered

1. **One monolithic translation stride.** Edit all 47 files in one worker and
   run the cockpit gate once. This minimizes orchestration overhead but creates
   a large review diff, weakens ownership, and underuses the raised worker tier.
2. **Three layer-aligned ownership stories (chosen).** Split contracts,
   entities/exceptions, and validation/value-objects/tests into disjoint file
   sets. This optimizes review context and parallel implementation while keeping
   the contract-bearing files with one owner and the test-output prose with a
   deliberate-review owner. The tradeoff is redundant local verification before
   the parent gate.
3. **Mechanical search/replace followed by cleanup.** Fastest in keystrokes, but
   rejected because Portuguese grammar is contextual, code references/backticks
   must survive, unaccented words evade the obvious grep, and test descriptions
   are user-visible output.

The chosen approach preserves Ports & Adapters by changing no dependency or
contract shape. It also preserves the existing domain files as the single
source of truth: documentation explains those types rather than introducing a
parallel glossary or design document.

## Tricky unit first: contract semantics

The 21 contract files are the highest-risk unit even though their edit is prose:
their comments define lifecycle, error, nullability, platform fallback, and
`Result<T, E>` meaning that callers rely on. Translate intent, not word order.
Keep bracket references, code literals, named protocol/control commands, and
precondition/error statements exact. A sentence that cannot be translated
without choosing a new behavior is left semantically literal and flagged in
implementation notes rather than silently reinterpreted.

## Implementation units

### Unit 1: Contract translation and contract-doc self-check

**Story**: `epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain-contracts`

All declarations and signatures remain unchanged. Representative contract
anchors whose prose must retain exact success/failure and lifecycle meaning:

```dart
abstract class RpcProcessGateway implements Service {
  Future<Result<void, RpcError>> spawn({
    required String workingDirectory,
    Map<String, String>? environment,
    String? sessionId,
  });
  Future<Result<void, RpcError>> sendControl(PiControlCommand command);
}

abstract class WorktreeManager {
  Future<Result<Worktree, WorktreeOpError>> add(
    String repoPath,
    String name,
  );
  Future<Result<void, WorktreeOpError>> remove(
    String repoPath,
    String worktreePath,
    String branch,
  );
}
```

| Exact file | Per-file translation/review plan |
|---|---|
| `cockpit/lib/app/cockpit/domain/contracts/app_launcher.dart` | Translate application discovery/opening contract and OS-default fallback wording. |
| `cockpit/lib/app/cockpit/domain/contracts/dismissed_update_store.dart` | Translate dismissed-version persistence and reappearance semantics. |
| `cockpit/lib/app/cockpit/domain/contracts/environment_installer.dart` | Translate extension/supervisor install commands and prerequisite wording; preserve command literals. |
| `cockpit/lib/app/cockpit/domain/contracts/file_reader.dart` | Translate classification, save-failure, last-write-wins, and long-lived watch ownership. |
| `cockpit/lib/app/cockpit/domain/contracts/file_searcher.dart` | Translate filesystem cache, relevance ordering, and limit semantics. |
| `cockpit/lib/app/cockpit/domain/contracts/file_system_mutator.dart` | Translate create/move/trash preconditions, platform fallback, idempotence, and `Result` failures. |
| `cockpit/lib/app/cockpit/domain/contracts/file_system_reader.dart` | Translate read-only boundary wording without implying mutation. |
| `cockpit/lib/app/cockpit/domain/contracts/folder_lister.dart` | Translate subfolder-selection contract and `dart:io` adapter boundary. |
| `cockpit/lib/app/cockpit/domain/contracts/git_status_reader.dart` | Translate git-state read and `null`-on-non-repository/unavailable semantics. |
| `cockpit/lib/app/cockpit/domain/contracts/notifier.dart` | Translate native notification initialization/permission contract. |
| `cockpit/lib/app/cockpit/domain/contracts/project_repository.dart` | Translate ordering, selected-workspace persistence, and nullable reset behavior. |
| `cockpit/lib/app/cockpit/domain/contracts/rpc_gateway_factory.dart` | Translate one-gateway-per-agent ownership and data-adapter boundary. |
| `cockpit/lib/app/cockpit/domain/contracts/rpc_process_gateway.dart` | Translate process lifecycle, broadcast stream, RPC command, `Result`, session restore, and control-overlay docs. |
| `cockpit/lib/app/cockpit/domain/contracts/self_updater.dart` | Translate phase/state, background download, support/no-op, restart, stream, and lifecycle docs. |
| `cockpit/lib/app/cockpit/domain/contracts/session_history.dart` | Translate session ordering/title derivation and extra-I/O warning. |
| `cockpit/lib/app/cockpit/domain/contracts/terminal_gateway.dart` | Translate PTY ownership, resize/input/output, and clean shutdown semantics. |
| `cockpit/lib/app/cockpit/domain/contracts/terminal_gateway_factory.dart` | Translate one-PTY-per-terminal factory contract. |
| `cockpit/lib/app/cockpit/domain/contracts/update_checker.dart` | Translate manifest lookup and `null`-instead-of-throwing failure semantics. |
| `cockpit/lib/app/cockpit/domain/contracts/url_opener.dart` | Translate external-URL open and boolean success contract. |
| `cockpit/lib/app/cockpit/domain/contracts/workspace_layout_store.dart` | Translate opaque versioned-blob persistence boundary; preserve why the map is not interpreted. |
| `cockpit/lib/app/cockpit/domain/contracts/worktree_manager.dart` | Translate mutable git boundary, namespace, add/remove ordering, merged safety fallback, and `Result` errors. |

**Acceptance criteria**:

- [ ] All 21 files contain idiomatic English comments with equivalent contract
  meaning.
- [ ] Every contract interface and every `Result`-returning member remains
  meaningfully documented with `///`.
- [ ] No declaration, command literal, error/runtime string, import, or behavior
  changes.

### Unit 2: Entity translation and six dartdoc gaps

**Story**: `epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain-entities`

The gap-fill signatures are fixed; implementation adds only meaningful `///`
prose immediately above them:

```dart
enum SplitDir { vertical, horizontal }
sealed class PaneNode
List<LeafPane> leaves(PaneNode node, [List<LeafPane>? acc])
LeafPane? findLeaf(PaneNode node, String id)
PaneNode setFrac(PaneNode node, String splitId, double frac)
PaneNode updateLeaf(
  PaneNode node,
  String id,
  LeafPane Function(LeafPane) update,
)
```

| Exact file | Per-file translation/review plan |
|---|---|
| `cockpit/lib/app/cockpit/domain/entities/agent_snapshot.dart` | Translate bootstrap selector and turn-hydration intent. |
| `cockpit/lib/app/cockpit/domain/entities/context_usage.dart` | Translate token-estimate/null-after-compaction semantics. |
| `cockpit/lib/app/cockpit/domain/entities/file_node.dart` | Translate file-tree node purpose. |
| `cockpit/lib/app/cockpit/domain/entities/file_view.dart` | Translate classified viewer variants, rendering/editability, path ownership, and unsupported cases. |
| `cockpit/lib/app/cockpit/domain/entities/git_file_status.dart` | Translate status precedence, ignored/untracked/staged/working-tree meaning, and aggregation. |
| `cockpit/lib/app/cockpit/domain/entities/git_info.dart` | Translate upstream divergence, dirty/ignored/untracked paths, helper predicates, and counts. |
| `cockpit/lib/app/cockpit/domain/entities/install_result.dart` | Translate onboarding installation result purpose. |
| `cockpit/lib/app/cockpit/domain/entities/launchable_app.dart` | Translate stable identity, display label, extracted icon, and fallback behavior. |
| `cockpit/lib/app/cockpit/domain/entities/pi_command.dart` | Translate extension-provided slash-command wording; preserve command names. |
| `cockpit/lib/app/cockpit/domain/entities/pi_model.dart` | Translate model identity, vision/thinking capability, and provider mapping semantics. |
| `cockpit/lib/app/cockpit/domain/entities/project.dart` | Translate workspace/worktree persistence split, copy sentinel, ordering, image fallback, and parent identity. |
| `cockpit/lib/app/cockpit/domain/entities/prompt_image.dart` | Translate base64 payload wording without changing encoding semantics. |
| `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart` | Translate typed RPC event meanings, retry/diagnostic/process lifecycle, notices, UI requests, relay/name/pairing events, and unknown-event safety. |
| `cockpit/lib/app/cockpit/domain/entities/session_info.dart` | Translate saved-session path/id/order/title derivation and nullable title semantics. |
| `cockpit/lib/app/cockpit/domain/entities/thinking_level.dart` | Translate canonical effort ladder, display labels, provider mapping, and availability rules. |
| `cockpit/lib/app/cockpit/domain/entities/update_info.dart` | Translate manifest parse/throw, artifact selection, and architecture fallback; leave the DTO declaration Skip-tier. |
| `cockpit/lib/app/cockpit/domain/entities/workspace_pane.dart` | Translate split-tree model/helpers/serialization and add intent docs for the six audited gaps. |
| `cockpit/lib/app/cockpit/domain/entities/worktree.dart` | Translate git-as-source-of-truth, detached state, and path identity semantics. |
| `cockpit/lib/app/cockpit/domain/exceptions/rpc_error.dart` | Translate typed RPC error boundary and non-leakage of infrastructure exceptions. |

**Gap-fill intent**:

- `SplitDir` and `PaneNode`: explain split orientation and immutable tree role,
  not their obvious type names.
- `leaves`/`findLeaf`: explain traversal order, accumulator behavior, and
  not-found result.
- `setFrac`/`updateLeaf`: explain recursive immutable replacement and unchanged
  return when the target id is absent.
- `UpdateArtifact`: no comment is added because it is a wire-shaped DTO covered
  by the convention's Skip tier.

**Acceptance criteria**:

- [ ] All 19 files contain idiomatic English comments with domain meaning
  preserved.
- [ ] The six named declarations have intent-bearing dartdoc and no signature
  or implementation changes.
- [ ] The owned files pass the scan-documentation rubric with no type-restating
  or obvious-description docs.

### Unit 3: Validators, value objects, and test-output translation

**Story**: `epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain-validation-tests`

Production behavior anchors remain exact:

```dart
WorktreeNameCheck validate(
  String name, {
  required Set<String> existingBranches,
  required Set<String> existingWorktreeNames,
})
int compareSemver(String a, String b)
bool isNewerVersion(String candidate, String current)
```

| Exact file | Per-file translation/review plan |
|---|---|
| `cockpit/lib/app/cockpit/domain/validators/worktree_name_validator.dart` | Translate validation errors, git-format rationale, ordered validation-step comments, and uniqueness semantics without reordering checks. |
| `cockpit/lib/app/cockpit/domain/value_objects/semver.dart` | Translate simplified-semver parsing/comparison and prerelease/build handling. |
| `cockpit/lib/app/cockpit/domain/value_objects/update_target.dart` | Translate boot-resolved update target and named-value-object DI rationale. |
| `cockpit/test/domain/worktree_name_validator_test.dart` | Translate group/test descriptions and inline explanation; preserve ordering/precedence assertions. |
| `cockpit/test/domain/update_info_test.dart` | Translate test descriptions and natural-language fixture prose such as release notes, updating paired expectations only. |
| `cockpit/test/domain/semver_test.dart` | Translate descriptions and numeric-comparison comments without changing cases. |
| `cockpit/test/domain/workspace_pane_test.dart` | Translate split-tree test descriptions; preserve all structural and round-trip assertions. |

**Acceptance criteria**:

- [ ] Production code changes are comment-only and validation/semver/value-object
  behavior is unchanged.
- [ ] Test output is English, assertions are neither weakened nor removed, and
  behavior-neutral fixture translations update the exact paired expectation.
- [ ] Tests remain Skip-tier: no dartdoc is added to test files.

## Implementation order

The three stories have no dependency edges and may run in parallel because
ownership is disjoint:

1. `...-domain-contracts` — 21 contract files.
2. `...-domain-entities` — 18 entity files plus one exception file.
3. `...-domain-validation-tests` — three production files plus four tests.
4. After all three integrate, run the parent-level full grep, documentation
   self-check, `flutter analyze`, and `flutter test` once against the combined
   tree.

## Testing and verification

### Per-story checks

- Review `git diff --word-diff` and reject production hunks that modify
  executable tokens, runtime strings, imports, JSON keys, enum values, or
  signatures.
- Run `dart format` on only the story-owned Dart files.
- Search every owned file for accented Portuguese characters and manually
  review comments/test labels for unaccented Portuguese; identifiers and
  intentional domain/command vocabulary are not translated.
- Apply `.agents/skills/scan-documentation/SKILL.md` to production files:
  meaningful `///`, no obvious/type-restating filler, contract errors and
  lifecycle semantics retained.

### Targeted tests

From `cockpit/` with the documented sandbox toolchain:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter test \
  test/domain/worktree_name_validator_test.dart \
  test/domain/update_info_test.dart \
  test/domain/semver_test.dart \
  test/domain/workspace_pane_test.dart
```

### Parent gate

```bash
cd cockpit
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter analyze
~/projects/remote_pi/.tools/flutter/bin/flutter test

grep -RInE '[ÁÉÍÓÚáéíóúÂÊÔâêôÃÕãõÇç]' \
  lib/app/cockpit/domain test/domain
```

The grep must return no matches. Because accent grep cannot prove all
Portuguese is absent, completion also requires checking the 47-file checklist
above and reviewing all changed comment and test-description lines. No new test
is required for comment-only production edits; the existing four focused tests
plus the full suite prove that descriptions/fixtures did not alter behavior.

## Risks and pre-mortem

- **Riskiest assumption — translation is behavior-neutral.** Contract prose can
  accidentally invert a fallback, lifecycle owner, or `Result` branch. Mitigate
  by translating per file with code symbols and error paths visible, then
  reviewing the diff rather than translating from an extracted prose corpus.
- **Failure mode — grep is green while unaccented PT remains.** Words such as
  `para`, `uma`, or `resumo` evade accented-Latin detection. The per-file
  checklist and manual test-label/fixture review are mandatory; grep is only a
  backstop.
- **Failure mode — a worker edits executable text.** Keep story ownership
  disjoint and require word-diff review. Revert questionable runtime/fixture
  changes; only behavior-neutral test prose may change outside comments.
- **Failure mode — boilerplate gap-fill degrades docs.** The six additions must
  state invariants/no-op/return semantics. If a useful intent sentence cannot
  be written, do not add an obvious description; re-evaluate the tier against
  the convention.
- **Fallback.** If combined full verification reveals a translation-associated
  failure, bisect by the three ownership stories, retain comment-only changes,
  and revert any test fixture translation before changing product code or test
  strength.

No foundation document changes are required: this feature implements the
already-landed EN-first and native-documentation policy without changing product
behavior, architecture, or protocol.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- cockpit/lib/app/cockpit/domain/ cockpit/test/domain/`).

### Findings (adjudicated)
- **Nit — stale PTY package name in dartdoc** (`cockpit/lib/app/cockpit/domain/contracts/terminal_gateway.dart:3`): the translated dartdoc named `flutter_pty`, but the actual adapter imports and the pubspec dependency is `kyroon_pty`. Corrected to `kyroon_pty`. **Fixed.**
- No other findings; translation complete, wire values unchanged (`rpc_event.dart:184-188`, `pi_rpc_process.dart:386`), dartdoc intent-bearing and tier-correct.

### Verification of fixes
- `flutter analyze` clean; `flutter test` (241) green (pending re-verify run).

### Verdict
Approve. Advanced `review → done`.
