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
/* eslint-disable no-console */
/**
 * E2E tests for sync edge cases
 *
 * These tests verify data integrity during edge case scenarios:
 * 1. Rapid workspace switching with resources
 * 2. Section/resource persistence after operations
 * 3. Concurrent operations don't corrupt data
 *
 * Based on patterns from sync-journeys.spec.ts for reliable selectors
 */
import { test, expect, chromium, BrowserContext } from "@playwright/test";
import path from "path";
import fs from "fs";
import {
  createWorkspace,
  cleanupApiWorkspaces,
  getTestToken,
  getOrCreateDashboardPage,
} from "./e2e-helpers";

const EXTENSION_PATH = process.env.EXTENSION_PATH
  ? path.resolve(process.env.EXTENSION_PATH)
  : path.join(__dirname, "../dist");

// Shared context and extension ID
let context: BrowserContext;
let extensionId: string;
const testToken = getTestToken();

test.beforeAll(async () => {
  // Verify extension is built
  if (!fs.existsSync(EXTENSION_PATH)) {
    throw new Error(
      `Extension not built. Run 'npm run build' first. Expected path: ${EXTENSION_PATH}`,
    );
  }

  // Launch browser with extension
  context = await chromium.launchPersistentContext("", {
    // Full Chromium in the new headless mode: supports MV3 extensions, no
    // xvfb needed (Playwright >= 1.49).
    channel: "chromium",
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
      "--no-sandbox",
      // Bazel's linux-sandbox mounts a tiny /dev/shm; Chromium crashes at
      // launch without this.
      "--disable-dev-shm-usage",
    ],
  });

  // Wait for extension to load and get its ID
  let background = context.serviceWorkers()[0];
  if (!background) {
    background = await context.waitForEvent("serviceworker");
  }
  // eslint-disable-next-line prefer-destructuring
  extensionId = background.url().split("/")[2];

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

test.describe("Sync Edge Cases - Data Integrity", () => {
  test.describe.configure({ mode: "serial" });

  // Clean up test workspaces before each test
  test.beforeEach(async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    await page.waitForLoadState("domcontentloaded");

    // Clean up existing test workspaces
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      await storage.set({
        tabula_workspaces: [],
        tabula_active_workspace: null,
        // Onboarded user so the first-run onboarding modal (#138) does not
        // overlay the dashboard under test.
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
    await page.waitForTimeout(500);
    await page.close();
  });

  test("should preserve resources during rapid workspace switches", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));
    await page.waitForLoadState("domcontentloaded");

    // Create workspace with resources
    const wsName = `RapidSwitch Test ${Date.now()}`;
    await createWorkspace(page, wsName);

    // Click on it to select it and wait for switch to complete
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();
    // Wait for workspace to be active (verify heading shows the workspace name)
    await expect(page.locator("h1.section-title").first()).toBeVisible({
      timeout: 5000,
    });
    await page.waitForTimeout(500);

    // Add a resource section (using sync-journeys pattern)
    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    await page
      .locator('input[placeholder="Section Title"]')
      .fill("Test Section");
    await page.getByText("Save", { exact: true }).click();
    await expect(
      page.locator(".section-title").filter({ hasText: "Test Section" }),
    ).toBeVisible();
    await page.waitForTimeout(500);

    // Add a resource to the section (using sync-journeys pattern)
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
    await page.locator('input[placeholder="Title"]').fill("Test Resource");
    await page
      .locator('input[placeholder="URL"]')
      .fill("https://example.com/test");
    await page.getByRole("button", { name: "Save", exact: true }).click();

    // Wait for resource to be visible and storage to persist
    await expect(
      page.locator(".item-title").filter({ hasText: "Test Resource" }).first(),
    ).toBeVisible({ timeout: 5000 });
    await page.waitForTimeout(1000); // Allow storage write to complete
    console.log("Resource added successfully");

    // Create another workspace for switching
    const wsName2 = `RapidSwitch Other ${Date.now()}`;
    await createWorkspace(page, wsName2);
    await page.waitForTimeout(500);

    // Rapid switch between workspaces 3 times with explicit verification
    console.log("Starting rapid switches...");
    // eslint-disable-next-line no-plusplus
    for (let i = 0; i < 3; i++) {
      // eslint-disable-next-line no-await-in-loop
      await page
        .locator(".nav-item")
        .filter({ hasText: wsName })
        .first()
        .click();
      // eslint-disable-next-line no-await-in-loop
      await page.waitForTimeout(800); // Slightly longer wait for stability
      // eslint-disable-next-line no-await-in-loop
      await page
        .locator(".nav-item")
        .filter({ hasText: wsName2 })
        .first()
        .click();
      // eslint-disable-next-line no-await-in-loop
      await page.waitForTimeout(800);
      console.log(`Completed switch round ${i + 1}`);
    }

    // Switch back to original workspace
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();

    // Use polling to verify resources are still there (handles async restore)
    console.log("Switched back to original workspace, verifying resources...");
    await expect(async () => {
      await expect(
        page.locator(".section-title").filter({ hasText: "Test Section" }),
      ).toBeVisible();
      await expect(
        page
          .locator(".item-title")
          .filter({ hasText: "Test Resource" })
          .first(),
      ).toBeVisible();
    }).toPass({
      timeout: 10000,
      intervals: [500, 1000, 2000, 3000],
    });

    console.log("Resources verified - test passed!");
    await page.close();
  });

  test("should maintain section integrity when adding multiple resources", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));
    await page.waitForLoadState("domcontentloaded");

    // Create workspace
    const wsName = `MultiResource Test ${Date.now()}`;
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // Click on it
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();
    await page.waitForTimeout(500);

    // Add a resource section
    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    await page
      .locator('input[placeholder="Section Title"]')
      .fill("Multi Section");
    await page.getByText("Save", { exact: true }).click();
    await expect(
      page.locator(".section-title").filter({ hasText: "Multi Section" }),
    ).toBeVisible();
    await page.waitForTimeout(500);

    // Add 3 resources in sequence
    const sectionContainer = page
      .locator(".section-container")
      .filter({ hasText: "Multi Section" });

    // eslint-disable-next-line no-restricted-syntax
    for (const site of ["Alpha", "Beta", "Gamma"]) {
      // eslint-disable-next-line no-await-in-loop
      await sectionContainer
        .locator('button[title="Add resource"]')
        .first()
        .click();
      // eslint-disable-next-line no-await-in-loop
      await page
        .locator(".dropdown-item")
        .filter({ hasText: "Add resource" })
        .click();
      // eslint-disable-next-line no-await-in-loop
      await page.locator('input[placeholder="Title"]').fill(site);
      // eslint-disable-next-line no-await-in-loop
      await page
        .locator('input[placeholder="URL"]')
        .fill(`https://example.com/${site.toLowerCase()}`);
      // eslint-disable-next-line no-await-in-loop
      await page.getByRole("button", { name: "Save", exact: true }).click();
      // eslint-disable-next-line no-await-in-loop
      await expect(
        page.locator(".item-title").filter({ hasText: site }).first(),
      ).toBeVisible();
      // eslint-disable-next-line no-await-in-loop
      await page.waitForTimeout(500);
      console.log(`Added resource: ${site}`);
    }

    // Reload page to verify persistence
    await page.reload();
    await page.waitForLoadState("domcontentloaded");
    await page.waitForTimeout(1000);

    // Navigate to workspace
    await page.locator(".nav-item").filter({ hasText: wsName }).first().click();
    await page.waitForTimeout(500);

    // Verify resources still exist
    await expect(
      page.locator(".section-title").filter({ hasText: "Multi Section" }),
    ).toBeVisible({
      timeout: 5000,
    });
    await expect(
      page.locator(".item-title").filter({ hasText: "Alpha" }).first(),
    ).toBeVisible({
      timeout: 5000,
    });
    await expect(
      page.locator(".item-title").filter({ hasText: "Beta" }).first(),
    ).toBeVisible({
      timeout: 5000,
    });
    await expect(
      page.locator(".item-title").filter({ hasText: "Gamma" }).first(),
    ).toBeVisible({
      timeout: 5000,
    });
    console.log("All resources verified after reload");

    await page.close();
  });

  test("should not lose data when switching workspaces immediately after adding resource", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    page.on("console", (msg) => console.log("PAGE LOG:", msg.text()));
    await page.waitForLoadState("domcontentloaded");

    // Create two workspaces
    const wsName1 = `Immediate Switch A ${Date.now()}`;
    const wsName2 = `Immediate Switch B ${Date.now()}`;

    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName1);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();
    await page.fill('input[placeholder="Enter name..."]', wsName2);
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForTimeout(500);

    // Switch to first workspace
    await page
      .locator(".nav-item")
      .filter({ hasText: wsName1 })
      .first()
      .click();
    await page.waitForTimeout(500);

    // Add a section
    await page
      .locator(".main-content button")
      .filter({ hasText: "RESOURCE SECTION" })
      .click();
    await page
      .locator('input[placeholder="Section Title"]')
      .fill("Immediate Section");
    await page.getByText("Save", { exact: true }).click();
    await expect(
      page.locator(".section-title").filter({ hasText: "Immediate Section" }),
    ).toBeVisible();
    await page.waitForTimeout(500);

    // Add a resource
    const sectionContainer = page
      .locator(".section-container")
      .filter({ hasText: "Immediate Section" });
    await sectionContainer
      .locator('button[title="Add resource"]')
      .first()
      .click();
    await page
      .locator(".dropdown-item")
      .filter({ hasText: "Add resource" })
      .click();
    await page.locator('input[placeholder="Title"]').fill("Immediate Resource");
    await page
      .locator('input[placeholder="URL"]')
      .fill("https://example.com/immediate");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    console.log("Resource saved, now switching immediately...");

    // Wait just a tiny bit then immediately switch workspaces
    await page.waitForTimeout(300);
    await page
      .locator(".nav-item")
      .filter({ hasText: wsName2 })
      .first()
      .click();
    await page.waitForTimeout(1000);

    // Switch back to first workspace
    await page
      .locator(".nav-item")
      .filter({ hasText: wsName1 })
      .first()
      .click();
    await page.waitForTimeout(1500);

    // Verify data persisted
    await expect(
      page.locator(".section-title").filter({ hasText: "Immediate Section" }),
    ).toBeVisible({ timeout: 5000 });
    await expect(
      page
        .locator(".item-title")
        .filter({ hasText: "Immediate Resource" })
        .first(),
    ).toBeVisible({ timeout: 5000 });
    console.log("Data persisted after immediate switch!");

    await page.close();
  });
});
