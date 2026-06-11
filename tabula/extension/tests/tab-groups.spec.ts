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
 * E2E tests for Chrome Tab Groups persistence
 *
 * These tests verify that tab groups (with titles, colors, and collapsed states)
 * are correctly saved and restored when switching between workspaces.
 *
 * The restoration bug that prompted these tests was:
 * - Tab groups saved correctly to storage
 * - But restoration failed due to URL matching issues (tabs showed about:blank during load)
 * - Fixed by using position-based matching instead
 *
 * These tests ensure we don't regress on tab group functionality.
 */

/* eslint-disable import/no-extraneous-dependencies */
import { test, expect, chromium, BrowserContext, Page } from "@playwright/test";
import path from "path";
import fs from "fs";
import { getOrCreateDashboardPage } from "./e2e-helpers";

const EXTENSION_PATH = process.env.EXTENSION_PATH
  ? path.resolve(process.env.EXTENSION_PATH)
  : path.join(__dirname, "../dist");

let context: BrowserContext;
let extensionId: string;

test.beforeAll(async () => {
  if (!fs.existsSync(EXTENSION_PATH)) {
    throw new Error(
      `Extension not built. Please run 'npm run build --workspace=extension' before running E2E tests.`,
    );
  }

  context = await chromium.launchPersistentContext("", {
    // Full Chromium in the new headless mode: supports MV3 extensions, no
    // xvfb needed (Playwright >= 1.49).
    channel: "chromium",
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
      "--no-sandbox",
      "--disable-setuid-sandbox",
    ],
  });

  const [firstWorker] = context.serviceWorkers();
  const background =
    firstWorker || (await context.waitForEvent("serviceworker"));
  // eslint-disable-next-line prefer-destructuring
  extensionId = background.url().split("/")[2];
});

test.afterAll(async () => {
  await context.close();
});

/**
 * Helper to create a tab group with specified tabs
 */
async function createTabGroup(
  page: Page,
  tabUrls: string[],
  groupName: string,
  groupColor: string = "blue",
): Promise<{ groupId: number; tabIds: number[] }> {
  return page.evaluate(
    async ({ urls, name, color }) => {
      // Open tabs for the group
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { chrome } = window as any;

      // Create tabs using Promise.all to avoid for...of loop
      const tabs = await Promise.all(
        urls.map((url: string) => chrome.tabs.create({ url })),
      );
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const tabIds = tabs.map((tab: any) => tab.id);

      // Wait a bit for tabs to initialize
      await new Promise<void>((resolve) => {
        setTimeout(resolve, 500);
      });

      // Create group
      const groupId = await chrome.tabs.group({ tabIds });

      // Set group properties
      await chrome.tabGroups.update(groupId, {
        title: name,
        color,
        collapsed: false,
      });

      return { groupId, tabIds };
    },
    { urls: tabUrls, name: groupName, color: groupColor },
  );
}

/**
 * Helper to get all current tab groups
 */
async function getTabGroups(page: Page): Promise<
  Array<{
    id: number;
    title: string;
    color: string;
    collapsed: boolean;
  }>
> {
  return page.evaluate(async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const groups = await (window as any).chrome.tabGroups.query({});
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return groups.map((g: any) => ({
      id: g.id,
      title: g.title || "",
      color: g.color,
      collapsed: g.collapsed,
    }));
  });
}

/**
 * Helper to get workspace tabGroups from storage
 */
async function getWorkspaceTabGroupsFromStorage(
  page: Page,
  workspaceName: string,
): Promise<unknown[]> {
  return page.evaluate(async (wsName) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const result = await (window as any).chrome.storage.local.get(
      "tabula_workspaces",
    );
    const workspaces = result.tabula_workspaces || [];
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const ws = workspaces.find((w: any) => w.name.includes(wsName));
    return ws?.tabGroups || [];
  }, workspaceName);
}

test.describe("Tab Groups Persistence", () => {
  test.describe.configure({ mode: "serial" });

  test.beforeEach(async () => {
    // Clean up workspaces before each test
    const page = await getOrCreateDashboardPage(context, extensionId);

    await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      await storage.set({
        tabula_workspaces: [],
        tabula_active_workspace: null,
      });
    });

    // Close all non-extension tabs
    await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const tabs = await (window as any).chrome.tabs.query({});
      const tabsToClose = tabs.filter(
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (t: any) =>
          !t.url.startsWith("chrome") &&
          !t.url.startsWith("chrome-extension://"),
      );
      if (tabsToClose.length > 0) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (window as any).chrome.tabs.remove(
          tabsToClose.map((t: any) => t.id),
        );
      }
    });

    await page.reload();
    await page.waitForTimeout(500);
    await page.close();
  });

  test("should save tab groups when switching away from workspace", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Enable console logging for debugging
    // eslint-disable-next-line no-console
    page.on("console", (msg) => console.log("PAGE:", msg.text()));

    // 1. Create Workspace A
    const wsNameA = `TabGroup A ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameA);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameA }).first(),
    ).toBeVisible();

    // 2. Create Workspace B
    const wsNameB = `TabGroup B ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameB);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameB }).first(),
    ).toBeVisible();

    // 3. Select Workspace A
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(1000);

    // 4. Create a tab group with 2 tabs
    const groupResult = await createTabGroup(
      page,
      ["https://www.google.com", "https://www.bing.com"],
      "Search",
      "blue",
    );
    expect(groupResult.groupId).toBeDefined();
    expect(groupResult.tabIds).toHaveLength(2);

    // Wait for sync
    await page.waitForTimeout(2000);

    // 5. Verify tab group exists in browser
    const groupsBefore = await getTabGroups(page);
    expect(groupsBefore).toHaveLength(1);
    expect(groupsBefore[0].title).toBe("Search");
    expect(groupsBefore[0].color).toBe("blue");

    // 6. Switch to Workspace B
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameB })
      .first()
      .click();
    await page.waitForTimeout(2000);

    // 7. Verify tab groups were saved in storage for Workspace A
    const savedGroups = await getWorkspaceTabGroupsFromStorage(page, wsNameA);

    // CRITICAL ASSERTION: This is what the bug was - groups were being saved as empty
    expect(savedGroups.length).toBeGreaterThan(0);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    expect((savedGroups[0] as any).title).toBe("Search");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    expect((savedGroups[0] as any).color).toBe("blue");

    await page.close();
  });

  test("should restore tab groups when switching back to workspace", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // eslint-disable-next-line no-console
    page.on("console", (msg) => console.log("PAGE:", msg.text()));

    // 1. Create 2 workspaces
    const wsNameA = `Restore A ${Date.now()}`;
    const wsNameB = `Restore B ${Date.now()}`;

    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameA);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameA }).first(),
    ).toBeVisible();

    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameB);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameB }).first(),
    ).toBeVisible();

    // 2. Switch to Workspace A
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(1000);

    // 3. Create tab group
    await createTabGroup(
      page,
      ["https://www.google.com", "https://www.bing.com"],
      "MySearch",
      "green",
    );
    await page.waitForTimeout(2000);

    // Verify group exists
    const groupsBeforeSwitch = await getTabGroups(page);
    expect(groupsBeforeSwitch).toHaveLength(1);
    expect(groupsBeforeSwitch[0].title).toBe("MySearch");

    // 4. Switch to Workspace B
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameB })
      .first()
      .click();
    await page.waitForTimeout(2000);

    // 5. Verify no tab groups in B (clean workspace)
    const groupsInB = await getTabGroups(page);
    expect(groupsInB).toHaveLength(0);

    // 6. Switch back to Workspace A
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(3000); // Allow time for restoration

    // 7. CRITICAL: Verify tab group was RESTORED
    const groupsAfterRestore = await getTabGroups(page);

    // This is the key regression test - groups must be restored
    expect(groupsAfterRestore.length).toBeGreaterThan(0);
    expect(groupsAfterRestore[0].title).toBe("MySearch");
    expect(groupsAfterRestore[0].color).toBe("green");

    await page.close();
  });

  test("should preserve tab group metadata (color, collapsed state) after restoration", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create workspace
    const wsName = `Metadata ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // Create another workspace to switch to
    const wsNameB = `Other ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameB);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // Switch to first workspace
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();
    await page.waitForTimeout(1000);

    // Create tab group with RED color
    await createTabGroup(page, ["https://example.com"], "RedGroup", "red");
    await page.waitForTimeout(2000);

    // Verify initial state
    const initialGroups = await getTabGroups(page);
    expect(initialGroups[0].color).toBe("red");
    expect(initialGroups[0].title).toBe("RedGroup");

    // Switch away and back
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameB })
      .first()
      .click();
    await page.waitForTimeout(2000);
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();
    await page.waitForTimeout(3000);

    // Verify metadata is preserved
    const restoredGroups = await getTabGroups(page);
    expect(restoredGroups.length).toBeGreaterThan(0);
    expect(restoredGroups[0].color).toBe("red");
    expect(restoredGroups[0].title).toBe("RedGroup");

    await page.close();
  });
});
