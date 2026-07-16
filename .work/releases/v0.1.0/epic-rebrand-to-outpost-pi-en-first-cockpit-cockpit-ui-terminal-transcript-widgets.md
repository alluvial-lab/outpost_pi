---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-terminal-transcript-widgets
kind: story
stage: done
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Translate terminal/transcript/editor widgets and terminal test

## Scope

Own exactly these files:

- `cockpit/lib/app/cockpit/ui/widgets/agent_composer.dart`
- `cockpit/lib/app/cockpit/ui/widgets/agent_markdown.dart`
- `cockpit/lib/app/cockpit/ui/widgets/agent_setup_checklist.dart`
- `cockpit/lib/app/cockpit/ui/widgets/agent_transcript.dart`
- `cockpit/lib/app/cockpit/ui/widgets/cockpit_terminal.dart`
- `cockpit/lib/app/cockpit/ui/widgets/cockpit_terminal_gesture.dart`
- `cockpit/lib/app/cockpit/ui/widgets/cockpit_terminal_painter.dart`
- `cockpit/lib/app/cockpit/ui/widgets/cockpit_terminal_render.dart`
- `cockpit/lib/app/cockpit/ui/widgets/code_editor.dart`
- `cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart`
- `cockpit/lib/app/cockpit/ui/widgets/media_view.dart`
- `cockpit/lib/app/cockpit/ui/widgets/terminal_link.dart`
- `cockpit/lib/app/cockpit/ui/widgets/terminal_pane.dart`
- `cockpit/test/ui/terminal_input_test.dart`

Translate comment/doc prose in the 13 lib files. Review the test's comments,
all 14 test-output descriptions, and natural-language fixture chunks one by
one. Preserve CSI/ESC bytes, event flags, assertions, grouping, and coverage.
Tests are Skip-tier for dartdoc.

## Documentation unit

Add missing Recommended-tier class dartdoc to the existing exported widgets
`AgentTranscript`, `CockpitTerminal`, and `CockpitTerminalGestureHandler`.
Preserve the non-obvious xterm-fork/cache/selection contract by documenting the
exported `CockpitTerminalState` and `CockpitTerminalRender` boundary where
needed. Do not rewrite upstream-style field descriptions or document Flutter
overrides merely to increase a count.

## Acceptance criteria

- [ ] The 13 lib files and terminal test contain EN-only comment/doc prose.
- [ ] All 14 tests remain, with unchanged assertions and terminal escape
      sequences; only natural-language descriptions/fixture prose/comments
      change.
- [ ] The three missing exported-widget docs use `///` and explain purpose and
      composition contract rather than restating names/types.
- [ ] Terminal fork/cache, selection ownership, rendering, editor, and media
      lifecycle behavior remains unchanged.
- [ ] No public signature or method body changes except reviewed literal prose
      and formatter output.

## Verification

From `cockpit/`:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
../.tools/flutter/bin/flutter pub get --offline
../.tools/flutter/bin/flutter test test/ui/terminal_input_test.dart
../.tools/flutter/bin/flutter analyze
../.tools/flutter/bin/dart format --output=none --set-exit-if-changed \
  lib/app/cockpit/ui/widgets/agent_composer.dart \
  lib/app/cockpit/ui/widgets/agent_markdown.dart \
  lib/app/cockpit/ui/widgets/agent_setup_checklist.dart \
  lib/app/cockpit/ui/widgets/agent_transcript.dart \
  lib/app/cockpit/ui/widgets/cockpit_terminal.dart \
  lib/app/cockpit/ui/widgets/cockpit_terminal_gesture.dart \
  lib/app/cockpit/ui/widgets/cockpit_terminal_painter.dart \
  lib/app/cockpit/ui/widgets/cockpit_terminal_render.dart \
  lib/app/cockpit/ui/widgets/code_editor.dart \
  lib/app/cockpit/ui/widgets/file_viewer.dart \
  lib/app/cockpit/ui/widgets/media_view.dart \
  lib/app/cockpit/ui/widgets/terminal_link.dart \
  lib/app/cockpit/ui/widgets/terminal_pane.dart \
  test/ui/terminal_input_test.dart
```

Review the word diff and changed string literals; the full cockpit suite is the
integrated parent gate.

## Implementation notes

- Files changed: all 13 owned widget files plus
  `cockpit/test/ui/terminal_input_test.dart`.
- Tests added: none; retained and translated all 14 existing terminal-input test
  cases, including deliberate review of fixture prose while preserving escape
  sequences, event flags, and assertions.
- Discrepancies from design: none. Added purpose/composition dartdoc to
  `AgentTranscript`, `CockpitTerminal`, and `CockpitTerminalGestureHandler`, and
  preserved the xterm fork, cache, selection, and native-picture lifecycle
  contracts on `CockpitTerminalState` and `CockpitTerminalRender`.
- Verification: offline pub resolution passed; targeted terminal test passed
  (14/14); `flutter analyze` passed with zero issues; full `flutter test` passed
  (241 tests); formatter check passed for all owned files; accented-PT and manual
  unaccented-PT sweeps found no remaining Portuguese prose.
- Adjacent issues parked: none.
- Rationale: kept upstream-style field docs and Flutter overrides unchanged, as
  required, and translated only comments, dartdoc, test descriptions, and
  natural-language fixture chunks so rendering and lifecycle behavior remain
  unchanged.
