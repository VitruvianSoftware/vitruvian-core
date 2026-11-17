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
 * E2E tests for modal animations and glassmorphic styling
 *
 * Tests the implementation of framer-motion animations and glassmorphic modals
 * as specified in Gap Analysis Section 1.B
 */

/* eslint-disable import/no-extraneous-dependencies */
import { test, expect, BrowserContext, Page } from "@playwright/test";
import { getOrCreateDashboardPage, launchExtension } from "./e2e-helpers";

// Shared context and extension ID
let context: BrowserContext;
let extensionId: string;

test.beforeAll(async () => {
  // Launch Chromium with the extension and get its id.
  ({ context, extensionId } = await launchExtension());
});

test.afterAll(async () => {
  await context.close();
});

test.describe("Modal Animations", () => {
  let page: Page;

  test.beforeEach(async () => {
    page = await getOrCreateDashboardPage(context, extensionId);
    await page.waitForLoadState("networkidle");
  });

  test.afterEach(async () => {
    await page.close();
  });

  test("should display glassmorphic overlay when creating new workspace", async () => {
    // Click to open the new workspace modal
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();

    // Verify modal overlay is visible with glassmorphic class
    const overlay = page
      .locator(".modal-overlay, .glassmorphic-overlay")
      .first();
    await expect(overlay).toBeVisible();

    // Verify modal content is visible
    const modalContent = page
      .locator(".modal-content, .glassmorphic-modal")
      .first();
    await expect(modalContent).toBeVisible();

    // Verify modal title
    await expect(page.getByText("New Workspace")).toBeVisible();

    // Close modal by clicking overlay
    await overlay.click({ position: { x: 5, y: 5 } });
    await expect(overlay).not.toBeVisible();
  });

  test("should close modal with Escape key", async () => {
    // Open new workspace modal
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();

    // Verify modal is visible
    await expect(page.getByText("New Workspace")).toBeVisible();

    // Press Escape
    await page.keyboard.press("Escape");

    // Verify modal is closed
    await expect(page.getByText("New Workspace")).not.toBeVisible();
  });

  test("should not close modal when clicking modal content", async () => {
    // Open new workspace modal
    await page.locator('button[title="Add"]').click();
    await page.getByText("New space").click();

    // Click on modal content area (not overlay)
    const modalContent = page
      .locator(".modal-content, .glassmorphic-modal")
      .first();
    await modalContent.click();

    // Verify modal is still visible
    await expect(page.getByText("New Workspace")).toBeVisible();

    // Close with Cancel button
    await page.getByRole("button", { name: "Cancel" }).click();
    await expect(page.getByText("New Workspace")).not.toBeVisible();
  });
});
