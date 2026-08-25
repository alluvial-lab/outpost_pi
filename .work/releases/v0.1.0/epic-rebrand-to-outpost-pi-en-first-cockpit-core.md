---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-core
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

# EN-first + dartdoc gap-fill — cockpit core module

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit `core` module — the shared foundation (cross-cutting domain,
data, UI, utils, routes, env). 54 PT-bearing Dart files: `core/domain` (15),
`core/data` (16), `core/ui` (17), plus `core/utils`, `core/routes.dart`,
`core/env.dart`, `core/app_intents.dart`, `core/core_module.dart`.

PT is overwhelmingly comment prose (the cockpit-wide ratio is ~2,100 PT
comment-lines vs ~18 string literals). Gap-fill scope is the Always tier per
the doc convention: exported Dart classes/functions from shared/domain
layers, service-layer functions, `Result`/`Either`-returning functions,
ViewModel exports. The `core/domain/contracts/` and `core/domain/entities/`
surfaces are the contract-bearing areas most likely to need gap-fill.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent mid-large slice. No `depends_on` — the
  cockpit's wire-stable identifiers (control-RPC discriminator) already
  migrated in the first rebrand epic. Can run in parallel with every other
  child feature. Shares the cockpit build gate (`flutter analyze` + `flutter
  test`) with the other cockpit features, but the file sets are disjoint.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format
  and the Always tier for Dart.
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference;
  read before editing `cockpit/`.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- Parent epic `## Grounded surface measurement` — the 54-file count for core.

## Edge case: generated file

`cockpit/lib/app/core/ui/file_icons/file_icon_map.g.dart` is a generated file
(`// GENERATED — do not edit by hand.`) whose header comment carries PT
("Mapeamento arquivo/pasta -> ícone..."). It is **shipped** (lives in `lib/`,
not in the epic's excluded generated/vendored dirs), so its PT is in scope for
translation. However it is **generated** (Skip tier for gap-fill — do not add
dartdoc to its internals). The design pass should: translate the header
comment to EN (one-time edit; the generator source is a script, out of scope
per the `scripts/` exclusion, so it will not be regenerated in this epic), and
skip gap-fill on the generated body. See parent epic `## Design decisions`.

## What this feature does NOT cover
- Wire-stable identifiers (control-RPC discriminator) — owned by the first
  rebrand epic, already shipped.
- Product-identity string renames — owned by the mechanical-rename feature.
- `scripts/` shell comments — out of scope (operator glue).
- Generated/vendored state (`.dart_tool/`, build output).

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
## Test files in scope

4 root-level cockpit test files carry PT and test core/DI/factory wiring:
`cockpit/test/widget_test.dart`, `cockpit/test/lsp_pool_di_test.dart`,
`cockpit/test/core_factories_resolve_test.dart`,
`cockpit/test/feature_resolves_core_upward_test.dart`. Tests are Skip-tier for
gap-fill (per the doc convention); the only work is PT→EN translation of
comments and test descriptions (the latter are user-facing in test output and
need translation-review, not sed).

Plus a grep confirming zero PT (accented Latin) in `cockpit/lib/app/core/`
and the 4 root-level `cockpit/test/*.dart` files.

## Design decisions

- **What is the authoritative source set?** Translate all 54 PT-bearing Dart
  files under `cockpit/lib/app/core/` plus the four named root tests. The
  layer probe found 16 domain files, 16 data files, 17 UI files, and five
  root/utils files; the earlier 15-file domain subtotal omitted
  `domain/contracts/disposable.dart`, whose unaccented sentence is still
  Portuguese. `ui/themes/themes.dart` is the one core Dart barrel with no PT
  and remains untouched. This reconciles the 54-file total without relying
  only on accented-character detection.
- **How are runtime strings handled?** Review every string literal manually and
  translate only human-readable PT. Preserve paths, protocol/control values,
  JSON keys, command names, identifiers, icon-map entries, and test
  expectations. The bounded core review found the theme assertion, two LSP
  debug labels, and two ephemeral-pairing labels as the runtime-string
  candidates; they are not safe for blanket replacement.
- **How broad is dartdoc gap-fill?** Use only the convention's Always tier. The
  verified gap inventory is the ten declarations listed below. Existing useful
  dartdoc is translated in place; Recommended/Skip declarations do not receive
  filler comments.
- **How is the work split?** Use three dependency-free stories with disjoint
  ownership: domain/composition/tests, data adapters, and UI/generated-file.
  This permits raised-tier parallel implementation while keeping the final
  cockpit-wide Flutter gate serialized after the three diffs converge.
- **How is the generated file handled?** Make a one-time edit only to the PT
  header of `file_icon_map.g.dart`. Do not format, reorder, document, or edit
  generated constants/maps. The generator script remains excluded.
- **Does this need UI mockups?** No. This changes documentation, diagnostic
  prose, test descriptions, and internal labels; it adds no screen, journey,
  layout, or interaction. The feature-design UI fallback is therefore skipped.
- **Was design-time advisory review needed?** No. The parent epic and landed
  documentation convention already lock the only potentially broad choices;
  this is a large file-count but low-risk, behavior-preserving content pass
  with no irreversible architecture decision.

## Architectural choice

Use a **layer-owned, review-first translation pass with an explicit dartdoc
inventory**. Each story owns complete files, translates existing prose in
context, reviews the few runtime/test strings separately, and adds dartdoc only
for named Always-tier gaps. This optimizes for semantic accuracy and merge-safe
parallel ownership.

Alternatives considered:

1. **One monolithic 58-file pass.** It has the simplest bookkeeping, but creates
   an unnecessarily large review unit and prevents independent raised-tier
   workers from owning disjoint layers.
2. **Separate translation and dartdoc stories.** It makes the two concerns
   visible, but both would edit the same declarations and comments, producing
   avoidable conflicts and duplicate context loading.
3. **One story per file.** It maximizes theoretical fan-out but turns a bounded
   prose pass into 58 tracking units and loses layer vocabulary consistency.

The chosen three-story split avoids overlapping writes while keeping each
worker responsible for coherent terminology in its layer. No production
abstraction, API, dependency direction, or generated contract changes.

## Implementation Units

### Unit 1: Domain contracts, composition roots, utilities, and root tests

**Story**: `epic-rebrand-to-outpost-pi-en-first-cockpit-core-domain-composition-tests`

**Files — domain translation (16):**

- `cockpit/lib/app/core/domain/contracts/disposable.dart`
- `cockpit/lib/app/core/domain/contracts/environment_probe.dart`
- `cockpit/lib/app/core/domain/contracts/lsp_client.dart`
- `cockpit/lib/app/core/domain/contracts/pairing_gateway.dart`
- `cockpit/lib/app/core/domain/contracts/revoke_gateway.dart`
- `cockpit/lib/app/core/domain/contracts/service.dart`
- `cockpit/lib/app/core/domain/contracts/settings_store.dart`
- `cockpit/lib/app/core/domain/contracts/system_permissions.dart`
- `cockpit/lib/app/core/domain/contracts/usecase.dart`
- `cockpit/lib/app/core/domain/entities/app_settings.dart`
- `cockpit/lib/app/core/domain/entities/lsp_diagnostic.dart`
- `cockpit/lib/app/core/domain/entities/pair_event.dart`
- `cockpit/lib/app/core/domain/entities/setup_check.dart`
- `cockpit/lib/app/core/domain/exceptions/lsp_error.dart`
- `cockpit/lib/app/core/domain/exceptions/relay_error.dart`
- `cockpit/lib/app/core/domain/result.dart`

**Files — composition/utils translation (5):**

- `cockpit/lib/app/core/app_intents.dart`
- `cockpit/lib/app/core/core_module.dart`
- `cockpit/lib/app/core/env.dart`
- `cockpit/lib/app/core/routes.dart`
- `cockpit/lib/app/core/utils/executable_resolver.dart`

**Files — test prose/description translation (4):**

- `cockpit/test/widget_test.dart`
- `cockpit/test/lsp_pool_di_test.dart`
- `cockpit/test/core_factories_resolve_test.dart`
- `cockpit/test/feature_resolves_core_upward_test.dart`

**Exact Always-tier declarations to document (9):**

```dart
abstract class Disposable {
  void dispose();
}

abstract class LspClientFactory {
  LspClient create({required LspServerSpec spec, required String rootPath});
}

abstract class PairingGatewayFactory {
  PairingGateway create();
}

abstract class RevokeGateway {
  Future<Result<void, RelayError>> revoke(
    String shortId, {
    Duration timeout,
  });
}

abstract class RevokeGatewayFactory {
  RevokeGateway create();
}

final class Success<S, F> extends Result<S, F> { /* unchanged */ }
final class Failure<S, F> extends Result<S, F> { /* unchanged */ }
extension CheckStatusX on CheckStatus { /* unchanged */ }

Future<String> resolveExecutable(
  String name, {
  List<String> unixCandidates = const [],
  List<String> unixHomeRelative = const [],
  List<String> windowsExtraDirs = const [],
});
```

The dartdoc must explain lifecycle ownership for `dispose`, fresh-instance
semantics for factories, `Success`/`Failure` branch meaning, the revoke
result/error contract, the setup-gate extension's purpose, and executable
resolution/fallback behavior. Do not restate parameter types. Existing member
comments inherited by implementations are not duplicated on overrides.

**Implementation notes:**

- Translate code comments and existing dartdoc with technical vocabulary
  preserved: LSP/JSON-RPC, Flutter Modular DI, `Result`, process lifecycle,
  `PiSpawnConfig`, and command/route identifiers remain literal.
- Translate test descriptions and comments, but keep setup/file-icon assertions,
  fixtures, import paths, and DI construction unchanged.
- `widget_test.dart` is owned here despite exercising a UI helper because all
  four root tests form one bounded composition/contract review set.
- `executable_resolver.dart` currently has adjacent prose whose attachment makes
  `resolveExecutable` undocumented; separate the intent into meaningful EN
  dartdoc without changing resolution order or timeout behavior.

**Acceptance criteria:**

- [ ] All 25 listed files contain no Portuguese prose or PT test descriptions.
- [ ] The nine named gaps have meaningful EN `///` dartdoc; tests and DTO-only
      declarations receive no gap-fill noise.
- [ ] Public signatures, DI graph, route constants, executable search order,
      result behavior, and test assertions are byte-semantically unchanged.
- [ ] The four named root tests pass.

---

### Unit 2: Data adapters and shared services

**Story**: `epic-rebrand-to-outpost-pi-en-first-cockpit-core-data-adapters`

**Files — data translation (16):**

- `cockpit/lib/app/core/data/lsp/lsp_client_impl.dart`
- `cockpit/lib/app/core/data/lsp/lsp_codec.dart`
- `cockpit/lib/app/core/data/lsp/lsp_command.dart`
- `cockpit/lib/app/core/data/lsp/lsp_launchers.dart`
- `cockpit/lib/app/core/data/lsp/lsp_process_registry.dart`
- `cockpit/lib/app/core/data/lsp/lsp_server_pool.dart`
- `cockpit/lib/app/core/data/lsp/lsp_text_edit.dart`
- `cockpit/lib/app/core/data/lsp/project_root_finder.dart`
- `cockpit/lib/app/core/data/relay/ephemeral_pi_rpc.dart`
- `cockpit/lib/app/core/data/relay/pairing_gateway_impl.dart`
- `cockpit/lib/app/core/data/relay/revoke_gateway_impl.dart`
- `cockpit/lib/app/core/data/repositories/hive_settings_store.dart`
- `cockpit/lib/app/core/data/rpc/jsonl_line_splitter.dart`
- `cockpit/lib/app/core/data/setup/environment_probe_impl.dart`
- `cockpit/lib/app/core/data/setup/outpost_pi_resolver.dart`
- `cockpit/lib/app/core/data/setup/system_permissions_impl.dart`

**Signatures and behavior boundaries to preserve:**

```dart
class LspClientImpl implements LspClient { /* unchanged */ }
class LspServerPool { /* unchanged */ }
class EphemeralPiRpc { /* unchanged */ }
class PairingGatewayImpl implements PairingGateway { /* unchanged */ }
class RevokeGatewayImpl implements RevokeGateway { /* unchanged */ }
class HiveSettingsStore implements SettingsStore { /* unchanged */ }
class JsonlLineSplitter
    extends StreamTransformerBase<List<int>, String> { /* unchanged */ }
```

**Implementation notes:**

- Translate comments/dartdoc in context; retain adapter-specific lifecycle and
  graceful-degradation details rather than replacing them with generic prose.
- Manually review the two LSP debug labels and two ephemeral pairing labels.
  Translate their human-readable PT only; keep logging shape, JSON keys,
  temp-directory mechanics, RPC prompt, and uniqueness suffix unchanged.
- Existing adapter docs already satisfy Always-tier coverage. Override methods
  inherit their domain contract; do not duplicate dartdoc merely because the
  implementation is public.
- No changes to LSP framing, process spawn/kill order, Hive keys, JSON fields,
  permission behavior, or executable resolution.

**Acceptance criteria:**

- [ ] All 16 listed files contain no Portuguese prose or human-readable PT
      runtime labels.
- [ ] No new dartdoc is added outside a genuinely discovered Always-tier gap;
      any discovery is recorded back in this feature before implementation is
      considered complete.
- [ ] LSP framing/lifecycle, pairing/revoke behavior, persistence, and setup
      probing are unchanged apart from human-readable labels.
- [ ] Focused LSP/data tests pass.

---

### Unit 3: Shared UI, themes, widgets, and generated-header exception

**Story**: `epic-rebrand-to-outpost-pi-en-first-cockpit-core-ui-generated-file`

**Files — UI translation (17):**

- `cockpit/lib/app/core/ui/file_icons/file_icon.dart`
- `cockpit/lib/app/core/ui/file_icons/file_icon_map.g.dart`
- `cockpit/lib/app/core/ui/file_icons/file_icons.dart`
- `cockpit/lib/app/core/ui/settings_controller.dart`
- `cockpit/lib/app/core/ui/themes/app_colors.dart`
- `cockpit/lib/app/core/ui/themes/app_theme.dart`
- `cockpit/lib/app/core/ui/themes/app_typography.dart`
- `cockpit/lib/app/core/ui/themes/cockpit_theme.dart`
- `cockpit/lib/app/core/ui/themes/syntax_colors.dart`
- `cockpit/lib/app/core/ui/themes/terminal_theme.dart`
- `cockpit/lib/app/core/ui/themes/theme_extensions.dart`
- `cockpit/lib/app/core/ui/widgets/app_menu.dart`
- `cockpit/lib/app/core/ui/widgets/code_editing_controller.dart`
- `cockpit/lib/app/core/ui/widgets/code_highlight.dart`
- `cockpit/lib/app/core/ui/widgets/hover_tap.dart`
- `cockpit/lib/app/core/ui/widgets/macos_notification_instructions_dialog.dart`
- `cockpit/lib/app/core/ui/widgets/window_controls.dart`

`cockpit/lib/app/core/ui/themes/themes.dart` is explicitly excluded: it is a
Skip-tier barrel and contains no Portuguese.

**Exact Always-tier declaration to document (1):**

```dart
extension AppThemeX on BuildContext {
  AppColors get colors;
  AppTypography get typo;
  SyntaxColors get syntax;
}
```

Document the extension's shared theme-token/fallback contract once; do not add
redundant comments to each obvious getter.

**Generated-file handling:**

- In `file_icon_map.g.dart`, translate only the leading generated-file header
  before `// ignore_for_file:`.
- Preserve `// GENERATED — do not edit by hand.`, attribution URL, version,
  license, regeneration warning, and dark/default variant meaning in EN.
- Do not add dartdoc to constants/maps and do not run formatting that rewrites
  the generated body. Review the diff to prove every line after
  `// ignore_for_file:` is unchanged.

**Implementation notes:**

- Translate existing widget/theme dartdoc without changing theme tokens,
  colors, typography, widget parameters, or rendering behavior.
- Manually translate the human-readable `CockpitTheme` assertion while
  preserving the assertion condition and exception behavior.
- `SettingsController` already has a meaningful ViewModel-style class contract;
  translate it but do not add one comment per self-documenting setter.

**Acceptance criteria:**

- [ ] The 17 listed files contain no Portuguese prose or human-readable PT
      assertion text.
- [ ] `AppThemeX` has meaningful EN `///` dartdoc and no redundant getter docs.
- [ ] `file_icon_map.g.dart` differs only in its leading header; all generated
      constants and mappings remain identical.
- [ ] Themes, widgets, icon lookup, and settings behavior are unchanged, and
      `cockpit/test/widget_test.dart` passes after integration.

## Always-tier dartdoc audit

The self-check applied `.agents/skills/scan-documentation/SKILL.md` to the core
surface and classified generated code, tests, barrels, DTO-only wire shapes,
trivial helpers, and Flutter `build()` overrides as Skip. It confirmed the
brief's approximate baseline as these **ten actionable gaps**:

| Layer | File | Declaration | Contract to document |
|---|---|---|---|
| domain | `domain/contracts/disposable.dart` | `Disposable.dispose` | explicit resource teardown |
| domain | `domain/contracts/lsp_client.dart` | `LspClientFactory.create` | fresh client and root/spec ownership |
| domain | `domain/contracts/pairing_gateway.dart` | `PairingGatewayFactory.create` | fresh ephemeral attempt |
| domain | `domain/contracts/revoke_gateway.dart` | `RevokeGateway.revoke` | `Result` success/failure and timeout |
| domain | `domain/contracts/revoke_gateway.dart` | `RevokeGatewayFactory.create` | fresh ephemeral revoke gateway |
| domain | `domain/result.dart` | `Success` | successful branch meaning |
| domain | `domain/result.dart` | `Failure` | failure branch meaning |
| domain | `domain/entities/setup_check.dart` | `CheckStatusX` | setup-gate projection purpose |
| utils | `utils/executable_resolver.dart` | `resolveExecutable` | platform resolution/fallback contract |
| UI | `ui/themes/theme_extensions.dart` | `AppThemeX` | token access and fallback contract |

If implementation exposes a mismatch between this syntax-level audit and the
actual declaration intent, update this inventory before adding docs; do not
silently widen the tier.

## Implementation Order

1. Run the three dependency-free stories in parallel with exclusive file
   ownership.
2. Re-run the scoped PT scan and `scan-documentation` audit over the converged
   tree; resolve only genuine misses.
3. Serialize formatting/analyze/test verification from `cockpit/` so parallel
   workers do not contend over Flutter tool state.

## Testing and verification

This is intended to be behavior-preserving, so tests prove that translation and
dartdoc edits did not alter syntax or behavior rather than adding new product
tests.

### Scoped language checks

From the repository root, scan exactly the 54 core source files and four root
tests:

```bash
rg -n '[À-ÖØ-öø-ÿ]' cockpit/lib/app/core \
  cockpit/test/widget_test.dart \
  cockpit/test/lsp_pool_di_test.dart \
  cockpit/test/core_factories_resolve_test.dart \
  cockpit/test/feature_resolves_core_upward_test.dart \
  --glob '*.dart'
```

Expected: no matches. Then run a manual lexical review for unaccented PT terms
such as `pareamento`, `falhou`, `desligou`, `arquivo`, `pasta`, `deve`, `para`,
`com`, and `sem`, because accented-only grep would have missed
`disposable.dart` and pairing labels. Treat technical/proper-name matches as
review candidates, not automatic replacements.

Re-run the `scan-documentation` rules against `cockpit/lib/app/core/`; expected:
no missing or inadequate Always-tier dartdoc, no docs added to generated/test/
barrel declarations, and no obvious type-restatement comments.

### Focused tests

From `cockpit/`, with the repository-local toolchain:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter test \
  test/widget_test.dart \
  test/lsp_pool_di_test.dart \
  test/core_factories_resolve_test.dart \
  test/feature_resolves_core_upward_test.dart

~/projects/remote_pi/.tools/flutter/bin/flutter test \
  test/data/lsp_codec_test.dart \
  test/data/lsp_server_pool_test.dart \
  test/data/lsp_root_and_offsets_test.dart \
  test/data/lsp_text_edit_test.dart
```

### Final integration gate

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
find lib/app/core -name '*.dart' \
  ! -path '*/ui/file_icons/file_icon_map.g.dart' -print0 \
  | xargs -0 ~/projects/remote_pi/.tools/flutter/bin/dart format \
      --output=none --set-exit-if-changed
~/projects/remote_pi/.tools/flutter/bin/dart format \
  --output=none --set-exit-if-changed \
  test/widget_test.dart \
  test/lsp_pool_di_test.dart \
  test/core_factories_resolve_test.dart \
  test/feature_resolves_core_upward_test.dart
~/projects/remote_pi/.tools/flutter/bin/flutter analyze
~/projects/remote_pi/.tools/flutter/bin/flutter test
```

Do not format `lib/app/core/ui/file_icons/file_icon_map.g.dart`. Review
`git diff --check` and the generated-file diff separately.

## Risks

- **Semantic drift in technical comments.** LSP framing, DI scope, process
  lifecycle, and Result semantics could be mistranslated even while code still
  compiles. Mitigation: translate by layer with local vocabulary and review the
  comment against the adjacent implementation.
- **Runtime label mistaken for an identifier.** The ephemeral pairing labels
  and debug/assert text are human-readable, but nearby JSON keys and commands
  are contracts. Mitigation: change only the bounded values identified above
  and keep keys/commands untouched.
- **Generated-body churn.** Formatting or broad replacement could rewrite a
  5,000-line generated map. Mitigation: header-only ownership plus a diff check
  proving no post-header changes.
- **False confidence from accented-only grep.** Portuguese can be entirely
  unaccented. Mitigation: the explicit 54-file inventory, known-term lexical
  review, and manual scan complement the required accent grep.
- **Parallel Flutter-tool contention.** Three writers can safely own disjoint
  files, but concurrent analyze/test processes share `.dart_tool` and cache
  state. Mitigation: parallelize editing/focused review, then serialize the
  final full gate.

Fallback: if parallel translation produces inconsistent terminology, keep the
three file-owned diffs but run one final vocabulary normalization pass before
verification. No rollback or architectural alternative is needed because the
work changes no APIs or persistence/wire shape.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- cockpit/lib/app/cockpit/core/`).

### Findings (adjudicated)
- **Nit — stale implementation note** (`.work/active/stories/epic-rebrand-to-outpost-pi-en-first-cockpit-core-ui-generated-file.md:98-102`): the note claimed four PT dartdoc lines remain in the generated map, but `file_icon_map.g.dart:17,1389,3517,4450` are English. Corrected the story note. **Fixed (story body only; no source change).**
- No other findings; PT sweeps clean, no behavior/contract change, intended literal translations bounded at `lsp_server_pool.dart:111,275`, `ephemeral_pi_rpc.dart:49,135`, `cockpit_theme.dart:33`. The fallback URL change at `update_viewmodel.dart:49` belongs to mechanical-rebrand commit `fd10433`, not this feature.

### Verdict
Approve. Advanced `review → done`.
