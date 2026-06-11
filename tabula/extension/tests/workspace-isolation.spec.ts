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

test.describe("Workspace Tab Isolation", () => {
  test.describe.configure({ mode: "serial" });

  test("new tabs are added only to active workspace", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create two workspaces
    const wsName1 = `NewTab Test 1 ${Date.now()}`;
    const wsName2 = `NewTab Test 2 ${Date.now()}`;

    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName1);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName2);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // Switch to Workspace 1
    await page
      .locator(".nav-item")
      .filter({ hasText: wsName1 })
      .first()
      .click();
    await page.waitForTimeout(500);

    // Open a new tab while in Workspace 1
    const newTab = await context.newPage();
    await newTab.goto("https://example.com/new-tab-test");
    await page.waitForTimeout(500);

    // Verify tab appears in Workspace 1
    await page.bringToFront();
    const activeTabsPanel = page
      .locator(".card-section")
      .filter({ hasText: "Active Tabs" });
    await expect(activeTabsPanel.getByText("example.com")).toBeVisible();

    // Switch to Workspace 2
    await page
      .locator(".nav-item")
      .filter({ hasText: wsName2 })
      .first()
      .click();
    await page.waitForTimeout(1000);

    // Workspace 2 should NOT have the tab from Workspace 1 in its Active Tabs
    // (The browser may close the tab due to workspace switching, but UI should be isolated)
    const ws2ActiveTabs = page
      .locator(".card-section")
      .filter({ hasText: "Active Tabs" });
    // Either no tabs, or no tab matching our specific URL
    const tabCount = await ws2ActiveTabs
      .locator('[data-testid="tab-item"]')
      .count();
    if (tabCount > 0) {
      // If there are tabs, they should not be our new-tab-test
      await expect(ws2ActiveTabs.getByText("new-tab-test")).not.toBeVisible();
    }

    await newTab.close();
    await page.close();
  });

  test("tab state persists across workspace switches", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    const wsName = `Persist Test ${Date.now()}`;

    // Create workspace
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // Switch to the workspace
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();
    await page.waitForTimeout(500);

    // Open a tab
    const testTab = await context.newPage();
    await testTab.goto("https://example.com/persist-test");
    await page.waitForTimeout(500);

    // Verify tab appears
    await page.bringToFront();
    const activeTabsPanel = page
      .locator(".card-section")
      .filter({ hasText: "Active Tabs" });
    await expect(activeTabsPanel.getByText("example.com")).toBeVisible();

    // Switch to another workspace (first one in the list)
    await page.locator(".nav-item").first().click();
    await page.waitForTimeout(1000);

    // Switch back to our workspace
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();
    await page.waitForTimeout(1000);

    // Tab should be restored
    await expect(activeTabsPanel.getByText("example.com")).toBeVisible();

    await testTab.close();
    await page.close();
  });
});
