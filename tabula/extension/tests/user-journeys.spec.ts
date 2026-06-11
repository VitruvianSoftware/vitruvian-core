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
import { test, expect, chromium, BrowserContext } from "@playwright/test";
import path from "path";
import fs from "fs";
import { getOrCreateDashboardPage } from "./e2e-helpers";

const EXTENSION_PATH = process.env.EXTENSION_PATH
  ? path.resolve(process.env.EXTENSION_PATH)
  : path.join(__dirname, "../dist");

// Shared context and extension ID
let context: BrowserContext;
let extensionId: string;

test.beforeAll(async () => {
  // Verify extension is built
  if (!fs.existsSync(EXTENSION_PATH)) {
    throw new Error(
      `Extension not built. Run 'npm run build' first. Expected path: ${EXTENSION_PATH}`,
    );
  }

  // Launch browser with extension
  context = await chromium.launchPersistentContext("", {
    // Full Chromium in the new headless mode: supports MV3 extensions, no
    // xvfb needed (Playwright >= 1.49).
    channel: "chromium",
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
      "--no-sandbox",
      // Bazel's linux-sandbox mounts a tiny /dev/shm; Chromium crashes at
      // launch without this.
      "--disable-dev-shm-usage",
    ],
  });

  // Wait for extension to load and get its ID
  let background = context.serviceWorkers()[0];
  if (!background) {
    background = await context.waitForEvent("serviceworker");
  }
  // eslint-disable-next-line prefer-destructuring
  extensionId = background.url().split("/")[2];
});

test.afterAll(async () => {
  await context.close();
});

/**
 * User Journey #4: Managing Tasks
 * - Add a new task
 * - Verify task appears
 * - Toggle task completion
 * - Delete task
 */
test.describe("User Journey: Managing Tasks", () => {
  test("should add, complete, and delete a task", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a workspace to work with
    const wsName = `Tasks Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    // Navigate to Tasks tab
    await page.locator(".tab-item").filter({ hasText: "Tasks" }).click();

    // Verify empty state
    await expect(page.getByText("No tasks yet")).toBeVisible();

    // Add a new task
    const taskTitle = `Test Task ${Date.now()}`;
    await page.fill('input[placeholder="Add a new task..."]', taskTitle);
    await page.keyboard.press("Enter");

    // Verify task appears
    await expect(
      page.locator(".list-item").filter({ hasText: taskTitle }),
    ).toBeVisible();
    await expect(page.getByText("No tasks yet")).not.toBeVisible();

    // Toggle task completion (click checkbox)
    const taskItem = page.locator(".list-item").filter({ hasText: taskTitle });
    const checkbox = taskItem.locator('input[type="checkbox"]');
    await checkbox.check();

    // Verify task is marked as complete (strikethrough style)
    await expect(
      taskItem.locator("div").filter({ hasText: taskTitle }),
    ).toHaveCSS("text-decoration", /line-through/);

    // Delete task
    await taskItem.locator("button.btn-icon.danger").click();

    // Verify task is removed
    await expect(
      page.locator(".list-item").filter({ hasText: taskTitle }),
    ).not.toBeVisible();
    await expect(page.getByText("No tasks yet")).toBeVisible();

    await page.close();
  });
});

/**
 * User Journey #10: User Profile & Settings
 * - Open user menu via avatar
 * - Verify user info is displayed
 * - Open Settings modal
 */
test.describe("User Journey: User Profile & Settings", () => {
  test("should open user menu and access settings", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Click user avatar to open menu
    await page.locator('[title="Account & Settings"]').click();

    // Verify dropdown menu appears with user info
    const dropdownMenu = page.locator(".dropdown-menu");
    await expect(dropdownMenu).toBeVisible();

    // Verify Settings option is present
    await expect(dropdownMenu.getByText("Settings")).toBeVisible();
    await expect(dropdownMenu.getByText("Log out")).toBeVisible();

    // Click Settings
    await dropdownMenu
      .locator(".dropdown-item")
      .filter({ hasText: "Settings" })
      .click();

    // Verify Settings modal opens (look for modal with "Settings" title)
    const settingsModal = page
      .locator(".modal-header")
      .filter({ hasText: "Settings" });
    await expect(settingsModal).toBeVisible({ timeout: 5000 });

    // Close modal by pressing escape
    await page.keyboard.press("Escape");

    await page.close();
  });
});

/**
 * User Journey #9: Sharing a Space
 * - Verify Share button is accessible
 * Note: Feature may be placeholder in current version
 */
test.describe("User Journey: Sharing a Space", () => {
  test("should have accessible Share functionality", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a workspace to work with
    const wsName = `Share Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    // Look for Share button in workspace header (exact match to avoid matching workspace name)
    const shareButton = page.getByRole("button", {
      name: "Share",
      exact: true,
    });

    // Verify Share button is visible and accessible
    await expect(shareButton).toBeVisible();

    // Note: We don't click Share as it may trigger browser native share
    // or be a placeholder. Just verify it exists.

    await page.close();
  });
});
