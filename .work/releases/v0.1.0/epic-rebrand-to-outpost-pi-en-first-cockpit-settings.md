---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-settings
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

# EN-first + dartdoc gap-fill — cockpit settings module

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit `settings` module (`cockpit/lib/app/settings/`): daemon
supervisor client, relay gateway, pairing/connectivity/cron/notifications
viewmodels and panels. 25 PT-bearing Dart files: `settings/ui` (13),
`settings/domain` (8), `settings/data` (3), plus `settings_module.dart`.

PT is predominantly comment prose, but this module holds user-facing settings
panels (connectivity, language, notifications, appearance) — a subset of the
~18 cockpit-wide PT string literals live here and need translation-review, not
mechanical sed. Gap-fill scope is the Always tier: ViewModel exports,
service-layer functions (supervisor client, relay gateway), `Result`-returning
functions.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent mid-size slice. No `depends_on` — the
  cockpit's wire-stable identifiers already migrated in the first rebrand
  epic. Can run in parallel with every other child feature. Shares the
  cockpit build gate with the other cockpit features, but the file set is
  disjoint (separate flutter_modular module).

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format
  and the Always tier for Dart (ViewModel exports, service-layer functions).
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- Parent epic `## Decomposition risks` — "user-visible UI text needs review"
  applies to the settings panels.

## What this feature does NOT cover
- Wire-stable identifiers (control-RPC discriminator) — owned by the first
  rebrand epic, already shipped.
- Product-identity string renames — owned by the mechanical-rename feature.
- `scripts/` shell comments — out of scope.
- Generated/vendored state.

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
Plus a grep confirming zero PT (accented Latin) in `cockpit/lib/app/settings/`.

## Design decisions

- **What is the owned translation set?** Translate exactly the 25 measured
  PT-bearing files listed below: 13 UI files, eight domain files, three data
  adapters, and `settings_module.dart`. The other ten EN-only Dart files under
  `cockpit/lib/app/settings/` are documentation-audit context only.
- **How are comments separated from runtime copy?** Use bounded exact
  replacements only inside `//` and `///` tokens for comment translation, then
  inspect the diff per file. Review every human-readable string literal in the
  settings panels/dialogs/ViewModels separately; never run blanket replacement
  across Dart source. The design-time literal probe found no obvious remaining
  PT runtime string in the owned files, so implementation must validate the UI
  surface rather than churn already-English copy.
- **How broad is dartdoc gap-fill?** The approximate 38-declaration syntax
  baseline is audit input, not an edit quota. Apply only the convention's
  Always tier. The intent-filtered audit below names 30 actionable declarations:
  domain `Result` contracts/converters and public ViewModel/controller actions.
  Data-adapter overrides inherit the domain contract and do not get duplicated
  comments; trivial getters, widgets, DTO fields, barrels, tests, private
  helpers, and Flutter overrides remain Recommended/Skip.
- **How is implementation split?** Spawn three dependency-free stories with
  exclusive ownership: domain/composition, data adapters, and UI/runtime-copy
  review. This matches the raised implementation tier while keeping the final
  Flutter gate serialized after the three diffs converge.
- **Are tests translated?** No. The five `cockpit/test/settings/*.dart` files
  contain no PT in the current probe and remain Skip-tier for gap-fill. They are
  verification targets only; test descriptions and assertions must not be
  changed merely to create work.
- **Does this need UI mockups?** No. Existing labels may be translated only if a
  PT literal is found; no screen, layout, interaction, or journey changes. The
  feature-design UI fallback is therefore skipped despite the parent having no
  mockups.
- **Was design-time advisory review needed?** No. The parent epic and landed
  documentation convention lock the only broad choices. This is a bounded,
  behavior-preserving prose/doc pass with no large or irreversible architecture
  decision, so direct reading was the economical path.

## Mapping and dispatch rationale

Direct-read mapping was sufficient: the feature is one vertical slice with a
fixed 35-file module, a measured 25-file PT inventory, and five focused settings
tests. Representative reads covered all 25 PT-bearing files plus the contract,
ViewModel, panel, and test seams. Exploratory fan-out was skipped because no
structural unknown remained. Three implementation stories are still warranted
because their domain/data/UI ownership is disjoint and can be edited in
parallel.

## Architectural choice

Use a **layer-owned, token-aware translation pass with one explicit Always-tier
dartdoc inventory**. Each worker owns complete files, translates existing
comments in context, and adds only named docs; the UI worker additionally
reviews human-readable literals one by one.

Alternatives considered:

1. **One monolithic 25-file pass.** Simplest bookkeeping, but it creates a large
   review unit and leaves raised-tier parallel capacity unused.
2. **Separate translation and dartdoc stories.** Makes concerns visible, but
   both workers would edit the same comments/declarations, creating avoidable
   conflicts and duplicate context loading.
3. **Blanket mechanical translation.** Fastest in keystrokes, but unsafe around
   commands, paths, JSON keys, cron expressions, error text, and UI copy; it
   also misses unaccented Portuguese.

The chosen split changes no APIs, dependency direction, persistence shape,
wire contract, lifecycle, or behavior. `ui -> domain <- data` remains intact,
and `settings_module.dart` remains the sole composition root.

## Tricky unit first: UI copy versus executable literals

The UI shard is riskiest because comment prose sits beside labels, tooltips,
error messages, paths, commands, URLs, QR data, and protocol/config terms. The
worker must classify each changed token before editing: translate comments and
human-readable PT only; preserve identifiers, command names, routes, JSON keys,
cron syntax, URLs, interpolation, and already-English strings. The current
probe found no obvious PT runtime literal, which is a reason to review and leave
copy unchanged—not a reason to skip the literal audit.

## Implementation units

### Unit 1: Domain contracts, entities, cron preview, and composition

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-settings-domain-composition`

**Comment-translation files (9):**

- `cockpit/lib/app/settings/domain/contracts/cron_gateway.dart` — preserve
  server-side validation and `Result` failure meaning.
- `cockpit/lib/app/settings/domain/contracts/daemon_supervisor.dart` — preserve
  UDS/CLI ownership, per-daemon versus fleet operations, and supervisor-restart
  semantics.
- `cockpit/lib/app/settings/domain/contracts/relay_gateway.dart` — preserve the
  shell/config adapter boundary and explicitly avoid implying direct relay
  protocol ownership.
- `cockpit/lib/app/settings/domain/cron_schedule.dart` — preserve five-field
  cron support, Vixie DOM/DOW matching, local-time preview, null-on-unsupported,
  and server-authoritative `next_run` semantics.
- `cockpit/lib/app/settings/domain/entities/cron_job.dart` — preserve raw wire
  values, skip/delivery variants, and log meaning.
- `cockpit/lib/app/settings/domain/entities/daemon_info.dart` — preserve daemon
  state projection and control-protocol correspondence.
- `cockpit/lib/app/settings/domain/entities/paired_device.dart` — preserve
  base64-safe revoke identity and display-label meaning.
- `cockpit/lib/app/settings/domain/exceptions/daemon_error.dart` — preserve the
  typed infrastructure-error boundary.
- `cockpit/lib/app/settings/settings_module.dart` — preserve feature-scoped
  binds, shared supervisor instance, page-scoped ViewModels, and core-owned
  pairing/revoke factories.

**Contract signatures remain unchanged:**

```dart
abstract class DaemonSupervisor {
  Future<Result<void, DaemonError>> start(String id);
  Future<Result<void, DaemonError>> startAll();
  Future<Result<void, DaemonError>> restartSupervisor();
}

abstract class CronGateway {
  Future<Result<List<CronJob>, DaemonError>> listCron();
  Future<Result<void, DaemonError>> addCron({
    required String daemonId,
    required String schedule,
    required String prompt,
    String? tz,
    bool skipIfBusy = true,
    bool wake = false,
    bool catchup = false,
  });
}

DateTime? nextCronRun(String expr, DateTime from);
Module buildSettingsModule();
```

**Acceptance criteria:**

- [ ] All nine files contain idiomatic EN comments/dartdoc with contract meaning
      preserved.
- [ ] The twelve named domain gaps in the audit have meaningful `///` docs.
- [ ] No signature, enum/wire value, JSON key, cron algorithm, route, bind, or
      lifecycle behavior changes.
- [ ] DTO fields and obvious members do not receive filler docs.

### Unit 2: Supervisor, Windows pipe, and relay adapters

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-settings-data-adapters`

**Comment-translation files (3):**

- `cockpit/lib/app/settings/data/daemon/supervisor_client_impl.dart` — translate
  UDS/named-pipe/CLI, registry rename, reply decoding, and platform-resolution
  rationale; preserve commands, JSON keys, timeouts, error strings, and
  process/socket behavior.
- `cockpit/lib/app/settings/data/daemon/win_named_pipe.dart` — translate Win32
  FFI/isolate, deadline, backoff, line framing, and handle/buffer cleanup
  rationale; preserve pipe naming and all native calls/constants.
- `cockpit/lib/app/settings/data/relay/relay_gateway_impl.dart` — translate
  config/peers file and shell-out rationale; preserve URLs, paths, JSON keys,
  health semantics, timeout mapping, and existing user-visible error text.

**Adapter signatures remain unchanged:**

```dart
class SupervisorClientImpl implements DaemonSupervisor, CronGateway;
String supervisorPipeName();
Future<String?> winPipeTransact(
  String pipeName,
  String requestLine, {
  Duration timeout = const Duration(seconds: 6),
});
class RelayGatewayImpl implements RelayGateway;
```

**Implementation notes:**

- Adapter overrides inherit the newly complete domain-port dartdoc. Do not
  duplicate every `Result` contract on `SupervisorClientImpl` or
  `RelayGatewayImpl`; retain class-level adapter-specific docs and existing
  useful private-helper docs.
- Review natural-language error strings only to verify they are already EN.
  Do not rewrite wording, exception mapping, or user-visible behavior without a
  separately scoped product decision.

**Acceptance criteria:**

- [ ] All three files contain EN-only comment prose.
- [ ] Existing adapter-specific class/helper docs still explain IO, lifecycle,
      platform, and failure behavior.
- [ ] No command, path, key, timeout, FFI call, process/socket ordering, error
      string, or `Result` behavior changes.
- [ ] No redundant dartdoc is added to inherited override methods.

### Unit 3: Settings panels, ViewModels, and dialog/controller lifecycle

**Story**:
`epic-rebrand-to-outpost-pi-en-first-cockpit-settings-ui-review`

**Comment-only / dartdoc files (5):**

- `cockpit/lib/app/settings/ui/cron_viewmodel.dart`
- `cockpit/lib/app/settings/ui/notifications_viewmodel.dart`
- `cockpit/lib/app/settings/ui/pairing_controller.dart`
- `cockpit/lib/app/settings/ui/revoke_controller.dart`
- `cockpit/lib/app/settings/ui/settings_env_gate.dart`

**Comment translation plus explicit runtime-string review (8):**

- `cockpit/lib/app/settings/ui/categories/appearance_settings_panel.dart`
- `cockpit/lib/app/settings/ui/categories/connectivity_settings_panel.dart`
- `cockpit/lib/app/settings/ui/categories/language_settings_panel.dart`
- `cockpit/lib/app/settings/ui/categories/notification_settings_panel.dart`
- `cockpit/lib/app/settings/ui/connectivity_viewmodel.dart`
- `cockpit/lib/app/settings/ui/daemons_viewmodel.dart`
- `cockpit/lib/app/settings/ui/pairing_dialog.dart`
- `cockpit/lib/app/settings/ui/revoke_dialog.dart`

The baseline review found the human-readable literals in these eight files
already English. Re-check labels, descriptions, tooltips, dialog copy, fallback
errors, and QR instructions individually; translate only a verified PT literal.
Preserve `outpost-pi`, paths, URLs, commands, enum values, interpolation, and QR
payloads.

**Public behavior signatures remain unchanged:**

```dart
class ConnectivityViewModel extends ChangeNotifier {
  Future<void> loadRelay();
  Future<void> loadDevices();
}

class CronViewModel extends ChangeNotifier {
  Future<void> reload();
  Future<void> setEnabled(CronJob job, bool enabled);
  Future<void> remove(CronJob job);
  Future<void> run(CronJob job);
}

class DaemonsViewModel extends ChangeNotifier {
  Future<void> start(String id);
  Future<void> stop(String id);
  Future<void> restart(String id);
  Future<void> remove(String id);
  Future<void> startAll();
  Future<void> stopAll();
  Future<void> restartAll();
}

class PairingController extends ChangeNotifier {
  Future<void> start();
  Future<void> retry();
}

class RevokeController extends ChangeNotifier {
  Future<void> run(PairedDevice device);
}
```

**Implementation notes:**

- Preserve controller ownership and teardown: pairing subscriptions/gateways,
  revoke late-notification suppression, ViewModel `_disposed` guards, and
  page-scoped module disposal remain unchanged.
- Preserve mounted guards around dialogs and notification permission flows.
- Do not gap-fill exported widgets solely because they are public; these panels
  have trivial constructors and are outside the Always tier.

**Acceptance criteria:**

- [ ] All 13 files contain EN-only comment prose and every human-readable
      literal has been reviewed separately from comment translation.
- [ ] The eighteen named UI/ViewModel gaps in the audit have meaningful `///`
      intent/lifecycle/error docs.
- [ ] Existing labels remain EN, and no command/path/identifier/interpolation or
      lifecycle behavior changes.
- [ ] The five focused settings test files pass unchanged.

## Always-tier dartdoc audit

The module has roughly 38 undocumented syntax-level candidates, but the
convention's intent filter yields these **30 actionable gaps**. Existing useful
class docs are translated in place. Implementation must update this inventory
before widening it; it must not silently document every public widget/member.

### Domain ports and converters (12)

| File | Declaration(s) | Contract to document |
|---|---|---|
| `domain/contracts/daemon_supervisor.dart` | `start`, `stop`, `restart` | per-daemon action and typed failure |
| `domain/contracts/daemon_supervisor.dart` | `startAll`, `stopAll`, `restartAll` | fleet-wide scope and typed failure |
| `domain/contracts/cron_gateway.dart` | `listCron`, `addCron` | list/add result and server validation |
| `domain/contracts/cron_gateway.dart` | `removeCron`, `setCronEnabled` | mutation target and typed failure |
| `domain/entities/cron_job.dart` | `cronResultFromWire` | unknown-wire fallback to `CronResult.unknown` |
| `domain/entities/daemon_info.dart` | `daemonStateFromWire` | unknown-wire fallback to `DaemonState.unknown` |

`RelayGateway`, `nextCronRun`, `supervisorPipeName`, `winPipeTransact`, and
`buildSettingsModule` already satisfy the Always tier after translation.

### UI/ViewModel and controller exports (18)

| File | Declaration(s) | Contract to document |
|---|---|---|
| `ui/cron_viewmodel.dart` | `CronLoad` | public load-state vocabulary |
| `ui/cron_viewmodel.dart` | `reload`, `setEnabled`, `remove`, `run` | hydration/mutation, busy state, and reload behavior |
| `ui/daemons_viewmodel.dart` | `DaemonsLoad` | public load-state vocabulary |
| `ui/daemons_viewmodel.dart` | `start`, `stop`, `restart`, `remove` | per-daemon busy/error/reload behavior |
| `ui/daemons_viewmodel.dart` | `startAll`, `stopAll`, `restartAll` | fleet busy/error/reload behavior |
| `ui/connectivity_viewmodel.dart` | `loadRelay`, `loadDevices` | independent loading/error state updates |
| `ui/pairing_controller.dart` | `start`, `retry` | ephemeral gateway replacement and retry lifecycle |
| `ui/revoke_controller.dart` | `run` | one-shot state transition and late-notification guard |

Trivial getters (`status`, `isBusy`, `anyBusy`, `hasDaemons`), self-documenting
fields, private helpers, Flutter `build()` overrides, and exported widgets with
simple constructors remain outside the Always gap-fill set. Data implementations
inherit the port docs rather than mirroring them.

## Implementation order

1. Run all three child stories in parallel; each has `depends_on: []` and
   exclusive file ownership.
2. Review the converged diff for terminology consistency (`relay`, `paired
   device`, `daemon`, `schedule`, `supervisor`, `pairing`, `revoke`) and rerun
   the scoped PT/string and documentation audits.
3. Serialize formatting, focused settings tests, `flutter analyze`, and the full
   `flutter test` gate from `cockpit/`.

## Testing and verification

No new product test is required for comment/dartdoc-only production edits. If a
runtime string actually changes, update only assertions that intentionally
cover that exact user-visible copy; never weaken or broadly rewrite tests.

### Scoped language and diff checks

From the repository root:

```bash
rg -n '[À-ÖØ-öø-ÿ]' cockpit/lib/app/settings --glob '*.dart'
```

Expected: no matches. Then manually review all 25 listed files for unaccented PT
(such as `para`, `com`, `sem`, `aparelho`, `pareamento`, `salvar`, `erro`,
`arquivo`) and inspect every changed quoted literal. Accent grep is a backstop,
not proof. Use `git diff --word-diff`/`git diff --check` to reject changes to
executable tokens, signatures, commands, paths, keys, or behavior.

Apply `.agents/skills/scan-documentation/SKILL.md` to all 35 module Dart files:

- every named Always-tier declaration has adjacent meaningful `///`;
- `Result` docs state success/failure or unknown/null meaning where non-obvious;
- lifecycle docs state ownership/teardown where relevant;
- no type-restating/obvious filler is added to widgets, DTOs, fields, overrides,
  tests, or private helpers.

### Focused settings tests

From `cockpit/`, using the repository-local toolchain:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter test \
  test/settings/app_preferences_settings_panel_test.dart \
  test/settings/connectivity_settings_panel_test.dart \
  test/settings/daemon_settings_panel_test.dart \
  test/settings/schedule_settings_panel_test.dart \
  test/settings/settings_route_shell_test.dart
```

### Final integration gate

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/dart format \
  --output=none --set-exit-if-changed lib/app/settings
~/projects/remote_pi/.tools/flutter/bin/flutter analyze
~/projects/remote_pi/.tools/flutter/bin/flutter test
```

If dependency resolution is needed first, run the documented offline step:

```bash
PUB_CACHE=~/projects/remote_pi/.pub-cache \
  ~/projects/remote_pi/.tools/flutter/bin/flutter pub get --offline
```

## Risks and pre-mortem

- **Riskiest assumption — runtime copy is already EN.** The accented-string
  probe can miss unaccented PT. Mitigation: the explicit eight-file literal
  review and changed-string diff are mandatory; no blanket replacement.
- **Contract prose can drift behavior.** A mistranslation could invert
  `Result`, timeout, lifecycle, or cron semantics while tests stay green.
  Mitigation: translate with adjacent code visible and retain symbols/error
  paths in dartdoc.
- **Documentation bloat.** Treating the ~38 syntax candidates as a quota would
  add noise to trivial widgets/getters. Mitigation: use the fixed 30-item
  Always-tier inventory and update it only with documented rationale.
- **Lifecycle comments can become false.** Pairing/revoke controllers and
  page-scoped ViewModels own resources. Mitigation: verify each lifecycle doc
  against `dispose` and the caller before accepting it.
- **Parallel Flutter-tool contention.** Three writers can own disjoint files,
  but concurrent Flutter commands share `.dart_tool`/cache state. Mitigation:
  parallelize edits and local review, then serialize the final full gate.

Fallback: if a translation or literal change causes a failure, retain verified
comment/dartdoc edits, revert the suspect runtime-string hunk, and re-translate
that one literal with its focused widget test. Do not change product logic or
weaken assertions to rescue a prose pass.

No foundation document update is required: this feature implements the already
landed EN-first/native-documentation policy without changing product behavior,
architecture, or protocol.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- cockpit/lib/app/settings/`).

### Findings
- None. PT sweeps clean; no signature/identifier/enum/wire-value/lifecycle
  change. Dartdoc meaningful and tier-appropriate.

### Verdict
Approve. Advanced `review → done`.
