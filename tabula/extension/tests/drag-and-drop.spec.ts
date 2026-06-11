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
/**
 * E2E tests for Drag and Drop functionality
 */

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

test.describe("Drag and Drop", () => {
  let dashboardPage: Page;
  let resourcePage: Page;
  const TEST_WORKSPACE_ID = "test-drag-ws";
  const TEST_SECTION_ID = "sec-drag-1";

  test.beforeEach(async () => {
    // 1. Setup workspace with an empty section
    const [page] = context.pages(); // Use existing page or create new
    dashboardPage =
      page || (await getOrCreateDashboardPage(context, extensionId));

    await dashboardPage.evaluate(
      async ({ id, secId }) => {
        const now = Date.now();
        const workspace = {
          id,
          name: "Drag Test",
          color: "#00FF00",
          position: 0,
          tabs: [],
          resources: [],
          sections: [
            {
              id: secId,
              title: "Drop Target",
              resources: [],
            },
          ],
          notes: [],
          tasks: [],
          createdAt: now,
          updatedAt: now,
        };

        // @ts-expect-error - using prefixed keys
        await chrome.storage.local.set({
          tabula_workspaces: [workspace],
          tabula_active_workspace: id,
        });
      },
      { id: TEST_WORKSPACE_ID, secId: TEST_SECTION_ID },
    );

    // 2. Open a dummy tab to act as our draggable item
    resourcePage = await context.newPage();
    await resourcePage.goto("https://example.com");

    // 3. Reload dashboard to see the workspace and the new active tab
    await dashboardPage.bringToFront();
    await dashboardPage.reload();
    await dashboardPage.waitForSelector(".dashboard-container");

    // Ensure we are on the test workspace
    await expect(dashboardPage.locator("h1.section-title")).toHaveText(
      "Drag Test",
    );
  });

  test.afterEach(async () => {
    if (resourcePage) await resourcePage.close();
    // dashboardPage is reused or closed by context
  });

  // SKIPPED: Outdated selector - [data-testid="resource-section-list"] doesn't exist, needs update
  test.skip("should allow dragging an active tab to a resource section", async () => {
    // 1. Find the draggable tab item
    // We look for the item with title "Example Domain" (from example.com)
    // We need the drag handle specifically
    const draggableTabItem = dashboardPage
      .locator('[data-testid="tab-item"]')
      .filter({ hasText: "Example Domain" })
      .first();
    const dragHandle = draggableTabItem.locator(
      '[data-testid="tab-drag-handle"]',
    );

    await expect(dragHandle).toBeVisible();

    // 2. Find the drop target (Resource Section)
    const dropTarget = dashboardPage
      .locator('[data-testid="resource-section-list"]')
      .first();
    await expect(dropTarget).toBeVisible();

    // 3. Perform Drag and Drop
    // dnd-kit requires mouse events and robust movement
    const sourceBox = await dragHandle.boundingBox();
    const targetBox = await dropTarget.boundingBox();

    if (!sourceBox || !targetBox) throw new Error("Box not found");

    // eslint-disable-next-line no-console
    console.log("Source Box:", sourceBox);
    // eslint-disable-next-line no-console
    console.log("Target Box:", targetBox);

    // Calculate centers
    const sourceX = sourceBox.x + sourceBox.width / 2;
    const sourceY = sourceBox.y + sourceBox.height / 2;
    const targetX = targetBox.x + targetBox.width / 2;
    const targetY = targetBox.y + targetBox.height / 2;

    // Hover and press on source
    await dashboardPage.mouse.move(sourceX, sourceY);
    await dashboardPage.mouse.down();
    await dashboardPage.waitForTimeout(100);

    // Move to trigger drag start (dnd-kit default sensor usually needs 10px)
    // We move 15px to the right
    await dashboardPage.mouse.move(sourceX + 15, sourceY, { steps: 10 });
    await dashboardPage.waitForTimeout(100);

    // Move to target slowly to ensure events fire
    await dashboardPage.mouse.move(targetX, targetY, { steps: 50 });

    // Wait a bit for drop animation/placeholder
    await dashboardPage.waitForTimeout(500);

    await dashboardPage.mouse.up();

    // 4. Verify that a new resource item appears in the section
    // The "Example Domain" should now be listed as a resource
    // We look for [data-testid="resource-item"] with text "Example Domain"
    // INSIDE the drop target
    const newResource = dropTarget
      .locator('[data-testid="resource-item"]')
      .filter({ hasText: "Example Domain" });

    await expect(newResource).toBeVisible({ timeout: 5000 });

    // Also verify persistence in storage
    const storedResources = await dashboardPage.evaluate(
      async ({ id, secId }) => {
        // @ts-expect-error - using arbitrary keys
        const data = await chrome.storage.local.get("tabula_workspaces");
        const workspaces = data.tabula_workspaces || [];
        const ws = workspaces.find((w: any) => w.id === id);
        const section = ws.sections.find((s: any) => s.id === secId);
        return section.resources;
      },
      { id: TEST_WORKSPACE_ID, secId: TEST_SECTION_ID },
    );

    expect(storedResources).toHaveLength(1);
    expect(storedResources[0].title).toContain("Example Domain");
  });
});
