import { defineConfig, devices } from "@playwright/test";

const isCi = Boolean(process.env.CI);

export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  fullyParallel: true,
  forbidOnly: isCi,
  reporter: "list",
  use: {
    baseURL: "http://127.0.0.1:3100",
    headless: true,
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    command: "corepack pnpm start --hostname 127.0.0.1 --port 3100",
    url: "http://127.0.0.1:3100/",
    reuseExistingServer: !isCi,
    timeout: 120_000,
  },
});
