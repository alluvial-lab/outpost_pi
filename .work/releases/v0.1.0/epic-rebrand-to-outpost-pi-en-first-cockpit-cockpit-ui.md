---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui
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

# EN-first + dartdoc gap-fill — cockpit module: UI layer

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit module's **UI layer** (`cockpit/lib/app/cockpit/ui/`):
viewmodels, widgets, session, states. 38 PT-bearing Dart files. This layer
holds the user-facing widgets and viewmodels — the slice most likely to
contain user-facing PT string literals (button labels, tooltips, error
messages) that need translation-review, not mechanical sed.

PT is predominantly comment prose, but the design pass must identify and
review any user-facing string literals (the cockpit-wide count is ~18 PT
string literals; a subset live in this layer). Gap-fill scope is the Always
tier: ViewModel exports, exported widgets with non-obvious contracts. Per the
doc convention, exported Flutter widgets with 3+ params are Recommended
(should have a doc comment), not Always.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: one of three layer-slices of the cockpit module. Sibling
  slices: `...-cockpit-domain`, `...-cockpit-data`. No `depends_on` between
  the three layers — disjoint file sets, shared build gate. Can run in
  parallel.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format;
  Always tier (ViewModel exports) vs Recommended tier (exported widgets with
  3+ params).
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- Parent epic `## Decomposition risks` — "user-visible UI text needs review,
  not just mechanical translation" applies most directly to this slice.

## What this feature does NOT cover
- The cockpit module's `domain/` and `data/` layers — sibling features.
- Wire-stable identifiers — owned by the first rebrand epic.
- `scripts/` shell comments — out of scope.
- Generated/vendored state.

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
## Test files in scope

1 cockpit UI test file carries PT: `cockpit/test/ui/terminal_input_test.dart`
(PT in both comments and test descriptions like `test('começa inativo', ...)`
— the latter are user-facing in test output and need translation-review, not
sed). Tests are Skip-tier for gap-fill (per the doc convention).

Plus a grep confirming zero PT (accented Latin) in
`cockpit/lib/app/cockpit/ui/` and `cockpit/test/ui/`.

## Design decisions

- **Does gap-fill cover only the 38 PT-bearing files?** No. Translation owns the
  38 measured files, while the documentation audit covers all 43 Dart files in
  `cockpit/lib/app/cockpit/ui/`. The five EN-only files can still contain an
  undocumented Always/Recommended-tier export.
- **Does the ~95-undocumented baseline mean “document all 95”?** No. It is a
  candidate baseline, not a requirement. Apply the convention's intent tiers:
  document ViewModel/controller/service contracts and non-obvious exported
  widgets with 3+ constructor parameters; skip DTO-shaped declarations,
  overrides, barrels, tests, private helpers, and trivial getters/fields.
  This prevents obvious-description noise.
- **How are translations applied safely?** Comment-only files may use bounded
  exact replacements inside comment tokens, followed by per-file diff review.
  Never run a global prose replacement across Dart source. Natural-language
  string literals and test descriptions/fixture prose are reviewed one by one;
  identifiers, commands, paths, escape sequences, and protocol/domain terms
  remain unchanged.
- **What user-visible PT was found in the UI source?** The source-string audit
  found one obvious PT placeholder in
  `widgets/worktree_create_dialog.dart`. The test has 14 PT test descriptions
  plus PT fixture prose and inline comments. Implementers must still inspect all
  changed literal lines because accented-character grep cannot find unaccented
  PT.
- **How should implementation fan out?** Use three independent, path-owned
  stories with no sibling dependencies. This gives raised-tier workers
  non-overlapping write ownership; each story performs local checks, and the
  integrated feature runs the full cockpit gate once all three land.
- **Are UI mockups required?** No. This is copy/comment/documentation work on
  existing surfaces with no layout, component, interaction, or visual change;
  it is a SKIP case under the UX/UI decision matrix.

## Architectural choice

Three approaches were considered:

1. **One blanket translation sweep.** Lowest coordination cost, but a global
   replacement can modify user-visible strings, fixture payloads, commands, or
   identifiers without semantic review and leaves no practical review boundary
   across 43 files.
2. **Three path-owned, token-aware shards (chosen).** Each worker translates
   comment tokens, reviews literals separately, and applies the same tiered
   dartdoc audit to its owned files. This optimizes parallelism and reviewability
   while preserving APIs and behavior.
3. **Introduce localization/code generation.** This would centralize UI copy,
   but it changes runtime architecture and is disproportionate to an EN-first
   hard cutover with a tiny remaining PT literal surface.

No module boundary, public signature, runtime behavior, persistence shape, or
wire contract changes. Existing `ui -> domain <- data` dependencies remain
untouched.

## Translation inventory and per-file plan

The local probe found 936 accented-PT-bearing lines across the 38 translation
files. `C` means comment/dartdoc translation only; `R` means a literal/test
surface requires individual review in addition to comments. Counts are the
accent-bearing-line baseline, not an edit quota.

### State, session, and ViewModels — story
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-state-session-viewmodels`

- `cockpit_page.dart` — C (45)
- `session/agent_entry.dart` — C (4)
- `session/agent_session.dart` — C (56)
- `session/file_viewer_session.dart` — C (13)
- `session/pane_item.dart` — C (1)
- `session/terminal_input.dart` — C (20)
- `session/terminal_session.dart` — C (14)
- `viewmodels/cockpit_viewmodel.dart` — C (164)
- `viewmodels/setup_viewmodel.dart` — C (9)
- `viewmodels/update_viewmodel.dart` — C (19)
- Gap-audit only (already EN): `session/agent_process_controller.dart`,
  `states/pane_node.dart`, `viewmodels/workspace_projection.dart`

### Terminal, transcript, and editor widgets — story
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-terminal-transcript-widgets`

- `widgets/agent_composer.dart` — C (66)
- `widgets/agent_markdown.dart` — C (10)
- `widgets/agent_setup_checklist.dart` — C (15)
- `widgets/agent_transcript.dart` — C (36)
- `widgets/cockpit_terminal.dart` — C (11)
- `widgets/cockpit_terminal_gesture.dart` — C (15)
- `widgets/cockpit_terminal_painter.dart` — C (24)
- `widgets/cockpit_terminal_render.dart` — C (23)
- `widgets/code_editor.dart` — C (27)
- `widgets/file_viewer.dart` — C (74)
- `widgets/media_view.dart` — C (12)
- `widgets/terminal_link.dart` — C (14)
- `widgets/terminal_pane.dart` — C (69)
- `cockpit/test/ui/terminal_input_test.dart` — R: comments, all 14 test
  descriptions, and natural-language fixture chunks; preserve CSI/ESC bytes and
  assertions exactly

### Workspace, navigation, and dialogs — story
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-workspace-navigation-review`

- `widgets/agent_edit_dialog.dart` — C (1)
- `widgets/cockpit_topbar.dart` — C (8)
- `widgets/confirm_dialog.dart` — C (6)
- `widgets/empty_pane.dart` — C (2)
- `widgets/file_tree_panel.dart` — C (41)
- `widgets/history_dialog.dart` — C (1)
- `widgets/model_picker.dart` — C (1)
- `widgets/pane_divider.dart` — C (3)
- `widgets/pane_view.dart` — C (68)
- `widgets/projects_rail.dart` — C (41)
- `widgets/subfolder_dialog.dart` — C (4)
- `widgets/welcome_view.dart` — C (4)
- `widgets/workspace_avatar.dart` — C (6)
- `widgets/workspace_settings_dialog.dart` — C (3)
- `widgets/worktree_create_dialog.dart` — R (6): review the branch-name
  placeholder separately from comment prose
- Gap-audit only (already EN): `widgets/update_card.dart`,
  `widgets/widgets.dart` (barrel remains Skip-tier)

## Implementation Units

### Unit 1: State/session/ViewModel contracts

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-state-session-viewmodels`

The public signatures are frozen. The audit centers on these existing
contract-bearing exports:

```dart
class CockpitViewModel extends ChangeNotifier
class SetupViewModel extends ChangeNotifier
class UpdateViewModel extends ChangeNotifier
final class AgentProcessController
final class WorkspaceProjection
class AgentSession extends PaneItem
```

**Implementation notes**:

- Translate the existing ViewModel/class/member docs to EN without changing
  lifecycle, persistence, workspace-command, or error semantics.
- Gap-fill missing intent docs on public behavior surfaces, especially:
  `AgentProcessController.boot/send/stop/killForRestart/dispose`, its
  `Result`-returning RPC methods, `WorkspaceProjection` realize/create/save/
  dispose operations, `AgentSession` public actions, the three setup recheck
  actions, and non-obvious `CockpitViewModel` mutation/lifecycle actions such as
  `init`, project/tab/pane removal, focus/selection, resize, and visibility
  toggles.
- Do not add docs merely to restate DTO fields, constructor parameters, trivial
  projection getters, or Flutter overrides. `AgentSessionBootRequest`,
  `AgentPrompt`, and tests remain Skip-tier unless an actual non-obvious
  contract is found.
- Existing EN docs in gap-audit-only files are retained unless missing or
  inadequate; this is not a prose rewrite.

**Acceptance criteria**:

- [ ] All 10 PT-bearing files in this unit contain EN-only comments/docs.
- [ ] Every Always-tier ViewModel/controller/service export in the 13 owned
      files has meaningful `///` intent/contract documentation.
- [ ] No public signature, body behavior, imports, or lifecycle ownership
      changes.
- [ ] Skip-tier omissions are intentional and explainable from the convention.

### Unit 2: Terminal/transcript/editor widgets and terminal test

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-terminal-transcript-widgets`

These existing Recommended-tier widget signatures remain unchanged:

```dart
class AgentTranscript extends StatelessWidget
class CockpitTerminal extends StatefulWidget
class CockpitTerminalGestureHandler extends StatefulWidget
class CockpitTerminalState extends State<CockpitTerminal>
class CockpitTerminalRender extends RenderBox
```

**Implementation notes**:

- Preserve the xterm-fork rationale, cache/lifecycle constraints, selection
  ownership, async mounted guards, and file/editor semantics while translating.
- Add missing purpose/contract dartdoc to `AgentTranscript`,
  `CockpitTerminal`, and `CockpitTerminalGestureHandler` (all exported widgets
  with 3+ parameters). Also document the non-obvious exported terminal state/
  render boundary where the class-level contract is currently only a regular
  file comment; do not copy every upstream parameter description into noise.
- In `terminal_input_test.dart`, translate test-output descriptions and fixture
  prose deliberately. Keep test grouping, terminal escape sequences, event
  flags, expectations, and coverage identical. Tests receive no dartdoc.

**Acceptance criteria**:

- [ ] All 13 owned lib files and the test contain EN-only comments and
      natural-language strings.
- [ ] The three missing Recommended-tier widget class docs are meaningful EN
      dartdoc, and terminal fork boundaries retain their non-obvious rationale.
- [ ] All 14 test cases remain present with unchanged assertions and escape
      sequences.
- [ ] No widget constructor, rendering behavior, or lifecycle path changes.

### Unit 3: Workspace/navigation/dialog widgets and literal review

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-workspace-navigation-review`

Representative exported surfaces remain signature-identical:

```dart
class CockpitTopbar extends StatelessWidget
class FileTreePanel extends StatefulWidget
class PaneView extends StatelessWidget
class ProjectsRail extends StatefulWidget
Future<void> showWorktreeCreateDialog(
  BuildContext context, {
  required String rootName,
  required WorktreeNamespace namespace,
  required Future<String?> Function(String name) onCreate,
})
```

**Implementation notes**:

- Translate comments/docs while preserving workspace/tree/tab/worktree intent.
- Review the PT worktree-name placeholder as UI copy; do not alter validation,
  callback values, branch rules, or the surrounding dialog behavior.
- Audit every exported widget with 3+ constructor parameters. Existing docs
  generally satisfy the Recommended tier and need translation, not redundant
  additions. Keep `widgets.dart` barrel and trivial `UpdateCard` surface in the
  Skip tier unless the audit finds a non-obvious contract.

**Acceptance criteria**:

- [ ] All 15 PT-bearing files in this unit contain EN-only comments/docs and the
      reviewed placeholder is EN-first.
- [ ] Existing Recommended-tier widget docs remain intent-bearing after
      translation; no obvious-description filler is added.
- [ ] Dialog labels, validation results, callback contracts, and navigation
      behavior are otherwise unchanged.

## Implementation order

1. Run the three child stories in parallel; they have disjoint file ownership
   and `depends_on: []`.
2. After all three land, inspect the combined diff for cross-story vocabulary
   consistency (`workspace`, `worktree`, `pane`, `tab`, `agent`, `relay`,
   `effort`) and run the integrated verification gate.
3. Advance the parent only after the 38-file PT inventory, five gap-only files,
   and terminal test are all accounted for.

## Testing

### Per-story checks

- Review `git diff --word-diff` and confirm changes are limited to comments,
  dartdoc, the explicitly reviewed natural-language literals, and formatting.
- Run formatter validation on owned files with the repository Dart SDK.
- The terminal story runs:

```bash
PUB_CACHE=../.pub-cache ../.tools/flutter/bin/flutter test test/ui/terminal_input_test.dart
```

### Integrated cockpit gate

From `cockpit/`:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
../.tools/flutter/bin/flutter pub get --offline
../.tools/flutter/bin/flutter analyze
../.tools/flutter/bin/flutter test
../.tools/flutter/bin/dart format --output=none --set-exit-if-changed \
  lib/app/cockpit/ui test/ui/terminal_input_test.dart
```

Then run an accented-PT sweep over `lib/app/cockpit/ui/` and `test/ui/`, plus a
manual/string-token review for unaccented PT. The sweep is a backstop, not the
sole proof: it would not catch the known unaccented placeholder or every test
phrase.

### Documentation self-check

Apply `.agents/skills/scan-documentation/SKILL.md` to the changed surface:

- `///` immediately precedes each covered declaration.
- Always-tier service/ViewModel/`Result` contracts explain intent, side effects,
  lifecycle, null/error meaning, or caller obligations where non-obvious.
- Recommended widget docs explain purpose and composition contract.
- No doc merely repeats a class name, parameter type, or return type.
- Tests, barrels, DTO mirrors, generated code, trivial members, and Flutter
  overrides are not gap-filled.

## Risks

- **Accent grep has false negatives.** Unaccented PT can survive; mitigate with
  the explicit literal inventory, token-aware review, and changed-string audit.
- **Translation can erase load-bearing rationale.** Terminal fork/cache,
  workspace projection, lifecycle, and async safety comments must preserve
  meaning and links, not be shortened mechanically.
- **The baseline can induce documentation bloat.** Treat ~95 as audit input and
  enforce the tier filter; quantity is not acceptance.
- **Parallel workers can create terminology drift.** File ownership prevents
  conflicts; the integration pass normalizes vocabulary without changing code.
- **Cockpit tooling is environment-sensitive.** Use the repo Flutter binary,
  writable repo pub cache, and offline pub resolution documented in the cockpit
  skill. Classify environment failures rather than weakening tests.

## Pre-mortem

The likeliest failure is a superficially clean accent grep that leaves
unaccented PT or changes a meaningful literal/escape fixture. The fallback is
not a broader replacement: revert the suspect literal, translate it manually,
and re-run the targeted terminal test plus changed-string review. The least
certain area is tier classification for public UI helpers; when uncertain,
prefer a concise intent doc only for a non-obvious caller/lifecycle contract,
not blanket coverage.

## Mockups

Not required. This feature changes copy/comments/documentation only and reuses
all existing UI composition and behavior.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- cockpit/lib/app/cockpit/ui/`).

### Findings
- None. PT sweeps clean (no residual Portuguese); no signature/identifier/enum/
  wire-value/lifecycle change. Intended literal translations bounded at
  `worktree_create_dialog.dart:136`. Dartdoc meaningful and tier-appropriate.

### Verdict
Approve. Advanced `review → done`.
