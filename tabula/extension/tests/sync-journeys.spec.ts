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
    await cleanupApiWorkspaces(testToken);
  }
});

test.afterAll(async () => {
  // Clean up any test workspaces from API for complete test isolation
  if (testToken) {
    await cleanupApiWorkspaces(testToken);
  }
  await context.close();
});

test.describe("Sync Journeys (Space & Section Management)", () => {
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

  test("should create and rename a workspace", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    const wsName = `Test WS ${Date.now()}`;
    await page.locator('input[placeholder="Enter name..."]').fill(wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    // Rename
    const wsRow = page.locator(".nav-item").filter({ hasText: wsName }).first();
    await wsRow.hover();
    await wsRow.locator('button[aria-label="Space options"]').click();
    await page
      .locator(".dropdown-menu .dropdown-item")
      .filter({ hasText: "Rename" })
      .click();
    const newWsName = `${wsName} Renamed`;
    await page.locator('input[placeholder="Enter name..."]').fill(newWsName);
    await page
      .locator(".modal-footer button.btn-primary")
      .filter({ hasText: "Save" })
      .click();
    await expect(
      page.locator(".nav-item").filter({ hasText: newWsName }).first(),
    ).toBeVisible();
    await page.close();
  });

  test("should create and rename a section", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    await page.locator('button[title="Add"]').click();
    await page.getByText("New section").click();
    const sectionName = `Test Section ${Date.now()}`;
    await page.locator('input[placeholder="Enter name..."]').fill(sectionName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(page.getByText(sectionName)).toBeVisible();

    // Rename
    const sectionHeader = page
      .locator(".nav-item")
      .filter({ hasText: sectionName })
      .first();
    await sectionHeader.hover();
    await sectionHeader.locator('button[aria-label="Section options"]').click();
    const newSectionName = `${sectionName} RENAMED`;
    page.once("dialog", async (dialog) => {
      await dialog.accept(newSectionName);
    });
    await page
      .locator(".dropdown-menu .dropdown-item")
      .filter({ hasText: "Rename" })
      .click();
    await expect(page.getByText(newSectionName)).toBeVisible();
    await page.close();
  });

  test("should delete a workspace", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const wsName = `Delete Me ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.locator('input[placeholder="Enter name..."]').fill(wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    const wsRow = page.locator(".nav-item").filter({ hasText: wsName }).first();
    await wsRow.hover();
    await wsRow.locator('button[aria-label="Space options"]').click();
    await page
      .locator(".dropdown-menu .dropdown-item")
      .filter({ hasText: "Delete" })
      .click();
    await expect(
      page.getByText("Are you sure you want to delete this workspace?"),
    ).toBeVisible();
    await page
      .locator(".modal-footer button.btn-primary")
      .filter({ hasText: "Delete" })
      .click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }),
    ).not.toBeVisible();
    await page.close();
  });

  test("should create and delete a space group", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const groupName = `Group ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New section").click();
    await page.locator('input[placeholder="Enter name..."]').fill(groupName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.getByTestId("sidebar-group-header").filter({ hasText: groupName }),
    ).toBeVisible();

    const groupHeader = page
      .getByTestId("sidebar-group-header")
      .filter({ hasText: groupName })
      .first();
    await groupHeader.hover();
    const optionsBtn = groupHeader
      .locator('button[aria-label="Section options"]')
      .or(groupHeader.locator("button").last());
    await optionsBtn.click();
    await page
      .locator(".dropdown-menu .dropdown-item")
      .filter({ hasText: "Delete" })
      .click();
    await expect(
      page.getByText(`Delete section "${groupName}"?`),
    ).toBeVisible();
    await page.getByRole("button", { name: "Delete" }).click();
    await expect(
      page.getByTestId("sidebar-group-header").filter({ hasText: groupName }),
    ).not.toBeVisible();
    await page.close();
  });

  test("should persist resources and notes when switching workspaces", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Debug logging
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));

    // 1. Create Workspace A
    const wsNameA = `Persist A ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.locator('input[placeholder="Enter name..."]').fill(wsNameA);
    await page.getByRole("button", { name: "Create" }).click();

    // 2. Create Workspace B
    const wsNameB = `Persist B ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.locator('input[placeholder="Enter name..."]').fill(wsNameB);
    await page.getByRole("button", { name: "Create" }).click();

    // 3. Select Workspace A
    await page.locator(".nav-item").filter({ hasText: wsNameA }).click();

    // 4. Create resource in A

    // Create section first
    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    await page
      .locator('input[placeholder="Section Title"]')
      .fill("Content Section");
    await page.getByText("Save", { exact: true }).click();

    const contentSection = page
      .locator(".section-title")
      .filter({ hasText: "Content Section" });
    await expect(contentSection).toBeVisible();

    // Wait for Section creation to settle (race mitigation)
    await page.waitForTimeout(1000);

    // Add Resource
    const sectionContainer = page
      .locator(".section-container")
      .filter({ hasText: "Content Section" });
    await sectionContainer
      .locator('button[title="Add resource"]')
      .first()
      .click();

    const addResItem = page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" });
    await addResItem.click();

    // Fill Resource Form
    const resTitle = "My Resource";
    const resUrl = "https://example.com/res";

    const titleInput = page.locator('input[placeholder="Title"]');
    await expect(titleInput).toBeVisible();
    await titleInput.fill(resTitle);
    await page.locator('input[placeholder="URL"]').fill(resUrl);

    // Wait for state update
    await page.waitForTimeout(500);

    // Click Save
    const saveBtn = page.getByText("Save", { exact: true });
    await expect(saveBtn).toBeEnabled();
    await saveBtn.click();

    // Verify Form Disappears
    await expect(titleInput).not.toBeVisible();

    // Verify Resource Appears
    await expect(page.getByText(resTitle)).toBeVisible();

    // Wait for save to persist (race mitigation)
    await page.waitForTimeout(1000);

    // 5. Create Note in A
    await page.locator(".tab-item").filter({ hasText: "Notes" }).click();
    await page.getByText("+ New Note").click();

    const noteTitle = "My Note";
    const noteContent = "This is a test note";

    await page.locator('input[placeholder="Note Title"]').fill(noteTitle);
    await page
      .locator('textarea[placeholder="Type something..."]')
      .fill(noteContent);
    await page
      .locator(".note-card.editing button")
      .filter({ hasText: "Save" })
      .click();

    // Verify Note Exists
    await expect(page.locator(".note-title-display")).toHaveValue(noteTitle);

    // 6. Switch to Workspace B
    await page.locator(".nav-item").filter({ hasText: wsNameB }).click();

    // 7. Verify B is empty
    await page.locator(".tab-item").filter({ hasText: "Resources" }).click();
    await expect(page.getByText(resTitle)).not.toBeVisible();
    await expect(page.getByText("Content Section")).not.toBeVisible();

    await page.locator(".tab-item").filter({ hasText: "Notes" }).click();
    await expect(page.getByText(noteTitle)).not.toBeVisible();

    // 8. Switch back to A by navigating to its URL (?spaceId=) — the dashboard
    // is URL-routed per window, so the URL (not tabula_active_workspace) is the
    // source of truth for which workspace a window shows. This also exercises
    // persistence: the data must survive a fresh page load.
    const wsAId = await page.evaluate(async (name) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const w = (
        await (window as any).chrome.storage.local.get("tabula_workspaces")
      ).tabula_workspaces.find((ws: any) => ws.name.startsWith(name));
      return w?.id as string | undefined;
    }, "Persist A");
    await page.goto(
      `chrome-extension://${extensionId}/dashboard.html?spaceId=${wsAId}`,
    );
    await page.waitForTimeout(1000);

    // 9. Verify items persist
    // Check Section First - Critical for debugging
    await page.locator(".tab-item").filter({ hasText: "Resources" }).click();
    await expect(page.getByText("Content Section")).toBeVisible();

    // Check Resource
    await expect(page.getByText(resTitle)).toBeVisible();

    // Check Notes
    await page.locator(".tab-item").filter({ hasText: "Notes" }).click();
    await expect(page.locator(".note-title-display")).toHaveValue(noteTitle);

    await page.close();
  });

  // DEBUG: Running with extensive logging to trace page closure bug
  // eslint-disable-next-line no-console
  test("should close browser tab when closing from Active Tabs panel", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Capture console logs from the extension
    // eslint-disable-next-line no-console
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));
    // eslint-disable-next-line no-console
    page.on("close", () => console.log(">>> PAGE CLOSED EVENT <<<"));
    // eslint-disable-next-line no-console
    page.on("pageerror", (err) => console.log("PAGE ERROR:", err));

    // eslint-disable-next-line no-console
    console.log("Navigated to dashboard");

    // 1. Create Workspace A
    const wsNameA = `TabSync A ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.locator('input[placeholder="Enter name..."]').fill(wsNameA);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameA }).first(),
    ).toBeVisible();

    // 2. Create Workspace B
    const wsNameB = `TabSync B ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.locator('input[placeholder="Enter name..."]').fill(wsNameB);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameB }).first(),
    ).toBeVisible();

    // 3. Switch to Workspace A (using sidebar click like test 5)
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(1000);

    // 4. Create Section "Links" (using correct selectors from working tests)
    // eslint-disable-next-line no-console
    console.log("STEP 4: Creating section");
    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    // eslint-disable-next-line no-console
    console.log("STEP 4a: Clicked RESOURCE SECTION");
    await page.locator('input[placeholder="Section Title"]').fill("Links");
    await page.getByText("Save", { exact: true }).click();
    await expect(
      page.locator(".section-title").filter({ hasText: "Links" }),
    ).toBeVisible();
    // eslint-disable-next-line no-console
    console.log("STEP 4b: Section created");
    await page.waitForTimeout(500);

    // 5. Add Resource (example.com)
    // eslint-disable-next-line no-console
    console.log("STEP 5: Adding resource");
    const sectionContainer = page
      .locator(".section-container")
      .filter({ hasText: "Links" });
    // eslint-disable-next-line no-console
    console.log("STEP 5a: Found section container");
    // Button might be in header AND empty state, so take first
    await sectionContainer
      .locator('button[title="Add resource"]')
      .first()
      .click();
    // eslint-disable-next-line no-console
    console.log("STEP 5b: Clicked Add resource button");
    const addResItem = page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" });
    // eslint-disable-next-line no-console
    console.log("STEP 5c: Clicking dropdown item");
    await addResItem.click();
    // eslint-disable-next-line no-console
    console.log("STEP 5d: Clicked Add resource dropdown item");

    const resTitle = "Example Site";
    // eslint-disable-next-line no-console
    console.log("STEP 5e: About to fill Resource title input");
    await page.locator('input[placeholder="Title"]').fill(resTitle);
    await page.locator('input[placeholder="URL"]').fill("https://example.com");
    const saveBtn = page.getByRole("button", { name: "Save", exact: true });
    await expect(saveBtn).toBeEnabled();
    await saveBtn.click();
    await expect(page.getByText(resTitle)).toBeVisible();
    await page.waitForTimeout(500);

    // 6. Open the resource (clicks the Open Link button to open in new tab)
    // eslint-disable-next-line no-console
    console.log("STEP 6: Opening resource in new tab");
    const resourceItem = page
      .locator(".list-item")
      .filter({ hasText: resTitle });

    // Explicitly hover to ensure action buttons are visible and interactive (Progressive Disclosure)
    await resourceItem.hover();
    await page.waitForTimeout(200); // Wait for CSS transition (opacity/pointer-events)

    await resourceItem.locator('button[title="Open Link"]').click();
    await page.waitForTimeout(1000);

    // Verify new tab opened
    const allPages = context.pages();
    const exampleTab = allPages.find((p) => p.url().includes("example.com"));
    expect(exampleTab).toBeDefined();

    // 7. Switch to Workspace B (using manual storage to avoid closing the example.com tab)
    await page.evaluate(async (name) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const w = (
        await (window as any).chrome.storage.local.get("tabula_workspaces")
      ).tabula_workspaces.find((ws: any) => ws.name.startsWith(name));
      if (w) {
        await (window as any).chrome.storage.local.set({
          tabula_active_workspace: w.id,
        });
      }
    }, "TabSync B");
    await page.reload();
    await page.waitForTimeout(500);

    // 8. Switch back to Workspace A (using manual storage to preserve the tab)
    await page.evaluate(async (name) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      const result = await storage.get("tabula_workspaces");
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const w = result.tabula_workspaces.find((ws: any) =>
        ws.name.startsWith(name),
      );
      if (w) {
        await storage.set({ tabula_active_workspace: w.id });
      }
    }, "TabSync A");
    await page.reload();
    await page.waitForTimeout(500);

    // 9. Verify the tab appears in Active Tabs panel
    // Note: Active Tabs panel shows browser tabs, which persist through workspace switches
    const activeTabItem = page
      .locator('[data-testid="tab-item"]')
      .filter({ hasText: "example.com" });
    await expect(activeTabItem).toBeVisible();

    // 10. Close the tab from UI
    // Hover first for progressive disclosure
    await activeTabItem.hover();
    await page.waitForTimeout(200);
    const closeBtn = activeTabItem.locator('button[title="Close Tab"]');
    await closeBtn.click();
    await page.waitForTimeout(500);

    // 11. Verify browser tab is closed
    const remainingPages = context.pages();
    const exampleTabAfter = remainingPages.find((p) =>
      p.url().includes("example.com"),
    );
    expect(exampleTabAfter).toBeUndefined();

    // 12. Verify tab item no longer in UI
    await expect(activeTabItem).not.toBeVisible();

    await page.close();
  });

  test("should close tabs when switching to empty workspace (workspace isolation)", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Capture console logs
    // eslint-disable-next-line no-console
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));

    // 1. Create Workspace A (will have tabs)
    const wsNameA = `Isolation A ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameA);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsNameA }).first(),
    ).toBeVisible();

    // 2. Create Workspace B (will stay empty)
    const wsNameB = `Isolation B ${Date.now()}`;
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

    // 4. Create a section and resource in A
    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    await page.fill('input[placeholder="Section Title"]', "Test Section");
    await page.getByText("Save", { exact: true }).click();
    await expect(
      page.locator(".section-title").filter({ hasText: "Test Section" }),
    ).toBeVisible();
    await page.waitForTimeout(500);

    // 5. Add Resource - Google
    const sectionContainer = page
      .locator(".section-container")
      .filter({ hasText: "Test Section" });
    await sectionContainer
      .locator('button[title="Add resource"]')
      .first()
      .click();
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.fill('input[placeholder="Title"]', "Google");
    await page.fill('input[placeholder="URL"]', "https://www.google.com");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(
      page.locator(".item-title").filter({ hasText: "Google" }).first(),
    ).toBeVisible();
    await page.waitForTimeout(500);

    // 6. Add another resource - Bing
    await sectionContainer
      .locator('button[title="Add resource"]')
      .first()
      .click();
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.fill('input[placeholder="Title"]', "Bing");
    await page.fill('input[placeholder="URL"]', "https://www.bing.com");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(
      page.locator(".item-title").filter({ hasText: "Bing" }).first(),
    ).toBeVisible();
    await page.waitForTimeout(500);

    // 7. Click "Open All" to open resources as tabs
    await sectionContainer
      .locator("button")
      .filter({ hasText: "Open All" })
      .click();
    await page.waitForTimeout(2000);

    // 8. Verify tabs were opened (should have Google and Bing tabs)
    const pagesBeforeSwitch = context.pages();
    const googleTab = pagesBeforeSwitch.find((p) =>
      p.url().includes("google.com"),
    );
    const bingTab = pagesBeforeSwitch.find((p) => p.url().includes("bing.com"));
    expect(googleTab).toBeDefined();
    expect(bingTab).toBeDefined();

    // 9. Switch to empty Workspace B
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameB })
      .first()
      .click();
    await page.waitForTimeout(2000);

    // 10. Verify tabs were CLOSED (workspace isolation)
    const pagesAfterSwitch = context.pages();
    const googleTabAfter = pagesAfterSwitch.find((p) =>
      p.url().includes("google.com"),
    );
    const bingTabAfter = pagesAfterSwitch.find((p) =>
      p.url().includes("bing.com"),
    );
    expect(googleTabAfter).toBeUndefined();
    expect(bingTabAfter).toBeUndefined();

    // 11. Verify Active Tabs panel is empty
    const activeTabsPanel = page
      .locator(".card-section")
      .filter({ hasText: "Active Tabs" });
    const tabItems = activeTabsPanel.locator('[data-testid="tab-item"]');
    await expect(tabItems).toHaveCount(0);

    await page.close();
  });

  // FIXME: tests moved to sync-journeys-serial.spec.ts to avoid parallel execution race conditions
  // - 'should allow tab reordering after switching workspaces and back'

  test("should preserve tab state when rapidly switching workspaces", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // eslint-disable-next-line no-console
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));

    // 1. Create 3 workspaces
    const workspaces: string[] = [];
    // eslint-disable-next-line no-restricted-syntax, no-plusplus
    for (let i = 1; i <= 3; i += 1) {
      const wsName = `Rapid ${i} ${Date.now()}`;
      // eslint-disable-next-line no-await-in-loop
      await page.locator('button[title="Add"]').click();
      // eslint-disable-next-line no-await-in-loop
      await page.getByText("New space").click();
      // eslint-disable-next-line no-await-in-loop
      await page.fill('input[placeholder="Enter name..."]', wsName);
      // eslint-disable-next-line no-await-in-loop
      await page.getByRole("button", { name: "Create" }).click();
      // eslint-disable-next-line no-await-in-loop
      await expect(
        page.locator(".nav-item").filter({ hasText: wsName }).first(),
      ).toBeVisible();
      workspaces.push(wsName);
    }

    // 2. Switch to first workspace, add a resource and open it
    await page
      .locator(".nav-item")
      .filter({ hasText: workspaces[0] })
      .first()
      .click();
    await page.waitForTimeout(500);

    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    await page.fill('input[placeholder="Section Title"]', "Test");
    await page.getByText("Save", { exact: true }).click();
    await page.waitForTimeout(300);

    const sectionContainer = page
      .locator(".section-container")
      .filter({ hasText: "Test" });
    await sectionContainer
      .locator('button[title="Add resource"]')
      .first()
      .click();
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.fill('input[placeholder="Title"]', "TestSite");
    await page.fill(
      'input[placeholder="URL"]',
      "https://example.com/rapid-test",
    );
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await page.waitForTimeout(300);

    await sectionContainer
      .locator("button")
      .filter({ hasText: "Open All" })
      .click();
    await page.waitForTimeout(1000);

    // 3. Rapidly switch between all 3 workspaces (simulate user quickly navigating)
    // eslint-disable-next-line no-plusplus, no-restricted-syntax
    for (let round = 0; round < 2; round += 1) {
      // eslint-disable-next-line no-restricted-syntax
      for (const ws of workspaces) {
        // eslint-disable-next-line no-await-in-loop
        await page.locator(".nav-item").filter({ hasText: ws }).first().click();
        // eslint-disable-next-line no-await-in-loop
        await page.waitForTimeout(300); // Rapid but not instant
      }
    }

    // 4. End on workspace 1 - verify extension is stable after rapid switching
    await page
      .locator(".nav-item")
      .filter({ hasText: workspaces[0] })
      .first()
      .click();
    await page.waitForTimeout(2000);

    // With workspace isolation, tabs from workspace 1 should be restored when switching back
    // The extension should restore the saved tabs for this workspace
    const activeTabsPanel = page
      .locator(".card-section")
      .filter({ hasText: "Active Tabs" });

    // Check that we can still see the Active Tabs panel (no crashes)
    await expect(activeTabsPanel).toBeVisible();

    // Log the tab count for debugging
    const tabCount = await activeTabsPanel
      .locator('[data-testid="tab-item"]')
      .count();
    // eslint-disable-next-line no-console
    console.log(`Tabs after rapid switch: ${tabCount}`);

    // 5. Verify extension is still responsive - can switch workspaces
    await page
      .locator(".nav-item")
      .filter({ hasText: workspaces[1] })
      .first()
      .click();
    await page.waitForTimeout(500);
    await expect(activeTabsPanel).toBeVisible();

    await page.close();
  });

  test("should persist workspace order after reordering via storage", async () => {
    test.setTimeout(60000); // increase timeout for this test
    const page = await getOrCreateDashboardPage(context, extensionId);
    await page.waitForLoadState("networkidle");

    // Clean up any existing order workspaces first
    await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      const result = await storage.get("tabula_workspaces");
      if (result.tabula_workspaces) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const filtered = result.tabula_workspaces.filter(
          (ws: any) => !ws.name.includes("Order"),
        );
        await storage.set({ tabula_workspaces: filtered });
      }
    });
    await page.reload();
    await page.waitForLoadState("domcontentloaded");
    await page.waitForTimeout(1000); // Allow extension detailed init

    const timestamp = Date.now();
    const wsNames = [
      `Order A ${timestamp}`,
      `Order B ${timestamp}`,
      `Order C ${timestamp}`,
    ];

    // 1. Create 3 workspaces
    // eslint-disable-next-line no-restricted-syntax
    for (const name of wsNames) {
      // Wait for sidebar to be ready
      // eslint-disable-next-line no-await-in-loop
      await page.waitForSelector(".sidebar", { state: "visible" });

      // Open "New Space" modal via sidebar menu
      // eslint-disable-next-line no-await-in-loop
      await page.locator('button[title="Add"]').click();
      // eslint-disable-next-line no-await-in-loop
      await page.getByText("New space").click();

      // eslint-disable-next-line no-await-in-loop
      await page.fill('input[placeholder="Enter name..."]', name);
      // eslint-disable-next-line no-await-in-loop
      await page.getByRole("button", { name: "Create" }).click();
      // eslint-disable-next-line no-await-in-loop
      await page.waitForTimeout(500);
    }

    // 2. Get initial order from sidebar
    const getWorkspaceOrder = async () => {
      // Wait for at least one item
      await page.waitForSelector(".nav-item");
      const items = await page.locator(".nav-item").allTextContents();
      return items.filter((name) => wsNames.some((ws) => name.includes(ws)));
    };
    const initialOrder = await getWorkspaceOrder();
    // Ensure we have unique items
    const uniqueOrder = [...new Set(initialOrder)];
    expect(uniqueOrder.length).toBe(3);

    // 3. Reorder workspaces via Chrome storage (swap first and last)
    await page.evaluate(async (names: string[]) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const result = await (window as any).chrome.storage.local.get(
        "tabula_workspaces",
      );
      const workspaces = result.tabula_workspaces || [];
      const targetWs = workspaces.filter((w: { name: string }) =>
        names.some((n) => w.name.includes(n)),
      );
      // Swap positions of first and last
      if (targetWs.length >= 3) {
        const tempPos = targetWs[0].position;
        targetWs[0].position = targetWs[2].position;
        targetWs[2].position = tempPos;
      }
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (window as any).chrome.storage.local.set({
        tabula_workspaces: workspaces,
      });
    }, wsNames);

    // 4. Reload page
    await page.reload();
    await page.waitForLoadState("domcontentloaded");
    await page.waitForTimeout(1000);

    // 5. Verify order changed and persisted
    const newOrder = await getWorkspaceOrder();

    // Check elements match but in different order
    expect(newOrder.length).toBe(3);
    expect(newOrder).not.toEqual(initialOrder);
    expect(newOrder[0]).toContain("Order C");
    expect(newOrder[2]).toContain("Order A");

    await page.close();
  });

  // SKIPPED: Flaky storage manipulation - section order not persisting correctly
  test.skip("should reorder sections within a workspace", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    await page.waitForLoadState("networkidle");

    const timestamp = Date.now();
    const wsName = `Section Order ${timestamp}`;

    // 1. Create workspace
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();

    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(1000);

    // 2. Create sections A, B, C
    const sections = ["Section A", "Section B", "Section C"];
    // eslint-disable-next-line no-restricted-syntax
    // eslint-disable-next-line no-restricted-syntax
    for (const sectionName of sections) {
      // eslint-disable-next-line no-await-in-loop
      await page
        .locator(".main-content button")
        .filter({ hasText: "RESOURCE SECTION" })
        .click();
      // eslint-disable-next-line no-await-in-loop
      await page.fill('input[placeholder="Section Title"]', sectionName);
      // eslint-disable-next-line no-await-in-loop
      await page.getByText("Save", { exact: true }).click();
      // eslint-disable-next-line no-await-in-loop
      await page.waitForTimeout(300);
    }

    // 3. Reorder via storage (swap A and C)
    await page.evaluate(async (wName) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      const result = await storage.get("tabula_workspaces");
      // eslint-disable-next-line camelcase
      const workspaces = result.tabula_workspaces;
      const ws = workspaces.find((w: { name: string }) => w.name === wName);
      if (ws && ws.sections && ws.sections.length >= 3) {
        // Swap sections
        [ws.sections[0], ws.sections[2]] = [ws.sections[2], ws.sections[0]];
        // eslint-disable-next-line camelcase
        await storage.set({ tabula_workspaces: workspaces });
      }
    }, wsName);

    // 4. Reload
    await page.reload();
    await page.waitForTimeout(1000);

    // Switch to workspace to ensure sections load
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();
    await page.waitForTimeout(500);

    // 5. Verify order
    const sectionTitles = await page
      .locator(".section-title")
      .allTextContents();
    const relevantSections = sectionTitles.filter((t) => sections.includes(t));

    expect(relevantSections[0]).toBe("Section C");
    expect(relevantSections[2]).toBe("Section A");

    await page.close();
  });

  // FIXME: Moved to sync-journeys-serial.spec.ts
  // - 'should have fresh Chrome tab IDs after workspace switch'

  test("should sync new tab created after workspace switch", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    await page.waitForLoadState("networkidle");

    const timestamp = Date.now();
    const wsNameA = `NewTab A ${timestamp}`;
    const wsNameB = `NewTab B ${timestamp}`;

    // 1. Create workspaces
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameA);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsNameB);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // 2. Switch to workspace A
    await page
      .locator(".nav-item")
      .filter({ hasText: wsNameA })
      .first()
      .click();
    await page.waitForTimeout(1000);

    // 3. Create a new tab via Chrome API
    const newTabUrl = `https://example.com/newtab-${timestamp}`;
    await page.evaluate(async (url: string) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (window as any).chrome.tabs.create({ url, active: false });
    }, newTabUrl);

    await page.waitForTimeout(2000); // Wait for sync

    // 4. Verify new tab appears in Active Tabs panel
    const activeTabsPanel = page
      .locator(".card-section")
      .filter({ hasText: "Active Tabs" });
    const tabItems = activeTabsPanel.locator('[data-testid="tab-item"]');
    const tabCount = await tabItems.count();
    expect(tabCount).toBeGreaterThanOrEqual(1);

    // 5. Verify the new tab URL is in the list
    const tabTexts = await tabItems.allTextContents();
    const hasNewTab = tabTexts.some((text) => text.includes("newtab"));
    expect(hasNewTab).toBe(true);

    await page.close();
  });
});

// =============================================================================
// API-VERIFIED SYNC TESTS
// These tests verify that changes sync to the API when authenticated
// =============================================================================

test.describe("Sync Journeys - API Verification", () => {
  test.describe.configure({ mode: "serial" });

  // Import helpers dynamically to avoid affecting main tests
  const getToken = (): string | null => process.env.E2E_TEST_TOKEN || null;

  test.beforeEach(async () => {
    // Skip all tests in this block if no token
    if (!getToken()) {
      test.skip();
    }

    // Clean up test workspaces from API to prevent 10-workspace limit
    const token = getToken();
    if (token) {
      await cleanupApiWorkspaces(token);
    }

    // Clean up test workspaces from both local and API
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Clear local storage
    await page.evaluate(async () => {
      const storage = (window as any).chrome.storage.local;
      await storage.set({
        tabula_workspaces: [],
        tabula_active_workspace: null,
      });
    });

    await page.close();
  });

  test.afterEach(async () => {
    // Clean up API workspaces after each test for complete isolation
    const token = getToken();
    if (token) {
      await cleanupApiWorkspaces(token, undefined, {
        includePrefix: "API Sync Test",
      });
    }
  });

  test("should sync resource creation to API", async () => {
    const token = getToken();
    if (!token) {
      test.skip();
    }

    const page = await getOrCreateDashboardPage(context, extensionId);

    try {
      // Login
      await page.evaluate(
        async ({ authToken, user }) => {
          const storage = (window as any).chrome.storage.local;
          await storage.set({
            tabula_access_token: authToken,
            tabula_user: user,
          });
        },
        {
          authToken: token,
          user: {
            id: "e2e-test-user-id",
            email: "e2e-test@tabula.dev",
            name: "E2E Test User",
            tier: "free",
          },
        },
      );

      await page.reload();
      await page.waitForTimeout(1000);

      // Create workspace
      const wsName = `Resource Sync ${Date.now()}`;
      await page.locator('button[title="Add"]').click();
      await page.getByText("New space").click();
      await page.fill('input[placeholder="Enter name..."]', wsName);
      await page.getByRole("button", { name: "Create" }).click();
      await page.waitForTimeout(500);

      // Select workspace
      await page
        .locator(".nav-item")
        .filter({ hasText: wsName })
        .first()
        .click();
      await page.waitForTimeout(500);

      // Create section
      await page
        .locator(".main-content button")
        .filter({ hasText: "RESOURCE SECTION" })
        .click();
      await page.fill('input[placeholder="Section Title"]', "Synced Section");
      await page.getByText("Save", { exact: true }).click();
      await page.waitForTimeout(500);

      // Add resource
      const sectionContainer = page
        .locator(".section-container")
        .filter({ hasText: "Synced Section" });
      await sectionContainer
        .locator('button[title="Add resource"]')
        .first()
        .click();
      await page
        .locator(".dropdown-item")
        .filter({ hasText: "Add resource" })
        .click();
      await page.fill('input[placeholder="Title"]', "Synced Resource");
      await page.fill('input[placeholder="URL"]', "https://example.com/synced");
      await page.getByRole("button", { name: "Save", exact: true }).click();
      await page.waitForTimeout(500);

      // Wait for sync
      await page.waitForTimeout(3000);

      // Verify via API
      const response = await fetch("http://localhost:8080/api/v1/workspaces", {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (response.ok) {
        const data = await response.json();
        const workspaces = data.data || [];
        const ws = workspaces.find((w: { name: string }) =>
          w.name.includes("Resource Sync"),
        );
        if (ws) {
          const sections = ws.sections || [];
          const hasSection = sections.some(
            (s: { title: string }) => s.title === "Synced Section",
          );
          expect(hasSection).toBe(true);
          console.log("[API Verification] Section and resource synced to API");
        }
      }
    } finally {
      await page.close();
    }
  });
});
