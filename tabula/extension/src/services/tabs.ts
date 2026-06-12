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
 * Tab management service for saving, restoring, and suspending tabs
 */

import type { Tab, TabGroup } from "../types";

export class TabService {
  /**
   * Get all tabs in the current window.
   * Maps Chrome's ephemeral groupId to stable TabGroup UUIDs when groups are provided.
   *
   * @param existingGroups - Tab groups to use for mapping Chrome groupIds to stable UUIDs
   */
  static async getCurrentTabs(
    existingGroups: TabGroup[] = [],
    windowId: number | undefined = undefined,
  ): Promise<Tab[]> {
    try {
      const tabs = await chrome.tabs.query(
        windowId !== undefined ? { windowId } : { currentWindow: true },
      );

      // Build a map of chromeGroupId -> stableGroupId for fast lookups
      const chromeToStableId = new Map<number, string>();
      existingGroups.forEach((g) => {
        if (g.chromeGroupId !== undefined) {
          chromeToStableId.set(g.chromeGroupId, g.id);
        }
      });

      // eslint-disable-next-line no-console
      console.log("[TabService.getCurrentTabs] Mapping info:", {
        tabCount: tabs.length,
        passedGroupsCount: existingGroups.length,
        mapSize: chromeToStableId.size,
        mapEntries: Array.from(chromeToStableId.entries()),
        sampleChromeGroupIds: tabs.slice(0, 5).map((t) => ({
          title: t.title?.substring(0, 15),
          chromeGroupId: t.groupId,
        })),
      });

      return tabs.map((tab) => {
        let title = "Untitled";
        if (tab.title && tab.title !== "Untitled") {
          title = tab.title;
        } else if (tab.url) {
          try {
            title = new URL(tab.url).hostname;
          } catch {
            // keep default
          }
        }

        // Map Chrome's ephemeral groupId to stable UUID if we have a matching group
        const chromeGroupId = tab.groupId !== -1 ? tab.groupId : undefined;
        const stableGroupId =
          chromeGroupId !== undefined
            ? chromeToStableId.get(chromeGroupId)
            : undefined;

        return {
          id: tab.id,
          url: tab.url || tab.pendingUrl || "",
          title,
          favIconUrl: tab.favIconUrl,
          pinned: tab.pinned,
          active: tab.active,
          index: tab.index,
          groupId: stableGroupId, // Stable UUID for persistence
          chromeGroupId, // Chrome's ephemeral ID for session tracking
        };
      });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to get current tabs:", error);
      return [];
    }
  }

  /**
   * Open tabs from a saved list.
   *
   * Returns the target window id and a `created` array aligned 1:1 with the
   * input `tabs` (null where a tab failed to open). Callers use this to (a)
   * restore groups by matching saved↔created by index without drift, and (b)
   * preserve tabs that failed to open instead of silently dropping them.
   */
  static async openTabs(
    tabs: Tab[],
    options: { inNewWindow?: boolean } = {},
  ): Promise<{ windowId?: number; created: (chrome.tabs.Tab | null)[] }> {
    try {
      const created: (chrome.tabs.Tab | null)[] = [];

      if (options.inNewWindow) {
        // Create new window with first tab
        const firstTab = tabs[0];
        if (!firstTab) return { windowId: undefined, created: [] };

        let newWindow: chrome.windows.Window;
        try {
          newWindow = await chrome.windows.create({
            url: firstTab.url,
            focused: true,
          });
          created.push(newWindow.tabs?.[0] ?? null);
        } catch (err) {
          // eslint-disable-next-line no-console
          console.warn(`Failed to open tab ${firstTab.url}:`, err);
          return { windowId: undefined, created: [null] };
        }

        // Open remaining tabs serially, recording success/failure per tab
        await tabs.slice(1).reduce(async (previousPromise, tab) => {
          await previousPromise;
          try {
            const t = await chrome.tabs.create({
              windowId: newWindow.id,
              url: tab.url,
              pinned: tab.pinned,
              active: tab.active || false,
            });
            created.push(t);
          } catch (err) {
            // eslint-disable-next-line no-console
            console.warn(`Failed to open tab ${tab.url}:`, err);
            created.push(null);
          }
        }, Promise.resolve());

        return { windowId: newWindow.id, created };
      }

      // Open in current window
      // Use serial execution to guarantee order and proper focus handling
      await tabs.reduce(async (previousPromise, tab) => {
        await previousPromise;
        try {
          const t = await chrome.tabs.create({
            url: tab.url,
            pinned: tab.pinned,
            active: tab.active || false,
          });
          created.push(t);
        } catch (err) {
          // eslint-disable-next-line no-console
          console.warn(`Failed to open tab ${tab.url}:`, err);
          created.push(null);
        }
      }, Promise.resolve());

      return { windowId: undefined, created };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to open tabs:", error);
      throw error;
    }
  }

  /*
   * Close all tabs in current window except pinned and extension pages
   */
  static async closeAllTabs(includePinned = false): Promise<void> {
    try {
      const tabs = await chrome.tabs.query({ currentWindow: true });
      const tabsToClose = tabs.filter((tab) => {
        // Don't close pinned tabs unless specified
        if (!includePinned && tab.pinned) return false;

        // Don't close extension pages (like the dashboard)
        if (tab.url && tab.url.startsWith("chrome-extension://")) return false;

        return !!tab.id;
      });

      const tabIds = tabsToClose
        .map((tab) => tab.id!)
        .filter((id) => typeof id === "number");

      if (tabIds.length > 0) {
        await chrome.tabs.remove(tabIds);
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to close tabs:", error);
      // Don't throw, just log
    }
  }

  /**
   * Suspend a tab (discard to save memory)
   */
  static async suspendTab(tabId: number): Promise<void> {
    try {
      await chrome.tabs.discard(tabId);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to suspend tab:", error);
      throw error;
    }
  }

  /**
   * Suspend all tabs except active and pinned
   */
  static async suspendInactiveTabs(): Promise<void> {
    try {
      const tabs = await chrome.tabs.query({
        currentWindow: true,
        pinned: false,
        active: false,
      });
      const suspendTasks = tabs
        .filter((tab) => tab.id && !tab.discarded)
        .map((tab) => this.suspendTab(tab.id!));
      await Promise.all(suspendTasks);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to suspend inactive tabs:", error);
      throw error;
    }
  }

  /**
   * Get memory usage statistics
   */
  static async getMemoryStats(): Promise<{
    totalTabs: number;
    suspendedTabs: number;
    activeTabs: number;
  }> {
    try {
      const tabs = await chrome.tabs.query({ currentWindow: true });
      const suspendedTabs = tabs.filter((tab) => tab.discarded).length;
      const activeTabs = tabs.length - suspendedTabs;
      return {
        totalTabs: tabs.length,
        suspendedTabs,
        activeTabs,
      };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to get memory stats:", error);
      return {
        totalTabs: 0,
        suspendedTabs: 0,
        activeTabs: 0,
      };
    }
  }

  /**
   * Close specific tabs by IDs
   */
  static async closeTabs(tabIds: (number | string)[]): Promise<void> {
    try {
      const validIds = tabIds
        .map((id) => (typeof id === "string" ? parseInt(id, 10) : id))
        .filter((id) => typeof id === "number" && !Number.isNaN(id));
      if (validIds.length > 0) {
        await chrome.tabs.remove(validIds);
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to close tabs:", error);
      // Don't throw to prevent UI crashes
    }
  }

  /**
   * Suspend multiple tabs by IDs
   */
  static async suspendTabs(tabIds: number[]): Promise<void> {
    try {
      const suspendTasks = tabIds.map((tabId) => this.suspendTab(tabId));
      await Promise.all(suspendTasks);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to suspend tabs:", error);
      throw error;
    }
  }

  /**
   * Pin or unpin tabs
   */
  static async setPinned(tabIds: number[], pinned: boolean): Promise<void> {
    try {
      const pinTasks = tabIds.map((tabId) =>
        chrome.tabs.update(tabId, { pinned }),
      );
      await Promise.all(pinTasks);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to pin/unpin tabs:", error);
      throw error;
    }
  }

  /**
   * Move a tab to a new position (for drag-and-drop reordering)
   */
  static async moveTab(
    tabId: number | string,
    newIndex: number,
  ): Promise<void> {
    try {
      const id = typeof tabId === "string" ? parseInt(tabId, 10) : tabId;
      if (
        typeof id !== "number" ||
        Number.isNaN(id) ||
        typeof newIndex !== "number"
      )
        return;
      await chrome.tabs.move(id, { index: newIndex });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to move tab:", error);
      // Suppress error to avoid breaking UI flow
    }
  }

  /**
   * Move a group of tabs to a new position (for drag-and-drop reordering)
   * Preserves group membership by re-grouping tabs after the move.
   */
  static async moveTabGroup(tabIds: number[], newIndex: number): Promise<void> {
    try {
      if (!tabIds?.length || typeof newIndex !== "number") return;

      // Get the current group ID from the first tab before moving
      const firstTab = await chrome.tabs.get(tabIds[0]);
      const originalGroupId = firstTab?.groupId;

      // Move all tabs to the new position
      await chrome.tabs.move(tabIds, { index: newIndex });

      // If the tabs were in a group, re-group them to preserve membership
      // chrome.tabs.move() can sometimes ungroup tabs, so we need to ensure they stay grouped
      if (originalGroupId && originalGroupId > 0) {
        // Re-add tabs to the same group to ensure they're still grouped together
        await chrome.tabs.group({ tabIds, groupId: originalGroupId });
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to move tab group:", error);
      // Suppress error to avoid breaking UI flow
    }
  }

  /**
   * Set the collapsed state of a Chrome tab group
   */
  static async setTabGroupCollapsed(
    groupId: number,
    collapsed: boolean,
  ): Promise<void> {
    try {
      await chrome.tabGroups.update(groupId, { collapsed });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to set tab group collapsed state:", error);
    }
  }

  /**
   * Add a tab to an existing Chrome tab group
   * @param tabId - The Chrome tab ID to add
   * @param chromeGroupId - The Chrome group ID to add the tab to
   */
  static async addTabToGroup(
    tabId: number,
    chromeGroupId: number,
  ): Promise<void> {
    try {
      await chrome.tabs.group({ tabIds: [tabId], groupId: chromeGroupId });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to add tab to group:", error);
    }
  }

  /**
   * Remove a tab from its current group (ungroup it)
   * @param tabId - The Chrome tab ID to ungroup
   */
  static async removeTabFromGroup(tabId: number): Promise<void> {
    try {
      await chrome.tabs.ungroup(tabId);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to remove tab from group:", error);
    }
  }

  /**
   * Get a specific tab by ID.
   * Note: Returns chromeGroupId only - use getCurrentTabs with groups for stable groupId mapping.
   */
  static async getTab(tabId: number | string): Promise<Tab | null> {
    try {
      const id = typeof tabId === "string" ? parseInt(tabId, 10) : tabId;
      if (Number.isNaN(id)) return null;

      const tab = await chrome.tabs.get(id);
      return {
        id: tab.id,
        url: tab.url || "",
        title: tab.title || "Untitled",
        favIconUrl: tab.favIconUrl,
        pinned: tab.pinned,
        index: tab.index,
        // Only store Chrome's ephemeral ID - stable mapping requires group context
        chromeGroupId: tab.groupId !== -1 ? tab.groupId : undefined,
      };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to get tab:", error);
      return null;
    }
  }

  /**
   * Duplicate a tab
   */
  static async duplicateTab(tabId: number): Promise<Tab | null> {
    try {
      const newTab = await chrome.tabs.duplicate(tabId);
      if (!newTab) return null;
      return {
        id: newTab.id,
        url: newTab.url || "",
        title: newTab.title || "Untitled",
        favIconUrl: newTab.favIconUrl,
        pinned: newTab.pinned,
        index: newTab.index,
      };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to duplicate tab:", error);
      return null;
    }
  }

  /**
   * Activate (focus) a specific tab
   */
  static async activateTab(tabId: number): Promise<void> {
    try {
      await chrome.tabs.update(tabId, { active: true });
      // Also invoke window focus just in case the tab is in a different window
      const tab = await chrome.tabs.get(tabId);
      if (tab.windowId) {
        await chrome.windows.update(tab.windowId, { focused: true });
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to activate tab:", error);
      throw error;
    }
  }

  /**
   * Generate a stable UUID for a tab group
   */
  private static generateTabGroupId(): string {
    const randomPart = Math.random().toString(36).substring(2, 11);
    return `tg_${Date.now()}_${randomPart}`;
  }

  /**
   * Get all tab groups in the current window.
   * Generates stable UUIDs for new groups, reuses existing UUIDs for matching groups.
   *
   * @param existingGroups - Previously saved groups to match against (for UUID reuse)
   */
  static async getCurrentTabGroups(
    existingGroups: TabGroup[] = [],
    windowId: number | undefined = undefined,
  ): Promise<TabGroup[]> {
    const result = await this.getCurrentTabGroupsResult(
      existingGroups,
      windowId,
    );
    return result.groups;
  }

  /**
   * Like getCurrentTabGroups, but distinguishes an authoritative "no groups"
   * result (reliable: true, groups: []) from a query failure / missing window
   * (reliable: false). Callers must NOT treat an unreliable empty result as a
   * real ungroup, or they'd resurrect stale stored groups (the ungroup wedge).
   */
  static async getCurrentTabGroupsResult(
    existingGroups: TabGroup[] = [],
    windowId: number | undefined = undefined,
  ): Promise<{ groups: TabGroup[]; reliable: boolean }> {
    try {
      // Use getCurrent() to get the window this extension page is in
      // This is more reliable than getAll() which can return a different window
      let targetWindowId = windowId;
      if (targetWindowId === undefined) {
        const currentWindow = await chrome.windows.getCurrent();
        if (!currentWindow?.id) {
          // eslint-disable-next-line no-console
          console.warn("[getCurrentTabGroups] No current window found");
          return { groups: [], reliable: false };
        }
        targetWindowId = currentWindow.id;
      }

      const chromeGroups = await chrome.tabGroups.query({
        windowId: targetWindowId,
      });

      // Build a map of chromeGroupId -> existingGroup for UUID reuse
      const existingByChrome = new Map<number, TabGroup>();
      existingGroups.forEach((g) => {
        if (g.chromeGroupId !== undefined) {
          existingByChrome.set(g.chromeGroupId, g);
        }
      });

      const groups = chromeGroups.map((group) => {
        // Try to find an existing group with the same Chrome ID (session continuity)
        const existing = existingByChrome.get(group.id);

        return {
          id: existing?.id || this.generateTabGroupId(), // Reuse existing UUID or generate new
          chromeGroupId: group.id, // Store Chrome's ephemeral ID for session tracking
          title: group.title,
          color: group.color,
          collapsed: group.collapsed,
        };
      });
      return { groups, reliable: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to get current tab groups:", error);
      return { groups: [], reliable: false };
    }
  }

  /**
   * Readiness probe for the initial post-load tab sync.
   *
   * On a soft refresh (Cmd+R) Chrome briefly reports `groupId: -1` for tabs
   * that ARE grouped, while `tabGroups.query()` already lists the groups. A
   * sync in that window would capture groups with no members and drop the
   * tab/group associations (the bug useTabSync used to dodge with a blind
   * 500ms delay). This returns true once the two APIs agree — either there are
   * no groups, or at least one tab has been assigned a real groupId — so the
   * caller can wait on the actual condition instead of guessing at timing.
   *
   * Query failures resolve to `true` (don't wedge startup): syncTabs has its
   * own guards against persisting an inconsistent snapshot.
   */
  static async areTabGroupsConsistent(
    windowId: number | undefined = undefined,
  ): Promise<boolean> {
    try {
      let targetWindowId = windowId;
      if (targetWindowId === undefined) {
        const currentWindow = await chrome.windows.getCurrent();
        if (!currentWindow?.id) return true;
        targetWindowId = currentWindow.id;
      }

      const [groups, tabs] = await Promise.all([
        chrome.tabGroups.query({ windowId: targetWindowId }),
        chrome.tabs.query({ windowId: targetWindowId }),
      ]);

      // No groups -> nothing to wait for. Chrome never keeps empty groups, so
      // groups.length > 0 means at least one tab should report a real groupId
      // once membership has been assigned.
      if (groups.length === 0) return true;
      return tabs.some((t) => t.groupId !== undefined && t.groupId !== -1);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to probe tab group consistency:", error);
      return true;
    }
  }

  /**
   * Restore tab groups after opening tabs.
   * This recreates groups based on saved metadata and groups tabs by their stable groupId (UUID).
   *
   * @param savedTabs - The original tabs with stable groupId associations (UUIDs)
   * @param savedGroups - The group metadata (id is stable UUID, title, color, collapsed)
   * @param newTabs - The newly created tabs (matched by position to savedTabs)
   */
  /**
   * Restore tab groups using the exact tabs created by openTabs (aligned 1:1
   * with savedTabs by index, null where a tab failed to open). This avoids the
   * index drift of position-matching against a re-query, which mis-assigns
   * groups whenever any tab fails to open.
   */
  static async restoreTabGroupsFromCreated(
    savedTabs: Tab[],
    savedGroups: TabGroup[],
    createdTabs: (chrome.tabs.Tab | null)[],
  ): Promise<void> {
    try {
      const groupMetadataMap = new Map<string, TabGroup>();
      savedGroups.forEach((group) => groupMetadataMap.set(group.id, group));

      const stableIdToTabIds = new Map<string, number[]>();
      savedTabs.forEach((savedTab, index) => {
        if (!savedTab.groupId) return;
        const created = createdTabs[index];
        if (created?.id) {
          const existing = stableIdToTabIds.get(savedTab.groupId) || [];
          existing.push(created.id);
          stableIdToTabIds.set(savedTab.groupId, existing);
        }
      });

      const groupEntries = Array.from(stableIdToTabIds.entries());
      await groupEntries.reduce(
        async (previousPromise, [stableGroupId, tabIds]) => {
          await previousPromise;
          if (tabIds.length === 0) return;
          const metadata = groupMetadataMap.get(stableGroupId);
          if (!metadata) return;
          const newChromeGroupId = await chrome.tabs.group({ tabIds });
          await chrome.tabGroups.update(newChromeGroupId, {
            title: metadata.title,
            color: metadata.color as chrome.tabGroups.ColorEnum,
            collapsed: metadata.collapsed,
          });
        },
        Promise.resolve(),
      );
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to restore tab groups:", error);
      // Don't throw - tab groups are a nice-to-have, not critical
    }
  }

  static async restoreTabGroups(
    savedTabs: Tab[],
    savedGroups: TabGroup[],
    newTabs: chrome.tabs.Tab[],
  ): Promise<void> {
    try {
      // eslint-disable-next-line no-console
      console.log("[restoreTabGroups] Starting with:", {
        savedTabsCount: savedTabs.length,
        savedGroupsCount: savedGroups.length,
        newTabsCount: newTabs.length,
      });

      // Build a map of stable groupId (UUID) -> group metadata
      const groupMetadataMap = new Map<string, TabGroup>();
      savedGroups.forEach((group) => {
        groupMetadataMap.set(group.id, group);
      });

      // eslint-disable-next-line no-console
      console.log(
        "[restoreTabGroups] Saved tabs with groupIds:",
        savedTabs
          .filter((t) => t.groupId)
          .map((t) => ({ url: t.url, groupId: t.groupId })),
      );

      // Filter newTabs to exclude extension pages and pinned tabs
      // (these are the tabs we actually opened)
      const relevantNewTabs = newTabs.filter(
        (t) => !t.pinned && !t.url?.startsWith("chrome-extension://"),
      );

      // eslint-disable-next-line no-console
      console.log(
        "[restoreTabGroups] Relevant new Chrome tabs:",
        relevantNewTabs.map((t) => ({
          id: t.id,
          url: t.url,
          status: t.status,
          index: t.index,
        })),
      );

      // Use POSITION-BASED matching since openTabs creates tabs in order
      // savedTabs[i] corresponds to relevantNewTabs[i]
      // Map stable groupId (UUID) -> Chrome tab IDs to group
      const stableIdToTabIds = new Map<string, number[]>();

      savedTabs.forEach((savedTab, index) => {
        if (!savedTab.groupId) return;

        // Match by position - savedTabs[index] maps to relevantNewTabs[index]
        const newTab = relevantNewTabs[index];
        if (newTab?.id) {
          const existing = stableIdToTabIds.get(savedTab.groupId) || [];
          existing.push(newTab.id);
          stableIdToTabIds.set(savedTab.groupId, existing);
          // eslint-disable-next-line no-console
          console.log(
            `[restoreTabGroups] Matched savedTab[${index}] (groupId=${savedTab.groupId}) to newTab ${newTab.id}`,
          );
        } else {
          // eslint-disable-next-line no-console
          console.log(
            `[restoreTabGroups] No newTab at index ${index} for savedTab with groupId=${savedTab.groupId}`,
          );
        }
      });

      // eslint-disable-next-line no-console
      console.log(
        "[restoreTabGroups] Groups to restore:",
        Array.from(stableIdToTabIds.entries()).map(([gid, tids]) => ({
          stableGroupId: gid,
          tabIds: tids,
          metadata: groupMetadataMap.get(gid),
        })),
      );

      // Create groups and apply metadata
      // Use serial reduce pattern to avoid eslint no-await-in-loop
      const groupEntries = Array.from(stableIdToTabIds.entries());
      await groupEntries.reduce(
        async (previousPromise, [stableGroupId, tabIds]) => {
          await previousPromise;
          if (tabIds.length === 0) return;

          const metadata = groupMetadataMap.get(stableGroupId);
          if (!metadata) return;

          // Create the group with all tabs at once
          // eslint-disable-next-line no-console
          console.log(
            "[restoreTabGroups] Creating group with tabIds:",
            tabIds,
            "metadata:",
            metadata,
          );
          const newChromeGroupId = await chrome.tabs.group({ tabIds });

          // Apply the saved metadata (title, color, collapsed)
          await chrome.tabGroups.update(newChromeGroupId, {
            title: metadata.title,
            color: metadata.color as chrome.tabGroups.ColorEnum,
            collapsed: metadata.collapsed,
          });
          // eslint-disable-next-line no-console
          console.log(
            "[restoreTabGroups] Created group:",
            newChromeGroupId,
            "with title:",
            metadata.title,
          );
        },
        Promise.resolve(),
      );

      // eslint-disable-next-line no-console
      console.log("[restoreTabGroups] Completed");
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to restore tab groups:", error);
      // Don't throw - tab groups are a nice-to-have, not critical
    }
  }
}
