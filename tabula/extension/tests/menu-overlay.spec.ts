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

// Shared context
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

  // Wait for extension to load
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

test.describe("Menu Overlay Regression Tests", () => {
  test("should close Spaces menu when clicking outside", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // 1. Open Spaces Menu
    await page.locator('button[title="Add"]').click();
    await expect(page.locator(".dropdown-menu")).toBeVisible();
    await expect(page.getByText("New space")).toBeVisible();

    // 2. Click outside (at 1, 1 - top left corner) which should be the overlay
    await page.mouse.click(1, 1);

    // 3. Verify menu closed
    await expect(page.locator(".dropdown-menu")).not.toBeVisible();
    await expect(page.getByText("New space")).not.toBeVisible();

    await page.close();
  });

  test("should close Sidebar Group menu when clicking outside", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a group to be safe
    const groupName = `Overlay Test Group ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New section").click();
    await page.fill('input[placeholder="Enter name..."]', groupName);
    await page.getByRole("button", { name: "Create" }).click();

    // Find the group header
    const groupHeader = page
      .locator(".nav-item")
      .filter({ hasText: groupName });
    await expect(groupHeader).toBeVisible();

    // Hover to reveal button
    await groupHeader.hover();

    // Click the "Section options" button using title
    const moreOptionsBtn = groupHeader.locator(
      'button[aria-label="Section options"]',
    );
    await moreOptionsBtn.click();

    // Verify menu open
    const menu = page.locator(".dropdown-menu");
    await expect(menu).toBeVisible();
    await expect(menu.getByText("Rename")).toBeVisible();

    // Click outside
    await page.mouse.click(1, 1);

    // Verify menu closed
    await expect(menu).not.toBeVisible();

    await page.close();
  });

  test("should close Workspace Item menu when clicking outside", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a workspace
    const wsName = `WS Menu Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();

    // Find the workspace item in sidebar
    const wsItem = page
      .locator(".nav-item")
      .filter({ hasText: wsName })
      .first();
    await expect(wsItem).toBeVisible();

    // Hover to reveal button
    await wsItem.hover();

    // Click 3-dots button using title
    const moreOptionsBtn = wsItem.locator('button[aria-label="Space options"]');
    await moreOptionsBtn.click();

    // Verify menu open
    const menu = page.locator(".dropdown-menu");
    await expect(menu).toBeVisible();
    await expect(menu.getByText("Delete")).toBeVisible();

    // Click outside
    await page.mouse.click(1, 1);

    // Verify menu closed
    await expect(menu).not.toBeVisible();

    await page.close();
  });

  test("should close User menu when clicking outside", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Click user avatar
    await page.locator('[title="Account & Settings"]').click();

    // Verify menu open
    const menu = page.locator(".dropdown-menu");
    await expect(menu).toBeVisible();
    await expect(menu.getByText("Settings")).toBeVisible();

    // Click outside
    await page.mouse.click(1, 1);

    // Verify menu closed
    await expect(menu).not.toBeVisible();

    await page.close();
  });
});
