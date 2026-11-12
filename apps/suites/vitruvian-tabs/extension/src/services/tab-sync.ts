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
 * TabSyncService - Unified Sync Layer for Tab Mutations
 *
 * This service centralizes all tab/group mutations to ensure consistent
 * bidirectional sync between Chrome and workspace state.
 *
 * Key principle: All Dashboard actions call Chrome APIs first.
 * Chrome events (handled by useTabSync) then update workspace state.
 *
 * Flow:
 *   Dashboard Action → TabSyncService.method() → Chrome API
 *                   → Chrome Event fires → useTabSync.syncTabs()
 *                   → Workspace state updated → UI re-renders
 */

import { TabService } from "./tabs";

export class TabSyncService {
  /**
   * Move a tab to a new position.
   * Called from Dashboard drag handlers.
   *
   * @param tabId - The Chrome tab ID to move
   * @param newIndex - The new position index
   */
  static async moveTab(tabId: number, newIndex: number): Promise<void> {
    // Call Chrome API - the event will trigger workspace update via useTabSync
    await TabService.moveTab(tabId, newIndex);
  }

  /**
   * Add a tab to an existing group.
   * Called from Dashboard drag handlers when dropping onto a grouped tab or group header.
   *
   * @param tabId - The Chrome tab ID to add to the group
   * @param chromeGroupId - The Chrome group ID to add the tab to
   */
  static async addTabToGroup(
    tabId: number,
    chromeGroupId: number,
  ): Promise<void> {
    // Call Chrome API - the event will trigger workspace update via useTabSync
    await TabService.addTabToGroup(tabId, chromeGroupId);
  }

  /**
   * Remove a tab from its group.
   * Called from Dashboard drag handlers when dropping onto an ungrouped area.
   *
   * @param tabId - The Chrome tab ID to remove from its group
   */
  static async removeTabFromGroup(tabId: number): Promise<void> {
    // Call Chrome API - the event will trigger workspace update via useTabSync
    await TabService.removeTabFromGroup(tabId);
  }

  /**
   * Close a tab.
   * Called from Dashboard when user closes a tab.
   *
   * @param tabId - The Chrome tab ID to close
   */
  static async closeTab(tabId: number): Promise<void> {
    await TabService.closeTabs([tabId]);
  }

  /**
   * Move all tabs in a group to a new position.
   * Called from Dashboard when dragging group headers.
   *
   * @param tabIds - The Chrome tab IDs in the group
   * @param newIndex - The new position index for the group
   */
  static async moveTabGroup(tabIds: number[], newIndex: number): Promise<void> {
    await TabService.moveTabGroup(tabIds, newIndex);
  }

  /**
   * Set the collapsed state of a tab group.
   * Called from Dashboard when user expands/collapses a group.
   *
   * @param chromeGroupId - The Chrome group ID
   * @param collapsed - Whether the group should be collapsed
   */
  static async setTabGroupCollapsed(
    chromeGroupId: number,
    collapsed: boolean,
  ): Promise<void> {
    await TabService.setTabGroupCollapsed(chromeGroupId, collapsed);
  }

  /**
   * Activate a tab (bring it to focus).
   * Called from Dashboard when user clicks to focus a tab.
   *
   * @param tabId - The Chrome tab ID to activate
   */
  static async activateTab(tabId: number): Promise<void> {
    await TabService.activateTab(tabId);
  }

  /**
   * Pin or unpin tabs.
   * Called from Dashboard context menu.
   *
   * @param tabIds - The Chrome tab IDs to pin/unpin
   * @param pinned - Whether to pin or unpin
   */
  static async setPinned(tabIds: number[], pinned: boolean): Promise<void> {
    await TabService.setPinned(tabIds, pinned);
  }

  /**
   * Duplicate a tab.
   * Called from Dashboard context menu.
   *
   * @param tabId - The Chrome tab ID to duplicate
   */
  static async duplicateTab(tabId: number): Promise<void> {
    await TabService.duplicateTab(tabId);
  }
}
