# Pattern: Paired Brightness Semantic Palettes

## Rationale

The brand contract defines each semantic role (background, surface, text,
accent, on-accent, status set) as a **complete dark/light pair**, and every
surface resolves brightness exactly once at its composition boundary. Widgets,
components, and pages never see raw color literals or mode conditionals — they
consume resolved semantic roles. This keeps the three codebases (Flutter app,
Flutter cockpit, Next site) visually lockstep while each keeps its native
theming idiom (ColorScheme + extensions, CSS custom properties).

## When to use

Whenever a design token contract must be consumed by more than one platform:
port the token contract into per-platform **paired** palettes, then select the
mode at exactly one boundary per surface (app theme builder, site `:root`
selectors). Never let mode selection leak into leaf components.

## When not to use

Not for one-off accents or single-mode surfaces; a paired palette is ceremony
without a second mode. Do not use ad-hoc `Color(0x...)`/hex literals in leaf
widgets/pages when a semantic role exists — extend the palette instead.

## Examples

### Example 1: contract source (design-system tokens)

**File:** `.mockups/design-system/tokens.css:25-116`

```css
--op-bg: #0d1210;            /* dark */
--op-text: #e8ece9;
/* ...light pair under [data-theme="light"] */
```

### Example 2: Flutter resolves the pair at the theme builder

**File:** `app/lib/ui/core/themes/app_colors.dart:17-151`, `app/lib/ui/core/themes/app_theme.dart:97-107`

```dart
/// Dark-native Phosphor Beacon theme.
ThemeData buildDarkTheme() => _buildTheme(
  brightness: Brightness.dark,
  colors: AppColors.dark,
  typo: AppTypography.dark,
);

/// Light Phosphor Beacon theme.
ThemeData buildLightTheme() => _buildTheme(
  brightness: Brightness.light,
  colors: AppColors.light,
  typo: AppTypography.light,
);
```

### Example 3: cockpit carries the same pair across theme, syntax, terminal

**Files:** `cockpit/lib/app/core/ui/themes/app_colors.dart:3-116`,
`cockpit/lib/app/core/ui/themes/app_theme.dart:19-46`,
`cockpit/lib/app/core/ui/themes/syntax_colors.dart:171-178`,
`cockpit/lib/app/core/ui/themes/terminal_theme.dart:7-54`

### Example 4: site selects via root data-theme + system preference

**File:** `site/src/app/globals.css:8-154`

```css
:root { --op-bg: #0d1210; /* dark defaults */ }
:root[data-theme="light"] { --op-bg: #f3f6f3; }
@media (prefers-color-scheme: light) {
  :root:not([data-theme="dark"]) { --op-bg: #f3f6f3; }
}
```

## Contract maintenance

- The Dart ports remain hand-maintained from `tokens.css` because app and
  cockpit intentionally keep native semantic APIs. Their direct shared roles
  are compared against the checked-in `branding/theme-contract.json` fixture;
  `scripts/sync-brand-contracts.py --check` rejects stale fixture output before
  either surface can silently drift.
