import { expect, test, type Page } from "@playwright/test";

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

/** Assert the stable production-render contract for one known site route. */
export async function assertRouteRenders(
  page: Page,
  route: (typeof SITE_ROUTES)[number],
): Promise<void> {
  const response = await page.goto(route, { waitUntil: "domcontentloaded" });
  if (!response) {
    throw new Error(`${route}: navigation returned no HTTP response.`);
  }

  expect(response.status(), `${route}: expected an HTTP 200 response`).toBe(200);
  const title = await page.title();
  expect(title.trim(), `${route}: expected a non-empty document title`).not.toBe("");
  await expect(
    page.locator("main"),
    `${route}: expected a visible main element`,
  ).toBeVisible();
}

for (const route of SITE_ROUTES) {
  test(`${route} renders from the production server`, async ({ page }) => {
    await assertRouteRenders(page, route);
  });
}
