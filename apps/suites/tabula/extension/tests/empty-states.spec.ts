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

import { test, expect, chromium, BrowserContext } from "@playwright/test";
import path from "path";
import fs from "fs";

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
      // Bazel\'s linux-sandbox mounts a tiny /dev/shm; Chromium crashes at
      // launch without this.
      "--disable-dev-shm-usage",
    ],
  });
});

test.afterAll(async () => {
  await context.close();
});

test.describe("Empty States", () => {
  test("should display empty state when no workspaces exist", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;

    // Seed Auth to bypass login with NO workspaces
    await page.goto(popupUrl);
    await page.evaluate(() => {
      return chrome.storage.local.set({
        tabula_user: {
          id: "test-user",
          name: "Test User",
          email: "test@example.com",
        },
        tabula_access_token: "fake-token",
        tabula_workspaces: [], // No workspaces
        tabula_space_groups: [], // No groups
        // Returning user (already onboarded) so the first-run onboarding modal
        // (#138) does not overlay the empty state under test.
        tabula_settings: {
          autoSuspend: false,
          suspendAfterMinutes: 30,
          syncEnabled: false,
          theme: "auto",
          autoSave: true,
          tabCloseMode: "hybrid",
          onboardingCompleted: true,
        },
      });
    });
    await page.reload();

    // Verify logged in and open dashboard
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    await expect(dashboardBtn).toBeVisible();

    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);
    await dashboardPage.waitForLoadState();

    // Wait for sidebar to load
    await dashboardPage.waitForSelector(".sidebar-nav");

    // Verify empty state is displayed
    await expect(dashboardPage.getByText("No spaces yet")).toBeVisible();
    await expect(
      dashboardPage.getByText("Create your first space to organize tabs"),
    ).toBeVisible();

    // Verify the New Space button in empty state is visible
    const emptyStateButton = dashboardPage.getByTestId(
      "empty-state-new-space-button",
    );
    await expect(emptyStateButton).toBeVisible();

    // Verify icon is present in empty state
    const emptyStateContainer = dashboardPage
      .locator("text=No spaces yet")
      .locator("..");
    await expect(
      emptyStateContainer.locator(".material-icons-outlined"),
    ).toBeVisible();

    await dashboardPage.close();
    await page.close();
  });

  test("should create workspace from empty state CTA", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;

    // Seed Auth to bypass login with NO workspaces
    await page.goto(popupUrl);
    await page.evaluate(() => {
      return chrome.storage.local.set({
        tabula_user: {
          id: "test-user",
          name: "Test User",
          email: "test@example.com",
        },
        tabula_access_token: "fake-token",
        tabula_workspaces: [], // No workspaces
        tabula_space_groups: [], // No groups
        // Returning user (already onboarded) so the first-run onboarding modal
        // (#138) does not overlay the empty state under test.
        tabula_settings: {
          autoSuspend: false,
          suspendAfterMinutes: 30,
          syncEnabled: false,
          theme: "auto",
          autoSave: true,
          tabCloseMode: "hybrid",
          onboardingCompleted: true,
        },
      });
    });
    await page.reload();

    // Open dashboard
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);
    await dashboardPage.waitForLoadState();

    // Wait for empty state
    await dashboardPage.waitForSelector("text=No spaces yet");

    // Click the New Space button in empty state
    const emptyStateButton = dashboardPage.getByTestId(
      "empty-state-new-space-button",
    );
    await emptyStateButton.click();

    // Verify modal opens
    await expect(dashboardPage.getByPlaceholder("Enter name...")).toBeVisible();

    // Create a workspace
    const workspaceName = `First Workspace ${Date.now()}`;
    await dashboardPage.getByPlaceholder("Enter name...").fill(workspaceName);
    await dashboardPage
      .getByRole("button", { name: "Create", exact: true })
      .click();

    // Verify workspace is created and empty state is gone
    await dashboardPage.waitForSelector(
      `.sidebar-nav .nav-item:has-text("${workspaceName}")`,
    );
    await expect(dashboardPage.getByText("No spaces yet")).not.toBeVisible();

    await dashboardPage.close();
    await page.close();
  });

  test("should display empty state in empty space group", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;

    // Create a space group with no workspaces
    const groupId = `group_${Date.now()}`;
    const workspaceId = `ws_${Date.now()}`;

    await page.goto(popupUrl);
    await page.evaluate(
      ({ gId, wsId }) => {
        return chrome.storage.local.set({
          tabula_user: {
            id: "test-user",
            name: "Test User",
            email: "test@example.com",
          },
          tabula_access_token: "fake-token",
          tabula_workspaces: [
            {
              id: wsId,
              name: "Test Workspace",
              position: 0,
              sections: [],
              created: Date.now(),
              updated: Date.now(),
            },
          ],
          tabula_space_groups: [
            {
              id: gId,
              title: "Empty Group",
              position: 0,
              collapsed: false,
              created: Date.now(),
              updated: Date.now(),
            },
          ],
          tabula_active_workspace: wsId,
        });
      },
      { gId: groupId, wsId: workspaceId },
    );
    await page.reload();

    // Open dashboard
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);
    await dashboardPage.waitForLoadState();

    // Wait for sidebar to load
    await dashboardPage.waitForSelector(".sidebar-nav");

    // Verify the empty group is visible
    await expect(dashboardPage.getByText("Empty Group")).toBeVisible();

    // Verify empty state is displayed in the group
    await expect(
      dashboardPage.getByText("Empty section • Drag spaces here"),
    ).toBeVisible();

    // Verify icon is present in empty group state
    const emptyGroupContainer = dashboardPage.locator(
      "text=Empty section • Drag spaces here",
    );
    await expect(
      emptyGroupContainer.locator(".material-icons-outlined"),
    ).toBeVisible();

    await dashboardPage.close();
    await page.close();
  });

  test("should hide empty group state when workspace exists in group", async () => {
    const page = await context.newPage();
    const id = await getExtensionId(context);
    const popupUrl = `chrome-extension://${id}/popup.html`;

    // Create a space group WITH a workspace in it
    const groupId = `group_${Date.now()}`;
    const workspaceId = `ws_${Date.now()}`;

    await page.goto(popupUrl);
    await page.evaluate(
      ({ gId, wsId }) => {
        return chrome.storage.local.set({
          tabula_user: {
            id: "test-user",
            name: "Test User",
            email: "test@example.com",
          },
          tabula_access_token: "fake-token",
          tabula_workspaces: [
            {
              id: wsId,
              name: "Test Workspace",
              position: 0,
              sections: [],
              created: Date.now(),
              updated: Date.now(),
              groupId: gId, // Workspace is already in the group
            },
          ],
          tabula_space_groups: [
            {
              id: gId,
              title: "Test Group",
              position: 0,
              collapsed: false,
              created: Date.now(),
              updated: Date.now(),
            },
          ],
          tabula_active_workspace: wsId,
        });
      },
      { gId: groupId, wsId: workspaceId },
    );
    await page.reload();

    // Open dashboard
    const dashboardBtn = page.getByRole("button", { name: "Dashboard" });
    const [dashboardPage] = await Promise.all([
      context.waitForEvent("page"),
      dashboardBtn.click(),
    ]);
    await dashboardPage.waitForLoadState();

    // Wait for sidebar to load
    await dashboardPage.waitForSelector(".sidebar-nav");

    // Verify empty state is NOT visible (because group has a workspace)
    await expect(
      dashboardPage.getByText("Empty section • Drag spaces here"),
    ).not.toBeVisible();

    // Verify workspace is in the group
    await expect(dashboardPage.getByText("Test Group")).toBeVisible();
    // Check for workspace in sidebar specifically (not the main content header)
    await expect(
      dashboardPage.locator(
        '.sidebar-nav .nav-item:has-text("Test Workspace")',
      ),
    ).toBeVisible();

    await dashboardPage.close();
    await page.close();
  });
});
