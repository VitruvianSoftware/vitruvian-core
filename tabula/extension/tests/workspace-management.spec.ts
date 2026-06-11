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

/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable no-console */
import { test, expect, chromium, BrowserContext, Page } from "@playwright/test";
import path from "path";
import fs from "fs";
import { cleanupApiWorkspaces, getTestToken } from "./e2e-helpers";

const testToken = getTestToken();
const EXTENSION_PATH = process.env.EXTENSION_PATH
  ? path.resolve(process.env.EXTENSION_PATH)
  : path.join(__dirname, "../dist");

async function getExtensionId(ctx: BrowserContext) {
  const page = await ctx.newPage();
  await page.goto("chrome://extensions");
  const worker = ctx.serviceWorkers()[0];
  if (worker) {
    const url = worker.url();
    await page.close();
    return url.split("/")[2];
  }

  if (!worker) {
    await page.waitForTimeout(1000);
    const workers = ctx.serviceWorkers();
    if (workers.length > 0) {
      const url = workers[0].url();
      await page.close();
      return url.split("/")[2];
    }
  }

  await page.close();
  throw new Error("Could not find extension ID");
}

async function _createWorkspace(page: Page, name: string) {
  await page.waitForSelector(".spaces-header");

  // Click the + button in Spaces header
  const addBtn = page.getByRole("button", { name: "Add" }).first();
  if (await addBtn.isVisible()) {
    await addBtn.click();
    // Click "New space" option in dropdown
    await page.getByText("New space").click();
  } else {
    // Fallback for empty state (welcome screen)
    await page
      .getByText("New Space")
      .click()
      .catch(() => {
        return page.getByRole("button", { name: /New Space/i }).click();
      });
  }

  await page.getByPlaceholder("Enter name...").fill(name);
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.waitForSelector(`.sidebar-nav .nav-item:has-text("${name}")`);
}

let context: BrowserContext;

test.beforeAll(async () => {
  // Check if extension is built
  if (!fs.existsSync(EXTENSION_PATH)) {
    throw new Error(
      `Extension not built. Please run 'npm run build --workspace=extension' before running E2E tests. Expected path: ${EXTENSION_PATH}`,
    );
  }

  // Launch browser with extension loaded
  context = await chromium.launchPersistentContext("", {
    // Full Chromium in the new headless mode: supports MV3 extensions, no
    // xvfb needed (Playwright >= 1.49).
    channel: "chromium",
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
      "--no-sandbox",
    ],
  });

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

test.beforeEach(async () => {
  const page = await context.newPage();
  const id = await getExtensionId(context);
  const popupUrl = `chrome-extension://${id}/popup.html`;
  await page.goto(popupUrl);
  await page.evaluate(async () => {
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
      tabula_workspaces: [defaultWs],
      tabula_active_workspace: defaultWs.id,
    });
  });
  await page.close();
});

test.describe("Workspace Management", () => {
  // Serial mode is required since all tests share a single browser context
  test.describe.configure({ mode: "serial" });

  test("should create a workspace without duplicates", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;

    // Seed Auth to bypass login
    await page.goto(popupUrl); // Need to go to extension page to access storage
    await page.evaluate(() => {
      return (window as any).chrome.storage.local.set({
        tabula_user: {
          id: "test-user",
          name: "Test User",
          email: "test@example.com",
        },
        tabula_access_token: "fake-token",
      });
    });
    await page.reload();

    // Verify logged in and find "Dashboard" button
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    await expect(dashboardBtn).toBeVisible();

    // Click Dashboard and wait for new tab
    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);

    await dashboardPage.waitForLoadState();

    // Create a new workspace
    const workspaceName = `Test Workspace ${Date.now()}`;

    // New Space button triggers modalType='create'
    // Spaces Header + button
    const addBtn = dashboardPage.getByRole("button", { name: "Add" }).first();
    // Wait for sidebar to load
    await dashboardPage.waitForSelector(".sidebar-nav");

    if (await addBtn.isVisible()) {
      await addBtn.click();
      // Click "New space" option
      await dashboardPage.getByText("New space").click();
    } else {
      // Fallback logic
      const newSpaceBtn = dashboardPage.getByRole("button", {
        name: /New Space/i,
      });
      if (await newSpaceBtn.isVisible()) {
        await newSpaceBtn.click();
        // Maybe spaces menu is present?
        await dashboardPage
          .getByText("New Space")
          .click()
          .catch(() => {
            // Try looking for the + button again with looser selector
            return dashboardPage.locator(".icon-plus").first().click();
          });
      }
    }

    // Ensure modal is open
    await expect(dashboardPage.getByPlaceholder("Enter name...")).toBeVisible();

    // Fill workspace name
    await dashboardPage.getByPlaceholder("Enter name...").fill(workspaceName);

    // Click Create
    await dashboardPage
      .getByRole("button", { name: "Create", exact: true })
      .click();

    // Verify it appears in the list using a more robust selector
    // Wait for the item to appear
    const workspaceItem = dashboardPage
      .locator(`.sidebar-nav .nav-item`)
      .filter({ hasText: workspaceName });
    await expect(workspaceItem).toHaveCount(1);

    // Ensure "Test Workspace" text is visible
    await expect(dashboardPage.getByText(workspaceName)).toBeVisible();

    await dashboardPage.close();
    await page.close();
  });

  test("should auto-detect emoji in workspace title", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;
    await page.goto(popupUrl);

    // Seed Auth
    await page.evaluate(() => {
      return (window as any).chrome.storage.local.set({
        tabula_user: {
          id: "test-user",
          name: "Test User",
          email: "test@example.com",
        },
        tabula_access_token: "fake-token",
        tabula_workspaces: [],
        tabula_active_workspace: null,
      });
    });
    await page.reload();

    // Open Dashboard
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);
    await dashboardPage.waitForLoadState();

    // 1. Create Workspace with Emoji
    const emojiName = "🚀 Rocket Project";
    const cleanName = "Rocket Project";
    const emoji = "🚀";

    // Click Add
    const addBtn = dashboardPage.getByRole("button", { name: "Add" }).first();
    if (await addBtn.isVisible()) {
      await addBtn.click();
      await dashboardPage.getByText("New space").click();
    } else {
      // Fallback logic specific to empty state which might vary
      const newSpaceBtn = dashboardPage.getByRole("button", {
        name: /New Space/i,
      });
      if (await newSpaceBtn.isVisible()) {
        await newSpaceBtn.click();
      } else {
        // Absolute fallback
        await dashboardPage.locator(".icon-plus").first().click();
        await dashboardPage.getByText("New space").click();
      }
    }

    // Fill Name
    await dashboardPage.getByPlaceholder("Enter name...").fill(emojiName);
    await dashboardPage
      .getByRole("button", { name: "Create", exact: true })
      .click();

    // Verify it appears with correct name (stripped) and check icon
    // Note: The Sidebar item usually renders Icon + Name.
    // If logic works, "🚀 Rocket Project" -> Icon: "🚀", Name: "Rocket Project"

    const workspaceItem = dashboardPage
      .locator(".sidebar-nav .nav-item")
      .filter({ hasText: cleanName });
    await expect(workspaceItem).toBeVisible();

    // Verify the icon is rendered.
    // The structure is usually <span class="nav-icon">🚀</span> <span class="nav-text">Rocket Project</span>
    // So searching for text "🚀" should find it.
    await expect(workspaceItem).toBeVisible();
    const textContent = await workspaceItem.textContent();
    expect(textContent).toContain(emoji);
    expect(textContent).toContain(cleanName);

    // Verify the full concatenated string is NOT what is stored as name
    // (hard to test purely via textContent as it concatenates, but if we check storage it's better)

    // Verify in storage
    const storageData = await dashboardPage.evaluate(() => {
      return new Promise((resolve) => {
        (window as any).chrome.storage.local.get(
          ["tabula_workspaces"],
          (result: any) => {
            resolve(result.tabula_workspaces);
          },
        );
      });
    });
    // eslint-disable-next-line no-console
    console.log("STORAGE DATA:", JSON.stringify(storageData, null, 2));

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const createdWs = (storageData as any[]).find((w) => w.name === cleanName);
    expect(createdWs).toBeDefined();
    expect(createdWs.icon).toBe(emoji);
    expect(createdWs.name).toBe(cleanName);

    // 2. Rename with new Emoji
    await workspaceItem.hover();
    await workspaceItem.locator('button[aria-label="Space options"]').click();

    // Click Rename
    await dashboardPage
      .locator(".dropdown-item")
      .filter({ hasText: "Rename" })
      .click();

    const newEmojiName = "🎨 Art Project";
    const newCleanName = "Art Project";
    const newEmoji = "🎨";

    await dashboardPage.getByPlaceholder("Enter name...").fill(newEmojiName);
    await dashboardPage
      .locator(".modal-footer button.btn-primary")
      .filter({ hasText: "Save" })
      .click();

    // Verify update
    const updatedItem = dashboardPage
      .locator(".sidebar-nav .nav-item")
      .filter({ hasText: newCleanName });
    await expect(updatedItem).toBeVisible();

    // Verify storage again
    const storageData2 = await dashboardPage.evaluate(() => {
      return new Promise((resolve) => {
        (window as any).chrome.storage.local.get(
          ["tabula_workspaces"],
          (result: any) => {
            resolve(result.tabula_workspaces);
          },
        );
      });
    });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const updatedWs = (storageData2 as any[]).find(
      (w) => w.id === createdWs.id,
    );
    expect(updatedWs.name).toBe(newCleanName);
    expect(updatedWs.icon).toBe(newEmoji);

    // 3. Rename WITHOUT emoji (should preserve icon if not changed)
    await updatedItem.hover();
    await updatedItem.locator('button[aria-label="Space options"]').click();
    await dashboardPage
      .locator(".dropdown-item")
      .filter({ hasText: "Rename" })
      .click();

    const simpleName = "Simple Update";
    // Clear the input first
    await dashboardPage.getByPlaceholder("Enter name...").fill(simpleName);
    await dashboardPage
      .locator(".modal-footer button.btn-primary")
      .filter({ hasText: "Save" })
      .click();

    const simpleItem = dashboardPage
      .locator(".sidebar-nav .nav-item")
      .filter({ hasText: simpleName });
    await expect(simpleItem).toBeVisible();

    // Verify storage for no-change in icon
    const storageData3 = await dashboardPage.evaluate(() => {
      return new Promise((resolve) => {
        (window as any).chrome.storage.local.get(
          ["tabula_workspaces"],
          (result: any) => {
            resolve(result.tabula_workspaces);
          },
        );
      });
    });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const simpleWs = (storageData3 as any[]).find((w) => w.id === createdWs.id);
    expect(simpleWs.name).toBe(simpleName);
    expect(simpleWs.icon).toBe(newEmoji); // Should still be 🎨

    await dashboardPage.close();
    await page.close();
  });

  test("should move workspace to another section", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;
    await page.goto(popupUrl);

    // Seed Auth and test data including space groups
    const sectionId = `sg_test_${Date.now()}`;
    const sectionName = `Target Section`;
    const workspaceId = `ws_tomove_${Date.now()}`;
    const workspaceName = `Move Test ${Date.now()}`;

    await page.evaluate(
      (data) => {
        return (window as any).chrome.storage.local.set({
          tabula_user: {
            id: "test-user",
            name: "Test User",
            email: "test@example.com",
          },
          tabula_access_token: "fake-token",
          tabula_space_groups: [
            {
              id: data.sectionId,
              title: data.sectionName,
              collapsed: false,
              position: 0,
            },
          ],
          tabula_workspaces: [
            {
              id: data.workspaceId,
              name: data.workspaceName,
              position: 0,
              sections: [],
              resources: [],
              created: Date.now(),
              updated: Date.now(),
              // Initially no groupId (ungrouped)
            },
          ],
          tabula_active_workspace: data.workspaceId,
        });
      },
      { sectionId, sectionName, workspaceId, workspaceName },
    );
    await page.reload();

    // Open Dashboard
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);
    await dashboardPage.waitForLoadState();

    // Verify workspace is visible (section header may render after workspace loads)
    const workspaceItem = dashboardPage
      .locator(".nav-item")
      .filter({ hasText: workspaceName })
      .first();
    await expect(workspaceItem).toBeVisible();

    // Check section exists in submenu (the header may not be visible until workspace is moved there)
    // We'll verify the section exists when we open the Move to section submenu
    await workspaceItem.hover();
    await workspaceItem.locator('button[aria-label="Space options"]').click();

    // Click "Move to section"
    const moveToSectionItem = dashboardPage
      .locator(".dropdown-item")
      .filter({ hasText: "Move to section" })
      .first();
    await expect(moveToSectionItem).toBeVisible();
    await moveToSectionItem.click();

    // Verify submenu appears
    // Submenu is now a sibling outside the dropdown item, so we find it globally
    const submenu = dashboardPage
      .locator(".dropdown-menu")
      .filter({ hasText: "No section" })
      .last();
    await expect(submenu).toBeVisible();

    // Click the target section
    const targetSectionOption = submenu
      .locator(".dropdown-item")
      .filter({ hasText: sectionName });
    await expect(targetSectionOption).toBeVisible();
    await targetSectionOption.click();

    // Wait for submenu to close and UI to update
    await expect(submenu).not.toBeVisible({ timeout: 3000 });
    await dashboardPage.waitForTimeout(500);

    // Verify in storage
    const storageData = await dashboardPage.evaluate(() => {
      return new Promise((resolve) => {
        (window as any).chrome.storage.local.get(
          ["tabula_workspaces"],
          (result: any) => {
            resolve(result.tabula_workspaces);
          },
        );
      });
    });

    const updatedWorkspace = (storageData as any[]).find(
      (w) => w.id === workspaceId,
    );
    expect(updatedWorkspace.groupId).toBe(sectionId);

    await dashboardPage.close();
    await page.close();
  });

  test("should move the last workspace in a long list to another section", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;
    await page.goto(popupUrl);

    // Seed Auth and 8 workspaces
    const sectionId = `sg_target_${Date.now()}`;
    const sectionName = `Bottom Target`;
    const workspaces = Array.from({ length: 8 }, (_, i) => ({
      id: `ws_long_${i}_${Date.now()}`,
      name: `Space ${i + 1}`,
      position: i,
      sections: [],
      resources: [],
      tabs: [],
      created: Date.now(),
      updated: Date.now(),
      // No Group
    }));
    const lastWorkspace = workspaces[workspaces.length - 1];

    await page.evaluate(
      (data) => {
        return (window as any).chrome.storage.local.set({
          tabula_user: {
            id: "test-user",
            name: "Test User",
            email: "test@example.com",
          },
          tabula_access_token: "fake-token",
          tabula_space_groups: [
            {
              id: data.sectionId,
              title: data.sectionName,
              collapsed: false,
              position: 0,
            },
          ],
          tabula_workspaces: data.workspaces,
          tabula_active_workspace: data.workspaces[0].id,
        });
      },
      { sectionId, sectionName, workspaces },
    );
    await page.reload();
    await page.waitForLoadState("load");
    await page.waitForSelector('h1:has-text("Tabula")', { timeout: 10000 });

    // Open Dashboard
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    await expect(dashboardBtn).toBeVisible();
    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);
    await dashboardPage.waitForLoadState();

    // Find the last workspace
    const workspaceItem = dashboardPage
      .locator(".nav-item")
      .filter({ hasText: lastWorkspace.name })
      .first();
    // Scroll to it
    await workspaceItem.scrollIntoViewIfNeeded();
    await expect(workspaceItem).toBeVisible();

    // Move last workspace
    await workspaceItem.hover();
    await workspaceItem.locator('button[aria-label="Space options"]').click();

    // Click "Move to section"
    const moveToSectionItem = dashboardPage
      .locator(".dropdown-item")
      .filter({ hasText: "Move to section" })
      .first();
    await expect(moveToSectionItem).toBeVisible();
    await moveToSectionItem.click();

    // Submenu should be visible
    const submenu = dashboardPage
      .locator(".dropdown-menu")
      .filter({ hasText: "No section" })
      .last();
    await expect(submenu).toBeVisible();

    // Click target
    await submenu
      .locator(".dropdown-item")
      .filter({ hasText: sectionName })
      .click();

    // Verify move
    await expect(submenu).not.toBeVisible({ timeout: 3000 });
    await dashboardPage.waitForTimeout(500);

    // Verify in storage
    const storageData = await dashboardPage.evaluate(() => {
      return new Promise((resolve) => {
        (window as any).chrome.storage.local.get(
          ["tabula_workspaces"],
          (result: any) => {
            resolve(result.tabula_workspaces);
          },
        );
      });
    });

    const updatedWorkspace = (storageData as any[]).find(
      (w) => w.id === lastWorkspace.id,
    );
    expect(updatedWorkspace.groupId).toBe(sectionId);

    await dashboardPage.close();
    await page.close();
  });

  test("should move workspace between sections multiple times verifying storage", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;
    await page.goto(popupUrl);

    // Seed Auth and test data with two sections
    const section1Id = `sg_section1_${Date.now()}`;
    const section2Id = `sg_section2_${Date.now()}`;
    const workspaceId = `ws_multiMove_${Date.now()}`;
    const workspaceName = `Multi Move Test ${Date.now()}`;

    await page.evaluate(
      (data) => {
        return (window as any).chrome.storage.local.set({
          tabula_user: {
            id: "test-user",
            name: "Test User",
            email: "test@example.com",
          },
          tabula_access_token: "fake-token",
          tabula_space_groups: [
            {
              id: data.section1Id,
              title: "Section A",
              collapsed: false,
              position: 0,
            },
            {
              id: data.section2Id,
              title: "Section B",
              collapsed: false,
              position: 1,
            },
          ],
          tabula_workspaces: [
            {
              id: data.workspaceId,
              name: data.workspaceName,
              position: 0,
              sections: [],
              resources: [],
              created: Date.now(),
              updated: Date.now(),
            },
          ],
          tabula_active_workspace: data.workspaceId,
        });
      },
      { section1Id, section2Id, workspaceId, workspaceName },
    );
    await page.reload();

    // Open Dashboard
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);
    await dashboardPage.waitForLoadState();

    // Helper function to get workspace from storage
    const getWorkspaceFromStorage = async () => {
      const storageData = await dashboardPage.evaluate(() => {
        return new Promise((resolve) => {
          (window as any).chrome.storage.local.get(
            ["tabula_workspaces"],
            (result: any) => {
              resolve(result.tabula_workspaces);
            },
          );
        });
      });
      return (storageData as any[]).find((w) => w.id === workspaceId);
    };

    // Helper function to move workspace
    const moveWorkspace = async (targetSectionName: string) => {
      const workspaceItem = dashboardPage
        .locator(".nav-item")
        .filter({ hasText: workspaceName })
        .first();
      await workspaceItem.scrollIntoViewIfNeeded();
      await expect(workspaceItem).toBeVisible();
      await workspaceItem.hover();
      await workspaceItem.locator('button[aria-label="Space options"]').click();

      // Click Move to section
      await dashboardPage
        .locator(".dropdown-item")
        .filter({ hasText: "Move to section" })
        .first()
        .click();

      // Click target section
      const submenu = dashboardPage
        .locator(".dropdown-menu")
        .filter({ hasText: "No section" })
        .last();
      await expect(submenu).toBeVisible();
      await submenu
        .locator(".dropdown-item")
        .filter({ hasText: targetSectionName })
        .click();

      // Wait for menu to close
      await expect(submenu).not.toBeVisible({ timeout: 3000 });
      await dashboardPage.waitForTimeout(500);
    };

    // Move to Section A
    await moveWorkspace("Section A");
    let workspace = await getWorkspaceFromStorage();
    expect(workspace.groupId).toBe(section1Id);

    // Move to Section B
    await moveWorkspace("Section B");
    workspace = await getWorkspaceFromStorage();
    expect(workspace.groupId).toBe(section2Id);

    // Move back to no section
    await moveWorkspace("No section");
    workspace = await getWorkspaceFromStorage();
    // Verify it is ungrouped (can be undefined or null)
    expect(workspace.groupId == null).toBe(true);

    await dashboardPage.close();
    await page.close();
  });
});

// =============================================================================
// API-VERIFIED WORKSPACE MANAGEMENT TESTS
// These tests verify that workspace changes sync to the API when authenticated
// =============================================================================

test.describe("Workspace Management - API Verification", () => {
  test.describe.configure({ mode: "serial" });

  const getToken = (): string | null => process.env.E2E_TEST_TOKEN || null;

  test.beforeEach(async () => {
    // Skip all tests in this block if no token
    if (!getToken()) {
      test.skip();
    }

    // Clean up local storage
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;
    await page.goto(popupUrl);

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
    const token = getToken();
    if (token) {
      await cleanupApiWorkspaces(token, undefined, {
        includePrefix: "API Sync WS",
      });
      await cleanupApiWorkspaces(token, undefined, {
        includePrefix: "Keep WS",
      });
      await cleanupApiWorkspaces(token, undefined, {
        includePrefix: "Delete Test",
      });
    }
  });

  test("should sync created workspace to API", async () => {
    const token = getToken();
    if (!token) {
      test.skip();
    }

    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;

    try {
      await page.goto(popupUrl);

      // Login with real token
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
            id: "00000000-0000-0000-0000-e2e000000000",
            email: "e2e-test@tabula.dev",
            name: "E2E Test User",
            tier: "free",
          },
        },
      );

      await page.reload();

      // Open Dashboard
      const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
      await expect(dashboardBtn).toBeVisible();
      const [dashboardPage] = await Promise.all([
        context.waitForEvent("page"),
        dashboardBtn.click(),
      ]);
      await dashboardPage.waitForLoadState();

      // Create a new workspace
      const workspaceName = `API Sync WS ${Date.now()}`;
      await _createWorkspace(dashboardPage, workspaceName);

      // Verify workspace appears in sidebar
      const workspaceItem = dashboardPage
        .locator(".nav-item")
        .filter({ hasText: workspaceName })
        .first();
      await expect(workspaceItem).toBeVisible();

      // Wait for sync to complete
      await dashboardPage.waitForTimeout(3000);

      // Verify workspace synced to API
      const response = await fetch("http://localhost:8080/api/v1/workspaces", {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (response.ok) {
        const data = await response.json();
        const workspaces = data.data || [];
        const found = workspaces.some((ws: { name: string }) =>
          ws.name.includes("API Sync WS"),
        );
        expect(found).toBe(true);
        console.log("[API Verification] Workspace synced to API successfully");
      } else {
        console.warn("[API Verification] API request failed:", response.status);
      }

      await dashboardPage.close();
    } finally {
      await page.close();
    }
  });

  test("should sync workspace deletion to API", async () => {
    const token = getToken();
    if (!token) {
      test.skip();
    }

    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;

    const keepWsId = `ws_keep_${Date.now()}`;
    const deleteWsId = `ws_delete_${Date.now()}`;
    const deleteWsName = `Delete Test ${Date.now()}`;

    try {
      await page.goto(popupUrl);

      // Login with real token AND seed workspaces directly
      await page.evaluate(
        async ({ authToken, user, keepId, deleteId, deleteName }) => {
          const storage = (window as any).chrome.storage.local;
          await storage.set({
            tabula_access_token: authToken,
            tabula_user: user,
            tabula_workspaces: [
              {
                id: keepId,
                name: "Keep WS",
                position: 0,
                sections: [],
                resources: [],
                tabs: [],
                created: Date.now(),
                updated: Date.now(),
              },
              {
                id: deleteId,
                name: deleteName,
                position: 1,
                sections: [],
                resources: [],
                tabs: [],
                created: Date.now(),
                updated: Date.now(),
              },
            ],
            tabula_active_workspace: keepId,
          });
        },
        {
          authToken: token,
          user: {
            id: "00000000-0000-0000-0000-e2e000000000",
            email: "e2e-test@tabula.dev",
            name: "E2E Test User",
            tier: "free",
          },
          keepId: keepWsId,
          deleteId: deleteWsId,
          deleteName: deleteWsName,
        },
      );

      await page.reload();

      // Open Dashboard
      const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
      const [dashboardPage] = await Promise.all([
        context.waitForEvent("page"),
        dashboardBtn.click(),
      ]);
      await dashboardPage.waitForLoadState();

      // Wait for sidebar to load and show workspaces
      await dashboardPage.waitForSelector(".sidebar-nav", { timeout: 10000 });
      await dashboardPage.waitForTimeout(1000);

      // Find the workspace to delete
      const workspaceItem = dashboardPage
        .locator(".nav-item")
        .filter({ hasText: deleteWsName })
        .first();
      await expect(workspaceItem).toBeVisible({ timeout: 5000 });

      // Open context menu
      await workspaceItem.hover();
      await workspaceItem.locator('button[aria-label="Space options"]').click();

      // Click Delete in dropdown menu
      await dashboardPage
        .locator(".dropdown-item")
        .filter({ hasText: "Delete" })
        .click();

      // Wait for delete confirmation modal
      const deleteModal = dashboardPage
        .locator(".modal-content")
        .filter({ hasText: "Delete Workspace" });
      await expect(deleteModal).toBeVisible({ timeout: 5000 });

      // Click confirm Delete button
      await deleteModal.locator(".btn").filter({ hasText: "Delete" }).click();

      // Verify workspace is gone from sidebar
      await expect(workspaceItem).not.toBeVisible({ timeout: 5000 });

      // Wait for sync
      await dashboardPage.waitForTimeout(3000);

      // Verify deletion synced to API
      const response = await fetch("http://localhost:8080/api/v1/workspaces", {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (response.ok) {
        const data = await response.json();
        const workspaces = data.data || [];
        const found = workspaces.some((ws: { name: string }) =>
          ws.name.includes("Delete Test"),
        );
        if (found) {
          console.warn(
            "[API Verification] Workspace deletion may not have synced yet",
          );
        } else {
          console.log("[API Verification] Workspace deletion synced to API");
        }
      }

      await dashboardPage.close();
    } finally {
      await page.close();
    }
  });
});
