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
/**
 * E2E Tests for URL-Based Workspace Routing (Multi-Window Support)
 *
 * Tests the Workona-style URL parameter feature where:
 * - dashboard.html?spaceId=xyz loads workspace xyz
 * - Switching workspaces updates the URL
 * - Session restore (page reload) preserves workspace state
 */
import { test, expect, chromium, BrowserContext } from "@playwright/test";
import path from "path";
import fs from "fs";
import {
  getOrCreateDashboardPage,
  createWorkspace,
  cleanupAllTestData,
} from "./e2e-helpers";

const EXTENSION_PATH = path.join(__dirname, "../dist");

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
});

test.afterAll(async () => {
  await context.close();
});

test.describe("URL-Based Workspace Routing", () => {
  test.describe.configure({ mode: "serial" });

  let testWorkspace1Id: string;
  let testWorkspace1Name: string;
  let testWorkspace2Name: string;

  test.beforeAll(async () => {
    // Setup: Create test workspaces and capture their IDs
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Clean up any existing test data
    await cleanupAllTestData(page);
    await page.waitForTimeout(500);

    // Create first workspace
    testWorkspace1Name = `URL Test A ${Date.now()}`;
    await createWorkspace(page, testWorkspace1Name);
    await page.waitForTimeout(500);

    // Capture workspace ID from storage
    testWorkspace1Id = await page.evaluate(async (wsName) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      const result = await storage.get("tabula_workspaces");
      const workspaces = result.tabula_workspaces || [];
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const ws = workspaces.find((w: any) => w.name === wsName);
      return ws?.id || "";
    }, testWorkspace1Name);

    // Create second workspace
    testWorkspace2Name = `URL Test B ${Date.now()}`;
    await createWorkspace(page, testWorkspace2Name);
    await page.waitForTimeout(500);
  });

  test("should load workspace from URL spaceId parameter", async () => {
    // Open NEW dashboard page with ?spaceId parameter
    const dashboardUrl = `chrome-extension://${extensionId}/dashboard.html?spaceId=${testWorkspace1Id}`;
    const page = await context.newPage();
    await page.goto(dashboardUrl);
    await page.waitForLoadState("domcontentloaded");

    // Wait for sidebar nav to load with workspaces
    await page.waitForSelector(".sidebar-nav .nav-item", { timeout: 10000 });
    // Wait for URL initialization to complete
    await page.waitForTimeout(2000);

    // Verify the correct workspace is active (shown in sidebar as active)
    const activeNavItem = page.locator(".nav-item.active");
    await expect(activeNavItem).toBeVisible({ timeout: 5000 });
    await expect(activeNavItem).toContainText(testWorkspace1Name);

    // Verify URL still contains spaceId
    expect(page.url()).toContain(`spaceId=${testWorkspace1Id}`);

    await page.close();
  });

  test("should update URL when switching workspaces", async () => {
    // Open a fresh dashboard without ?spaceId= so no workspace is initially active from URL
    const page = await context.newPage();
    await page.goto(`chrome-extension://${extensionId}/dashboard.html`);
    await page.waitForLoadState("domcontentloaded");
    await page.waitForSelector(".sidebar-nav .nav-item", { timeout: 10000 });
    await page.waitForTimeout(1000);

    // First switch to workspace 2 (this should ALWAYS trigger a switch since we start fresh)
    await page
      .locator(".nav-item")
      .filter({ hasText: testWorkspace2Name })
      .first()
      .click();
    await page.waitForTimeout(1500);

    // URL should now contain SOME spaceId (workspace 2's ID)
    expect(page.url()).toContain("spaceId=");

    // Now switch to workspace 1
    await page
      .locator(".nav-item")
      .filter({ hasText: testWorkspace1Name })
      .first()
      .click();
    await page.waitForTimeout(1500);

    // URL should now contain spaceId=workspace1
    expect(page.url()).toContain(`spaceId=${testWorkspace1Id}`);

    await page.close();
  });

  test("should persist workspace state across page reload (session restore)", async () => {
    // Open dashboard with specific workspace
    const dashboardUrl = `chrome-extension://${extensionId}/dashboard.html?spaceId=${testWorkspace1Id}`;
    const page = await context.newPage();
    await page.goto(dashboardUrl);
    await page.waitForLoadState("domcontentloaded");
    await page.waitForSelector(".sidebar-nav .nav-item", { timeout: 10000 });
    await page.waitForTimeout(1500);

    // Verify workspace 1 is active
    const activeNavItem = page.locator(".nav-item.active");
    await expect(activeNavItem).toBeVisible({ timeout: 5000 });
    await expect(activeNavItem).toContainText(testWorkspace1Name);

    // Reload the page (simulates session restore)
    await page.reload();
    await page.waitForLoadState("domcontentloaded");
    await page.waitForTimeout(1000);

    // Workspace 1 should STILL be active after reload
    await expect(activeNavItem).toContainText(testWorkspace1Name);

    // URL should still contain the spaceId
    expect(page.url()).toContain(`spaceId=${testWorkspace1Id}`);

    await page.close();
  });

  test("should handle invalid spaceId gracefully", async () => {
    // Open dashboard with non-existent workspace ID
    const fakeWorkspaceId = "non-existent-workspace-12345";
    const dashboardUrl = `chrome-extension://${extensionId}/dashboard.html?spaceId=${fakeWorkspaceId}`;
    const page = await context.newPage();
    await page.goto(dashboardUrl);
    await page.waitForLoadState("domcontentloaded");
    await page.waitForTimeout(1000);

    // Should not crash - dashboard should load with some workspace (or empty state)
    // The sidebar should be visible
    await expect(page.locator(".sidebar")).toBeVisible();

    // The key assertion is that the page loads without error

    await page.close();
  });
});

test.describe("Multi-Context Workspace Isolation", () => {
  test("two browser tabs can have different active workspaces via URL", async () => {
    // Create test workspaces for this test
    const page1 = await getOrCreateDashboardPage(context, extensionId);
    // Wait for sidebar (not nav-item, since sidebar may be empty until we create workspaces)
    await page1.waitForSelector(".sidebar", { timeout: 10000 });

    const wsNameA = `Context A ${Date.now()}`;
    const wsNameB = `Context B ${Date.now()}`;

    await createWorkspace(page1, wsNameA);
    await page1.waitForTimeout(500);
    await createWorkspace(page1, wsNameB);
    await page1.waitForTimeout(500);

    // Get workspace IDs
    const workspaceIds = await page1.evaluate(
      async (names) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const storage = (window as any).chrome.storage.local;
        const result = await storage.get("tabula_workspaces");
        const workspaces = result.tabula_workspaces || [];
        return {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          idA: workspaces.find((w: any) => w.name === names.a)?.id || "",
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          idB: workspaces.find((w: any) => w.name === names.b)?.id || "",
        };
      },
      { a: wsNameA, b: wsNameB },
    );

    // Close setup page
    await page1.close();

    // Open page1 with workspace A
    const pageA = await context.newPage();
    await pageA.goto(
      `chrome-extension://${extensionId}/dashboard.html?spaceId=${workspaceIds.idA}`,
    );
    await pageA.waitForLoadState("domcontentloaded");
    await pageA.waitForSelector(".sidebar-nav .nav-item", { timeout: 10000 });
    await pageA.waitForTimeout(2000);

    // Verify page A shows workspace A as active
    const activeNavItemA = pageA.locator(".nav-item.active");
    await expect(activeNavItemA).toBeVisible({ timeout: 5000 });
    await expect(activeNavItemA).toContainText(wsNameA);

    // Open page2 (different tab in same context) with workspace B
    const pageB = await context.newPage();
    await pageB.goto(
      `chrome-extension://${extensionId}/dashboard.html?spaceId=${workspaceIds.idB}`,
    );
    await pageB.waitForLoadState("domcontentloaded");
    await pageB.waitForSelector(".sidebar-nav .nav-item", { timeout: 10000 });
    await pageB.waitForTimeout(2000);

    // Verify page B shows workspace B as active (NOT affected by page A)
    const activeNavItemB = pageB.locator(".nav-item.active");
    await expect(activeNavItemB).toBeVisible({ timeout: 5000 });
    await expect(activeNavItemB).toContainText(wsNameB);

    // Go back to page A and verify it STILL shows workspace A
    // (not changed by page B loading workspace B)
    await pageA.bringToFront();
    await pageA.waitForTimeout(500);
    const activeNavItemA2 = pageA.locator(".nav-item.active");
    await expect(activeNavItemA2).toContainText(wsNameA);

    // CRITICAL TEST: Switch workspace in page B and verify page A is unaffected
    // This tests Bug 2: main content shouldn't follow shared state
    await pageB.bringToFront();
    await pageB.waitForTimeout(500);

    // Create a third workspace to switch to
    const wsNameC = `Context C ${Date.now()}`;
    await createWorkspace(pageB, wsNameC);
    await pageB.waitForTimeout(1000);

    // Switch page B to workspace C by clicking on it
    await pageB
      .locator(".nav-item")
      .filter({ hasText: wsNameC })
      .first()
      .click();
    await pageB.waitForTimeout(1500);

    // Verify page B now shows workspace C
    const activeNavItemB2 = pageB.locator(".nav-item.active");
    await expect(activeNavItemB2).toContainText(wsNameC);

    // Verify page B's header shows workspace C
    const headerB = pageB.locator(".section-title").first();
    await expect(headerB).toContainText(wsNameC);

    // NOW CHECK PAGE A - it should STILL show workspace A's content
    await pageA.bringToFront();
    await pageA.waitForTimeout(500);

    // Verify page A's sidebar still shows workspace A as active
    const activeNavItemA3 = pageA.locator(".nav-item.active");
    await expect(activeNavItemA3).toContainText(wsNameA);

    // Verify page A's HEADER (main content) still shows workspace A's name
    // This is the critical check for Bug 2
    const headerA = pageA.locator(".section-title").first();
    await expect(headerA).toContainText(wsNameA);

    // Both pages are now independent - each shows its own workspace from URL
    await pageA.close();
    await pageB.close();
  });
});
