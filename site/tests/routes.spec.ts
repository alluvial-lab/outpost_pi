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

test("Digital Asset Links is served as the release pairing association", async ({
  request,
}) => {
  const response = await request.get("/.well-known/assetlinks.json");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("application/json");
  expect(await response.json()).toEqual([
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: "dev.kevoun.outpostpi",
        sha256_cert_fingerprints: [
          "63:B8:F2:D5:DA:E7:3A:41:27:9A:46:79:9A:72:72:9C:B4:7D:C4:64:90:F3:B0:E4:92:30:D0:B9:72:4C:4C:5B",
        ],
      },
    },
  ]);
});
