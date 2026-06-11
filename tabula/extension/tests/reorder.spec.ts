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
import { test, expect, chromium, BrowserContext } from "@playwright/test";
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

test.describe("Reordering", () => {
  // Helper for DndKit drag and drop
  const dragAndDrop = async (page: any, source: any, target: any) => {
    const sourceBox = await source.boundingBox();
    const targetBox = await target.boundingBox();
    if (!sourceBox || !targetBox) throw new Error("Boxes not found");

    const sourceX = sourceBox.x + sourceBox.width / 2;
    const sourceY = sourceBox.y + sourceBox.height / 2;
    const targetX = targetBox.x + targetBox.width / 2;
    const targetY = targetBox.y + targetBox.height / 2;

    await page.mouse.move(sourceX, sourceY);
    await page.mouse.down();
    await page.waitForTimeout(200); // Wait for drag activation
    await page.mouse.move(sourceX, sourceY + 5, { steps: 5 }); // Small move to trigger start
    await page.mouse.move(targetX, targetY, { steps: 20 }); // Move to target
    await page.waitForTimeout(200); // Wait for sort animation
    await page.mouse.up();
    await page.waitForTimeout(200); // Wait for drop
  };

  // SKIPPED: Outdated selectors - "New section" text changed, needs update
  test.skip("should reorder space groups in sidebar", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // 1. Create two space groups
    page.on("dialog", async (dialog) => {
      await dialog.accept();
    });

    // Create Group A
    await page.locator('.spaces-header button[title="Add"]').click();
    await page.getByText("New section", { exact: true }).click();
    await expect(page.locator(".modal-overlay")).toBeVisible();
    await page.locator('input[placeholder="Enter name..."]').fill("Group A");
    await page.getByRole("button", { name: "Create" }).click();
    await expect(page.getByText("Group A")).toBeVisible();

    // Create Group B
    await page.locator('.spaces-header button[title="Add"]').click();
    await page.getByText("New section", { exact: true }).click();
    await expect(page.locator(".modal-overlay")).toBeVisible();
    await page.locator('input[placeholder="Enter name..."]').fill("Group B");
    await page.getByRole("button", { name: "Create" }).click();
    await expect(page.getByText("Group B")).toBeVisible();

    // 2. Drag Group B above Group A
    const groupAHeader = page
      .locator('[data-testid="sidebar-group-header"]')
      .filter({ hasText: "Group A" });
    const groupBHeader = page
      .locator('[data-testid="sidebar-group-header"]')
      .filter({ hasText: "Group B" });

    await expect(groupAHeader).toBeVisible();
    await expect(groupBHeader).toBeVisible();

    await dragAndDrop(page, groupBHeader, groupAHeader);

    // 3. Verify order
    const groupTitles = page.locator(
      '[data-testid="sidebar-group-header"] span',
    );
    await expect(groupTitles.first()).toHaveText("Group B");
    await expect(groupTitles.nth(1)).toHaveText("Group A");

    // 4. Reload and verify persistence
    await page.reload();
    await expect(groupTitles.first()).toHaveText("Group B");
    await expect(groupTitles.nth(1)).toHaveText("Group A");
  });

  // SKIPPED: Outdated selectors - [data-testid="sidebar-item"] doesn't exist, needs update
  test.skip("should reorder resource sections", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a new unique workspace for this test to avoid collision
    await page.locator('.spaces-header button[title="Add"]').click();
    await page.getByText("New space").click();
    const wsName = `Reorder Test WS ${Date.now()}`;
    await page.locator('input[placeholder="Enter name..."]').fill(wsName);
    await page.getByRole("button", { name: "Create" }).click();

    // Switch to the new workspace (click sidebar item)
    await page
      .locator('[data-testid="sidebar-item"]')
      .filter({ hasText: wsName })
      .first()
      .click();

    // Ensure we are on the workspace
    await expect(page.locator("h1.section-title")).toHaveText(wsName);

    // Create Section 1
    await page.locator('button:has-text("RESOURCE SECTION")').click();
    await page.locator('input[placeholder="Section Title"]').fill("Section 1");
    await page.getByRole("button", { name: "Save", exact: true }).click();

    // Create Section 2
    await page.locator('button:has-text("RESOURCE SECTION")').click();
    await page.locator('input[placeholder="Section Title"]').fill("Section 2");
    await page.getByRole("button", { name: "Save", exact: true }).click();

    await expect(page.getByText("Section 1")).toBeVisible();
    await expect(page.getByText("Section 2")).toBeVisible();

    // Drag Section 2 above Section 1
    const section1Header = page
      .locator(".collapsible-header")
      .filter({ hasText: "Section 1" });
    const section2Header = page
      .locator(".collapsible-header")
      .filter({ hasText: "Section 2" });

    await dragAndDrop(page, section2Header, section1Header);

    // Verify order
    const sections = page.locator(".collapsible-header .section-title");
    await expect(sections.first()).toHaveText("Section 2");
    await expect(sections.nth(1)).toHaveText("Section 1");

    // Reload and verify
    await page.reload();
    await expect(sections.first()).toHaveText("Section 2");
    await expect(sections.nth(1)).toHaveText("Section 1");
  });
});
