---
id: feature-site-test-baseline-route-smoke-and-workflow
kind: story
stage: implementing
tags: [site, testing]
parent: feature-site-test-baseline
depends_on: [feature-site-test-baseline-computed-style-contract]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Add a thin production-route smoke baseline

## Checkpoint

Reuse the browser harness from
`feature-site-test-baseline-computed-style-contract` to smoke the current
production-rendered App Router pages. Keep one explicit route inventory in
`site/tests/routes.spec.ts` for the current fourteen page routes:
`/`, `/cockpit`, `/docs`, `/download`, `/privacy`, `/terms`, `/tutorials`,
`/tutorials/claude-mesh`, `/tutorials/cockpit-team`, `/tutorials/daemon`,
`/tutorials/getting-started`, `/tutorials/mesh-local`, `/tutorials/mesh-remote`,
and `/why`.

Run one independent test per route against `next start`. For each response,
assert HTTP 200, a non-empty document title, and a visible `main` element. Do
not assert copy, layout dimensions, screenshots, or release-manifest network
responses: those are not stable baseline contracts. An intentionally added
page must update this inventory, which makes route coverage reviewable rather
than silently skipping a new route.

Wire the site CI job to install only Chromium, retain the existing lint and
build commands, and run the new `pnpm check` after dependencies are installed.
The production build runs before Playwright starts its `next start` server.

## Design element

- `site/tests/routes.spec.ts` owns the typed route inventory and parameterized
  status/title/main assertions.
- `.github/workflows/ci.yml` owns the site lane's browser prerequisite and
  invokes `pnpm check` (or equivalent ordered lint, build, and test commands)
  after `pnpm install --frozen-lockfile`. Use `pnpm exec playwright install
  --with-deps chromium`; do not install Firefox/WebKit or add a screenshot job.
- The route test must wait for `domcontentloaded`, not `networkidle`, so the
  smoke remains deterministic despite external font or release-manifest
  requests. A server response failure is reported with its route.

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

**Acceptance evidence**

- All fourteen current page routes return 200 from the production server and
  expose a non-empty title plus visible `main` content.
- A failing route identifies its path; no route is silently skipped because a
  page has external data or client-side decoration.
- CI installs only Chromium, runs `pnpm lint`, `pnpm build`, and the browser
  tests through the checked-in workflow, and leaves no test reports tracked.
- `cd site && pnpm check` passes locally in an environment with the Playwright
  Chromium binary available.

## Ordering constraint

Wait for the computed-style checkpoint's runner/config and package scripts.
This story owns the CI workflow edit and route test only after that harness is
available; it must not introduce a second runner or duplicate server setup.
