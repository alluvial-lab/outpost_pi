---
id: feature-theme-token-cross-surface-contract
kind: feature
stage: done
tags: [app, cockpit, branding, testing]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Theme token cross-surface contract (generate/golden the ports + dual-mode contrast tests)

## Brief

Formed by groom 2026-08-26 from two items that are the two halves of one
contract problem: `gate-patterns-v050-token-port-drift` is the drift risk,
`gate-tests-theme-dual-mode-contrast` is explicitly its verification half
("natural home for the shared cross-surface fixture noted in the
`paired-brightness-semantic-palettes` pattern's drift risks").

Sources (bodies retained in `.work/archive/`).

## Work

1. **Token-port drift** — `tokens.css` is ported by hand into app and cockpit
   Dart with duplicated literal assertions and no shared cross-surface
   fixture; any contract change risks silent per-surface drift. Direction:
   generate or golden-test the ports against the contract
   (`.mockups/design-system/tokens.css` is the contract per AGENTS.md).
2. **Dual-mode theme property tests** — current theme tests assert registry
   literals + font names only; public builders
   (`app/lib/ui/core/themes/app_theme.dart:74-84`,
   `cockpit/lib/app/core/ui/themes/app_theme.dart:19-45`) are never invoked.
   Property-oriented tests for both builders: correct brightness, token
   extensions, semantic ColorScheme wiring, WCAG AA ratios for
   primary-text/bg, muted-text/bg, accent/bg, on-accent/accent. Keep literal
   identity assertions only for the locked brand contract.
3. **Mark geometry triple-encoding** (carried from the token-port item) —
   Constellation III encoded in Python (`scripts/generate-brand-assets.py:19-56`),
   canonical SVG (`branding/`, declared source of truth), and independently
   in `site/src/app/opengraph-image.tsx:37-46`. Single-source the geometry.

The shared cross-surface fixture from (2) is the anchor (1) generates or
golds against — design them together.

## Design decisions

- **Generate Dart palettes or golden-test native ports**: Keep the app and cockpit palettes hand-authored and golden-test their direct shared roles against one checked-in JSON fixture generated from `tokens.css`. Dart code generation would need two output templates, would blur each surface's intentionally different semantic roles, and would add production build tooling for values that change rarely. A generated golden plus a mandatory freshness check catches CSS-to-fixture and fixture-to-Dart drift while remaining cheap to reverse if the token surface later grows enough to justify codegen.
- **Golden freshness**: A root Python synchronizer owns fixture generation and a `--check` mode enforced in CI. Merely checking Dart against an unchecked JSON copy would move rather than remove the drift risk.
- **Fixture scope**: The shared fixture contains only direct, named CSS contract roles for dark and light modes plus the WCAG AA normal-text threshold. App-only and cockpit-only derived roles stay in their native palettes and are not promoted into a false cross-surface contract.
- **Canonical mark source**: `branding/logo-foreground.svg` is the machine-readable Constellation III geometry source. A restricted standard-library SVG reader projects its path, rounded rectangle, circles, colors, stroke, and viewBox into Pillow drawing data and a checked-in generated TypeScript constant. The generated projection is reviewable contract source, analogous to checked-in protocol projections, not a build artifact.
- **Dependency shape**: Root/site contract tooling lands first, mobile proves the shared role vocabulary second, and cockpit adopts that vocabulary third. The linear chain deliberately prevents two Flutter surfaces from inventing different fixture aliases during the first migration; feature implementation still remains one cohesive ownership/review bundle.
- **Discovery and review posture**: Direct-read mapping was sufficient after inspecting the CSS contract, both palettes/builders/tests, canonical SVG, rasterizer, OG component, and CI. No exploratory adapter is available in this delegated context; design-time advisory review is non-blocking, while the caller's standard single-pass fresh-context review remains required after implementation.
- **UI mockups**: None. This feature changes contract projection and tests without changing a user-facing composition or journey.

## Architectural choice

### Considered approaches

1. **Generate production Dart from CSS.** Parse `tokens.css` and emit app and cockpit palette declarations. This gives the strongest edit-once behavior, but needs separate templates because the two `AppColors` APIs intentionally differ, makes CSS syntax part of both Flutter builds, and risks generated files swallowing meaningful surface-specific derivation. The tooling cost is disproportionate to a small, stable palette.
2. **Generate one shared golden fixture and assert native ports against it (chosen).** A root synchronizer projects the canonical CSS into deterministic JSON; CI checks freshness; each Flutter suite maps only its direct shared roles to the fixture and then tests its public builder properties. This preserves native APIs while closing both drift seams with little production complexity.
3. **Parse CSS directly in each Flutter test.** This avoids a generated JSON file but duplicates a CSS parser and repository-path assumptions in two Dart suites. The test machinery itself would become another hand-maintained cross-language contract.

The chosen approach follows the project's generated-or-inferred contract rule without overfitting code generation to two intentionally different native theme types. The same synchronizer pattern also solves the mark's triple encoding: canonical SVG in, checked projections out, with a deterministic check.

## Implementation Units

### Unit 1: Shared contract synchronizer and canonical geometry fan-out

**Story**: `feature-theme-token-cross-surface-contract-contract-tooling`

**Files**:
- `scripts/brand_contract.py` (new)
- `scripts/sync-brand-contracts.py` (new)
- `scripts/generate-brand-assets.py`
- `branding/theme-contract.json` (new checked-in golden)
- `site/src/generated/constellation_mark.generated.ts` (new checked-in projection)
- `site/src/app/opengraph-image.tsx`
- `.github/workflows/ci.yml`

```python
@dataclass(frozen=True)
class RoundedRect:
    x: float
    y: float
    width: float
    height: float
    radius: float

@dataclass(frozen=True)
class Circle:
    cx: float
    cy: float
    radius: float

@dataclass(frozen=True)
class MarkGeometry:
    view_box: tuple[float, float, float, float]
    edge_path: str
    stroke_width: float
    stroke_linecap: str
    hub: RoundedRect
    peers: tuple[Circle, ...]
    ink: str
    accent: str


def load_mark_geometry(path: Path) -> MarkGeometry: ...
def build_theme_fixture(tokens_css: str) -> dict[str, object]: ...
def render_mark_typescript(mark: MarkGeometry) -> str: ...
def sync_contracts(*, check: bool) -> bool: ...
```

```ts
// Generated by scripts/sync-brand-contracts.py; do not edit.
export const constellationMark = {
  viewBox: "0 0 1024 1024",
  edgePath: "M 398 564 L 695 385 M 398 564 L 633 693",
  strokeWidth: 34,
  strokeLinecap: "round",
  hub: { x: 314, y: 480, width: 168, height: 168, radius: 25 },
  peers: [
    { cx: 695, cy: 385, radius: 63 },
    { cx: 633, cy: 693, radius: 71 },
  ],
  ink: "#E4EFE8",
  accent: "#74CC9C",
} as const;
```

**Implementation notes**:
- Parse only the canonical `:root, :root[data-theme="dark"]` and `:root[data-theme="light"]` declarations and an explicit allowlist of shared color variables. Reject missing, duplicate, unsupported, or non-color values with the token/selector named in the error. Do not attempt to become a general CSS parser.
- Emit deterministic JSON with `schemaVersion: 1`, `source: ".mockups/design-system/tokens.css"`, `wcagAaNormalText: 4.5`, and `modes.dark/light`. Use stable role names (`bgPrimary`, `bgSecondary`, `bgTertiary`, `textPrimary`, `textSecondary`, `textLink`, `textLinkHover`, `border`, `borderStrong`, `accent`, `accentHover`, `accentMuted`, `onAccent`, `success`, `warning`, `error`, `info`, and status backgrounds).
- The restricted SVG reader fails fast unless the foreground SVG contains the expected one path, one rounded rectangle, and two peer circles within a 1024-unit viewBox. It reads geometry and mark colors rather than reproducing coordinates.
- Refactor `draw_mark` to accept `MarkGeometry`; it may still own raster concerns such as supersampling, round-cap emulation, alpha/background choice, and output dimensions.
- The TypeScript projection is generated source because `ImageResponse` needs renderable geometry without runtime filesystem/network dependence. `opengraph-image.tsx` maps the constant into SVG elements and retains only layout/copy/background concerns.
- `sync-brand-contracts.py --check` prints the stale output paths and exits non-zero without writing. Its write mode updates only the JSON/TypeScript contract projections; raster regeneration remains an explicit `generate-brand-assets.py` action.
- Add a `brand-contract` CI change filter/job, and include token/fixture paths in app and cockpit filters plus SVG/generated geometry paths in site. This ensures changing a canonical source cannot skip its consumer suites.

**Acceptance criteria**:
- [ ] Changing any allowlisted CSS role without syncing makes `python3 scripts/sync-brand-contracts.py --check` fail; syncing produces deterministic JSON.
- [ ] Missing or structurally changed canonical SVG geometry fails with an actionable boundary error rather than silently drawing a partial mark.
- [ ] Rasterizer and OG component contain no Constellation III coordinate, radius, or stroke-width copies.
- [ ] Generated TypeScript exactly reflects the canonical SVG and `pnpm lint && pnpm build` accepts its use.
- [ ] CI path routing runs the synchronizer and every affected consumer lane on contract changes.

---

### Unit 2: Mobile public-theme contract and contrast properties

**Story**: `feature-theme-token-cross-surface-contract-app-theme-properties`

**Files**:
- `app/test/ui/core/themes/theme_contract_fixture.dart` (new test helper)
- `app/test/ui/core/themes/app_theme_test.dart`

```dart
final class ThemeContractFixture {
  ThemeContractFixture._(this._modes, this.wcagAaNormalText);

  final Map<String, Map<String, String>> _modes;
  final double wcagAaNormalText;

  static ThemeContractFixture load({String path = '../branding/theme-contract.json'});
  Color color(Brightness brightness, String role);
}

Map<String, Color> appContractRoles(AppColors colors);
double wcagContrast(Color foreground, Color background);
```

**Implementation notes**:
- The loader is test-only and validates `schemaVersion`, both modes, role strings, and `#RRGGBB`/`rgba(...)` forms before producing Flutter colors. A malformed fixture fails at the test boundary with the role named.
- `appContractRoles` maps only direct ports: background/surface/tertiary surface, border pair, primary/muted text, accent/accent-hover/on-accent, and success/warning/error/info. Derived roles such as user bubbles and badges remain covered only by behavior that uses them, not forced into the shared fixture.
- Table-drive both `buildDarkTheme()` and `buildLightTheme()`. Read the installed `AppColors` and `AppTypography` extensions from each built `ThemeData`, then assert brightness, scaffold background, and every Material scheme mapping.
- Compute WCAG 2.1 relative luminance through Flutter's `Color.computeLuminance()` and apply `(lighter + 0.05) / (darker + 0.05)`. Assert the fixture threshold against built values, not fixture values, so a builder wiring regression fails.
- Remove the duplicated per-mode hex matrices. Retain Space Mono checks and the strong-divider property because they protect separate stable behavior.

**Acceptance criteria**:
- [ ] Every direct mobile palette role equals the corresponding shared fixture role in dark and light modes.
- [ ] Both public theme builders install the requested brightness and matching color/typography extensions.
- [ ] Material semantic slots map to the intended `AppColors` roles.
- [ ] Primary text/background, muted text/background, accent/background, and on-accent/accent are each at least 4.5:1 in both modes.
- [ ] App analysis and non-E2E tests pass without production-code changes solely for test access.

---

### Unit 3: Cockpit public-theme contract and contrast properties

**Story**: `feature-theme-token-cross-surface-contract-cockpit-theme-properties`

**Files**:
- `cockpit/test/core/ui/themes/theme_contract_fixture.dart` (new test helper, same fixture schema/vocabulary as app)
- `cockpit/test/core/ui/themes/app_theme_test.dart`

```dart
final class ThemeContractFixture {
  ThemeContractFixture._(this._modes, this.wcagAaNormalText);

  final Map<String, Map<String, String>> _modes;
  final double wcagAaNormalText;

  static ThemeContractFixture load({String path = '../branding/theme-contract.json'});
  Color color(Brightness brightness, String role);
}

Map<String, Color> cockpitContractRoles(AppColors colors);
double wcagContrast(Color foreground, Color background);
```

**Implementation notes**:
- Keep the test helper local to Cockpit rather than creating a production/shared Dart package; the JSON schema and role names are the seam, and a tiny native loader avoids coupling the two Flutter package graphs.
- Table-drive `buildTokens(brightness: ...)` and `buildTheme(brightness: ...)` for dark and light. Cockpit does not install Flutter `ThemeExtension`s; its equivalent public seam is the `CockpitTokens` bundle, so assert that bundle and the shadcn scheme agree rather than inventing a Material extension requirement.
- Map shadcn roles precisely: background/foreground, card/cardForeground, primary/primaryForeground, secondary/secondaryForeground, muted/mutedForeground, accent/accentForeground, destructive, border/input/ring. Account for shadcn's neutral `accent` slot; the brand accent is `primary`.
- Run the four required contrast pairs against `buildTokens(...).colors`. Retain focused terminal cursor, syntax color, and configured typography tests; remove only duplicated shared palette literals.

**Acceptance criteria**:
- [ ] Every direct cockpit palette role equals the corresponding shared fixture role in both modes.
- [ ] `buildTokens` and `buildTheme` resolve the requested brightness and semantically agree.
- [ ] Every listed shadcn slot maps to the intentional cockpit role, including neutral shadcn accent versus brand primary.
- [ ] The four required pairs are each at least 4.5:1 in dark and light modes.
- [ ] Cockpit analysis and tests pass, preserving independent syntax/terminal/font evidence.

## Implementation order

1. `feature-theme-token-cross-surface-contract-contract-tooling` — establish fixture freshness, SVG projection, CI routing, and site consumption.
2. `feature-theme-token-cross-surface-contract-app-theme-properties` — establish the fixture role mapping and exercise mobile builders.
3. `feature-theme-token-cross-surface-contract-cockpit-theme-properties` — reuse the established vocabulary for cockpit builders and shadcn wiring.

## Simplification

- Delete the duplicate dark/light hex assertion matrices from both Flutter theme tests; the fixture-backed maps supersede them.
- Delete geometry coordinates, radii, and stroke width from `scripts/generate-brand-assets.py` and `site/src/app/opengraph-image.tsx`; only canonical SVG plus checked projections remain.
- Do not create a shared production Dart package, CSS parser in Dart, or generated palette classes. Those abstractions cost more than the stable contract currently warrants.
- Keep surface-specific semantic aliases rather than forcing app and cockpit into one `AppColors` API; their native role differences are intentional, not drift.

## Testing

- **Contract freshness**: `python3 scripts/sync-brand-contracts.py --check` protects canonical CSS/SVG to checked-projection seams and rejects stale generated sources.
- **Cross-surface interface tests**: app and cockpit compare their native direct-role maps to the same fixture. This is the core drift regression evidence.
- **Public-builder properties**: both modes exercise actual theme builders, extensions/token bundles, and framework color schemes rather than only static registries.
- **Accessibility regression**: four contract-relevant pairs are checked at WCAG AA normal-text ratio 4.5 against resolved production colors.
- **Site integration**: lint/build proves the generated SVG projection is compatible with Next `ImageResponse`; no screenshot golden is added because geometry equality is already checked structurally at the source/projection seam.
- **Test removal**: retire only duplicated palette literal matrices. Preserve font, terminal, syntax, and strong-divider assertions because they protect distinct contracts.

## Risks

- **Riskiest assumption**: a deliberately restricted CSS/SVG parser will remain valid for the canonical files. Mitigation: fail fast on selectors, missing roles, primitive counts, and unsupported values; do not silently accept a new shape. If the design system moves beyond simple declarations/primitives, replace the parser with a real library or revisit production codegen rather than widening regexes indefinitely.
- **Repository-relative fixtures**: Flutter tests assume their documented owning-subproject cwd, so `../branding/theme-contract.json` resolves in CLI and CI. The fixture loader must emit the resolved path on failure. If IDE runners use another cwd, allow an explicit loader path in focused tests rather than copying fixtures.
- **Checked-in projection drift**: generated JSON/TypeScript only protects the contract when `--check` is unavoidable. CI path filters therefore include canonical inputs and all projections; local verification documents the same command.
- **SVG rendering equivalence**: Pillow's round-cap emulation and Satori SVG rendering can differ at anti-aliased pixels even with identical geometry. This feature guarantees geometry identity, not byte-identical rasterization across engines; existing platform raster generation remains the visual output path.
- **Where confidence is lowest**: Next `ImageResponse` support for mapped generated SVG primitives under the pinned version. The fallback is to generate a complete SVG data URI from the same canonical model, still checked by the synchronizer, without restoring hand-authored geometry.

## Implementation summary

Completed the serial checkpoints in dependency order:

1. `feature-theme-token-cross-surface-contract-contract-tooling` — added the
   deterministic CSS/SVG synchronizer, checked-in JSON and TypeScript
   projections, canonical SVG-backed Pillow rendering, OG projection use, and
   CI routing.
2. `feature-theme-token-cross-surface-contract-app-theme-properties` — added
   fixture-backed mobile direct-role assertions and public dual-mode builder,
   Material wiring, and WCAG checks.
3. `feature-theme-token-cross-surface-contract-cockpit-theme-properties` —
   added the same fixture-backed vocabulary for Cockpit and asserted both
   token/theme builders, shadcn semantic slots, and WCAG checks.

Each child advanced directly to `done` with its own implementation commit:
`152cd56d`, `c5337b4a`, and `88dbef69` respectively. No implementation
blockers or design deviations were recorded. Corrective commit `732a6686`
also removed the canonical-color override from the rasterizer, keeping
canonical SVG colors authoritative.

## Integrated verification

- `python3 scripts/sync-brand-contracts.py --check` — PASS.
- `python3 -m py_compile scripts/brand_contract.py scripts/sync-brand-contracts.py scripts/generate-brand-assets.py` — PASS.
- `cd app && flutter analyze` — PASS.
- `cd app && flutter test --exclude-tags e2e --concurrency=2` — PASS (960 tests).
- `cd cockpit && flutter analyze` — PASS.
- `cd cockpit && flutter test` — PASS (286 tests).
- `cd site && corepack pnpm lint` — PASS.
- `cd site && corepack pnpm build` — PASS.

## Review closure

Standard one-pass review is closed. Receiver adjudication confirmed all
review findings; this permitted fix-verify pass applied each correction with
no re-review.

### Findings fixed

1. Cockpit now maps `accentSoft` to the shared `accentMuted` role, and the
   regression test proves an `accentSoft`-only drift fails the contract check.
2. CSS parsing now accepts only the documented contract grammar and rejects
   declarations in additional selectors instead of relying on cascade
   computation.
3. Canonical SVG parsing now rejects unexpected semantic attributes, including
   `transform`, and projection validation rejects mark geometry drift in the
   full-dark, full-light, monochrome, and banner SVGs.
4. `LogoMark` consumes the generated canonical TypeScript projection; the
   synchronizer validates all four mark-bearing SVG projections against
   `branding/logo-foreground.svg`.
5. Checked-in parser regressions cover stale fixtures, unsupported CSS grammar,
   unexpected SVG attributes, missing primitives, and deterministic outputs.
6. Pattern references, `AGENTS.md`, and `branding/README.md` describe the
   fixture/synchronizer and single-canonical/projection model.
7. The summary records corrective commit `732a6686`.

### Break-it proof

Each scratch mutation was reverted before closure:

- Changing only Cockpit `accentSoft` to `0x2474CC9D` made the focused theme
  test exit 1 with `dark role accentMuted drifted from the shared fixture`.
- Appending `:root { --color-accent: #FFFFFF; }` to `tokens.css` made
  `sync-brand-contracts.py --check` exit 1 with `Unsupported CSS grammar
  outside the canonical contract blocks`.
- Adding `transform="translate(10 0)"` to the canonical path made the check
  exit 1 with `edge path has unsupported attribute(s): transform`.
- Changing one path coordinate in `logo-full-dark.svg` made the check exit 1
  with `edge path drifted from canonical geometry`.

### Verification

- `python3 scripts/sync-brand-contracts.py --check` — PASS.
- `python3 -m unittest discover -s scripts -p 'test_*.py'` — PASS (5 tests).
- Cockpit focused theme test — PASS; `flutter analyze` — PASS; full
  `flutter test` — PASS (314 tests in the concurrent working tree).
- App focused theme test — PASS. A full app rerun was attempted but timed out
  in the unrelated pairing view-model suite after 973 tests while other app
  work was dirty; no app files changed in this fix.
- Site `corepack pnpm lint && corepack pnpm build` — PASS.
- `pnpm check` was not required because no site test configuration changed.

### Commits

- `afc3e0ed` — Cockpit accentMuted fixture mapping and regression proof.
- `849efdec` — strict CSS/SVG parser, projection validation, parser tests, CI.
- `58b30709` — canonical mark projection consumption and current-state docs.
- Closure commit: this commit.
