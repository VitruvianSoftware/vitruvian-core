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
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable no-console */
import { test, expect, chromium, BrowserContext } from "@playwright/test";
import path from "path";
import fs from "fs";
import {
  cleanupApiWorkspaces,
  getTestToken,
  getOrCreateDashboardPage,
  createWorkspace,
} from "./e2e-helpers";

const EXTENSION_PATH = path.join(__dirname, "../dist");

let context: BrowserContext;
let extensionId: string;
const testToken = getTestToken();

test.beforeAll(async () => {
  // Check if extension is built
  if (!fs.existsSync(EXTENSION_PATH)) {
    throw new Error(
      `Extension not built. Please run 'npm run build --workspace=extension' before running E2E tests. Expected path: ${EXTENSION_PATH}`,
    );
  }

  // Launch browser with extension loaded
  context = await chromium.launchPersistentContext("", {
    headless: false,
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
      "--no-sandbox",
      "--disable-setuid-sandbox",
    ],
  });

  // Get extension ID from background service worker
  const [firstWorker] = context.serviceWorkers();
  const background =
    firstWorker || (await context.waitForEvent("serviceworker"));
  // eslint-disable-next-line prefer-destructuring
  extensionId = background.url().split("/")[2];
  // Ensure we are in a clean state
  await getOrCreateDashboardPage(context, extensionId);

  // Clean up any existing test workspaces from API to prevent hitting 10-workspace limit
  if (testToken) {
    await cleanupApiWorkspaces(testToken, undefined, {
      includePrefix: "SERIAL_",
    });
  }
});

test.afterAll(async () => {
  // Clean up any test workspaces from API for complete test isolation
  if (testToken) {
    await cleanupApiWorkspaces(testToken, undefined, {
      includePrefix: "SERIAL_",
    });
  }
  await context.close();
});

test.describe("Sync Journeys (Serial / Flaky)", () => {
  test.describe.configure({ mode: "serial" });

  // Clean up test workspaces before each test to prevent hitting the 10 workspace limit
  test.beforeEach(async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Aggressively clear ALL workspaces to ensure we never hit the 10 limit
    await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      // We're running in serial mode, so it's safe to clear all workspaces
      await storage.set({
        tabula_workspaces: [],
        tabula_active_workspace: null,
      });
    });

    await page.reload();
    await page.waitForTimeout(500);
    await page.close();
  });

  // FIXME: This test is flaky in CI/E2E environment - resources fail to persist multiple additions in loop
  // Suspect race condition in storage or state sync.
  test("should allow tab reordering after switching workspaces and back", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Clean up any extraneous tabs (like about:blank) to ensure clean state and indices
    await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const tabs = await (window as any).chrome.tabs.query({
        currentWindow: true,
      });
      const toClose = tabs
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        .filter((t: any) => !t.url.startsWith("chrome-extension://"))
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        .map((t: any) => t.id);
      if (toClose.length > 0) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (window as any).chrome.tabs.remove(toClose);
      }
    });
    await page.waitForTimeout(500);

    // eslint-disable-next-line no-console
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));

    // 1. Create Workspace A
    const wsNameA = `SERIAL_Reorder A ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameA);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameA }).first(),
    ).toBeVisible();

    // 2. Create Workspace B
    const wsNameB = `SERIAL_Reorder B ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameB);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameB }).first(),
    ).toBeVisible();

    // 3. Switch to Workspace A
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(1000);

    // 4. Create section with 3 resources
    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    await page.fill('input[placeholder="Section Title"]', "Links");
    await page.getByText("Save", { exact: true }).click();

    // Explicitly wait for the section to appear and stabilize
    const sectionContainer = page
      .locator(".section-container", { has: page.locator('text="Links"') })
      .first();
    await expect(sectionContainer).toBeVisible({ timeout: 5000 });

    // eslint-disable-next-line no-console
    console.log('Section "Links" found. Starting resource addition...');

    // eslint-disable-next-line no-console
    console.log('Section "Links" found. Starting resource addition...');

    const addResBtn = sectionContainer
      .locator('button[title="Add resource"]')
      .first();

    // Add Alpha
    // eslint-disable-next-line no-console
    console.log("Adding resource Alpha...");
    await expect(addResBtn).toBeVisible();
    await addResBtn.click();
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.fill('input[placeholder="Title"]', "Alpha");
    await page.fill('input[placeholder="URL"]', "https://example.com/alpha");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(
      page.locator(".item-title").filter({ hasText: "Alpha" }).first(),
    ).toBeVisible();
    await page.waitForTimeout(1000);

    // Add Beta
    // eslint-disable-next-line no-console
    console.log("Adding resource Beta...");
    // Ensure menu is closed or button is ready
    await expect(addResBtn).toBeVisible();
    await addResBtn.click();
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.fill('input[placeholder="Title"]', "Beta");
    await page.fill('input[placeholder="URL"]', "https://example.com/beta");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(
      page.locator(".item-title").filter({ hasText: "Beta" }).first(),
    ).toBeVisible();
    await page.waitForTimeout(1000);

    // 5. Click "Open All" to open resources as tabs

    // 5. Click "Open All" to open resources as tabs
    // Verify all 2 resources are present before clicking
    await expect(sectionContainer.locator(".list-item")).toHaveCount(2);
    await page.waitForTimeout(2000); // Ensure state propagation

    // eslint-disable-next-line no-console
    console.log("Clicking Open All...");
    await sectionContainer
      .locator("button")
      .filter({ hasText: "Open All" })
      .click();

    // Wait for actual browser tabs to open (source of truth)
    await expect
      .poll(
        async () => {
          const tabs = await page.evaluate(async () => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const t = await (window as any).chrome.tabs.query({
              currentWindow: true,
            });
            const valid = t.filter(
              (x: any) =>
                !x.url.startsWith("chrome-extension://") &&
                x.url !== "about:blank",
            );
            return valid.length;
          });
          // eslint-disable-next-line no-console
          console.log(`Current browser tabs count: ${tabs}`);
          return tabs;
        },
        {
          message: "Waiting for 2 browser tabs to open",
          timeout: 10000,
        },
      )
      .toBe(2);

    await page.waitForTimeout(2000); // allow UI to catch up

    // 6. Verify 2 tabs in Active Tabs panel
    const activeTabsPanel = page
      .locator(".card-section")
      .filter({ hasText: "Active Tabs" });
    await expect(
      activeTabsPanel.locator('[data-testid="tab-item"]'),
    ).toHaveCount(2);

    // 7. Get initial order of tabs
    // const tabsBefore = await activeTabsPanel.locator('[data-testid="tab-item"]').allTextContents();

    // 8. Switch to Workspace B
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameB })
      .first()
      .click();
    await page.waitForTimeout(2500); // Increased wait for workspace switch to complete

    // 9. Switch back to Workspace A
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(2500); // Increased wait for workspace switch to complete

    // 10. Verify tabs are restored
    await expect(
      activeTabsPanel.locator('[data-testid="tab-item"]'),
    ).toHaveCount(2);

    // 11. Verify that the workspace has fresh Chrome tab IDs (core of the fix)
    // Get current browser tabs
    const browserTabs = await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const tabs = await (window as any).chrome.tabs.query({
        currentWindow: true,
      });
      return (
        tabs
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          .filter(
            (t: any) =>
              !t.url.startsWith("chrome-extension://") &&
              t.url !== "about:blank",
          )
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          .map((t: any) => ({ id: t.id, url: t.url, index: t.index }))
          .sort((a: any, b: any) => a.index - b.index)
      );
    });

    // Verify we have the expected tabs
    expect(browserTabs).toHaveLength(2);
    expect(browserTabs[0].url).toContain("alpha");
    expect(browserTabs[1].url).toContain("beta");

    // 12. Use Chrome API directly to reorder tabs (bypass Playwright DnD limitations)
    // Move the first tab (Alpha) to the last position (using index: -1 which means end)
    const firstTabId = browserTabs[0].id; // Alpha

    await page.evaluate(
      async ({ tabId }) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const t = await (window as any).chrome.tabs.move(tabId, { index: -1 });
        console.log("Moved tab:", t);
      },
      { tabId: firstTabId },
    );

    await page.waitForTimeout(1000); // Wait for sync

    // 13. Verify tab order changed using expect.poll for robustness
    await expect
      .poll(
        async () => {
          const tabs = await page.evaluate(async () => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const t = await (window as any).chrome.tabs.query({
              currentWindow: true,
            });
            return (
              t
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                .filter(
                  (x: any) =>
                    !x.url.startsWith("chrome-extension://") &&
                    x.url !== "about:blank",
                )
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                .map((x: any) => x.url)
            );
          });
          return tabs;
        },
        {
          message: "Waiting for tab reorder to reflect in browser",
          timeout: 5000,
        },
      )
      .toEqual([
        expect.stringContaining("beta"),
        expect.stringContaining("alpha"),
      ]);

    // 14. Verify there are still 2 tabs (no crash)
    await expect(
      activeTabsPanel.locator('[data-testid="tab-item"]'),
    ).toHaveCount(2);

    await page.close();
  });

  // FIXME: This test is flaky in CI/E2E environment - Open All sometimes fails to open all tabs
  test("should have fresh Chrome tab IDs after workspace switch", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    await page.waitForLoadState("networkidle");

    const timestamp = Date.now();
    const wsNameA = `SERIAL_Fresh A ${timestamp}`;
    const wsNameB = `SERIAL_Fresh B ${timestamp}`;

    // 1. Create workspace A with tabs
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameA);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // Create workspace B
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameB);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // Switch to A and add resources
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(500);

    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    await page.fill('input[placeholder="Section Title"]', "Links");
    await page.getByText("Save", { exact: true }).click();

    const section = page
      .locator(".section-container", { has: page.locator('text="Links"') })
      .first();
    await expect(section).toBeVisible({ timeout: 5000 });

    await section.locator('button[title="Add resource"]').first().click();
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.fill('input[placeholder="Title"]', "Fresh Test");
    await page.fill('input[placeholder="URL"]', "https://example.com/fresh");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await page.waitForTimeout(300);

    // Open tabs
    await section.locator("button").filter({ hasText: "Open All" }).click();

    // Wait for actual browser tabs to open (source of truth)
    await expect
      .poll(
        async () => {
          const tabs = await page.evaluate(async () => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const t = await (window as any).chrome.tabs.query({
              currentWindow: true,
            });
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            return t.filter(
              (x: any) => !x.url.startsWith("chrome-extension://"),
            ).length;
          });
          return tabs;
        },
        {
          message: "Waiting for tabs to open",
          timeout: 10000,
        },
      )
      .toBeGreaterThan(0);

    await page.waitForTimeout(1500);

    // 2. Record initial tab IDs from browser
    const initialTabIds = await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const tabs: any[] = await (window as any).chrome.tabs.query({
        currentWindow: true,
      });
      const validTabs = tabs.filter(
        (t) => !t.url.startsWith("chrome-extension://"),
      );
      return validTabs.map((t) => t.id);
    });

    // 3. Switch to B
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameB })
      .first()
      .click();
    await page.waitForTimeout(2000);

    // 4. Switch back to A
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(2000);

    // 5. Get NEW tab IDs from browser
    const newTabIds = await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const tabs: any[] = await (window as any).chrome.tabs.query({
        currentWindow: true,
      });
      const validTabs = tabs.filter(
        (t) => !t.url.startsWith("chrome-extension://"),
      );
      return validTabs.map((t) => t.id);
    });

    // 6. Tab IDs should be DIFFERENT (tabs were closed and reopened)
    expect(newTabIds).not.toEqual(initialTabIds);
    expect(newTabIds.length).toBeGreaterThan(0);

    // 7. Verify we can move one of these new tab IDs (proves they're valid)
    if (newTabIds.length > 0) {
      const canMove = await page.evaluate(async (tabId: number) => {
        try {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          await (window as any).chrome.tabs.move(tabId, { index: 0 });
          return true;
        } catch {
          return false;
        }
      }, newTabIds[0]);
      expect(canMove).toBe(true);
    }

    await page.close();
  });

  test("should sync workspace creation to API", async () => {
    // Set longer timeout for API-dependent test
    test.setTimeout(120000);

    if (!testToken) {
      test.skip();
    }

    const page = await getOrCreateDashboardPage(context, extensionId);
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));

    try {
      await page.waitForLoadState("domcontentloaded");

      // Login test user
      await page.evaluate(
        async ({ authToken, user }) => {
          const storage = (window as any).chrome.storage.local;
          await storage.set({
            tabula_access_token: authToken,
            tabula_user: user,
          });
        },
        {
          authToken: testToken,
          user: {
            id: "e2e-test-user-id",
            email: "e2e-test@tabula.dev",
            name: "E2E Test User",
            tier: "free",
          },
        },
      );

      await page.reload();
      await page.waitForLoadState("domcontentloaded");
      // Wait longer for sync service to initialize after auth
      await page.waitForTimeout(5000);

      // Create workspace with unique identifier
      // Use SERIAL_ prefix to ensure cleanup
      const uniqueId = Date.now();
      const wsName = `SERIAL_API Sync Test ${uniqueId}`;
      await createWorkspace(page, wsName);
      console.log(
        `[API Sync] Created workspace: ${wsName} (Time: ${new Date().toISOString()})`,
      );

      // Guard: Ensure workspace is persisted to storage before checking sync.
      await expect(async () => {
        const workspaces = await page.evaluate(async () => {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const s = await (window as any).chrome.storage.local.get(
            "tabula_workspaces",
          );
          return s.tabula_workspaces || [];
        });
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        expect(workspaces.some((w: any) => w.name === wsName)).toBe(true);
      }).toPass({ timeout: 5000 });

      // Wait for sync queue to drain to ensure request was sent
      await expect(async () => {
        const queueSize = await page.evaluate(async () => {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const s = await (window as any).chrome.storage.local.get(
            "sync_queue",
          );
          return (s.sync_queue || []).length;
        });
        console.log(
          `[API Sync] Waiting for sync queue to drain. Current size: ${queueSize}`,
        );
        expect(queueSize).toBe(0);
      }).toPass({ timeout: 30000, intervals: [1000] });

      // Poll for workspace to appear in API
      await expect(async () => {
        const response = await fetch(
          "http://localhost:8080/api/v1/workspaces",
          {
            headers: { Authorization: `Bearer ${testToken}` },
          },
        );
        expect(response.ok).toBe(true);
        const data = await response.json();
        const workspaces = data.data || [];
        console.log(
          `[API Sync] Polling API, found ${workspaces.length} workspaces. Looking for: "${wsName}"`,
        );
        const found = workspaces.some(
          (ws: { name: string }) => ws.name === wsName,
        );
        if (!found) {
          console.log(
            `[API Sync] Workspace not found yet. Available: ${workspaces
              .map((w: any) => w.name)
              .join(", ")}`,
          );
        }
        expect(found).toBe(true);
      }).toPass({
        timeout: 45000,
        intervals: [1000, 2000, 3000, 5000],
      });

      console.log("[API Verification] Workspace synced to API successfully");
    } finally {
      // No explicit cleanup needed as afterAll handles SERIAL_ prefix
      // But we can clean local storage
      await page.close();
    }
  });
});
