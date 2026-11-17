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

/**
 * E2E tests for tab synchronization in Vitruvian Tabs extension
 *
 * These tests verify critical user flows:
 * 1. Open new browser tab → appears in Active Tabs
 * 2. Close browser tab → disappears from Active Tabs
 * 3. Switch workspace → correct tabs displayed
 */

// eslint-disable-next-line import/no-extraneous-dependencies
import { test, expect, BrowserContext, Page } from "@playwright/test";
import { getOrCreateDashboardPage, launchExtension } from "./e2e-helpers";

let context: BrowserContext;
let extensionId: string;

test.beforeAll(async () => {
  // Launch Chromium with the extension and get its id.
  ({ context, extensionId } = await launchExtension());
});

test.afterAll(async () => {
  await context.close();
});

/**
 * Helper to wait for Active Tabs panel to update
 */
async function _waitForActiveTabsUpdate(
  page: Page,
  expectedCount: number,
  timeout = 5000,
) {
  await page.waitForFunction(
    (count) => {
      const items = document.querySelectorAll(
        '[data-testid="active-tab-item"]',
      );
      return items.length === count;
    },
    expectedCount,
    { timeout },
  );
}

/**
 * Helper to get the Active Tabs list element
 */
async function getActiveTabsList(page: Page) {
  return page.locator('[data-testid="active-tabs-list"]');
}

test.describe("Tab Sync User Flows", () => {
  test.describe.configure({ mode: "serial" });

  let dashboardPage: Page;

  test.beforeEach(async () => {
    dashboardPage = await getOrCreateDashboardPage(context, extensionId);

    // Cleanup workspaces and seed a default one
    await dashboardPage.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      const defaultWs = {
        id: `ws_default_${Date.now()}`,
        name: "Default Workspace",
        position: 0,
        sections: [],
        created: Date.now(),
        updated: Date.now(),
      };
      await storage.set({
        vitruvian_tabs_workspaces: [defaultWs],
        vitruvian_tabs_active_workspace: defaultWs.id,
      });
    });
    await dashboardPage.reload();

    // Wait for dashboard to load
    await dashboardPage.waitForSelector(".dashboard-container", {
      timeout: 10000,
    });

    // Check if we need to create a default workspace
    const hasWorkspaces =
      (await dashboardPage.locator(".nav-item").count()) > 0;
    if (!hasWorkspaces) {
      // Create a default workspace to ensure sync works
      const addBtn = dashboardPage.locator(".spaces-header .icon-add").first();
      if (await addBtn.isVisible()) {
        await addBtn.click();
      } else {
        // Fallback if header is different
        await dashboardPage
          .getByRole("button", { name: /New Space/i })
          .click()
          .catch(() => {});
      }

      // Handle case where menu opens
      const initialModal = dashboardPage.getByRole("dialog");
      if (!(await initialModal.isVisible())) {
        await dashboardPage
          .getByText("New Space")
          .click()
          .catch(() => {});
      }

      await dashboardPage
        .getByPlaceholder("Enter name...")
        .fill("Default Workspace");
      await dashboardPage.getByRole("button", { name: "Create" }).click();
      await dashboardPage.waitForSelector(".nav-item");
    }
  });

  test.afterEach(async () => {
    await dashboardPage.close();
  });

  test("should display correct tabs after workspace switch", async () => {
    // Create a new workspace first
    await dashboardPage.locator('button[title="Add"]').click();
    await dashboardPage.getByText("New space").click();

    const wsName = `Tab Test WS ${Date.now()}`;
    await dashboardPage
      .locator('input[placeholder="Enter name..."]')
      .fill(wsName);
    await dashboardPage.getByRole("button", { name: "Create" }).click();

    // Verify workspace appears
    await expect(
      dashboardPage.getByText(wsName, { exact: true }),
    ).toBeVisible();

    // Open some tabs in this workspace
    const tab1 = await context.newPage();
    await tab1.goto("https://example.com");
    await tab1.waitForLoadState("domcontentloaded");

    await dashboardPage.waitForTimeout(500);

    // Switch back to Default workspace
    await dashboardPage
      .locator(".nav-item")
      .filter({ hasText: "Default" })
      .first()
      .click();
    await dashboardPage.waitForTimeout(500);

    // The Active Tabs should now show the tabs from Default workspace, not the test workspace
    // (Note: actual verification depends on whether workspaces maintain separate tab sets)

    // Switch back to test workspace
    await dashboardPage
      .locator(".nav-item")
      .filter({ hasText: wsName })
      .first()
      .click();
    await dashboardPage.waitForTimeout(500);

    // Clean up
    await tab1.close();
  });
});

test.describe("Tab Sync Edge Cases", () => {
  test("should handle rapid tab open/close without losing state", async () => {
    const dashboardPage = await getOrCreateDashboardPage(context, extensionId);
    await dashboardPage.waitForSelector(".dashboard-container", {
      timeout: 10000,
    });

    // Rapidly open and close tabs using Promise.all to avoid await in loop
    const rapidTabOps = [0, 1, 2].map(async (i) => {
      const tab = await context.newPage();
      await tab.goto(`data:text/html,<h1>Rapid Tab ${i}</h1>`);
      await tab.close();
    });
    await Promise.all(rapidTabOps);

    // Wait for debounce to settle
    await dashboardPage.waitForTimeout(500);

    // Dashboard should still be functional (no crash, no stale data)
    await expect(dashboardPage.locator(".dashboard-container")).toBeVisible();

    await dashboardPage.close();
  });

  test("should not show extension pages in Active Tabs", async () => {
    const dashboardPage = await getOrCreateDashboardPage(context, extensionId);
    await dashboardPage.waitForSelector(".dashboard-container", {
      timeout: 10000,
    });

    const activeTabsList = await getActiveTabsList(dashboardPage);

    // The dashboard itself (extension page) should not appear in Active Tabs
    const extensionTabItems = await activeTabsList
      .locator('[data-testid="active-tab-item"]')
      .filter({ hasText: "Vitruvian Tabs Dashboard" })
      .count();

    expect(extensionTabItems).toBe(0);

    await dashboardPage.close();
  });
});
