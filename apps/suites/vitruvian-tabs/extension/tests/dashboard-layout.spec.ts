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
 * E2E tests for Dashboard Layout
 *
 * Verifies that the dashboard layout remains stable (50/50 split)
 * even when long content is present.
 */

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

test.describe("Dashboard Layout", () => {
  let page: Page;

  test.beforeEach(async () => {
    page = await getOrCreateDashboardPage(context, extensionId);
    await page.waitForSelector(".dashboard-container");
  });

  test.afterEach(async () => {
    await page.close();
  });

  test("should maintain 50/50 column split with long URLs", async () => {
    // 1. Create a dummy resource with a very long URL
    const longUrl = `https://example.com/${"very-long-url-".repeat(50)}`;
    const title = "Long URL Resource";

    // Evaluate Javascript to directly inject a workspace with a long resource into the store/storage
    const TEST_WORKSPACE_ID = "test-layout-ws";

    // eslint-disable-next-line no-console
    console.log("Injecting test workspace...");

    await page.evaluate(
      async ({ id, longUrl: url, title: resourceTitle }) => {
        const now = Date.now();
        const workspace = {
          id,
          name: "Layout Test",
          color: "#FF0000",
          position: 0,
          tabs: [],
          resources: [], // Root resources
          sections: [
            {
              id: "sec-1",
              title: "Test Section",
              resources: [
                {
                  id: "res-1",
                  title: resourceTitle,
                  url,
                  faviconUrl: "",
                  createdAt: now,
                },
              ],
            },
          ],
          notes: [],
          tasks: [],
          createdAt: now,
          updatedAt: now,
        };

        await chrome.storage.local.set({
          vitruvian_tabs_workspaces: [workspace],
          vitruvian_tabs_active_workspace: id,
        });
      },
      { id: TEST_WORKSPACE_ID, longUrl, title },
    );

    // eslint-disable-next-line no-console
    console.log("Reloading page...");

    // Reload page to pick up storage changes
    await page.reload();
    await page.waitForSelector(".dashboard-container");

    // eslint-disable-next-line no-console
    console.log("Verifying workspace loaded...");

    // Ensure we are viewing the test workspace
    await expect(page.locator("h1.section-title")).toHaveText("Layout Test");

    // 2. Measure the columns
    const columns = page.locator(".content-grid > div"); // Direct children of grid
    await expect(columns).toHaveCount(2);

    const leftCol = columns.first();
    const rightCol = columns.last();

    const leftBox = await leftCol.boundingBox();
    const rightBox = await rightCol.boundingBox();

    expect(leftBox).not.toBeNull();
    expect(rightBox).not.toBeNull();

    if (leftBox && rightBox) {
      // 3. Verify widths are approximately equal (allow small sub-pixel differences)
      const diff = Math.abs(leftBox.width - rightBox.width);
      // eslint-disable-next-line no-console
      console.log(
        `Left width: ${leftBox.width}, Right width: ${rightBox.width}`,
      );
      expect(diff).toBeLessThan(2); // Pixel difference tolerance
    }

    // 5. Verify text truncation styling
    // Locate the resource item text container
    // Hierarchy: .list-item -> .item-content -> .item-subtitle (URL)
    const itemTitle = page.locator(".item-subtitle").first(); // URL is usually in subtitle

    // Check computed style for text-overflow
    const overflow = await itemTitle.evaluate((el) => {
      const style = window.getComputedStyle(el);
      return style.textOverflow;
    });
    expect(overflow).toBe("ellipsis");
  });
});
