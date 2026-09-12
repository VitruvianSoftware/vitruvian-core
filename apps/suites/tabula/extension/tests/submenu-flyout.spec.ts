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
import {
  test,
  expect,
  chromium,
  BrowserContext,
  Page,
  Locator,
} from "@playwright/test";
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
      `Extension not built. Run 'npm run build' first. Expected path: ${EXTENSION_PATH}`,
    );
  }
  context = await chromium.launchPersistentContext("", {
    channel: "chromium",
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
      "--no-sandbox",
      "--disable-dev-shm-usage",
    ],
  });
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

/**
 * Regression tests for the workspace menu submenus (Change color / Move to
 * section). These used to render as `position: fixed` nested inside the
 * `backdrop-filter` `.dropdown-menu`, so the hardcoded `left: 284px` resolved
 * against the menu (not the viewport) and the sidebar's overflow clipped them —
 * the flyout never appeared. They now portal to <body> and open beside the row.
 *
 * `toBeVisible()` alone is not enough (a clipped/off-screen element can still
 * report visible), so each test also asserts the flyout's bounding box sits
 * flush beside the menu and fully inside the viewport.
 */
test.describe("Workspace submenu flyouts", () => {
  async function openWorkspaceMenu(page: Page): Promise<Locator> {
    const wsName = `Submenu Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();

    const wsItem = page
      .locator(".nav-item")
      .filter({ hasText: wsName })
      .first();
    await expect(wsItem).toBeVisible();
    await wsItem.hover();
    await wsItem.locator('button[aria-label="Space options"]').click();

    // The parent menu is the dropdown containing "Change color".
    const menu = page.locator(".dropdown-menu", { hasText: "Change color" });
    await expect(menu).toBeVisible();
    return menu;
  }

  async function assertFlyoutBesideMenu(
    page: Page,
    menu: Locator,
    flyout: Locator,
  ) {
    await expect(flyout).toBeVisible();
    const menuBox = await menu.boundingBox();
    const flyBox = await flyout.boundingBox();
    const viewport = page.viewportSize();
    expect(menuBox).not.toBeNull();
    expect(flyBox).not.toBeNull();
    if (!menuBox || !flyBox || !viewport) return;

    // Opens flush beside the menu's right edge (not 284px off to the side).
    expect(flyBox.x).toBeGreaterThanOrEqual(menuBox.x + menuBox.width - 16);
    expect(flyBox.x).toBeLessThanOrEqual(menuBox.x + menuBox.width + 16);
    // Fully on screen (the bug pushed it past the sidebar / viewport edge).
    expect(flyBox.x).toBeGreaterThanOrEqual(0);
    expect(flyBox.x + flyBox.width).toBeLessThanOrEqual(viewport.width + 1);
    expect(flyBox.y).toBeGreaterThanOrEqual(0);
  }

  test("Change color submenu opens beside the menu", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const menu = await openWorkspaceMenu(page);

    await menu.getByText("Change color").click();
    const flyout = page.getByTestId("submenu-flyout");
    await expect(flyout.getByText("Red")).toBeVisible();
    await assertFlyoutBesideMenu(page, menu, flyout);

    await page.close();
  });

  test("Move to section submenu opens beside the menu", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const menu = await openWorkspaceMenu(page);

    await menu.getByText("Move to section").click();
    const flyout = page.getByTestId("submenu-flyout");
    await expect(flyout.getByText("No section")).toBeVisible();
    await assertFlyoutBesideMenu(page, menu, flyout);

    await page.close();
  });
});
