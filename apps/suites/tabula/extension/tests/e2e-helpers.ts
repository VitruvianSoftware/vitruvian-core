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
 * E2E Test Helpers
 *
 * Utility functions for E2E tests that need authenticated API access.
 * Supports both local testing (with running API) and CI pipeline testing.
 */

import { Page, BrowserContext } from "@playwright/test";
import jwt from "jsonwebtoken";

/**
 * Rate limit delay (ms) - helps avoid 429 errors between API operations
 */
const RATE_LIMIT_DELAY = 2000;

/**
 * Sleep helper for rate limiting
 */
function sleep(ms: number): Promise<void> {
  // eslint-disable-next-line no-promise-executor-return
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Test user credentials - must match seed-test-user.ts in api/prisma
 */
export const TEST_USER = {
  id: "00000000-0000-0000-0000-e2e000000000",
  email: "e2e-test@tabula.dev",
  name: "E2E Test User",
  tier: "free",
};

/**
 * A SECOND seeded e2e user, dedicated to the cross-device convergence spec
 * (sync-convergence.spec.ts). Playwright runs spec files in parallel workers
 * (`workers: 2`) against ONE shared backend, and several specs broadly delete
 * the seeded user's workspaces between tests (`cleanupApiWorkspaces`). The
 * convergence tests hold a workspace live across long (25-40s) two-device
 * windows, so a parallel spec's cleanup would delete it mid-test — and the
 * convergence spec's own cleanup would delete theirs. Giving convergence its
 * own user removes that shared-state collision entirely. Must match the second
 * user seeded in `api/prisma/seed-test-user.ts`.
 */
export const CONV_TEST_USER = {
  id: "00000000-0000-0000-0000-e2e000000002",
  email: "e2e-conv@tabula.dev",
  name: "E2E Convergence User",
  tier: "free",
};

/**
 * Mint (or read) a JWT for a seeded e2e user (defaults to {@link TEST_USER}).
 *
 * For the default user, prefers `E2E_TEST_TOKEN` (emitted by the seed and
 * injected into the pw_suite env), otherwise signs one from `JWT_SECRET` —
 * which the pw_suite Bazel target exports — so API-backed sync tests actually
 * RUN in CI instead of skipping (the gap that left SS-2/SS-3 at `[/]`). For any
 * OTHER user, always signs fresh from `JWT_SECRET` (the shared `E2E_TEST_TOKEN`
 * belongs to the default user). Payloads match `api/prisma/seed-test-user.ts`.
 * Returns null only when no secret is available (a non-e2e local run).
 */
export function mintTestToken(
  user: { id: string; email: string; tier: string } = TEST_USER,
): string | null {
  if (user.id === TEST_USER.id) {
    const existing = process.env.E2E_TEST_TOKEN;
    if (existing) return existing;
  }
  const secret = process.env.JWT_SECRET;
  if (!secret) return null;
  return jwt.sign({ id: user.id, email: user.email, tier: user.tier }, secret, {
    expiresIn: "24h",
  });
}

/**
 * Check if API is available
 */
export async function isApiAvailable(
  baseUrl = "http://localhost:8080",
): Promise<boolean> {
  try {
    const response = await fetch(`${baseUrl}/health`);
    return response.ok;
  } catch {
    return false;
  }
}

/**
 * Login test user by setting auth token in Chrome storage
 *
 * @param page - Playwright page instance
 * @param token - JWT token (from E2E_TEST_TOKEN env var or generated)
 */
export async function loginTestUser(page: Page, token: string): Promise<void> {
  await page.evaluate(
    async ({ authToken, user }) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome.storage.local;
      await storage.set({
        tabula_access_token: authToken,
        tabula_user: user,
      });
    },
    { authToken: token, user: TEST_USER },
  );
}

/**
 * Logout test user by removing auth token from Chrome storage
 */
export async function logoutTestUser(page: Page): Promise<void> {
  await page.evaluate(async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const storage = (window as any).chrome.storage.local;
    await storage.remove(["tabula_access_token", "tabula_user"]);
  });
}

/**
 * Get the E2E test token from environment variable
 * Falls back to generating one if API is available
 */
export function getTestToken(): string | null {
  return process.env.E2E_TEST_TOKEN || null;
}

/**
 * Setup function for tests that need authenticated API access
 *
 * Usage:
 *   test.beforeEach(async ({ page }) => {
 *     const token = getTestToken();
 *     if (!token) {
 *       test.skip();
 *       return;
 *     }
 *     await loginTestUser(page, token);
 *   });
 */
export async function setupAuthenticatedTest(page: Page): Promise<boolean> {
  const token = getTestToken();
  if (!token) {
    console.warn(
      "[E2E] No E2E_TEST_TOKEN found. Skipping authenticated test. " +
        "Run `npm run db:seed:test -w api` to generate a token.",
    );
    return false;
  }

  await loginTestUser(page, token);
  return true;
}

/**
 * Clean up test data created during tests
 *
 * @param page - Playwright page instance
 * @param workspaceIds - IDs of workspaces to clean up
 */
export async function cleanupTestData(
  page: Page,
  workspaceIds: string[] = [],
): Promise<void> {
  // Clean up workspaces from storage
  await page.evaluate(async (ids) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const storage = (window as any).chrome.storage.local;
    const result = await storage.get("tabula_workspaces");
    const workspaces = result.tabula_workspaces || [];

    // Filter out test workspaces
    const filtered = workspaces.filter(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (ws: any) => !ids.includes(ws.id) && !ws.name.includes("Test"),
    );

    await storage.set({
      tabula_workspaces: filtered,
      tabula_active_workspace: filtered[0]?.id || null,
    });
  }, workspaceIds);
}

/**
 * Clean up ALL test data - resets storage to clean state
 */
export async function cleanupAllTestData(page: Page): Promise<void> {
  await page.evaluate(async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const storage = (window as any).chrome.storage.local;
    await storage.set({
      tabula_workspaces: [],
      tabula_active_workspace: null,
      tabula_space_groups: [],
    });
  });
}

/**
 * Delete backups for the test user via API
 * Call this in afterEach/afterAll to clean up API data
 */
export async function cleanupTestBackups(
  token: string,
  baseUrl = "http://localhost:8080",
): Promise<void> {
  try {
    const response = await fetch(`${baseUrl}/api/v1/backups`, {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    if (!response.ok) {
      // eslint-disable-next-line no-console
      console.warn(
        "[E2E] Failed to fetch backups for cleanup:",
        response.status,
      );
      return;
    }

    const data = await response.json();
    // API returns { data: { backups: [...], total: number } }
    const backups = data.data?.backups || data.backups || data.data || [];

    // Delete each backup (sequential required for API)
    // eslint-disable-next-line no-restricted-syntax
    for (const backup of backups) {
      // eslint-disable-next-line no-await-in-loop
      await fetch(`${baseUrl}/api/v1/backups/${backup.id}`, {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });
      // Rate limit delay to avoid 429 errors
      // eslint-disable-next-line no-await-in-loop
      await sleep(RATE_LIMIT_DELAY);
    }

    if (backups.length > 0) {
      // eslint-disable-next-line no-console
      console.log(`[E2E] Cleaned up ${backups.length} test backups`);
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("[E2E] Failed to cleanup backups:", error);
  }
}

// =============================================================================
// API VERIFICATION HELPERS
// =============================================================================

/**
 * Fetch workspaces from API to verify sync
 */
export async function fetchWorkspacesFromApi(
  token: string,
  baseUrl = "http://localhost:8080",
): Promise<{ id: string; name: string }[] | null> {
  try {
    const response = await fetch(`${baseUrl}/api/v1/workspaces`, {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    if (!response.ok) {
      // eslint-disable-next-line no-console
      console.warn(
        "[E2E] Failed to fetch workspaces from API:",
        response.status,
      );
      return null;
    }

    const data = await response.json();
    return data.data || [];
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("[E2E] Failed to fetch workspaces:", error);
    return null;
  }
}

/**
 * Verify a workspace exists in the API with expected properties
 */
export async function verifyWorkspaceInApi(
  token: string,
  workspaceName: string,
  baseUrl = "http://localhost:8080",
): Promise<boolean> {
  const workspaces = await fetchWorkspacesFromApi(token, baseUrl);
  if (!workspaces) return false;
  return workspaces.some((ws) => ws.name.includes(workspaceName));
}

/**
 * Delete all workspaces from API (cleanup)
 */
export interface CleanupOptions {
  includePrefix?: string;
  excludePrefix?: string;
}

/**
 * Delete all workspaces from API (cleanup)
 */
export async function cleanupApiWorkspaces(
  token: string,
  baseUrl = "http://localhost:8080",
  options: CleanupOptions = { excludePrefix: "SERIAL_" },
): Promise<void> {
  const workspaces = await fetchWorkspacesFromApi(token, baseUrl);
  if (!workspaces) return;

  // eslint-disable-next-line no-restricted-syntax
  for (const ws of workspaces) {
    if (options.includePrefix && !ws.name.startsWith(options.includePrefix)) {
      // eslint-disable-next-line no-continue
      continue;
    }
    if (options.excludePrefix && ws.name.startsWith(options.excludePrefix)) {
      // eslint-disable-next-line no-continue
      continue;
    }

    // eslint-disable-next-line no-await-in-loop
    await fetch(`${baseUrl}/api/v1/workspaces/${ws.id}`, {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });
    // Rate limit delay to avoid 429 errors
    // eslint-disable-next-line no-await-in-loop
    await sleep(RATE_LIMIT_DELAY);
  }

  if (workspaces.length > 0) {
    // eslint-disable-next-line no-console
    console.log(
      `[E2E] Cleaned up workspaces from API (Options: ${JSON.stringify(options)})`,
    );
  }
}

/**
 * Wait for workspace to sync to API (with retries)
 */
export async function waitForWorkspaceSync(
  token: string,
  workspaceName: string,
  maxRetries = 5,
  delayMs = 1000,
  baseUrl = "http://localhost:8080",
): Promise<boolean> {
  // eslint-disable-next-line no-plusplus
  for (let i = 0; i < maxRetries; i++) {
    // eslint-disable-next-line no-await-in-loop
    const found = await verifyWorkspaceInApi(token, workspaceName, baseUrl);
    if (found) return true;
    // eslint-disable-next-line no-await-in-loop, no-promise-executor-return
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
  return false;
}

/**
 * Create a workspace via UI and wait for it to appear in sidebar.
 * This is the recommended way to create workspaces in E2E tests.
 *
 * @param page - Playwright page (must be on dashboard)
 * @param name - Workspace name
 * @param timeout - Timeout for waiting for workspace to appear (default: 10000ms)
 */
export async function createWorkspace(
  page: Page,
  name: string,
  timeout = 10000,
): Promise<void> {
  // Wait for spaces header to be ready
  await page.waitForSelector(".spaces-header", { timeout: 5000 }).catch(() => {
    // Fall through - might be in empty state
  });

  // Click the Add button in Spaces header
  const addBtn = page.locator('button[title="Add"]');
  if (await addBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
    await addBtn.click();
    // Click "New space" in dropdown
    await page.getByText("New space").click();
  } else {
    // Fallback: look for empty state button or first available "New Space" option
    const emptyStateBtn = page.getByTestId("empty-state-new-space-button");
    if (await emptyStateBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
      await emptyStateBtn.click();
    } else {
      // Try alternative selectors
      await page.getByRole("button", { name: "Add" }).first().click();
      await page.getByText("New space").click();
    }
  }

  // Fill name and create
  await page.getByPlaceholder("Enter name...").fill(name);
  await page.getByRole("button", { name: "Create", exact: true }).click();

  // Wait for workspace to appear in sidebar
  await page.waitForSelector(`.sidebar-nav .nav-item:has-text("${name}")`, {
    timeout,
  });
}

/**
 * Get the existing pinned dashboard page from the browser context.
 * The extension auto-opens a pinned dashboard tab on install, so we should reuse it
 * instead of creating a new tab. This prevents having two dashboard tabs open.
 *
 * @param context - Browser context
 * @param extensionId - Extension ID
 * @returns The existing dashboard page, or null if not found
 */
export async function getDashboardPage(
  context: BrowserContext,
  extensionId: string,
): Promise<Page | null> {
  const dashboardUrl = `chrome-extension://${extensionId}/dashboard.html`;

  // Look through all existing pages for the dashboard
  const pages = context.pages();
  const dashboardPage = pages.find(
    (p) =>
      p.url().includes(dashboardUrl) ||
      p.url().includes(`${extensionId}/dashboard`),
  );

  if (dashboardPage) {
    // Found existing dashboard tab - bring it to focus
    await dashboardPage.bringToFront();
    return dashboardPage;
  }

  // Dashboard tab not found (shouldn't happen if extension installed correctly)
  return null;
}

/**
 * Get or create a dashboard page. Prefers reusing the existing pinned dashboard tab.
 * Falls back to creating a new page if no existing dashboard is found.
 *
 * @param context - Browser context
 * @param extensionId - Extension ID
 * @returns A page on the dashboard
 */
/**
 * Close duplicate dashboard tabs, keeping only one.
 * The extension auto-opens a pinned dashboard on install, and tests may open additional ones.
 * This ensures only one dashboard tab exists for cleaner test isolation.
 *
 * @param context - Browser context
 * @param extensionId - Extension ID
 */
export async function closeDuplicateDashboardTabs(
  context: BrowserContext,
  extensionId: string,
): Promise<void> {
  const pages = context.pages();
  // Only match dashboard.html specifically, not popup.html or other extension pages
  const dashboardPages = pages.filter((p) =>
    p.url().includes(`chrome-extension://${extensionId}/dashboard.html`),
  );

  // Keep first dashboard, close the rest
  if (dashboardPages.length > 1) {
    const [, ...duplicates] = dashboardPages;
    await Promise.all(duplicates.map((p) => p.close()));
    // eslint-disable-next-line no-console
    console.log(`[E2E] Closed ${duplicates.length} duplicate dashboard tab(s)`);
  }
}

/**
 * Keep one inert page alive for the whole suite. On Linux (CI), Chrome EXITS
 * when its last window closes — and the test flows routinely get there:
 * workspace switches close the launch-time about:blank, and tests close their
 * own dashboard pages when done. Once the browser exits, every remaining test
 * in the (serial) file fails with "Target page, context or browser has been
 * closed". macOS keeps Chrome alive with zero windows, which is why this only
 * bites in CI.
 *
 * The anchor is the extension's manifest.json: it runs no app code, and
 * workspace switches never close chrome-extension:// tabs.
 */
async function ensureAnchorPage(
  context: BrowserContext,
  extensionId: string,
): Promise<void> {
  const anchorUrl = `chrome-extension://${extensionId}/manifest.json`;
  const exists = context.pages().some((p) => p.url() === anchorUrl);
  if (!exists) {
    const anchor = await context.newPage();
    await anchor.goto(anchorUrl);
  }
}

/**
 * Suppress the first-run onboarding modal (#138) for tests that aren't
 * exercising it. The extension auto-opens the dashboard at install with zero
 * workspaces, which triggers the onboarding overlay before a test can seed
 * data — and that overlay then intercepts pointer events. Mark onboarding as
 * completed (merging into any existing settings) and reload so the dashboard
 * mounts without it. Best-effort: never let this break a test's setup.
 */
async function suppressOnboarding(page: Page): Promise<void> {
  try {
    await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storage = (window as any).chrome?.storage?.local;
      if (!storage) return;
      const current =
        (await storage.get("tabula_settings")).tabula_settings || {};
      await storage.set({
        tabula_settings: { ...current, onboardingCompleted: true },
      });
    });
    await page.reload();
    await page.waitForLoadState("domcontentloaded");
  } catch {
    // Best-effort only.
  }
}

/**
 * Get or create a dashboard page. Prefers reusing the existing pinned dashboard tab.
 * Falls back to creating a new page if no existing dashboard is found.
 *
 * @param context - Browser context
 * @param extensionId - Extension ID
 * @returns A page on the dashboard
 */
export async function getOrCreateDashboardPage(
  context: BrowserContext,
  extensionId: string,
): Promise<Page> {
  // Make sure the browser can never drop to zero pages mid-suite (see above)
  await ensureAnchorPage(context, extensionId);

  // Wait up to 2 seconds for the extension to auto-open the dashboard tab
  // This handles the race condition where the test starts before the extension finishes installing
  const startTime = Date.now();
  while (Date.now() - startTime < 2000) {
    // eslint-disable-next-line no-await-in-loop
    const existingPage = await getDashboardPage(context, extensionId);
    if (existingPage) {
      // Found it! Ensure duplicates are closed
      // eslint-disable-next-line no-await-in-loop
      await closeDuplicateDashboardTabs(context, extensionId);
      // Get it again in case the survivor changed or we need to be sure
      // eslint-disable-next-line no-await-in-loop
      const survivor = await getDashboardPage(context, extensionId);
      if (survivor) {
        // eslint-disable-next-line no-await-in-loop
        await survivor.bringToFront();
        // eslint-disable-next-line no-await-in-loop
        await survivor.waitForLoadState("domcontentloaded");
        // eslint-disable-next-line no-await-in-loop
        await suppressOnboarding(survivor);
        return survivor;
      }
    }
    // Wait a bit before retry
    // eslint-disable-next-line no-await-in-loop
    await new Promise((resolve) => {
      setTimeout(resolve, 100);
    });
  }

  // Double check cleanup before creating new one
  await closeDuplicateDashboardTabs(context, extensionId);
  const finalCheck = await getDashboardPage(context, extensionId);
  if (finalCheck) {
    await suppressOnboarding(finalCheck);
    return finalCheck;
  }

  // No existing dashboard found after waiting, create a new page (fallback)
  const dashboardUrl = `chrome-extension://${extensionId}/dashboard.html`;
  const page = await context.newPage();
  await page.goto(dashboardUrl);
  await page.waitForLoadState("domcontentloaded");
  await suppressOnboarding(page);
  return page;
}
