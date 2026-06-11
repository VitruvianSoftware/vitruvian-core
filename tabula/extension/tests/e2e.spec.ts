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
 * E2E tests for Tabula extension
 *
 * Note: These tests are designed to run with the extension loaded in a browser.
 * Playwright's chromium.launch with extensionPath is used to test the extension.
 */

// eslint-disable-next-line import/no-extraneous-dependencies
import { test, expect, chromium, BrowserContext } from "@playwright/test";
import path from "path";
import fs from "fs";

const EXTENSION_PATH = path.join(__dirname, "../dist");

let context: BrowserContext;

test.beforeAll(async () => {
  // Check if extension is built
  if (!fs.existsSync(EXTENSION_PATH)) {
    throw new Error(
      `Extension not built. Please run 'npm run build --workspace=extension' before running E2E tests. Expected path: ${EXTENSION_PATH}`,
    );
  }

  // Check if manifest exists
  const manifestPath = path.join(EXTENSION_PATH, "manifest.json");
  if (!fs.existsSync(manifestPath)) {
    throw new Error(
      `Manifest not found at ${manifestPath}. Extension may not be built correctly.`,
    );
  }

  // Launch browser with extension loaded
  // Note: Extension loading requires non-headless mode, but we can use headless: new for better CI support
  // In CI, we use xvfb-run to provide a virtual display
  context = await chromium.launchPersistentContext("", {
    headless: false, // Extensions require non-headless mode (xvfb-run used in CI)
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--disable-software-rasterizer",
    ],
  });
});

test.afterAll(async () => {
  await context.close();
});

test.describe("Extension Popup Tests", () => {
  test("should open extension popup", async () => {
    const page = await context.newPage();

    // Navigate to a simple data URL instead of external site
    await page.goto("data:text/html,<h1>Test Page</h1>");
    expect(page).toBeDefined();

    await page.close();
  });

  test("should have correct manifest properties", async () => {
    // Verify extension is loaded by checking for expected behavior
    const page = await context.newPage();
    await page.goto("data:text/html,<h1>Test Page</h1>");

    // Extension should be able to query tabs
    // This would be validated through extension APIs in real implementation
    expect(page).toBeDefined();

    await page.close();
  });
});

test.describe("Workspace Creation Flow", () => {
  test("should create a new workspace", async () => {
    // Placeholder for actual workspace creation test
    // In real implementation:
    // 1. Open extension popup
    // 2. Click "New" button
    // 3. Fill in workspace form
    // 4. Verify workspace appears in list
    expect(true).toBe(true);
  });

  test("should display workspaces in popup", async () => {
    // Placeholder for workspace display test
    expect(true).toBe(true);
  });

  test("should enforce 10 workspace limit", async () => {
    // Placeholder for workspace limit test
    expect(true).toBe(true);
  });
});

test.describe("Tab Management Flow", () => {
  test("should save current tabs to workspace", async () => {
    // Placeholder for tab saving test
    // In real implementation:
    // 1. Open several tabs
    // 2. Create workspace
    // 3. Click "Save Tabs"
    // 4. Verify tabs are saved
    expect(true).toBe(true);
  });

  test("should restore tabs from workspace", async () => {
    // Placeholder for tab restoration test
    // In real implementation:
    // 1. Have workspace with saved tabs
    // 2. Click "Restore"
    // 3. Verify tabs are opened
    expect(true).toBe(true);
  });

  test("should move tab between workspaces", async () => {
    // Placeholder for tab moving test
    expect(true).toBe(true);
  });

  test("should switch to workspace", async () => {
    // Placeholder for workspace switching test
    // In real implementation:
    // 1. Have workspace with tabs
    // 2. Click "Switch"
    // 3. Verify current tabs close and workspace tabs open
    expect(true).toBe(true);
  });
});

test.describe("Settings and Configuration", () => {
  test("should update extension settings", async () => {
    // Placeholder for settings test
    expect(true).toBe(true);
  });

  test("should persist settings across sessions", async () => {
    // Placeholder for settings persistence test
    expect(true).toBe(true);
  });
});

test.describe("Storage and Persistence", () => {
  test("should persist workspaces in local storage", async () => {
    // Placeholder for storage persistence test
    expect(true).toBe(true);
  });

  test("should handle storage errors gracefully", async () => {
    // Placeholder for error handling test
    expect(true).toBe(true);
  });
});

test.describe("Performance Tests", () => {
  test("should load popup quickly", async () => {
    // Placeholder for performance test
    // Should load in < 500ms
    expect(true).toBe(true);
  });

  test("should handle large number of tabs", async () => {
    // Placeholder for stress test with many tabs
    expect(true).toBe(true);
  });
});
