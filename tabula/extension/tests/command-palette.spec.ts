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
import { test, expect, chromium, BrowserContext } from "@playwright/test";
import path from "path";
import fs from "fs";
import { getOrCreateDashboardPage } from "./e2e-helpers";

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

/**
 * Command Palette E2E Tests
 * Tests the Global Search feature (Cmd+K)
 */
test.describe("Command Palette", () => {
  test("should open and close Command Palette with Cmd+K", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Wait for dashboard to load
    await expect(page.locator(".sidebar")).toBeVisible();

    // Command palette should not be visible initially
    await expect(page.locator(".command-palette-overlay")).not.toBeVisible();

    // Ensure focus
    await page.click(".sidebar");

    // Use Control+K
    await page.keyboard.press("Control+k");

    // Command palette should be visible
    await expect(page.locator(".command-palette-overlay")).toBeVisible();
    await expect(page.locator(".command-palette-input")).toBeVisible();

    // Input should be focused
    await expect(page.locator(".command-palette-input")).toBeFocused();

    // Press Escape to close
    await page.keyboard.press("Escape");

    // Command palette should be hidden
    await expect(page.locator(".command-palette-overlay")).not.toBeVisible();

    await page.close();
  });

  test("should open Command Palette when clicking the header search bar", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a workspace to ensure header (and search bar) is visible
    const wsName = `Search Bar Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    // Verify search bar is visible
    const searchBar = page.locator(".search-bar");
    await expect(searchBar).toBeVisible();

    // Click it
    await searchBar.click();

    // Verify command palette opens and input is focused
    await expect(page.locator(".command-palette-overlay")).toBeVisible();
    await expect(page.locator(".command-palette-input")).toBeFocused();

    // Close it
    await page.keyboard.press("Escape");
    await expect(page.locator(".command-palette-overlay")).not.toBeVisible();

    await page.close();
  });

  test("should search and filter workspaces", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create test workspaces
    const workspace1 = `Search Test Alpha ${Date.now()}`;
    const workspace2 = `Search Test Beta ${Date.now()}`;

    // Create first workspace
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', workspace1);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: workspace1 }).first(),
    ).toBeVisible();

    // Create second workspace
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', workspace2);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: workspace2 }).first(),
    ).toBeVisible();

    // Open command palette
    await page.click(".sidebar");
    await page.keyboard.press("Control+k");

    await expect(page.locator(".command-palette-overlay")).toBeVisible();

    // Search for "Alpha"
    await page.fill(".command-palette-input", "Alpha");

    // Should show workspace1 but not workspace2
    await expect(
      page
        .locator(".command-palette-result")
        .filter({ hasText: workspace1 })
        .first(),
    ).toBeVisible();
    await expect(
      page.locator(".command-palette-result").filter({ hasText: workspace2 }),
    ).not.toBeVisible();

    // Clear search and type "Beta"
    await page.fill(".command-palette-input", "Beta");

    // Should show workspace2 but not workspace1
    await expect(
      page
        .locator(".command-palette-result")
        .filter({ hasText: workspace2 })
        .first(),
    ).toBeVisible();
    await expect(
      page.locator(".command-palette-result").filter({ hasText: workspace1 }),
    ).not.toBeVisible();

    await page.keyboard.press("Escape");
    await page.close();
  });

  test("should navigate with keyboard arrows and select with Enter", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a test workspace
    const wsName = `Keyboard Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    // Create a second workspace so we have results to navigate
    const wsName2 = `Keyboard Test 2 ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName2);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName2 }).first(),
    ).toBeVisible();

    // Open command palette
    await page.click(".sidebar");
    await page.keyboard.press("Control+k");

    await expect(page.locator(".command-palette-overlay")).toBeVisible();

    // First result should be selected by default
    const firstResult = page.locator(".command-palette-result").first();
    await expect(firstResult).toHaveClass(/selected/);

    // Press arrow down
    await page.keyboard.press("ArrowDown");

    // Second result should be selected
    const secondResult = page.locator(".command-palette-result").nth(1);
    await expect(secondResult).toHaveClass(/selected/);

    // Press arrow up
    await page.keyboard.press("ArrowUp");

    // First result should be selected again
    await expect(firstResult).toHaveClass(/selected/);

    await page.keyboard.press("Escape");
    await page.close();
  });

  test("should switch workspace when selecting from search", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create two test workspaces
    const workspace1 = `Switch Test 1 ${Date.now()}`;
    const workspace2 = `Switch Test 2 ${Date.now()}`;

    // Create first workspace
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', workspace1);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: workspace1 }).first(),
    ).toBeVisible();

    // Create second workspace
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', workspace2);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: workspace2 }).first(),
    ).toBeVisible();

    // workspace2 should be active (last created)
    // Note: App doesn't auto-switch if a workspace is already active, so we manually switch
    await page.locator(".nav-item").filter({ hasText: workspace2 }).click();
    await expect(
      page.locator(".nav-item.active").filter({ hasText: workspace2 }),
    ).toBeVisible();
    // A workspace switch holds a brief "switching" guard (~500ms) to let tab
    // events settle; wait it out so the subsequent command-palette switch
    // isn't coalesced away.
    await page.waitForTimeout(700);

    // Open command palette and search for workspace1
    await page.keyboard.press("Control+k");

    await expect(page.locator(".command-palette-overlay")).toBeVisible();
    await page.fill(".command-palette-input", workspace1);

    // Click on the workspace1 result
    await page
      .locator(".command-palette-result")
      .filter({ hasText: workspace1 })
      .first()
      .click();

    // Command palette should close
    await expect(page.locator(".command-palette-overlay")).not.toBeVisible();

    // workspace1 should now be active
    await expect(
      page.locator(".nav-item.active").filter({ hasText: workspace1 }),
    ).toBeVisible();

    await page.close();
  });

  test("should display empty state for no results", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Open command palette
    await page.click(".sidebar");
    await page.keyboard.press("Control+k");

    await expect(page.locator(".command-palette-overlay")).toBeVisible();

    // Search for something that doesn't exist
    await page.fill(".command-palette-input", "xyznonexistent12345");

    // Should show empty state
    await expect(page.locator(".command-palette-empty")).toBeVisible();
    await expect(page.getByText("No results found")).toBeVisible();

    await page.keyboard.press("Escape");
    await page.close();
  });

  test("should close when clicking on overlay", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Open command palette
    await page.click(".sidebar");
    await page.keyboard.press("Control+k");

    await expect(page.locator(".command-palette-overlay")).toBeVisible();

    // Click on the overlay (not the content)
    await page
      .locator(".command-palette-overlay")
      .click({ position: { x: 10, y: 10 } });

    // Command palette should close
    await expect(page.locator(".command-palette-overlay")).not.toBeVisible();

    await page.close();
  });

  test("should search for resources and tabs", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a workspace with resources
    const wsName = `Resource Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    // Switch to Resources tab
    await page.locator(".tab-item").filter({ hasText: "Resources" }).click();

    // Add a resource
    await page.locator('button[title="Add resource"]').first().click();
    await page.waitForTimeout(500); // Wait for dropdown animation
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.waitForTimeout(500); // Wait for state update/render crash prevention

    // Wait for the form to appear
    await expect(page.locator('input[placeholder="Title"]')).toBeVisible();

    await page.fill('input[placeholder="Title"]', "GitHub Documentation");
    await page.fill('input[placeholder="URL"]', "https://docs.github.com");
    await page.getByRole("button", { name: "Save", exact: true }).click();

    // Wait for resource to appear
    await expect(
      page.locator(".list-item").filter({ hasText: "GitHub Documentation" }),
    ).toBeVisible();

    // Open command palette
    await page.click(".sidebar");
    await page.keyboard.press("Control+k");

    await expect(page.locator(".command-palette-overlay")).toBeVisible();

    // Search for the resource
    await page.fill(".command-palette-input", "GitHub Documentation");

    // Should find the resource
    await expect(
      page
        .locator(".command-palette-result")
        .filter({ hasText: "GitHub Documentation" }),
    ).toBeVisible();

    // Should show the resource type badge
    await expect(
      page
        .locator(".command-palette-result")
        .filter({ hasText: "GitHub Documentation" })
        .locator(".result-type"),
    ).toHaveText("resource");

    await page.keyboard.press("Escape");
    await page.close();
  });

  test("should filter results by type", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a workspace and add resources
    const wsName = `Filter Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    // Add a resource
    await page.locator(".tab-item").filter({ hasText: "Resources" }).click();
    await page.locator('button[title="Add resource"]').first().click();
    await page.waitForTimeout(500);
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.waitForTimeout(500);

    await expect(page.locator('input[placeholder="Title"]')).toBeVisible();
    await page.fill('input[placeholder="Title"]', "Test Resource");
    await page.fill('input[placeholder="URL"]', "https://example.com");
    await page.getByRole("button", { name: "Save", exact: true }).click();

    await expect(
      page.locator(".list-item").filter({ hasText: "Test Resource" }),
    ).toBeVisible();

    // Open command palette
    await page.click(".sidebar");
    await page.keyboard.press("Control+k");
    await expect(page.locator(".command-palette-overlay")).toBeVisible();

    // Filter should show all results initially
    await expect(page.locator(".filter-button.active")).toHaveText("All");

    // Click workspace filter
    await page
      .locator(".filter-button")
      .filter({ hasText: "Workspace" })
      .click();
    await expect(page.locator(".filter-button.active")).toHaveText("Workspace");

    // Should only show workspace results
    const results = page.locator(".command-palette-result");
    const count = await results.count();
    // eslint-disable-next-line no-plusplus
    for (let i = 0; i < count; i++) {
      // eslint-disable-next-line no-await-in-loop
      await expect(results.nth(i).locator(".result-type")).toHaveText(
        "workspace",
      );
    }

    // Click resource filter
    await page
      .locator(".filter-button")
      .filter({ hasText: "Resource" })
      .click();
    await expect(page.locator(".filter-button.active")).toHaveText("Resource");

    // Should only show resource results
    const resourceResults = page.locator(".command-palette-result");
    const resourceCount = await resourceResults.count();
    // eslint-disable-next-line no-plusplus
    for (let i = 0; i < resourceCount; i++) {
      // eslint-disable-next-line no-await-in-loop
      await expect(resourceResults.nth(i).locator(".result-type")).toHaveText(
        "resource",
      );
    }

    await page.keyboard.press("Escape");
    await page.close();
  });

  test("should show and use search history", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Create a workspace
    const wsName = `History Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await expect(
      page.locator(".nav-item").filter({ hasText: wsName }).first(),
    ).toBeVisible();

    // Open command palette and search
    await page.click(".sidebar");
    await page.keyboard.press("Control+k");
    await expect(page.locator(".command-palette-overlay")).toBeVisible();

    // Type a search query
    await page.fill(".command-palette-input", "History Test");

    // Select a result
    await page.keyboard.press("Enter");

    // Command palette should close
    await expect(page.locator(".command-palette-overlay")).not.toBeVisible();

    // Open command palette again
    await page.keyboard.press("Control+k");
    await expect(page.locator(".command-palette-overlay")).toBeVisible();

    // Should show search history
    await expect(page.locator(".search-history")).toBeVisible();
    await expect(page.locator(".search-history-header")).toHaveText(
      "Recent Searches",
    );
    await expect(
      page.locator(".search-history-item").filter({ hasText: "History Test" }),
    ).toBeVisible();

    // Click on a history item
    await page
      .locator(".search-history-item")
      .filter({ hasText: "History Test" })
      .click();

    // Input should be filled with the history item
    await expect(page.locator(".command-palette-input")).toHaveValue(
      "History Test",
    );

    await page.keyboard.press("Escape");
    await page.close();
  });
});
