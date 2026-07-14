---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-state-session-viewmodels
kind: story
stage: implementing
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate and document cockpit UI state/session/ViewModels

## Scope

Own exactly these files:

- `cockpit/lib/app/cockpit/ui/cockpit_page.dart`
- `cockpit/lib/app/cockpit/ui/session/agent_entry.dart`
- `cockpit/lib/app/cockpit/ui/session/agent_process_controller.dart`
- `cockpit/lib/app/cockpit/ui/session/agent_session.dart`
- `cockpit/lib/app/cockpit/ui/session/file_viewer_session.dart`
- `cockpit/lib/app/cockpit/ui/session/pane_item.dart`
- `cockpit/lib/app/cockpit/ui/session/terminal_input.dart`
- `cockpit/lib/app/cockpit/ui/session/terminal_session.dart`
- `cockpit/lib/app/cockpit/ui/states/pane_node.dart`
- `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`
- `cockpit/lib/app/cockpit/ui/viewmodels/setup_viewmodel.dart`
- `cockpit/lib/app/cockpit/ui/viewmodels/update_viewmodel.dart`
- `cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart`

Ten files carry PT comments/docs; the controller, pane-state, and workspace
projection files are gap-audit-only. Translate comment tokens to EN and apply
the parent feature's intent-tier audit. Do not modify runtime behavior or public
signatures.

## Documentation unit

Preserve and translate the existing class docs for `CockpitViewModel`,
`SetupViewModel`, `UpdateViewModel`, and session types. Add meaningful `///`
only where the convention requires it, prioritizing:

- lifecycle and `Result`-returning methods on `AgentProcessController`;
- realize/create/save/dispose contracts on `WorkspaceProjection`;
- public action/lifecycle methods on `AgentSession`;
- setup recheck actions;
- non-obvious mutation/lifecycle actions on `CockpitViewModel` (`init`,
  project/tab/pane removal, focus/selection, resize, and visibility toggles).

Skip DTO-shaped requests/prompts, barrels/tests, overrides, private helpers,
and trivial projection getters/fields whose signature is sufficient.

## Acceptance criteria

- [ ] The 10 PT-bearing owned files contain EN-only comments/docs.
- [ ] Every Always-tier ViewModel/controller/service export in the 13 owned
      files has meaningful dartdoc explaining intent, side effects, lifecycle,
      or error/null behavior as applicable.
- [ ] The audit does not add obvious-description docs to Skip-tier declarations.
- [ ] No imports, signatures, method bodies, persistence behavior, or lifecycle
      ownership changes except formatter output.
- [ ] Changed files are formatted and pass the relevant analyzer check.

## Verification

From `cockpit/`, with the repo toolchain/cache:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
../.tools/flutter/bin/flutter pub get --offline
../.tools/flutter/bin/flutter analyze
../.tools/flutter/bin/dart format --output=none --set-exit-if-changed \
  lib/app/cockpit/ui/cockpit_page.dart \
  lib/app/cockpit/ui/session \
  lib/app/cockpit/ui/states \
  lib/app/cockpit/ui/viewmodels
```

Also review the word diff and run the parent feature's PT and documentation
self-checks. The full cockpit test suite is the integrated parent gate.
