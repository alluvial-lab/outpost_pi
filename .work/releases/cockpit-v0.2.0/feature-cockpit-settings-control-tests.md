---
id: feature-cockpit-settings-control-tests
kind: feature
stage: done
tags: [cockpit, testing]
parent: null
depends_on: []
release_binding: cockpit-v0.2.0
gate_origin: tests
created: 2026-07-15
updated: 2026-07-20
---

# Cockpit: behavior coverage for the settings/control split

## Brief

Three test-quality gate findings describe coverage gaps in the Cockpit
settings/control surface — the tests sample one value, cover rename/cancel but
not the successful create flow, and assert only importability rather than
persistence/controller behavior. This feature adds behavior-level coverage:

- `gate-tests-app-preference-persistence` — app-preference panels only have importability coverage, not persistence/controller behavior
- `gate-tests-control-command-serialization` — control-command serialization test only samples one relay action
- `gate-tests-daemon-create-flow` — daemon tests cover rename/cancel but not the successful create flow

## Simplification opportunity

Strengthen existing tests to cover the behavior contracts (persistence,
full serialization matrix, successful create). No production-code change
required unless a test surfaces a real bug — in which case route that as a
separate story.

## Source

Promoted from backlog by `scope` (2026-07-15). 3 `gate-tests-*` findings from
the v0.6.0 release `gate-tests` pass.

## Design decisions

- **Test boundary**: strengthen the three existing Cockpit test files and use
  their current public seams (`SettingsController`,
  `schemaControlPromptForTesting`, and `FilePicker.platform`) rather than add
  production-only test hooks. The contracts are observable without changing
  production code.
- **Preference coverage**: use widget interactions for the deterministic
  Appearance and Notification controls, and keep Language command persistence
  at the app-scoped `SettingsController` boundary. Pumping
  `LanguageSettingsPanel` starts one real LSP probe per catalog entry and leaves
  process/timeout work in the widget-test clock; injecting a probe solely for
  this test would widen production API for no product behavior. Existing LSP
  save/reset tests remain and gain the missing format preference assertion.
- **Control matrix authority**: enumerate all four relay actions with literal
  schema wire values in the test and assert the case keys equal
  `PiRelayControlAction.values`. The production enum remains the source of
  truth; the explicit test expectations independently detect a wrong mapping or
  a newly added action without coverage.
- **Daemon picker seam**: substitute a `FilePicker` subclass through the
  package's public `FilePicker.platform` singleton, restore the original in
  teardown, and drive the real create dialog. Do not bypass dialog validation
  by calling `DaemonsViewModel.create` directly.
- **Failure triage**: this feature changes tests only. If an honest behavior test
  exposes a product defect, keep the failing evidence and route the production
  repair as a separate bug story; do not weaken the assertion or fold the fix
  into this feature.
- **Execution ownership**: direct-read design across three bounded existing
  test surfaces. One Cockpit implementation owner should carry all three child
  checkpoints; exploratory fan-out or one worker per story would add handoff
  cost without improving isolation.

## Architectural choice

### Option A — extend the existing behavior tests at public seams (chosen)

Add focused cases to the three files already responsible for preferences,
control serialization, and daemon panel wiring. Reuse their memory store,
Modular pump helpers, recording ViewModel, and visible test helpers. This
optimizes for behavior-level evidence with no product API or dependency change.

### Option B — controller/data-only tests

Call `SettingsController`, `PiControlCommand`, and `DaemonsViewModel` directly.
These tests would be cheap and deterministic, but they would miss the two
important UI seams in the findings: panel callbacks reaching the persistence
owner and the create dialog returning the chosen folder/name to the ViewModel.

### Option C — introduce injectable panel adapters for every native/async effect

Add an LSP probe port and folder-picker port to make every panel independently
pumpable. This would maximize widget isolation, but it changes production
composition and abstractions for a small test-only slice. The existing public
picker seam and controller boundary already cover the required contracts.

**Choice:** Option A. It tests the stable behavior boundaries the gate named,
keeps native effects deterministic where a supported seam exists, and avoids
production changes that do not earn their maintenance cost.

## Implementation Units

### Unit 1: Prove app-preference interactions persist through the app-scoped owner

**File**: `cockpit/test/settings/app_preferences_settings_panel_test.dart`

**Story**: `gate-tests-app-preference-persistence`

```dart
Future<void> _pumpPreferencePanel(
  WidgetTester tester, {
  required Widget panel,
  required SettingsController controller,
  NotificationsViewModel? notifications,
});

final class _RecordingSettingsStore implements SettingsStore {
  AppSettings? saved;
  AppSettings _current = const AppSettings();

  @override
  Future<AppSettings> load();

  @override
  Future<void> save(AppSettings settings);
}
```

**Implementation Notes**:
- Replace the broad importability-only assertion with behavior that pumps
  `AppearanceSettingsPanel`, edits the first font field, and toggles the
  conversation switch. Assert the recording store receives trimmed font and
  `pinUserMessage` values through `SettingsController`.
- Pump `NotificationSettingsPanel` with the same controller/store composition
  and an immediate fake `NotificationsViewModel`; toggle Enable notifications
  and assert the persisted setting. Find controls by visible label/semantic
  type, not private widget structure.
- Retain the existing LSP command/formatter save-and-reset tests, add
  `setFormatOnSave` persistence, and update the stale file-level comment so it
  describes the real behavior coverage. Do not start real language servers in
  this suite.
- Reuse one Modular/Shadcn pump helper and the existing recording store rather
  than create panel-specific harness classes.

**Acceptance Criteria**:
- [ ] Appearance interaction updates live controller state and the last value
      saved by `SettingsStore`; the panel never receives or imports a store.
- [ ] Notification enable/disable interaction persists through the same owner
      and remains deterministic on macOS and non-macOS test hosts.
- [ ] Language command, formatter, reset, whitespace normalization, and format-
      on-save behavior all persist through `SettingsController`.
- [ ] The former importability assertion is removed or narrowed so it does not
      masquerade as behavior evidence.

---

### Unit 2: Cover the complete schema control-command serialization matrix

**File**: `cockpit/test/data/pi_rpc_process_control_test.dart`

**Story**: `gate-tests-control-command-serialization`

```dart
const expectedRelayCommands = <PiRelayControlAction, String>{
  PiRelayControlAction.on: 'relay_on',
  PiRelayControlAction.off: 'relay_off',
  PiRelayControlAction.toggle: 'relay_toggle',
  PiRelayControlAction.status: 'relay_status',
};

Map<String, Object?> decodeControl(PiControlCommand command) =>
    jsonDecode(
      schemaControlPromptForTesting(command)['message']! as String,
    ) as Map<String, Object?>;
```

**Implementation Notes**:
- Parameterize the current status-only test over `expectedRelayCommands`. For
  each action assert the outer prompt shape, absence of the retired NUL prefix,
  and exact `{type: outpost_pi_control, command: <wire>}` envelope.
- Assert the matrix keys cover `PiRelayControlAction.values` so a new relay
  action cannot silently remain untested.
- Keep the trimmed successful rename assertion and add a synchronous
  `throwsA(isA<RpcError>()...)` assertion for an empty/whitespace-only rename.
  The error message should state that a non-empty name is required.
- Preserve the existing UI-response variant test; it protects a separate
  process-boundary contract and is not duplicate control coverage.

**Acceptance Criteria**:
- [ ] `relay_on`, `relay_off`, `relay_toggle`, and `relay_status` each serialize
      to their exact schema envelope through the prompt transport.
- [ ] No relay case emits the retired `\u0000outpost-pi-ctrl:` encoding.
- [ ] The test fails when an action is added without a matrix case.
- [ ] Rename trims a valid name and rejects an empty/whitespace-only name with
      `RpcError` before any frame can be written.

---

### Unit 3: Drive the successful daemon-create dialog path

**File**: `cockpit/test/settings/daemon_settings_panel_test.dart`

**Story**: `gate-tests-daemon-create-flow`

```dart
final class _DirectoryFilePicker extends FilePicker {
  _DirectoryFilePicker(this.path);

  final String path;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => path;
}
```

**Implementation Notes**:
- In a widget test, install `_DirectoryFilePicker('/work/new-agent')` through
  `FilePicker.platform`, register teardown that restores the original, and pump
  an online/ready `_PanelDaemonsViewModel`.
- Tap Create daemon, enter a non-empty name, choose the fake directory, then
  submit the real `DaemonEditorDialog`. Pump only until the dialog closes; do
  not wait on the panel's periodic timer.
- Assert the ViewModel records exactly
  `('/work/new-agent', 'Build agent')`. Retain the existing cancel assertion as
  the complementary negative path and the rename test as a distinct contract.
- Do not mock `showDaemonEditorDialog`, call `vm.create` directly, or add a
  production folder-picker abstraction for this test.

**Acceptance Criteria**:
- [ ] The successful create journey supplies both the chosen directory and
      trimmed name to `DaemonsViewModel.create(cwd, name: ...)` exactly once.
- [ ] Choosing a directory exercises the real dialog validation and return
      value rather than bypassing the widget.
- [ ] The picker singleton and panel timer are cleaned up so later tests do not
      inherit native/global state.
- [ ] Existing rename, cancel, daemon action, fleet action, reload, and timer-
      cancellation coverage remains green.

## Implementation Order

1. Unit 1 strengthens preference persistence evidence and consolidates its
   existing harness (`gate-tests-app-preference-persistence`).
2. Unit 2 adds the independent control schema matrix and rename boundary
   failure (`gate-tests-control-command-serialization`).
3. Unit 3 adds the native-picker-backed create journey after the simpler widget
   harness patterns are established (`gate-tests-daemon-create-flow`).
4. Run the three focused test files, format/analyze changed Dart, then run the
   Cockpit suite during implementation. On green evidence, advance child
   checkpoints directly to `done`, then the feature to one standard review pass.

## Child checkpoints

The three pre-existing child stories are confirmed and collectively cover every
implementation unit; no additional child is created:

- `gate-tests-app-preference-persistence` — `depends_on: []`
- `gate-tests-control-command-serialization` — `depends_on: []`
- `gate-tests-daemon-create-flow` — `depends_on: []`

Their empty dependency arrays are retained because the contracts and write
regions are independent. The numbered order is a one-owner sequence for
coherent harness reuse, not a semantic dependency and not a reason to
manufacture graph edges. Per the delegated concurrent-design write boundary,
the pre-existing story files remain unchanged; this feature body coordinates
their design.

## Simplification

- Replace importability-only preference evidence with persisted behavior where
  deterministic public seams exist.
- Reuse `_RecordingSettingsStore`, the Modular pump shape, and
  `_PanelDaemonsViewModel`; do not introduce a shared test-support library for
  three local files.
- Parameterize the existing relay test instead of adding four nearly identical
  tests, and keep one explicit literal matrix as the independent schema oracle.
- Keep the current production boundaries. No new dependency, generated schema,
  native adapter, ViewModel API, or foundation-doc update is required.
- Do not delete the UI-response serialization, daemon cancel/rename, or LSP
  normalization cases; they protect non-overlapping behavior.

## Testing

- **Interface tests**: panel interactions prove UI callbacks reach the app-owned
  controller/ViewModel boundaries; schema prompt decoding proves the process
  adapter emits the external command contract.
- **Regression tests**: the full relay matrix catches partial variant coverage;
  empty rename catches boundary validation; successful daemon creation catches
  the previously unexercised folder/name handoff.
- **Complex-unit tests**: none. Production logic is simple; value comes from
  exercising seams, not duplicating implementation internals.
- **Test data**: use local recording fakes and one fixed directory/name. No Hive
  box, filesystem directory, real platform dialog, real LSP process, golden, or
  snapshot is needed.
- **Verification deferred to implementation**: from `cockpit/`, run the three
  focused files first with the repo Flutter binary and `PUB_CACHE`, then Dart
  format/check, `flutter analyze`, and `flutter test` as resources permit. No
  test or build runs occur in this design phase.

## Risks

- **Riskiest assumption**: `FilePicker.platform` is initialized and replaceable
  under the Cockpit widget-test binding. The package intentionally exposes this
  platform singleton and accepts subclasses; if host initialization differs,
  the fallback is a file-local method-channel fake, not a production adapter.
- **Language panel side effects**: pumping the complete panel starts real
  process probes and timeout work. The design deliberately proves persistence
  at `SettingsController`, the owning stable boundary. If direct LSP-panel
  interaction later becomes a required product regression, add a separately
  justified probe port rather than accepting a flaky process test here.
- **Finder brittleness**: Shadcn internals may change. Select by user-visible
  labels and final domain calls/settings, and avoid assertions about private
  widget trees or animation frame counts.
- **Honest failure path**: a newly failing behavior assertion may reveal a real
  product bug. That blocks the affected checkpoint until a separate bug story
  is routed; test weakening is not a fallback.

## Other agent review

- Invoked because: not invoked. This is a bounded test-only design over three
  known files with no production, persistence-format, lifecycle, security, or
  wire-contract change; direct source inspection provided the required
  evidence, so Part IV's risk-driven policy skips design-time advisory review.
- Fixed/active blockers: none.
- Parked: none.
- Rejected: production-only LSP probe and folder-picker abstractions; they add
  API/composition cost without being required by the behavior contracts.
- Skipped/degraded: effective implementation/final review weight remains
  `standard` (caller default): one fresh-context feature review after
  verification, receiver adjudication, and fixes for material current-cycle
  blockers without re-review.

## Implementation

- Execution capability: `openai-codex/gpt-5.6-sol` (autopilot caller selection).
- Completed all three child checkpoints: app-preference interactions now prove persistence through `SettingsController`; relay control serialization covers the full action matrix and rename validation; daemon creation drives the real editor dialog through the public `FilePicker.platform` seam.
- Production code and public APIs were unchanged. Test-local fakes reuse existing recording boundaries, and native/global picker state plus the daemon panel timer are restored or disposed.
- Integrated verification: `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache flutter test --no-pub` passed all 257 tests after the final child, compared with a green 256-test baseline before daemon-create coverage.
- Additional analysis: `flutter analyze --no-pub` found no issue in the changed tests; it remains non-zero for two unrelated pre-existing/concurrent info diagnostics in `pi_rpc_process.dart` and `file_viewer.dart`.
- Review weight: `standard` (caller override); ready for one independent feature-level pass.
- Adjacent production bugs parked: none.

## Review (standard, cross-model, 2026-07-19) — adjudicated

One balanced fresh-context cross-model pass (`openai-codex/gpt-5.6-sol` vs host `umans/umans-glm-5.2`). Verdict **APPROVED — ready for done**. No blocker or material current-cycle findings.

### Lower-risk — parked unbound in backlog

- `gate-docs-control-transport-nul-prefix-contradiction` — foundation docs (`docs/SPEC.md`, `docs/ARCHITECTURE.md`) simultaneously say the NUL-prefix protocol was retired and describe it as Cockpit's active transport. Cockpit now emits structured `outpost_pi_control` JSON; the prefix is extension-side compatibility only. Predates this feature; doesn't invalidate its tests. Routed to the `gate-docs` drift surface.

### Nits — noted, no work created

- `app_preferences_settings_panel_test.dart:39-44` selects controls via `.first`/widget type rather than visible labels (brittle but not false-green — final controller/store behavior is asserted).
- Child stories use `gate_origin: testing` while the feature and configured gate name use `tests`. Normalize when next touched; current stage/dependency state is coherent.

### Acceptance + integrity (reviewer-confirmed)

- Preferences: real Appearance/Notification panels drive `SettingsController` + recording `SettingsStore`; assertions cover trimmed persistence + controller state (not importability/trivia).
- Control matrix: all four relay actions have literal independent wire expectations + enum-completeness enforcement (wrong mapping or uncovered new action fails).
- Daemon creation: drives the real dialog + validation through `FilePicker.platform`, verifies the exact trimmed ViewModel call once; ViewModel mocked only at the intended panel boundary.
- Scope: commits c9504ec, 730d273, 5e8b4d5 changed only test + `.work` files — no `cockpit/lib/` production changes.
- No test weakening, tautological assertions, stale fixtures, or hidden production fixes.
- Count progression coherent: 253 → 255 (preferences +2) → 256 (serialization +1) → 257 (daemon +1). 256 was the baseline before the daemon story, not before the whole feature (matches the implementation record).

Verification: `flutter test --no-pub` 257 pass.

Advanced `review → done`.
