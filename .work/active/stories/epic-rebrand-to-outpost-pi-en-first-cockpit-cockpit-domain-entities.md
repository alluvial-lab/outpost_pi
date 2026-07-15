---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain-entities
kind: story
stage: review
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate cockpit domain entities and fill owned dartdoc gaps

## Scope

Translate Portuguese comment prose to English in these 19 PT-bearing files:

- `cockpit/lib/app/cockpit/domain/entities/agent_snapshot.dart`
- `cockpit/lib/app/cockpit/domain/entities/context_usage.dart`
- `cockpit/lib/app/cockpit/domain/entities/file_node.dart`
- `cockpit/lib/app/cockpit/domain/entities/file_view.dart`
- `cockpit/lib/app/cockpit/domain/entities/git_file_status.dart`
- `cockpit/lib/app/cockpit/domain/entities/git_info.dart`
- `cockpit/lib/app/cockpit/domain/entities/install_result.dart`
- `cockpit/lib/app/cockpit/domain/entities/launchable_app.dart`
- `cockpit/lib/app/cockpit/domain/entities/pi_command.dart`
- `cockpit/lib/app/cockpit/domain/entities/pi_model.dart`
- `cockpit/lib/app/cockpit/domain/entities/project.dart`
- `cockpit/lib/app/cockpit/domain/entities/prompt_image.dart`
- `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart`
- `cockpit/lib/app/cockpit/domain/entities/session_info.dart`
- `cockpit/lib/app/cockpit/domain/entities/thinking_level.dart`
- `cockpit/lib/app/cockpit/domain/entities/update_info.dart`
- `cockpit/lib/app/cockpit/domain/entities/workspace_pane.dart`
- `cockpit/lib/app/cockpit/domain/entities/worktree.dart`
- `cockpit/lib/app/cockpit/domain/exceptions/rpc_error.dart`

Perform the bounded Always-tier gap fill in `workspace_pane.dart` by adding
meaningful English `///` contract documentation for these six public domain
declarations without changing their signatures:

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

`UpdateArtifact` is a manifest DTO whose declaration restates the wire shape;
it remains Skip-tier under the documentation convention. Do not expand this
story into the nine EN-only domain entity files: they are outside the measured
translation set. Preserve all runtime strings, JSON keys, persistence shapes,
enum values, and executable code.

## Acceptance criteria

- [ ] All Portuguese comment prose in the 19 listed files is idiomatic English while preserving domain and lifecycle meaning.
- [ ] The six listed `workspace_pane.dart` declarations have meaningful English dartdoc focused on purpose, invariants, mutation/return semantics, and no-op behavior where relevant.
- [ ] `UpdateArtifact` is left without boilerplate dartdoc as an explicit DTO Skip-tier disposition.
- [ ] No executable declaration, runtime string, JSON/persistence key, enum value, import, or public signature changes.
- [ ] The scan-documentation rubric reports no remaining Always-tier gap in the 19-file owned set.
- [ ] A targeted accented-Latin grep reports no matches in the 19 files, and a manual lexical review catches unaccented Portuguese residue.
- [ ] `dart format` is run on the owned files; from `cockpit/`, `flutter analyze` and `flutter test` pass (or an exact environment failure is reported without weakening tests).

## Implementation notes

- Files changed: the 18 scoped files under `cockpit/lib/app/cockpit/domain/entities/` and `cockpit/lib/app/cockpit/domain/exceptions/rpc_error.dart`.
- Tests added: none; this is a behavior-preserving documentation translation.
- Discrepancies from design: none. For `setFrac` and `updateLeaf`, “unchanged when absent” is documented as structurally unchanged rather than object-identical because the existing recursive implementation rebuilds split nodes; executable behavior remains untouched.
- Documentation disposition: added intent and traversal/update/no-op contracts to the six listed declarations; left `UpdateArtifact` undocumented as the explicit wire-DTO Skip-tier case.
- Dispatch rationale: direct-read implementation was sufficient because the story supplied a fixed, disjoint file inventory and required no integration discovery.
- Verification: formatted all 19 owned Dart files (`0 changed` after translation); accented-Portuguese grep returned no matches; manual lexical review found no unaccented Portuguese residue; `flutter analyze` passed with no issues; full `flutter test` passed (241 tests).
- Adjacent issues parked: none.
