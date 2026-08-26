---
id: feature-site-test-baseline-computed-style-contract
kind: story
stage: done
tags: [site, testing]
parent: feature-site-test-baseline
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Establish the browser-backed site theme contract

## Checkpoint

Add the smallest real-browser test harness needed to prove the site's dual-mode
CSS contract. Use `@playwright/test` with one Chromium project and a local
`next start` web server. The test must exercise CSS custom-property resolution
and `prefers-color-scheme`, not source-text aliases or screenshots.

The four named partitions are table-driven:

1. system dark with no `data-theme` attribute → dark roles;
2. system light with no `data-theme` attribute → light roles;
3. system light with `data-theme="dark"` → dark roles;
4. system dark with `data-theme="light"` → light roles.

The expected direct role fixture is intentionally small and mirrors the
canonical values in `site/src/app/globals.css`: `--color-bg-primary`,
`--color-bg-secondary`, `--color-text-primary`, `--color-text-secondary`,
`--brand-accent`, and `--color-on-accent`. The test reads their resolved values
through `getComputedStyle` on the document and a probe element, then computes
WCAG 2.1 relative luminance and asserts these normal-text pairs in each resolved
mode: primary text/background, secondary text/background, accent/background,
and on-accent/accent. Each ratio must be at least `4.5`; failure output names
the partition, roles, resolved colors, and ratio.

## Design element

- `site/playwright.config.ts` owns the single Chromium project, `baseURL`,
  `pnpm start` web server, bounded timeout, and CI/local server reuse policy.
- `site/tests/theme-contract.ts` owns the typed role names, dark/light expected
  fixture, four partition records, computed-color parsing, and contrast helper.
- `site/tests/theme-contract.spec.ts` owns the browser assertions. It uses
  `page.emulateMedia({ colorScheme })`, sets only the forced `data-theme`
  override, and never captures or compares screenshots.
- `site/package.json` and `site/pnpm-lock.yaml` add the test dependency and
  scripts: `test` runs Playwright and `check` runs `pnpm lint && pnpm build &&
  pnpm test`, so a direct check includes the production build required by
  `next start`.
- Root `.gitignore` ignores Playwright's `test-results/` and
  `playwright-report/` outputs; no browser artifacts are checked in.

Representative interfaces:

```ts
import type { Page } from "@playwright/test";

export const DIRECT_THEME_ROLES = [
  "--color-bg-primary",
  "--color-bg-secondary",
  "--color-text-primary",
  "--color-text-secondary",
  "--brand-accent",
  "--color-on-accent",
] as const;

type DirectThemeRole = (typeof DIRECT_THEME_ROLES)[number];
type ThemeMode = "dark" | "light";
type ThemeRoles = Record<DirectThemeRole, string>;
type ThemePartition = {
  name: string;
  system: ThemeMode;
  forced: ThemeMode | null;
  expected: ThemeMode;
};

export async function readResolvedTheme(
  page: Page,
): Promise<ThemeRoles>;

export function contrastRatio(
  foreground: string,
  background: string,
): number;
```

**Acceptance evidence**

- The four table rows run with the exact system/attribute combinations above,
  and each resolves to the expected dark or light direct-role values.
- Assertions use browser-computed values after CSS cascade/media-query
  resolution; no screenshot, source-text grep, or jsdom-style approximation is
  accepted as the contract evidence.
- Every required AA pair is calculated from the resolved colors and meets
  `4.5`, with a useful failure message when a role or ratio regresses.
- `pnpm check` and the isolated `pnpm test -- theme-contract.spec.ts` pass from
  `site/` after the production build exists.

## Ordering constraint

This checkpoint establishes the Playwright dependency, config, and `check`
script that the route smoke checkpoint reuses. Keep the browser scope to
Chromium; adding projects, visual snapshots, or a broader accessibility suite
is outside this baseline.

## Implementation run

- Executed inline in the host because this harness exposes no implementation
  subagent adapter. The feature's site-only write boundary was preserved while
  unrelated app, cockpit, pi-extension, and relay changes remained untouched.
- Worker capability recorded from the caller: `openai-codex/gpt-5.6-luna` at
  `xhigh`; this was a bounded browser-test scaffolding delivery.

## Implementation notes

- Added `site/playwright.config.ts` with one Chromium project, a production
  `next start` server on `127.0.0.1:3100`, and local-only server reuse
  (`reuseExistingServer` is disabled when `CI` is set).
- Added `site/tests/theme-contract.ts` and
  `site/tests/theme-contract.spec.ts`. The four table-driven partitions use
  browser-computed custom-property values and a hidden probe element, then
  calculate WCAG 2.1 contrast ratios from the resolved colors. No screenshots,
  source-text parsing, or DOM emulation is used.
- Added the `test` and ordered `check` scripts to `site/package.json`, recorded
  `@playwright/test` in `site/pnpm-lock.yaml`, and ignored Playwright reports
  and per-test output in the root `.gitignore`.

## Verification evidence

- `cd site && corepack pnpm lint` — PASS.
- `cd site && corepack pnpm exec tsc --noEmit` — PASS.
- `cd site && corepack pnpm build` — PASS.
- `cd site && corepack pnpm exec playwright install chromium` — PASS; Chromium
  and its headless shell downloaded successfully and no system dependency
  failure was reported.
- `cd site && corepack pnpm exec playwright test theme-contract.spec.ts` —
  PASS (4 tests across all four required partitions).
- `cd site && corepack pnpm test` — PASS (18 tests, including the route
  checkpoint currently present in the working tree).
