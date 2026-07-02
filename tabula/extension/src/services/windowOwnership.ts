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
 * Window Ownership Service
 *
 * Tracks which browser window currently "owns" each workspace.
 * Only one window can be the active owner for a workspace at a time.
 * This enables conflict resolution when multiple windows try to open the same workspace.
 *
 * Lifecycle: records live in chrome.storage.local and are cleaned up by the
 * background worker on window close (chrome.windows.onRemoved) and wiped on
 * browser startup (window IDs from a previous session are meaningless and may
 * be recycled, which would otherwise cause false conflicts).
 */

import { crossWindowSync } from "./CrossWindowSyncService";

export interface WindowOwnershipRecord {
  workspaceId: string;
  windowId: number;
  tabId: number; // Dashboard tab ID
  lastActive: number; // Timestamp
}

export type ClaimResult =
  { claimed: true } | { claimed: false; owner: WindowOwnershipRecord };

const STORAGE_KEY = "tabula_window_ownership";
const LOCK_NAME = "tabula_ownership_lock";

/**
 * Run a callback under the ownership lock. Falls back to direct execution in
 * environments without the Web Locks API.
 */
async function withLock<T>(callback: () => Promise<T>): Promise<T> {
  if (typeof navigator !== "undefined" && "locks" in navigator) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return (navigator as any).locks.request(LOCK_NAME, callback);
  }
  return callback();
}

/**
 * Get all active window ownership records
 */
export async function getWindowOwnership(): Promise<WindowOwnershipRecord[]> {
  const result = await chrome.storage.local.get(STORAGE_KEY);
  return (result[STORAGE_KEY] as WindowOwnershipRecord[] | undefined) || [];
}

/**
 * Get ownership record for a specific workspace
 */
export async function getWorkspaceOwner(
  workspaceId: string,
): Promise<WindowOwnershipRecord | null> {
  const records = await getWindowOwnership();
  return records.find((r) => r.workspaceId === workspaceId) || null;
}

/**
 * Clear ownership for a specific workspace.
 *
 * When releasedWindowId is provided, only the record held by THAT window is
 * removed (a fresh claim by a third window stays intact) and a RELEASE is
 * broadcast attributed to that window. Without it, the clear is unconditional
 * and nothing is broadcast (we'd only be guessing the owner).
 */
export async function clearWorkspaceOwnership(
  workspaceId: string,
  releasedWindowId?: number,
): Promise<void> {
  await withLock(async () => {
    const records = await getWindowOwnership();
    const filtered =
      releasedWindowId !== undefined
        ? records.filter(
            (r) =>
              !(
                r.workspaceId === workspaceId && r.windowId === releasedWindowId
              ),
          )
        : records.filter((r) => r.workspaceId !== workspaceId);
    await chrome.storage.local.set({ [STORAGE_KEY]: filtered });
  });

  if (releasedWindowId !== undefined) {
    crossWindowSync.broadcastRelease(workspaceId, releasedWindowId);
  }
}

/**
 * Check if a workspace is owned by another window (not the current one)
 */
export async function isWorkspaceOwnedByOtherWindow(
  workspaceId: string,
  currentWindowId: number,
): Promise<WindowOwnershipRecord | null> {
  const owner = await getWorkspaceOwner(workspaceId);
  if (owner && owner.windowId !== currentWindowId) {
    // Verify the window still exists
    try {
      await chrome.windows.get(owner.windowId);
      return owner; // Window exists, conflict detected
    } catch {
      // Window no longer exists, clean up the stale record (attributed to the
      // dead owner so other windows can clear their lockout state)
      await clearWorkspaceOwnership(workspaceId, owner.windowId);
      return null;
    }
  }
  return null;
}

/**
 * Atomically check-and-claim ownership of a workspace.
 *
 * The liveness check and the claim happen inside one lock acquisition, so two
 * windows racing to switch to the same workspace cannot both succeed (the
 * loser gets the winner's record back for the conflict popover).
 */
export async function tryClaimWorkspace(
  workspaceId: string,
  windowId: number,
  tabId: number,
): Promise<ClaimResult> {
  let displaced: WindowOwnershipRecord[] = [];

  const result = await withLock(async (): Promise<ClaimResult> => {
    const records = await getWindowOwnership();
    const owner = records.find((r) => r.workspaceId === workspaceId);

    if (owner && owner.windowId !== windowId) {
      // Live foreign owner blocks the claim; a dead one is displaced below
      try {
        await chrome.windows.get(owner.windowId);
        return { claimed: false, owner };
      } catch {
        // Owner window is gone — fall through and take over
      }
    }

    // Records this write displaces: this window's previous workspace(s) and
    // any (dead) owner of the target workspace
    displaced = records.filter(
      (r) =>
        (r.windowId === windowId && r.workspaceId !== workspaceId) ||
        (r.workspaceId === workspaceId && r.windowId !== windowId),
    );

    const filtered = records.filter(
      (r) => r.workspaceId !== workspaceId && r.windowId !== windowId,
    );
    filtered.push({ workspaceId, windowId, tabId, lastActive: Date.now() });
    await chrome.storage.local.set({ [STORAGE_KEY]: filtered });
    return { claimed: true };
  });

  if (result.claimed) {
    // Broadcasts happen outside the lock; CLAIM first so lockouts engage
    crossWindowSync.broadcastClaim(workspaceId, windowId, tabId);
    displaced.forEach((r) =>
      crossWindowSync.broadcastRelease(r.workspaceId, r.windowId),
    );
  }
  return result;
}

/**
 * Register ownership of a workspace for the current window (take-over
 * semantics — used by the conflict popover's explicit "move tabs here" flow
 * and as an idempotent refresh after a successful switch).
 */
export async function registerWorkspaceOwnership(
  workspaceId: string,
  windowId: number,
  tabId: number,
): Promise<void> {
  let displaced: WindowOwnershipRecord[] = [];

  // Use Web Locks API to ensure atomic read-modify-write
  await withLock(async () => {
    const records = await getWindowOwnership();

    // Records this write displaces (so their windows can observe the release):
    // this window's previous workspace(s) and the target's previous owner
    displaced = records.filter(
      (r) =>
        (r.windowId === windowId && r.workspaceId !== workspaceId) ||
        (r.workspaceId === workspaceId && r.windowId !== windowId),
    );

    // Remove any existing ownership for this workspace OR this window
    // Enforces: 1 Window = 1 Active Workspace
    // Also ensures we claim the workspace from any previous owner
    const filtered = records.filter(
      (r) => r.workspaceId !== workspaceId && r.windowId !== windowId,
    );

    // Add new ownership record
    filtered.push({
      workspaceId,
      windowId,
      tabId,
      lastActive: Date.now(),
    });

    await chrome.storage.local.set({ [STORAGE_KEY]: filtered });
  });

  // Broadcast instant claim to other windows (outside the lock)
  crossWindowSync.broadcastClaim(workspaceId, windowId, tabId);
  // And releases for whatever this claim displaced, so locked-out windows
  // holding those workspaces can re-enable their sync
  displaced.forEach((r) =>
    crossWindowSync.broadcastRelease(r.workspaceId, r.windowId),
  );
}

/**
 * Clear all ownership records for a specific window (on window close)
 */
export async function clearWindowOwnership(windowId: number): Promise<void> {
  let released: WindowOwnershipRecord[] = [];

  await withLock(async () => {
    const records = await getWindowOwnership();
    released = records.filter((r) => r.windowId === windowId);
    const filtered = records.filter((r) => r.windowId !== windowId);
    await chrome.storage.local.set({ [STORAGE_KEY]: filtered });
  });

  // Tell surviving windows these workspaces are free again
  released.forEach((r) =>
    crossWindowSync.broadcastRelease(r.workspaceId, windowId),
  );
}

/**
 * Wipe all ownership records. Called on browser startup: window IDs from the
 * previous session are dead and may be recycled by new windows, so stale
 * records would cause false conflicts or wrong-window tab moves.
 */
export async function clearAllWindowOwnership(): Promise<void> {
  await withLock(async () => {
    await chrome.storage.local.remove(STORAGE_KEY);
  });
}

/**
 * Update last active timestamp for a workspace
 */
export async function updateOwnershipActivity(
  workspaceId: string,
): Promise<void> {
  await withLock(async () => {
    const records = await getWindowOwnership();
    const record = records.find((r) => r.workspaceId === workspaceId);
    if (record) {
      record.lastActive = Date.now();
      await chrome.storage.local.set({ [STORAGE_KEY]: records });
    }
  });
}

/**
 * Get tabs from a window that owns a workspace
 * Returns the tabs to display in the conflict popover
 */
export async function getOwnerWindowTabs(
  ownerRecord: WindowOwnershipRecord,
): Promise<chrome.tabs.Tab[]> {
  try {
    const tabs = await chrome.tabs.query({ windowId: ownerRecord.windowId });
    // Filter out the dashboard tab itself AND pinned tabs
    const filtered = tabs.filter(
      (tab) => tab.id !== ownerRecord.tabId && !tab.pinned,
    );
    return filtered;
  } catch {
    return [];
  }
}

/**
 * Focus the window that owns a workspace ("Go to window" action)
 */
export async function focusOwnerWindow(
  ownerRecord: WindowOwnershipRecord,
): Promise<void> {
  await chrome.windows.update(ownerRecord.windowId, { focused: true });
  // Also focus the dashboard tab
  if (ownerRecord.tabId) {
    await chrome.tabs.update(ownerRecord.tabId, { active: true });
  }
}

/**
 * Move tabs from owner window to current window
 */
export async function moveTabsToCurrentWindow(
  tabIds: number[],
  currentWindowId: number,
): Promise<void> {
  if (tabIds.length === 0) return;
  await chrome.tabs.move(tabIds, { windowId: currentWindowId, index: -1 });
}

export const WindowOwnershipService = {
  getWindowOwnership,
  getWorkspaceOwner,
  isWorkspaceOwnedByOtherWindow,
  tryClaimWorkspace,
  registerWorkspaceOwnership,
  clearWorkspaceOwnership,
  clearWindowOwnership,
  clearAllWindowOwnership,
  updateOwnershipActivity,
  getOwnerWindowTabs,
  focusOwnerWindow,
  moveTabsToCurrentWindow,
};
