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

import { useEffect, useCallback, useRef } from "react";
import type { Workspace } from "../types";
import { TabService } from "../services/tabs";
import { WorkspaceService } from "../services/workspace";
import { WindowOwnershipService } from "../services/windowOwnership";
import { crossWindowSync } from "../services/CrossWindowSyncService";
import { getDeviceId } from "../services/deviceId";
import { useLatest } from "./useLatest";

/**
 * How long another device's active-device lease is honored after its last
 * tab-sync save. Within this window we treat the workspace as "live
 * elsewhere" and pause our own automatic tab capture; an explicit switch
 * (claimActiveDevice) takes the lease over.
 */
export const ACTIVE_DEVICE_STALE_MS = 2 * 60 * 1000;

/**
 * Startup readiness poll cadence and bound (replaces the old blind 500ms
 * delay). We poll Chrome's tab/group consistency every INIT_SYNC_POLL_MS and
 * give up waiting after INIT_SYNC_MAX_WAIT_MS, after which the initial sync
 * runs anyway — syncTabs' own "groups detected but no groupIds yet" guard keeps
 * a still-inconsistent snapshot from being persisted.
 */
const INIT_SYNC_POLL_MS = 50;
const INIT_SYNC_MAX_WAIT_MS = 2000;

interface UseTabSyncOptions {
  /** Ref to current workspace - prevents stale closure issues */
  activeWorkspaceRef: React.RefObject<Workspace | null>;
  /** Ref to track if currently switching workspaces */
  isSwitchingRef: React.RefObject<boolean>;
  /** State setter for active workspace */
  setActiveWorkspaceData: (workspace: Workspace) => void;
  /** Whether tab sync is enabled */
  enabled?: boolean;
  /** Debounce delay in ms */
  debounceMs?: number;
  /** Current window ID for ownership verification */
  currentWindowId?: number;
  /**
   * The workspace id this window intends to sync (drives the ownership-lost
   * reset; refs can't be effect dependencies)
   */
  activeWorkspaceId?: string | null;
}

/**
 * Hook to synchronize browser tabs with workspace state.
 *
 * Key design decisions:
 * 1. Uses refs for workspace state to avoid stale closures in event handlers
 * 2. Updates local state immediately, then persists to storage (optimistic update)
 * 3. Respects isSwitchingRef to prevent sync during workspace transitions
 * 4. All browser tabs belong to the current workspace while it's active
 * 5. Also syncs Chrome Tab Groups for preservation across workspace switches
 */
export const useTabSync = ({
  activeWorkspaceRef,
  isSwitchingRef,
  setActiveWorkspaceData,
  enabled = true,
  debounceMs = 100,
  currentWindowId,
  activeWorkspaceId,
}: UseTabSyncOptions) => {
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );
  const initPollRef = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );
  const isSyncingRef = useRef(false);
  const ownershipLostRef = useRef(false);
  // syncTabs is memoized once (its deps are all referentially stable), so the
  // window id must be read through a ref or the guard would forever see the
  // pre-mount undefined value and silently disable itself.
  const currentWindowIdRef = useLatest(currentWindowId);

  // Reset ownership lost flag when this window's intended workspace changes
  useEffect(() => {
    ownershipLostRef.current = false;
  }, [activeWorkspaceId]);

  // Listen for ownership claims/releases from other windows to instantly
  // lock/unlock sync (faster than waiting for a storage round-trip)
  useEffect(() => {
    if (!currentWindowId || !enabled) return undefined;

    const unsubscribe = crossWindowSync.subscribe((msg) => {
      if (
        msg.type === "CLAIM_WORKSPACE" &&
        activeWorkspaceRef.current?.id === msg.workspaceId
      ) {
        // If another window claims our active workspace, lock us out immediately
        // This is faster than waiting for storage update
        if (msg.windowId !== currentWindowId) {
          // eslint-disable-next-line no-console
          console.log(
            "[useTabSync] Locked out by broadcast active claim from:",
            msg.windowId,
          );
          ownershipLostRef.current = true;
          // Cancel any pending debounced sync
          clearTimeout(timeoutRef.current);
        }
      }
      if (
        msg.type === "RELEASE_WORKSPACE" &&
        activeWorkspaceRef.current?.id === msg.workspaceId
      ) {
        // Our workspace was released by its (former) owner — sync may resume.
        // syncTabs still re-validates against storage before writing.
        if (msg.windowId !== currentWindowId && ownershipLostRef.current) {
          // eslint-disable-next-line no-console
          console.log(
            "[useTabSync] Lockout cleared by release from:",
            msg.windowId,
          );
          ownershipLostRef.current = false;
        }
      }
    });
    return unsubscribe;
  }, [currentWindowId, enabled, activeWorkspaceRef]);

  /**
   * Sync current browser tabs and tab groups to workspace state.
   * This captures ALL current browser tabs as belonging to the active workspace.
   */
  const syncTabs = useCallback(async () => {
    // Check if we're in the force-remote window (after backup restore)
    // If so, skip sync to preserve restored data
    const forceRemoteResult = await chrome.storage.local.get(
      "tabula_force_remote_until",
    );
    const forceRemoteUntil = forceRemoteResult.tabula_force_remote_until as
      number | undefined;
    if (forceRemoteUntil && Date.now() < forceRemoteUntil) {
      // eslint-disable-next-line no-console
      console.log(
        "[useTabSync.syncTabs] Skipping - force-remote active after restore",
      );
      return;
    }

    // Prevent concurrent syncs - wait for previous sync to complete
    if (isSyncingRef.current) {
      // eslint-disable-next-line no-console
      console.log("[useTabSync.syncTabs] Skipping - sync already in progress");
      return;
    }

    const currentWorkspace = activeWorkspaceRef.current;
    const workspaceId = currentWorkspace?.id;
    if (!workspaceId || isSwitchingRef.current) return;

    // Guard: Only the window that OWNS the workspace should sync tabs.
    // This prevents race conditions where a window losing tabs (because they were moved to another window)
    // attempts to sync "empty state" and overwrites the valid state from the new owner.
    // Fail closed: until the window id resolves we cannot prove ownership, so
    // we must not write.
    const windowId = currentWindowIdRef.current;
    if (windowId == null) {
      // eslint-disable-next-line no-console
      console.log(
        "[useTabSync.syncTabs] Skipping - window id not resolved yet",
      );
      return;
    }

    // Authoritative ownership check (verifies the owner window is alive and
    // self-cleans stale records). The broadcast ref is a fast-path cache; the
    // storage check both confirms a suspected lockout and heals a stale one.
    const foreignOwner =
      await WindowOwnershipService.isWorkspaceOwnedByOtherWindow(
        workspaceId,
        windowId,
      );
    if (foreignOwner) {
      // eslint-disable-next-line no-console
      console.log(
        "[useTabSync.syncTabs] Skipping - workspace owned by another window:",
        foreignOwner.windowId,
      );
      ownershipLostRef.current = true; // Cache the loss
      return;
    }
    if (ownershipLostRef.current) {
      // No live foreign owner — the lockout is stale, clear it and proceed
      // eslint-disable-next-line no-console
      console.log("[useTabSync.syncTabs] Lockout was stale - resuming sync");
      ownershipLostRef.current = false;
    }

    // Set the sync lock
    isSyncingRef.current = true;

    try {
      // ALWAYS read existing tab groups from storage first to preserve stable UUIDs
      // React state may be empty on page load, but storage has the persisted data
      const storedWorkspace =
        await WorkspaceService.getWorkspaceById(workspaceId);
      const storedTabGroups = storedWorkspace?.tabGroups || [];
      const storedTabs = storedWorkspace?.tabs || [];

      // Cross-device gate: window ownership is per-profile and cannot protect
      // against ANOTHER LAPTOP live-syncing the same workspace. The server
      // maintains an advisory active-device lease (renewed by tab-sync saves,
      // taken over by explicit switches). If another device holds a fresh
      // lease, pause our automatic capture instead of fighting it write-for-
      // write — otherwise the two devices clobber each other's tabs forever.
      if (
        storedWorkspace?.activeDeviceId &&
        storedWorkspace.activeDeviceSeenAt
      ) {
        const deviceId = await getDeviceId();
        const seenAt = new Date(storedWorkspace.activeDeviceSeenAt).getTime();
        const leaseFresh = Date.now() - seenAt < ACTIVE_DEVICE_STALE_MS;
        if (storedWorkspace.activeDeviceId !== deviceId && leaseFresh) {
          // eslint-disable-next-line no-console
          console.log(
            "[useTabSync.syncTabs] Skipping - workspace is live on another device:",
            storedWorkspace.activeDeviceId,
          );
          return;
        }
      }

      // Fall back to React state only if storage is empty
      const existingGroups =
        storedTabGroups.length > 0
          ? storedTabGroups
          : currentWorkspace.tabGroups || [];

      // eslint-disable-next-line no-console
      console.log("[useTabSync.syncTabs] Existing groups:", {
        fromStorage: storedTabGroups.length,
        fromReactState: currentWorkspace.tabGroups?.length || 0,
        using: existingGroups.length,
      });

      // Get current tab groups from Chrome (reusing existing UUIDs when possible).
      // `reliable` distinguishes a genuine "no groups" from a failed query — the
      // difference between persisting a real ungroup and wedging sync forever.
      const { groups: currentTabGroups, reliable: groupsReliable } =
        await TabService.getCurrentTabGroupsResult(existingGroups);

      // Get current browser tabs and filter out pinned tabs and extension pages
      // Pass groups so tabs can be mapped to stable group UUIDs
      const currentTabs = await TabService.getCurrentTabs(currentTabGroups);

      // Build a URL->groupId map from stored tabs for recovery
      const storedGroupIdByUrl = new Map<string, string>();
      storedTabs.forEach((t) => {
        if (t.groupId && t.url) {
          storedGroupIdByUrl.set(t.url, t.groupId);
        }
      });

      // Track how many tabs had their groupId preserved from storage
      let preservedGroupIdCount = 0;

      // Build a set of stored tab URLs for fast lookup
      const storedTabUrls = new Set(
        storedTabs.map((t) => t.url).filter(Boolean),
      );

      // Preserve groupId from stored tabs ONLY for brand new tabs (not in storage yet)
      // This handles the race where Chrome's tabs API returns groupId: -1 temporarily
      // for a NEW tab. But if the tab URL was already in storage, Chrome's current state
      // takes precedence - this ensures ungrouped tabs lose their groupId.
      const tabsWithPreservedGroups = currentTabs.map((tab) => {
        const isNewTab = tab.url && !storedTabUrls.has(tab.url);
        if (
          !tab.groupId &&
          tab.url &&
          storedGroupIdByUrl.has(tab.url) &&
          isNewTab
        ) {
          preservedGroupIdCount += 1;
          return { ...tab, groupId: storedGroupIdByUrl.get(tab.url) };
        }
        return tab;
      });

      const cleanTabs = tabsWithPreservedGroups.filter(
        (tab) => !tab.pinned && !tab.url.startsWith("chrome-extension://"),
      );

      // eslint-disable-next-line no-console
      console.log("[useTabSync.syncTabs] Syncing:", {
        workspaceId,
        numTabs: cleanTabs.length,
        numTabGroups: currentTabGroups.length,
        existingTabGroups: existingGroups.length,
        preservedGroupIdCount,
      });

      // CRITICAL: If we preserved groupIds from stored tabs, we MUST use the stored groups
      // to ensure the IDs match. Otherwise tabs have old IDs but groups have new IDs.
      let tabGroupsToSave = currentTabGroups;
      if (preservedGroupIdCount > 0 && storedTabGroups.length > 0) {
        // Use stored groups when we preserved stored groupIds
        tabGroupsToSave = storedTabGroups;
      } else if (
        currentTabGroups.length === 0 &&
        !groupsReliable &&
        existingGroups.length > 0
      ) {
        // Only resurrect stored groups when the Chrome query was UNRELIABLE.
        // An authoritative empty result means the user really ungrouped all
        // tabs and must be persisted as [] (otherwise sync wedges forever).
        tabGroupsToSave = existingGroups;
      }

      // eslint-disable-next-line no-console
      console.log("[useTabSync.syncTabs] Using tabGroups:", {
        fromApi: currentTabGroups.length,
        preserving: currentTabGroups.length === 0 && existingGroups.length > 0,
        finalCount: tabGroupsToSave.length,
        groupDetails: tabGroupsToSave.map((g) => ({
          id: g.id,
          chromeId: g.chromeGroupId,
          title: g.title,
        })),
      });

      // eslint-disable-next-line no-console
      console.log("[useTabSync.syncTabs] Tab groupIds:", {
        tabsWithGroups: cleanTabs.filter((t) => t.groupId).length,
        sampleTabs: cleanTabs.slice(0, 3).map((t) => ({
          id: t.id,
          title: t.title?.substring(0, 20),
          groupId: t.groupId,
        })),
      });

      // Defensive: If CHROME currently reports groups but no tab claims
      // membership, Chrome hasn't finished assigning tabs to groups yet — skip
      // and wait for handleTabUpdate. Test currentTabGroups (the live Chrome
      // result), NOT tabGroupsToSave: a stale resurrected/preserved group must
      // not block persisting a genuine ungroup (matches the sibling guard in
      // WorkspaceService._saveCurrentTabsToWorkspace).
      const tabsWithGroupIds = cleanTabs.filter((t) => t.groupId).length;
      if (currentTabGroups.length > 0 && tabsWithGroupIds === 0) {
        // eslint-disable-next-line no-console
        console.log(
          "[useTabSync.syncTabs] Skipping - groups detected but tabs have no groupIds yet",
        );
        return;
      }

      // Re-validate at the write point: a lockout broadcast or a workspace
      // switch may have landed while we were awaiting the Chrome APIs above.
      if (ownershipLostRef.current || isSwitchingRef.current) {
        // eslint-disable-next-line no-console
        console.log(
          "[useTabSync.syncTabs] Aborting write - lost ownership/switching mid-sync",
        );
        return;
      }
      if (activeWorkspaceRef.current?.id !== workspaceId) {
        // eslint-disable-next-line no-console
        console.log(
          "[useTabSync.syncTabs] Aborting write - active workspace changed mid-sync",
        );
        return;
      }

      // Update local state immediately for instant feedback.
      //
      // Base the update on the freshest PERSISTED workspace, not the
      // activeWorkspaceRef snapshot: the ref can lag storage by a few ticks
      // after a granular edit (addResourceToSection/addNote/... persist
      // synchronously, but the ref only catches up once loadWorkspaces + a
      // re-render run). Spreading the stale ref here lets a tab event firing in
      // that window overwrite the UI's resources/notes/tasks with a pre-edit
      // snapshot (#46 — "resources fail to persist multiple additions"). Only
      // tabs/tabGroups are authored by this sync, so we override just those.
      const freshBase = storedWorkspace ?? currentWorkspace;
      setActiveWorkspaceData({
        ...freshBase,
        tabs: cleanTabs,
        tabGroups: tabGroupsToSave,
      });

      // Persist to storage (tabs and tabGroups separately to avoid breaking updateWorkspace signature)
      await WorkspaceService.updateWorkspaceTabs(
        workspaceId,
        cleanTabs,
        tabGroupsToSave,
      );
    } finally {
      // Always clear the sync lock
      isSyncingRef.current = false;
    }
  }, [activeWorkspaceRef, isSwitchingRef, setActiveWorkspaceData]);

  /**
   * Debounced sync to prevent excessive updates during rapid tab changes.
   */
  const debouncedSync = useCallback(() => {
    if (isSwitchingRef.current) return;
    clearTimeout(timeoutRef.current);
    timeoutRef.current = setTimeout(syncTabs, debounceMs);
  }, [syncTabs, isSwitchingRef, debounceMs]);

  /**
   * Handle tab removal - remove from workspace and sync.
   */
  const handleTabRemoved = useCallback(
    (tabId: number) => {
      if (isSwitchingRef.current) return;
      const currentWorkspace = activeWorkspaceRef.current;
      if (!currentWorkspace) return;

      // Optimistic update - remove tab from UI immediately
      const updatedTabs = currentWorkspace.tabs.filter((t) => t.id !== tabId);
      setActiveWorkspaceData({ ...currentWorkspace, tabs: updatedTabs });

      // Sync to persist the removal
      debouncedSync();
    },
    [activeWorkspaceRef, isSwitchingRef, setActiveWorkspaceData, debouncedSync],
  );

  /**
   * Handle tab update events (URL/title changes).
   */
  const handleTabUpdate = useCallback(
    (
      _tabId: number,
      changeInfo: chrome.tabs.OnUpdatedInfo,
      _tab: chrome.tabs.Tab,
    ) => {
      // Only sync on meaningful changes (including groupId and pinned changes)
      if (
        changeInfo.url ||
        changeInfo.title ||
        changeInfo.status === "complete" ||
        changeInfo.groupId !== undefined ||
        changeInfo.pinned !== undefined
      ) {
        debouncedSync();
      }
    },
    [debouncedSync],
  );

  // Set up Chrome tab event listeners
  useEffect(() => {
    if (!enabled) return undefined;

    // Register listeners IMMEDIATELY so no early tab/group event is missed.
    // Any sync triggered during Chrome's transient "groups exist but tabs still
    // report groupId -1" window after a soft refresh is safely skipped by
    // syncTabs' own guard, so early registration cannot persist a bad snapshot.
    chrome.tabs.onCreated.addListener(debouncedSync);
    chrome.tabs.onUpdated.addListener(handleTabUpdate);
    chrome.tabs.onRemoved.addListener(handleTabRemoved);
    chrome.tabs.onMoved.addListener(debouncedSync);
    chrome.tabs.onDetached.addListener(debouncedSync);
    chrome.tabs.onAttached.addListener(debouncedSync);

    // Tab group event listeners
    chrome.tabGroups.onCreated.addListener(debouncedSync);
    chrome.tabGroups.onUpdated.addListener(debouncedSync);
    chrome.tabGroups.onRemoved.addListener(debouncedSync);

    // Condition-based startup (replaces the old blind 500ms delay). On a soft
    // refresh Chrome's tabs.query() briefly reports groupId -1 for grouped tabs
    // while tabGroups.query() already lists the groups; syncing in that window
    // drops tab/group associations. Poll TabService.areTabGroupsConsistent
    // until Chrome's two APIs agree, THEN run the initial sync. This resolves
    // the instant Chrome is ready (no groups -> immediately) instead of always
    // paying a fixed delay, and waits up to INIT_SYNC_MAX_WAIT_MS under load.
    let cancelled = false;
    (async () => {
      const start = Date.now();
      while (!cancelled) {
        let consistent = true;
        try {
          // eslint-disable-next-line no-await-in-loop
          consistent = await TabService.areTabGroupsConsistent(
            currentWindowIdRef.current ?? undefined,
          );
        } catch {
          consistent = true;
        }
        if (consistent || Date.now() - start >= INIT_SYNC_MAX_WAIT_MS) break;
        // eslint-disable-next-line no-await-in-loop
        await new Promise((resolve) => {
          initPollRef.current = setTimeout(resolve, INIT_SYNC_POLL_MS);
        });
      }
      if (!cancelled) debouncedSync();
    })();

    return () => {
      cancelled = true;
      clearTimeout(initPollRef.current);
      clearTimeout(timeoutRef.current);
      chrome.tabs.onCreated.removeListener(debouncedSync);
      chrome.tabs.onUpdated.removeListener(handleTabUpdate);
      chrome.tabs.onRemoved.removeListener(handleTabRemoved);
      chrome.tabs.onMoved.removeListener(debouncedSync);
      chrome.tabs.onDetached.removeListener(debouncedSync);
      chrome.tabs.onAttached.removeListener(debouncedSync);

      // Remove tab group listeners
      chrome.tabGroups.onCreated.removeListener(debouncedSync);
      chrome.tabGroups.onUpdated.removeListener(debouncedSync);
      chrome.tabGroups.onRemoved.removeListener(debouncedSync);
    };
  }, [enabled, debouncedSync, handleTabUpdate, handleTabRemoved]);

  return {
    syncTabs,
    debouncedSync,
    handleTabRemoved,
  };
};

export default useTabSync;
