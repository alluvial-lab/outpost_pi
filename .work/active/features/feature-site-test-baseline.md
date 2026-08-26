---
id: feature-site-test-baseline
kind: feature
stage: review
tags: [site, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Site test baseline (with light/dark contract as first coverage)

## Brief

Formed by groom 2026-08-26: `idea-site-test-baseline` (site/ has zero test
files) and `gate-tests-site-light-dark-contract` (no reproducible
light/dark/contrast check) are one test program — the light/dark contract is
the concrete first story under the broader baseline, not a separate program.

Sources (bodies retained in `.work/archive/`).

## Work

1. **Thin baseline** — a smoke render test per route or a link/metadata
   check, wired into the `pnpm lint`/`pnpm build` workflow (`site/` commands
   per AGENTS.md).
2. **Light/dark computed-style contract** — browser/computed-style test over
   four partitions: system-dark (no attr), system-light (no attr),
   forced-dark under light system, forced-light under dark system. Assert
   resolved key roles + AA ratios from `globals.css` (`:86` explicit light
   values, `:114` system-light overrides), not screenshots. Replaces the
   one-time contrast/alias scans recorded in `story-brand-site-sync`.

Out of scope (noted, opportunistic): `globals.css` is 2282 LOC and may
warrant a split at the next styling pass.

## Design decisions

- **Browser runner**: use `@playwright/test` with one Chromium project. The
  contract depends on the browser's real custom-property cascade,
  `prefers-color-scheme` media query, `data-theme` selector precedence,
  `color-mix` handling, and computed colors. A Node-only test, source parser,
  jsdom, or happy-dom would be lighter but cannot provide reliable evidence for
  all four partitions; the browser is the smallest honest dependency for this
  requirement. Avoid the rest of Playwright's browser matrix, visual
  snapshots, and accessibility suite.
- **Server target**: run the tests against the production `next start` server
  after `next build`, not a mocked component tree or `next dev`. This catches
  route/render regressions while keeping the site presentational and backend
  free.
- **Theme oracle**: keep a small typed expected-role fixture in the test
  helper, anchored to the direct values in `site/src/app/globals.css`. Read
  actual values through `getComputedStyle` and calculate WCAG 2.1 ratios from
  those resolved values. The test is therefore a drift alarm for the CSS
  contract, not a source-text alias scan; updating tokens requires an explicit
  fixture/test review.
- **Route scope**: smoke the current fourteen page routes with an explicit
  inventory and assert only 200 response, non-empty title, and visible `main`.
  Do not turn this baseline into a copy, layout, link crawler, screenshot, or
  external-release-manifest test suite.
- **Workflow**: add a `site` `check` script that orders lint, production
  build, and Playwright tests. CI installs only Chromium and runs that script;
  existing `pnpm lint` and `pnpm build` remain independently available.
- **UI/mockups**: none. This feature changes test/config surfaces only and
  does not add or alter a user-facing composition or journey. No parent epic
  exists from which to inherit mocks.

## Architectural choice

Three plausible approaches were considered:

1. **Node test runner plus jsdom/happy-dom** — cheap and fast, and adequate for
   pure component or DOM assertions, but it does not faithfully exercise the
   browser cascade, media-query preference, `color-mix`, or computed-color
   serialization required here. It would make the four-partition test appear
   covered while testing a different CSS engine.
2. **Static CSS parsing and contrast checks** — avoids browser installation and
   can inspect the declared hex values, but cannot prove that selector order,
   media queries, inherited variables, and forced attributes resolve as users
   see them. It repeats the old one-time scan that this feature is replacing.
3. **Playwright test against `next start` (chosen)** — adds one browser-backed
   dev dependency and a Chromium CI install, but directly verifies the
   production route and computed-style behavior. A single project and four
   table rows keep the runtime and maintenance proportional to this baseline.

Choose option 3 because the four theme partitions are the highest-risk
contract and real CSS resolution is non-negotiable. The additional browser
binary is narrower and more honest than a lighter test that cannot observe the
required behavior.

## Implementation Units

### Unit 1: Browser harness and four-partition theme contract

**Story**: `feature-site-test-baseline-computed-style-contract`

**Files**:

- `site/playwright.config.ts`
- `site/tests/theme-contract.ts`
- `site/tests/theme-contract.spec.ts`
- `site/package.json`
- `site/pnpm-lock.yaml`
- `.gitignore`

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

export async function readResolvedTheme(page: Page): Promise<ThemeRoles>;
export function contrastRatio(foreground: string, background: string): number;
```

**Implementation notes**:

- Configure `baseURL` on `http://127.0.0.1:3100` and a `pnpm start`
  `webServer`; allow an already-running server only for local development,
  never to hide a CI startup failure.
- Set the emulated system color scheme before navigation. For forced rows,
  set exactly one `data-theme` value on `<html>` after navigation and assert
  the final computed result. No theme toggle UI or production code is needed.
- Read each direct role from browser-computed CSS and use a small hidden probe
  element for actual `color`/`background-color` resolution. Parse the
  browser's computed RGB values with local standard-library code; do not add a
  color library for six opaque roles.
- The expected fixture contains the dark values (`#0d1210`, `#131a16`,
  `#e4efe8`, `#89978d`, `#74cc9c`, `#0a2418`) and light values (`#f3f6f3`,
  `#f8faf8`, `#182019`, `#57635a`, `#256e47`, `#ffffff`) for the roles above.
  These are deliberately reviewed whenever `globals.css` changes.
- Calculate relative luminance and contrast as `(L1 + 0.05) / (L2 + 0.05)`;
  assert at least `4.5` for primary text/background, secondary
  text/background, accent/background, and on-accent/accent in every resolved
  mode. Include partition and role names in failures.
- Add `test` (`playwright test`) and `check` (`pnpm lint && pnpm build && pnpm
  test`) scripts. Ignore Playwright reports and results as transient output.

**Acceptance criteria**:

- [ ] All four system/attribute partitions resolve the expected dark or light
      direct roles through browser computed styles.
- [ ] The test proves the media-query/attribute precedence rather than merely
      comparing source literals, and contains no screenshot assertion.
- [ ] All required AA pairs meet `4.5` in both resolved modes with diagnostic
      failure output.
- [ ] `site/pnpm-lock.yaml` records the runner dependency and `pnpm check`
      can run a production build followed by the browser suite.

### Unit 2: Production route smoke and CI wiring

**Story**: `feature-site-test-baseline-route-smoke-and-workflow`

**Files**:

- `site/tests/routes.spec.ts`
- `.github/workflows/ci.yml`

Representative interface:

```ts
import type { Page } from "@playwright/test";

export const SITE_ROUTES = [
  "/",
  "/cockpit",
  "/docs",
  "/download",
  "/privacy",
  "/terms",
  "/tutorials",
  "/tutorials/claude-mesh",
  "/tutorials/cockpit-team",
  "/tutorials/daemon",
  "/tutorials/getting-started",
  "/tutorials/mesh-local",
  "/tutorials/mesh-remote",
  "/why",
] as const;

export async function assertRouteRenders(
  page: Page,
  route: (typeof SITE_ROUTES)[number],
): Promise<void>;
```

**Implementation notes**:

- Parameterize one independent test per route against the `next start` server.
  Navigate with `waitUntil: "domcontentloaded"`; do not wait for `networkidle`
  or make external font/release-manifest calls part of the contract.
- Require a 200 response, a non-empty `document.title`, and visible `main`.
  Include the route in assertion messages. Do not assert copy, screenshots,
  dimensions, or dynamic download data.
- In the site CI lane, install dependencies with the existing frozen pnpm
  command, install only Chromium with `pnpm exec playwright install --with-deps
  chromium`, then run `pnpm check`. Keep the existing site path filter and
  timeout appropriate for a production build plus one browser.

**Acceptance criteria**:

- [ ] The fourteen current App Router page routes each return 200 and expose a
      non-empty title and visible `main` from the production server.
- [ ] A broken route fails with its path instead of being silently omitted.
- [ ] CI runs lint, production build, and the browser tests, installing no
      browser engines beyond Chromium.
- [ ] No Playwright report, browser cache, or build output is tracked.

## Implementation Order

1. `feature-site-test-baseline-computed-style-contract` — establish the single
   browser runner, production-server config, theme helper, four partitions, and
   `check` script.
2. `feature-site-test-baseline-route-smoke-and-workflow` — reuse that harness
   for route smoke coverage and wire the site CI lane.

The feature remains one cohesive implementation/review bundle; the child
stories are durable checkpoints for the runner/theme contract and the route/CI
integration rather than separate worker assignments.

## Simplification

- Use one Chromium project and one local computed-style helper; do not add
  Vitest/Jest, jsdom, happy-dom, a CSS parser, a color package, screenshot
  snapshots, or a multi-browser matrix.
- Keep the explicit route inventory limited to the fourteen current page
  routes and the three stable smoke assertions. Broader link crawling and
  metadata validation are parked as future coverage if a demonstrated need
  appears.
- Leave `site/src/app/globals.css` as-is. Splitting its 2282 lines is
  explicitly outside this baseline and would mix structural styling work with
  test scaffolding.

## Testing

- The browser theme contract is the primary interface test: it protects CSS
  cascade/media precedence, semantic role resolution, and AA contrast in all
  four required environments.
- The route suite is a production-render smoke test: it protects page startup
  and basic document composition across every current page route without
  binding tests to marketing copy or external manifest data.
- `pnpm lint`, `pnpm build`, and `pnpm check` are the verification commands from
  `site/`; CI must run the same ordered check after installing Chromium.
- No existing site tests or fixtures are removed; there are none. No generated
  browser output is retained.

## Risks

- **Browser prerequisite and runtime cost**: Chromium installation is heavier
  than a DOM-only test and may be unavailable on a constrained local machine.
  CI explicitly installs only Chromium; local verification reports the missing
  browser as an environment prerequisite rather than weakening the contract.
- **Expected-role fixture drift**: the small expected map intentionally repeats
  canonical CSS values so a token change fails loudly. Updating it must be a
  reviewed contract change, not an automatic read of the same CSS file (which
  could make source and test fail together).
- **Route inventory drift**: a new App Router page must add its path to the
  explicit smoke inventory. The implementation review should compare the list
  with `site/src/app/**/page.tsx`; automatic source parsing is not added to this
  thin baseline because it would test file discovery rather than route behavior.

## Implementation run

- Executed inline in the host because this harness exposes no implementation
  subagent adapter. The site-only ownership boundary was preserved; unrelated
  concurrent app, cockpit, pi-extension, and relay changes were not touched.
- Worker capability recorded from the caller: `openai-codex/gpt-5.6-luna` at
  `xhigh`; review weight is `standard` from the autopilot caller's default.

## Completed checkpoints

- `feature-site-test-baseline-computed-style-contract` — advanced directly to
  `done` in `b4ff28a2`. Added the one-project Chromium Playwright harness,
  production `next start` server, four-partition computed-style contract,
  computed WCAG ratio helper, scripts, lockfile dependency, and transient
  output ignores.
- `feature-site-test-baseline-route-smoke-and-workflow` — advanced directly to
  `done` in `ef1c3617` after its dependency. Added independent smoke tests for
  the fourteen current App Router page routes and wired the CI site lane to
  install only Chromium and run `pnpm check`.

## Integrated verification

- `cd site && PATH="/tmp/outpost-corepack-bin:$PATH" pnpm check` — PASS:
  lint, production build, and all 18 Chromium tests (14 route tests plus the
  four required theme partitions).
- `cd site && corepack pnpm exec playwright install chromium` — PASS; Chromium
  and its headless shell were available locally. CI uses the corresponding
  `pnpm exec playwright install --with-deps chromium` command.
- Route inventory was derived from `site/src/app/**/page.tsx`: one root page
  and thirteen nested page files, excluding the generated not-found and asset
  endpoints. No browser reports, results, or build output are tracked.

The feature is implementation-complete and eligible for the standard feature
review. No implementation blocker remains.
