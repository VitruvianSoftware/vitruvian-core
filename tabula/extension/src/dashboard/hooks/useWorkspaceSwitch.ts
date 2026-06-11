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
 * Custom hook for Workspace Switching logic
 *
 * Handles the delicate process of switching workspaces, including syncing,
 * preventing race conditions, managing the switching state, updating
 * the URL for Multi-Window support, and detecting ownership conflicts.
 */
/* eslint-disable no-param-reassign */

import { MutableRefObject, useState, useCallback, useEffect } from "react";
import { WorkspaceService } from "../../services/workspace";
import {
  WindowOwnershipRecord,
  WindowOwnershipService,
} from "../../services/windowOwnership";
import { crossWindowSync } from "../../services/CrossWindowSyncService";
import type { Workspace } from "../../types";
import { setSpaceIdInUrl } from "../../utils/router";

export interface UseWorkspaceSwitchProps {
  activeWorkspaceId: string | null;
  switchWorkspace: (id: string) => Promise<void>;
  isSwitchingRef: MutableRefObject<boolean>;
  setActiveWorkspaceData: (workspace: Workspace | null) => void;
  // Multi-Window support: callback to update local (per-window) active workspace
  setLocalActiveWorkspaceId?: (id: string | null) => void;
  // Current window ID for conflict detection
  currentWindowId?: number;
  // Action to set active workspace ID in store without side effects
  setActiveWorkspaceId: (id: string | null) => void;
}

export interface ConflictInfo {
  targetWorkspaceId: string;
  ownerRecord: WindowOwnershipRecord;
}

export interface UseWorkspaceSwitchReturn {
  handleSwitch: (id: string) => Promise<void>;
  /** Currently detected conflict (null if none) */
  conflict: ConflictInfo | null;
  /** Clear the conflict (user dismissed popover) */
  clearConflict: () => void;
  /** Force switch even if there's a conflict (after user dismisses popover) */
  forceSwitch: (id: string, options?: { restore?: boolean }) => Promise<void>;
}

export const useWorkspaceSwitch = ({
  activeWorkspaceId,
  switchWorkspace,
  isSwitchingRef,
  setActiveWorkspaceData,
  setLocalActiveWorkspaceId,
  currentWindowId,
  setActiveWorkspaceId,
}: UseWorkspaceSwitchProps): UseWorkspaceSwitchReturn => {
  const [conflict, setConflict] = useState<ConflictInfo | null>(null);

  const clearConflict = useCallback(() => {
    setConflict(null);
  }, []);

  // Listen for broadcast events to detect conflicts instantly
  useEffect(() => {
    if (!currentWindowId) return;

    const unsubscribe = crossWindowSync.subscribe((msg) => {
      if (msg.type === "CLAIM_WORKSPACE") {
        // If another window claims our active workspace, we might need to react
        if (
          msg.workspaceId === activeWorkspaceId &&
          msg.windowId !== currentWindowId
        ) {
          // eslint-disable-next-line no-console
          console.log(
            "[useWorkspaceSwitch] Current workspace claimed by another window:",
            msg,
          );
          // Potential future enhancement: Show an alert or generic "Session Taken" modal here
        }
      }
    });

    return unsubscribe;
  }, [currentWindowId, activeWorkspaceId]);

  // Core switch logic (shared by handleSwitch and forceSwitch)
  const performSwitch = useCallback(
    async (id: string, options: { restore?: boolean } = { restore: true }) => {
      if (isSwitchingRef.current) return;
      try {
        isSwitchingRef.current = true;

        if (options.restore) {
          // STANDARD SWITCH: Restore tabs from storage
          // Force a sync of CURRENT workspace BEFORE switching to ensure latest state is saved.
          // Guard: only save the departing workspace if no OTHER live window
          // owns it — a window that already lost the workspace must not
          // clobber the new owner's state on its way out.
          if (activeWorkspaceId) {
            const departingOwner = currentWindowId
              ? await WindowOwnershipService.isWorkspaceOwnedByOtherWindow(
                  activeWorkspaceId,
                  currentWindowId,
                )
              : null;
            if (!departingOwner) {
              await WorkspaceService.saveCurrentTabsToWorkspace(
                activeWorkspaceId,
              );
            } else {
              // eslint-disable-next-line no-console
              console.log(
                "[useWorkspaceSwitch] Skipping departing save - workspace owned by window:",
                departingOwner.windowId,
              );
            }
          }

          // Perform the actual workspace switch (restore tabs)
          await switchWorkspace(id);
        } else {
          // ADOPT SWITCH: Adopt current tabs (used after moving tabs during conflict resolution)
          // We moved tabs here, so we want to SAVE them to the target workspace, not overwrite them
          // eslint-disable-next-line no-console
          console.log(
            "[useWorkspaceSwitch] Adopting current tabs for workspace:",
            id,
          );

          // 1. Set the active workspace ID in the global store (without triggering restore)
          setActiveWorkspaceId(id);

          // 2. Save the current state of this window (including moved tabs) to the workspace
          await WorkspaceService.saveCurrentTabsToWorkspace(id);
        }

        // Update Dashboard's activeWorkspace state with fresh data
        const freshWorkspace = await WorkspaceService.getWorkspaceById(id);
        if (freshWorkspace) {
          setActiveWorkspaceData(freshWorkspace);
        }

        // Update local active workspace ID for multi-window independence
        if (setLocalActiveWorkspaceId) {
          setLocalActiveWorkspaceId(id);
        }

        // Re-affirm ownership (idempotent; refreshes the dashboard tabId —
        // the atomic claim already happened in handleSwitch/forceSwitch)
        if (currentWindowId) {
          const currentTab = await chrome.tabs.getCurrent();
          if (currentTab?.id) {
            await WindowOwnershipService.registerWorkspaceOwnership(
              id,
              currentWindowId,
              currentTab.id,
            );
          }
        }

        // Update URL for Multi-Window support
        setSpaceIdInUrl(id);
      } catch (error) {
        // A failed switch must not pin ownership to a window that never
        // finished restoring — release the claim so other windows can take it
        if (currentWindowId) {
          await WindowOwnershipService.clearWorkspaceOwnership(
            id,
            currentWindowId,
          ).catch(() => undefined);
        }
        throw error;
      } finally {
        setTimeout(() => {
          isSwitchingRef.current = false;
        }, 500);
      }
    },
    [
      activeWorkspaceId,
      switchWorkspace,
      isSwitchingRef,
      setActiveWorkspaceData,
      setLocalActiveWorkspaceId,
      currentWindowId,
      setActiveWorkspaceId,
    ],
  );

  const handleSwitch = useCallback(
    async (id: string) => {
      // Already on this workspace: re-claim it idempotently (heals stale
      // ownership after restarts/crashes) but skip the full switch
      if (id === activeWorkspaceId) {
        if (currentWindowId) {
          const currentTab = await chrome.tabs.getCurrent();
          const claim = await WindowOwnershipService.tryClaimWorkspace(
            id,
            currentWindowId,
            currentTab?.id ?? -1,
          );
          if (!claim.claimed) {
            setConflict({ targetWorkspaceId: id, ownerRecord: claim.owner });
          }
        }
        return;
      }

      // Atomically check-and-claim BEFORE switching: two windows racing to
      // the same workspace can no longer both pass a check and both restore
      if (currentWindowId) {
        const currentTab = await chrome.tabs.getCurrent();
        const claim = await WindowOwnershipService.tryClaimWorkspace(
          id,
          currentWindowId,
          currentTab?.id ?? -1,
        );
        if (!claim.claimed) {
          // Conflict detected - show popover instead of switching
          setConflict({ targetWorkspaceId: id, ownerRecord: claim.owner });
          return;
        }
      }

      // Claim held - proceed with switch
      await performSwitch(id);
    },
    [activeWorkspaceId, currentWindowId, performSwitch],
  );

  const forceSwitch = useCallback(
    async (id: string, options?: { restore?: boolean }) => {
      setConflict(null);
      // Take-over semantics: claim ownership up front so the previous owner's
      // tab sync locks out before any tabs move/restore (the conflict popover
      // already does this for the adopt path; this covers restore as well)
      if (currentWindowId) {
        const currentTab = await chrome.tabs.getCurrent();
        await WindowOwnershipService.registerWorkspaceOwnership(
          id,
          currentWindowId,
          currentTab?.id ?? -1,
        );
      }
      await performSwitch(id, options);
    },
    [performSwitch, currentWindowId],
  );

  return {
    handleSwitch,
    conflict,
    clearConflict,
    forceSwitch,
  };
};
