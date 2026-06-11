/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import { defineConfig, devices } from "@playwright/test";

/**
 * See https://playwright.dev/docs/test-configuration.
 */
// Under Bazel the E2E auth token is self-signed here: the seed task creates a
// deterministic user (fixed UUID) and JWT_SECRET is a known test constant, so
// every Playwright worker process (each loads this config) derives the same
// token the old CI captured from the seeder's stdout.
if (!process.env.E2E_TEST_TOKEN && process.env.JWT_SECRET) {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const jwt = require("jsonwebtoken");
  process.env.E2E_TEST_TOKEN = jwt.sign(
    {
      id: "00000000-0000-0000-0000-e2e000000000",
      email: "e2e-test@tabula.dev",
      tier: "free",
    },
    process.env.JWT_SECRET,
    { expiresIn: "24h" },
  );
}

export default defineConfig({
  testDir: "./tests",
  testMatch: "**/*.spec.ts",
  // Set to false to ensure API tests don't hit 10-workspace limit from concurrent runs
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  // Use single worker to prevent concurrent workspace creation hitting API limits
  // Pin workers explicitly: Playwright's core-count detection overshoots
  // Bazel's local resource accounting.
  workers: 2,
  reporter: "line",
  use: {
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "on", // Enable video recording to verify single dashboard tab
  },

  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        // Additional args for extension testing in CI
        launchOptions: {
          args: ["--no-sandbox", "--disable-setuid-sandbox"],
        },
      },
    },
  ],

  // Note: No webServer needed for browser extension E2E tests
  // Extensions are loaded directly into the browser, not served from a web server
});
