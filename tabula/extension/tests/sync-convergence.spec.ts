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
import { test, expect, chromium, BrowserContext, Page } from "@playwright/test";
import path from "path";
import fs from "fs";
import {
  getOrCreateDashboardPage,
  mintTestToken,
  CONV_TEST_USER,
  cleanupApiWorkspaces,
} from "./e2e-helpers";

/**
 * Cross-device sync convergence (#136).
 *
 * "Device A" is the real extension; "Device B" is a second device represented
 * by direct authenticated API calls carrying a distinct `x-device-id`. Both act
 * on the same user against the live backend (api + postgres + redis), which is
 * exactly how two installs converge in production: REST upsert with version-
 * based optimistic locking (409 on a stale baseVersion) + a client-side
 * last-write-wins reconciliation keyed on updatedAt. Using an API-backed second
 * device (rather than a second flaky browser context) keeps these timing-
 * sensitive convergence assertions deterministic.
 *
 * Conflict granularity is per-workspace: resources/notes/tasks live inside the
 * workspace JSON, so two devices editing the SAME workspace resolve at
 * workspace granularity — the later whole-workspace write wins (see
 * docs/tabula/architecture/conflict-resolution.md).
 */

const API = "http://localhost:8080";
const DEVICE_B = "e2e-device-b";

const EXTENSION_PATH = process.env.EXTENSION_PATH
  ? path.resolve(process.env.EXTENSION_PATH)
  : path.join(__dirname, "../dist");

// Convergence runs on its OWN seeded user (not the shared TEST_USER) so the
// other specs' parallel workspace cleanups never touch the workspaces these
// tests hold live across long two-device windows. See e2e-helpers.CONV_TEST_USER.
const token = mintTestToken(CONV_TEST_USER);

interface ApiWorkspace {
  id: string;
  name: string;
  version: number;
  sections?: { id: string; title: string; resources?: unknown[] }[];
  notes?: { id: string; title: string }[];
  tasks?: { id: string; title: string }[];
}

// ---- Device B: direct authenticated API -----------------------------------

async function apiList(): Promise<ApiWorkspace[]> {
  const res = await fetch(`${API}/api/v1/workspaces`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) return [];
  const json = (await res.json()) as { data?: ApiWorkspace[] };
  return json.data ?? [];
}

async function apiById(id: string): Promise<ApiWorkspace | undefined> {
  return (await apiList()).find((w) => w.id === id);
}

async function apiPut(
  id: string,
  patch: Record<string, unknown>,
  baseVersion: number,
): Promise<number> {
  const res = await fetch(`${API}/api/v1/workspaces/${id}`, {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "x-device-id": DEVICE_B,
    },
    body: JSON.stringify({ ...patch, baseVersion }),
  });
  return res.status;
}

// ---- Device A: the real extension -----------------------------------------

async function readLocal(page: Page): Promise<ApiWorkspace[]> {
  return page.evaluate(async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const storage = (window as any).chrome.storage.local;
    const result = await storage.get("tabula_workspaces");
    return (result.tabula_workspaces || []) as ApiWorkspace[];
  });
}

async function createSpaceA(page: Page, name: string): Promise<void> {
  await page.locator('button[title="Add"]').click();
  await page.getByText("New space").click();
  await page.locator('input[placeholder="Enter name..."]').fill(name);
  await page.getByRole("button", { name: "Create" }).click();
  await expect(
    page.locator(".nav-item").filter({ hasText: name }).first(),
  ).toBeVisible();
}

async function renameSpaceA(
  page: Page,
  currentName: string,
  newName: string,
  options: { confirmVisible?: boolean } = {},
): Promise<void> {
  // confirmVisible asserts the optimistic nav-item update right after Save. That
  // post-condition is safe in isolation, but in the LWW scenario a SECOND device
  // has just edited the same space server-side, so inbound sync can transiently
  // revert the visible name while the client reconciles the 409 — racing this
  // assertion. Callers exercising that path pass confirmVisible:false and verify
  // the true converged state via the backend + local-storage polls instead.
  const { confirmVisible = true } = options;
  const row = page
    .locator(".nav-item")
    .filter({ hasText: currentName })
    .first();
  await row.hover();
  await row.locator('button[aria-label="Space options"]').click();
  await page
    .locator(".dropdown-menu .dropdown-item")
    .filter({ hasText: "Rename" })
    .click();
  const input = page.locator('input[placeholder="Enter name..."]');
  await expect(input).toBeVisible();
  await input.fill(newName);
  const save = page
    .locator(".modal-footer button.btn-primary")
    .filter({ hasText: "Save" });
  await save.click();
  if (confirmVisible) {
    await expect(
      page.locator(".nav-item").filter({ hasText: newName }).first(),
    ).toBeVisible({ timeout: 15000 });
  } else {
    // The rename was committed once the modal dismisses; convergence of the name
    // itself is asserted by the caller's waitForApi / waitForLocalA polls.
    await expect(save).toBeHidden({ timeout: 15000 });
  }
}

/** Poll the backend until `check` holds, returning the matching workspace. */
async function waitForApi(
  id: string,
  check: (w: ApiWorkspace | undefined) => boolean,
  message: string,
): Promise<ApiWorkspace> {
  await expect
    .poll(async () => check(await apiById(id)), {
      message,
      timeout: 45000,
      intervals: [500, 1000, 1500, 2000, 3000],
    })
    .toBe(true);
  const ws = await apiById(id);
  if (!ws) throw new Error(`workspace ${id} vanished after converging`);
  return ws;
}

/**
 * Reload device A (forces a fresh pull + merge on dashboard mount) and poll its
 * local storage until `check` holds. Reloading inside the poll guarantees each
 * attempt re-pulls from the backend rather than waiting on SSE timing.
 */
async function waitForLocalA(
  page: Page,
  check: (w: ApiWorkspace[]) => boolean,
  message: string,
): Promise<void> {
  await expect
    .poll(
      async () => {
        await page.reload();
        await page.waitForLoadState("domcontentloaded");
        await page.waitForTimeout(1200);
        return check(await readLocal(page));
      },
      { message, timeout: 70000, intervals: [1500, 2500, 3500, 4000] },
    )
    .toBe(true);
}

test.describe("Cross-device sync convergence (#136)", () => {
  // Two-device convergence (reloads + backend polls) can run long under CI
  // load; the 30s Playwright default would cut a slow-but-correct converge off
  // mid-poll. Give each test generous headroom (it returns as soon as it
  // converges, so green runs stay fast).
  test.describe.configure({ mode: "serial", timeout: 120000 });

  let context: BrowserContext;
  let extensionId: string;

  test.beforeAll(async () => {
    if (!token) {
      // No JWT_SECRET / E2E_TEST_TOKEN — cannot reach the authed backend.
      // In the Bazel e2e lane JWT_SECRET is always set, so this only skips a
      // bare `playwright test` run without secrets.
      test.skip();
      return;
    }
    if (!fs.existsSync(EXTENSION_PATH)) {
      throw new Error(`Extension not built. Expected path: ${EXTENSION_PATH}`);
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
    if (!background) background = await context.waitForEvent("serviceworker");
    // eslint-disable-next-line prefer-destructuring
    extensionId = background.url().split("/")[2];
  });

  test.afterAll(async () => {
    if (token) await cleanupApiWorkspaces(token);
    await context?.close();
  });

  test.beforeEach(async () => {
    await cleanupApiWorkspaces(token as string);
    const page = await getOrCreateDashboardPage(context, extensionId);
    // Sign device A in and start from a clean local slate.
    await page.evaluate(
      async ({ authToken, user }) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const storage = (window as any).chrome.storage.local;
        await storage.set({
          tabula_access_token: authToken,
          tabula_user: user,
          tabula_workspaces: [],
          tabula_active_workspace: null,
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
      },
      { authToken: token, user: CONV_TEST_USER },
    );
    await page.reload();
    await page.waitForTimeout(800);
    await page.close();
  });

  test("a local create on device A pushes to the backend", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const name = `Conv push ${Date.now()}`;
    await createSpaceA(page, name);
    await expect
      .poll(async () => (await apiList()).some((w) => w.name === name), {
        message: "device A's create should reach the backend",
        timeout: 25000,
        intervals: [500, 1000, 1500, 2000],
      })
      .toBe(true);
    await page.close();
  });

  test("a backend edit by device B converges into device A", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const name = `Conv pull ${Date.now()}`;
    await createSpaceA(page, name);

    // Wait for A's create on the server and capture id + version.
    let serverId = "";
    await expect
      .poll(
        async () => {
          const w = (await apiList()).find((x) => x.name === name);
          if (w) serverId = w.id;
          return !!w;
        },
        { message: "A's create lands server-side", timeout: 25000 },
      )
      .toBe(true);
    const created = await apiById(serverId);
    expect(created).toBeTruthy();

    // Device B renames it on the backend.
    const renamed = `${name} [edited by B]`;
    const status = await apiPut(serverId, { name: renamed }, created!.version);
    expect(status).toBe(200);
    await waitForApi(serverId, (w) => w?.name === renamed, "B's rename lands");

    // Device A must converge to B's change after a fresh pull.
    await waitForLocalA(
      page,
      (wss) => wss.some((w) => w.id === serverId && w.name === renamed),
      "device A converges to device B's backend edit",
    );
    await page.close();
  });

  test("later write wins predictably across devices (workspace-granularity LWW)", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const base = `Conv lww ${Date.now()}`;
    await createSpaceA(page, base);

    let serverId = "";
    await expect
      .poll(
        async () => {
          const w = (await apiList()).find((x) => x.name === base);
          if (w) serverId = w.id;
          return !!w;
        },
        { message: "A's create lands server-side", timeout: 25000 },
      )
      .toBe(true);
    const created = await apiById(serverId);

    // Device B edits FIRST (older write).
    const bName = `${base} [B-first]`;
    expect(await apiPut(serverId, { name: bName }, created!.version)).toBe(200);
    await waitForApi(
      serverId,
      (w) => w?.name === bName,
      "B's edit lands first",
    );

    // Device A edits LATER (newer write) without having pulled B's edit, so its
    // queued PUT 409s on the now-stale baseVersion and the client reconciles by
    // last-write-wins (A is newer) — A's whole-workspace write must win. The
    // optimistic nav-item assertion is skipped here because B's concurrent edit
    // makes it race; the convergence polls below are the real assertions.
    const aName = `${base} [A-later]`;
    await renameSpaceA(page, base, aName, { confirmVisible: false });

    // The later writer (A) wins on the backend; B's rename is overwritten.
    await waitForApi(
      serverId,
      (w) => w?.name === aName,
      "later writer (device A) wins on the backend",
    );

    // And both ends converge: A's local copy equals the server's winner.
    await waitForLocalA(
      page,
      (wss) => wss.some((w) => w.id === serverId && w.name === aName),
      "device A converges to the LWW winner (no split-brain)",
    );
    await page.close();
  });

  test("device B edits to resources, notes, and tasks converge into device A", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const name = `Conv nested ${Date.now()}`;
    await createSpaceA(page, name);

    let serverId = "";
    await expect
      .poll(
        async () => {
          const w = (await apiList()).find((x) => x.name === name);
          if (w) serverId = w.id;
          return !!w;
        },
        { message: "A's create lands server-side", timeout: 25000 },
      )
      .toBe(true);
    const created = await apiById(serverId);

    // Device B adds a section+resource, a note, and a task in one PUT.
    const status = await apiPut(
      serverId,
      {
        sections: [
          {
            id: "sec-b-1",
            title: "Section by B",
            resources: [
              {
                id: "res-b-1",
                title: "Resource by B",
                url: "https://b.example",
              },
            ],
          },
        ],
        notes: [
          { id: "note-b-1", title: "Note by B", content: "hello from B" },
        ],
        tasks: [{ id: "task-b-1", title: "Task by B", completed: false }],
      },
      created!.version,
    );
    expect(status).toBe(200);
    await waitForApi(
      serverId,
      (w) => (w?.sections?.length ?? 0) > 0 && (w?.notes?.length ?? 0) > 0,
      "B's nested edits land server-side",
    );

    // Device A converges to all of B's nested entities.
    await waitForLocalA(
      page,
      (wss) => {
        const w = wss.find((x) => x.id === serverId);
        if (!w) return false;
        const hasResource = (w.sections ?? []).some((s) =>
          (s.resources ?? []).some(
            (r) => (r as { title?: string }).title === "Resource by B",
          ),
        );
        const hasNote = (w.notes ?? []).some((n) => n.title === "Note by B");
        const hasTask = (w.tasks ?? []).some((t) => t.title === "Task by B");
        return hasResource && hasNote && hasTask;
      },
      "device A converges to B's resource, note, and task",
    );
    await page.close();
  });

  test("device B's section reorder converges into device A (array order preserved)", async () => {
    const page = await getOrCreateDashboardPage(context, extensionId);
    const name = `Conv reorder ${Date.now()}`;
    await createSpaceA(page, name);

    let serverId = "";
    await expect
      .poll(
        async () => {
          const w = (await apiList()).find((x) => x.name === name);
          if (w) serverId = w.id;
          return !!w;
        },
        { message: "A's create lands server-side", timeout: 25000 },
      )
      .toBe(true);

    // Sections render in their stored ARRAY order (no position-sort), so a
    // reorder is purely an array permutation that must round-trip through the
    // backend and converge into device A. Driving the reorder from device B
    // (an authoritative, strictly-newer API write) keeps this deterministic —
    // the older storage-hand-edit approach raced device A's own in-flight sync.
    const sec = (id: string, title: string) => ({ id, title, resources: [] });

    // 1. Device B establishes the initial order [A, B, C].
    const created = await apiById(serverId);
    expect(
      await apiPut(
        serverId,
        {
          sections: [
            sec("sec-a", "Section A"),
            sec("sec-b", "Section B"),
            sec("sec-c", "Section C"),
          ],
        },
        created!.version,
      ),
    ).toBe(200);
    const ordered = await waitForApi(
      serverId,
      (w) =>
        (w?.sections ?? []).map((s) => s.title).join(",") ===
        "Section A,Section B,Section C",
      "B's initial section order lands server-side",
    );

    // 2. Device B reorders the SAME sections to [C, B, A] (same ids, permuted).
    expect(
      await apiPut(
        serverId,
        {
          sections: [
            sec("sec-c", "Section C"),
            sec("sec-b", "Section B"),
            sec("sec-a", "Section A"),
          ],
        },
        ordered.version,
      ),
    ).toBe(200);
    await waitForApi(
      serverId,
      (w) =>
        (w?.sections ?? []).map((s) => s.title).join(",") ===
        "Section C,Section B,Section A",
      "B's reorder lands server-side",
    );

    // 3. Device A converges to the reordered array (data layer).
    await waitForLocalA(
      page,
      (wss) => {
        const w = wss.find((x) => x.id === serverId);
        return (
          (w?.sections ?? []).map((s) => s.title).join(",") ===
          "Section C,Section B,Section A"
        );
      },
      "device A converges to device B's section reorder",
    );

    // 4. And device A RENDERS the sections in that array order (UI layer).
    await page.locator(".nav-item").filter({ hasText: name }).first().click();
    await expect
      .poll(
        async () =>
          (await page.locator(".section-title").allTextContents()).filter((t) =>
            ["Section A", "Section B", "Section C"].includes(t),
          ),
        {
          message: "device A renders sections in reordered order",
          timeout: 15000,
        },
      )
      .toEqual(["Section C", "Section B", "Section A"]);
    await page.close();
  });
});
