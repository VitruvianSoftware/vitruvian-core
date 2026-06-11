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
import { createWorkspace, getOrCreateDashboardPage } from "./e2e-helpers";

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

test.describe("Notes Editor", () => {
  test("should support Markdown formatting and preview", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // 1. Create workspace (Use SERIAL_ prefix to avoid parallel cleanup interference)
    const wsName = `SERIAL_Notes_Test_${Date.now()}`;
    await createWorkspace(page, wsName);

    // 2. Go to Notes tab
    await page.locator(".tab-item").filter({ hasText: "Notes" }).click();

    // 3. Create New Note with Markdown
    await page.getByText("+ New Note").click();

    await page.locator(".note-title-input").fill("Markdown Test Note");
    // Target the textarea inside NoteEditor
    await page
      .locator(".note-content-input")
      .fill("This is **bold** and *italic* text.");

    // Wait for button to be enabled
    const saveBtn = page.getByRole("button", { name: "Save" });
    await expect(saveBtn).toBeEnabled();
    // Small delay to ensure state propagation
    await page.waitForTimeout(500);

    // Save
    await saveBtn.click();

    // 4. Verify Note in List
    // Use .note-header class to ensure we are looking at the saved note, not the edit form
    const noteTitleInput = page.locator(
      '.note-card .note-header input[value="Markdown Test Note"]',
    );
    await expect(noteTitleInput).toBeVisible();

    const noteCard = page.locator(".note-card").filter({
      has: page.locator('.note-header input[value="Markdown Test Note"]'),
    });
    await expect(noteCard).toBeVisible();

    // 5. Verify Editor is present
    const editor = noteCard.locator(".note-editor");
    await expect(editor).toBeVisible();

    // Verify Toolbar exists
    await expect(editor.locator(".note-toolbar")).toBeVisible();

    // 6. Test Preview Mode
    // Default is Write mode
    await expect(editor.locator("textarea")).toBeVisible();

    // Click Preview button (icon visibility)
    await editor.locator('button[title="Preview"]').click();

    // Verify Preview rendered
    const preview = editor.locator(".markdown-preview");
    await expect(preview).toBeVisible();

    // Verify HTML content
    const htmlContent = await preview.innerHTML();
    expect(htmlContent).toContain("<strong>bold</strong>");
    expect(htmlContent).toContain("<em>italic</em>");

    // Switch back to Edit
    await editor.locator('button[title="Edit"]').click();
    await expect(editor.locator("textarea")).toBeVisible();
  });

  test("should toggle fullscreen mode", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);

    // Use SERIAL_ prefix to avoid parallel cleanup interference
    const wsName = `SERIAL_Notes_FS_${Date.now()}`;
    await createWorkspace(page, wsName);

    await page.locator(".tab-item").filter({ hasText: "Notes" }).click();
    await page.getByText("+ New Note").click();
    await page.locator(".note-title-input").fill("FS Test");
    await page.locator(".note-content-input").fill("Content");
    await page.getByRole("button", { name: "Save" }).click();

    // Fix: Use specific selector to avoid ambiguity with the create form
    const noteCard = page
      .locator(".note-card")
      .filter({ has: page.locator('.note-header input[value="FS Test"]') });

    const editor = noteCard.locator(".note-editor");
    await editor.locator('button[title="Fullscreen"]').click();

    // Verify class
    await expect(editor).toHaveClass(/fullscreen/);

    // Verify z-index or style (implicit via visual check but useful assertion)
    const zIndex = await editor.evaluate(
      (el) => window.getComputedStyle(el).zIndex,
    );
    expect(zIndex).toBe("9999");

    // Exit Fullscreen
    await editor.locator('button[title="Exit Fullscreen"]').click();
    await expect(editor).not.toHaveClass(/fullscreen/);
  });
});
