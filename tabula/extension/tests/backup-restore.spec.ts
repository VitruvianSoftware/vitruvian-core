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

/* eslint-disable import/no-extraneous-dependencies */
/* eslint-disable no-console */
/**
 * E2E tests for Backup & Restore functionality
 *
 * Tests the backup UI in the Settings modal > Backups tab
 * Requires E2E_TEST_TOKEN environment variable to be set.
 *
 * Run locally:
 *   1. Start API: tabcli dev start --api
 *   2. Generate token: npm run db:seed:test -w api
 *   3. Export token: export E2E_TEST_TOKEN=<token>
 *   4. Run tests: npm run test:e2e -w extension
 */
import { test, expect, chromium, BrowserContext } from "@playwright/test";
import path from "path";
import fs from "fs";
import {
  getTestToken,
  loginTestUser,
  logoutTestUser,
  cleanupAllTestData,
  cleanupTestBackups,
  createWorkspace,
  cleanupApiWorkspaces,
  getOrCreateDashboardPage,
} from "./e2e-helpers";

const EXTENSION_PATH = path.join(__dirname, "../dist");

// Shared context and extension ID
let context: BrowserContext;
let extensionId: string;
let testToken: string | null;

test.beforeAll(async () => {
  // Check for test token
  testToken = getTestToken();
  if (!testToken) {
    console.warn(
      "[backup-restore.spec.ts] No E2E_TEST_TOKEN found. " +
        "Run `npm run db:seed:test -w api` and export the token.",
    );
  }

  // Verify extension is built
  if (!fs.existsSync(EXTENSION_PATH)) {
    throw new Error(
      `Extension not built. Run 'npm run build' first. Expected path: ${EXTENSION_PATH}`,
    );
  }

  // Launch browser with extension
  context = await chromium.launchPersistentContext("", {
    headless: false,
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
    ],
  });

  // Wait for extension to load and get its ID
  let background = context.serviceWorkers()[0];
  if (!background) {
    background = await context.waitForEvent("serviceworker");
  }
  // eslint-disable-next-line prefer-destructuring
  extensionId = background.url().split("/")[2];

  // Clean up any existing test workspaces from API to prevent hitting 10-workspace limit
  if (testToken) {
    await cleanupApiWorkspaces(testToken);
  }
});

test.afterAll(async () => {
  // Cleanup test backups and workspaces from API
  if (testToken) {
    await cleanupTestBackups(testToken);
    await cleanupApiWorkspaces(testToken);
  }
  await context.close();
});

test.describe("Backup & Restore", () => {
  test.describe.configure({ mode: "serial" });

  test.beforeEach(async () => {
    // Skip tests if no token available
    if (!testToken) {
      test.skip();
    }
  });

  test("should show Backups tab in Settings modal", async () => {
    if (!testToken) {
      test.skip();
    }

    const page = await getOrCreateDashboardPage(context, extensionId);
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));

    try {
      await page.waitForLoadState("domcontentloaded");

      // Login test user
      await loginTestUser(page, testToken);
      await page.reload();
      await page.waitForLoadState("domcontentloaded");
      await page.waitForTimeout(1000);

      // Open Settings via user menu
      await page.locator('[title="Account & Settings"]').click();
      const dropdownMenu = page.locator(".dropdown-menu");
      await expect(dropdownMenu).toBeVisible();
      await dropdownMenu
        .locator(".dropdown-item")
        .filter({ hasText: "Settings" })
        .click();

      // Verify Settings modal opens
      const settingsModal = page
        .locator(".modal-header")
        .filter({ hasText: "Settings" });
      await expect(settingsModal).toBeVisible({ timeout: 5000 });

      // Wait for settings to load
      const accountContent = page.getByText("User Information");
      await expect(accountContent).toBeVisible({ timeout: 10000 });

      // Click on Backups tab
      const backupsTab = page.locator("button").filter({ hasText: "Backups" });
      await backupsTab.click();

      // Verify Backups heading appears
      await expect(
        page.locator("h2").filter({ hasText: "Backups" }),
      ).toBeVisible({
        timeout: 5000,
      });

      // Verify backup stats section exists
      await expect(page.getByText("Total Backups")).toBeVisible();
      await expect(page.getByText("Storage Used")).toBeVisible();

      // Verify Create Backup button exists
      await expect(
        page.getByRole("button", { name: /Create Backup/i }),
      ).toBeVisible();

      await page.keyboard.press("Escape");
    } finally {
      // Cleanup
      await cleanupAllTestData(page);
      await logoutTestUser(page);
      await page.close();
    }
  });

  test("should create a backup successfully", async () => {
    // Set longer timeout for API-dependent test
    test.setTimeout(60000);

    if (!testToken) {
      test.skip();
    }

    // Explicit API cleanup to ensure clean state (handles parallel test interference)
    await cleanupApiWorkspaces(testToken);
    await cleanupTestBackups(testToken); // Clear backups to avoid limit

    const page = await getOrCreateDashboardPage(context, extensionId);
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));

    try {
      await page.waitForLoadState("domcontentloaded");

      // Login test user
      await loginTestUser(page, testToken);
      await page.reload();
      await page.waitForLoadState("domcontentloaded");
      await page.waitForTimeout(1000);

      // Create a workspace first so we have something to backup
      const wsName = `Backup Test ${Date.now()}`;
      await createWorkspace(page, wsName);
      await page.waitForTimeout(500);

      // Open Settings > Backups
      await page.locator('[title="Account & Settings"]').click();
      await page
        .locator(".dropdown-menu")
        .locator(".dropdown-item")
        .filter({ hasText: "Settings" })
        .click();
      await expect(page.getByText("User Information")).toBeVisible({
        timeout: 10000,
      });
      await page.locator("button").filter({ hasText: "Backups" }).click();
      await expect(
        page.locator("h2").filter({ hasText: "Backups" }),
      ).toBeVisible({
        timeout: 5000,
      });

      // Get current backup count using reliable data-testid selector
      const backupCountLocator = page.getByTestId("backup-count");
      await expect(backupCountLocator).toBeVisible({ timeout: 10000 });
      const initialCountText = await backupCountLocator.textContent();
      const initialCount = parseInt(initialCountText || "0", 10);
      console.log(`[backup-restore] Initial backup count: ${initialCount}`);

      // Click Create Backup
      const createBackupBtn = page.getByRole("button", {
        name: /Create Backup/i,
      });
      await expect(createBackupBtn).toBeEnabled({ timeout: 5000 });
      await createBackupBtn.click();

      // Poll for backup count to increase (more reliable than static wait)
      // The button shows "Creating..." while working, then the count updates
      // Use longer timeout to handle slow API responses during parallel test runs
      await expect(async () => {
        const currentText = await backupCountLocator.textContent();
        const currentCount = parseInt(currentText || "0", 10);
        console.log(
          `[backup-restore] Current backup count: ${currentCount}, initial: ${initialCount}`,
        );
        expect(currentCount).toBeGreaterThan(initialCount);
      }).toPass({
        timeout: 20000, // Longer timeout for parallel runs
        intervals: [500, 1000, 1000, 2000, 3000, 5000],
      });

      console.log("[backup-restore] Backup created successfully");
      await page.keyboard.press("Escape");
    } finally {
      // Cleanup
      await cleanupAllTestData(page);
      await logoutTestUser(page);
      await page.close();
    }
  });
});
