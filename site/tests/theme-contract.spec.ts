import { expect, test } from "@playwright/test";

import {
  AA_CONTRAST_PAIRS,
  DIRECT_THEME_ROLES,
  EXPECTED_THEME_ROLES,
  contrastRatio,
  readResolvedTheme,
  THEME_PARTITIONS,
  WCAG_AA_NORMAL_TEXT_RATIO,
} from "./theme-contract";

for (const partition of THEME_PARTITIONS) {
  test(`${partition.name} resolves the ${partition.expected} theme`, async ({ page }) => {
    await page.emulateMedia({ colorScheme: partition.system });
    await page.goto("/", { waitUntil: "domcontentloaded" });

    await page.locator("html").evaluate((html, forcedTheme) => {
      if (forcedTheme === null) {
        html.removeAttribute("data-theme");
      } else {
        html.setAttribute("data-theme", forcedTheme);
      }
    }, partition.forced);

    expect(
      await page.locator("html").getAttribute("data-theme"),
      `${partition.name}: forced theme attribute did not match the partition`,
    ).toBe(partition.forced);

    const actual = await readResolvedTheme(page);
    const expected = EXPECTED_THEME_ROLES[partition.expected];
    for (const role of DIRECT_THEME_ROLES) {
      expect(
        actual[role],
        `${partition.name}: ${role} resolved to ${actual[role]}, expected ${expected[role]}`,
      ).toBe(expected[role]);
    }

    for (const pair of AA_CONTRAST_PAIRS) {
      const ratio = contrastRatio(actual[pair.foreground], actual[pair.background]);
      expect(
        ratio,
        `${partition.name}: ${pair.foreground} on ${pair.background} resolved to ${actual[pair.foreground]} on ${actual[pair.background]} (ratio ${ratio.toFixed(2)})`,
      ).toBeGreaterThanOrEqual(WCAG_AA_NORMAL_TEXT_RATIO);
    }
  });
}
