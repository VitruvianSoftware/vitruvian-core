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

import React, { useEffect, useMemo, useRef, useState } from "react";
import { DndContext, pointerWithin } from "@dnd-kit/core";
import {
  SortableContext,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { useWorkspaceStore } from "../stores/workspace";
import { WorkspaceService } from "../services/workspace";
import type { Workspace } from "../types";
import { FEATURE_FLAGS } from "../constants/features";
import "../styles/dashboard.css";
import { Modal } from "../components/Modal";
import { Icon } from "../components/icons";
import { useTheme } from "../hooks/useTheme";
import { useTabSync } from "../hooks/useTabSync";
import { useLiveTabs } from "../hooks/useLiveTabs";
import { useLatest } from "../hooks/useLatest";
import { SortableNavItem } from "./SortableNavItem";
import { AccountSettings } from "../components/AccountSettings";
import { AuthService, User } from "../services/auth";
import { ApiService } from "../services/api";
import { SyncStatusIndicator } from "../components/SyncStatusIndicator";
import { UpdateBanner } from "../components/UpdateBanner";
import { UpdateCheckService } from "../services/updateCheck";
import { DroppableContainer } from "./DroppableContainer";
import { ResourceSection } from "./ResourceSection";
import { NotesPanel } from "./NotesPanel";
import { TasksPanel } from "./TasksPanel";
import { OpenTabsPanel } from "./OpenTabsPanel";
import { UserMenu } from "./UserMenu";
import { SidebarHeader } from "./SidebarHeader";
import { SpacesHeader } from "./SpacesHeader";
import { WorkspaceMenuItem } from "./WorkspaceMenuItem";
import { SidebarGroupHeader } from "./SidebarGroupHeader";
import { useDragAndDrop } from "./hooks/useDragAndDrop";
import { useNotesAndTasks } from "./hooks/useNotesAndTasks";
import { useResourceHandlers } from "./hooks/useResourceHandlers";
import { useMenuState } from "./hooks/useMenuState";
import { useWorkspaceSwitch } from "./hooks/useWorkspaceSwitch";
import { useRelayImport } from "./hooks/useRelayImport";
import { ConfirmModal } from "./ConfirmModal";
import { CommandPalette } from "./CommandPalette";
import { SyncService } from "../services/sync";
import { GhostOverlay } from "./GhostOverlay";
import { getSpaceIdFromUrl } from "../utils/router";
import { TabConflictPopover } from "../components/TabConflictPopover";
import { CrossDeviceSessionPopover } from "../components/CrossDeviceSessionPopover";
import type { CrossDeviceTab } from "../components/CrossDeviceSessionPopover";
import { useCrossDeviceSession } from "./hooks/useCrossDeviceSession";
import { WindowOwnershipService } from "../services/windowOwnership";
import { OnboardingModal } from "../components/onboarding/OnboardingModal";
import { shouldShowOnboarding } from "../components/onboarding/shouldShowOnboarding";
import { StorageService } from "../services/storage";
import { useSettingsStore } from "../stores/settings";

export const Dashboard: React.FC = () => {
  useEffect(() => {
    // Initialize sync service on dashboard mount
    SyncService.initialize();
  }, []);

  const {
    workspaces,
    spaceGroups,
    activeWorkspaceId,
    loadWorkspaces,
    createWorkspace: createWorkspaceAction,
    updateWorkspace: updateWorkspaceAction,
    switchWorkspace,
    deleteWorkspace: deleteWorkspaceAction,
    createSpaceGroup,
    deleteSpaceGroup,
    updateSpaceGroup,
    toggleSpaceGroupCollapse,
    reorderWorkspaces,
    reorderSpaceGroups,
    reorderSections,
    setActiveWorkspace: setActiveWorkspaceAction,
  } = useWorkspaceStore();

  // Theme management
  const { theme, setTheme } = useTheme();

  // First-run onboarding (#138)
  const [showOnboarding, setShowOnboarding] = useState(false);
  const onboardingCheckedRef = useRef(false);

  // The first-run check runs AFTER loadWorkspaces() resolves (see the "Load
  // initial data" effect below) so it reads the real loaded count. Deciding
  // here would race the async load — workspaces is [] on first render even for
  // returning users, which flashed the onboarding modal over a populated
  // dashboard.

  const finishOnboarding = () => {
    setShowOnboarding(false);
    void useSettingsStore
      .getState()
      .updateSettings({ onboardingCompleted: true })
      .catch(() => {});
  };

  const handleOnboardingCreateSpace = async (name: string) => {
    const ws = await createWorkspaceAction({ name });
    setActiveWorkspaceAction(ws.id);
  };

  const handleOnboardingAddResource = async (input: {
    title: string;
    url: string;
  }) => {
    const id = useWorkspaceStore.getState().activeWorkspaceId;
    if (!id) return;
    await WorkspaceService.addResource(id, {
      title: input.title || "New Resource",
      url: input.url,
    });
    await loadWorkspaces();
  };

  const handleOnboardingSaveTabs = async () => {
    const id = useWorkspaceStore.getState().activeWorkspaceId;
    if (!id) return;
    await useWorkspaceStore.getState().saveCurrentTabs(id);
  };

  const [activeWorkspace, setActiveWorkspaceData] = useState<Workspace | null>(
    null,
  );
  // Use useLatest to always have current workspace in event handlers (prevents stale closures)
  const activeWorkspaceRef = useLatest(activeWorkspace);
  const [activeTab, setActiveTab] = useState<"resources" | "notes" | "tasks">(
    "resources",
  );

  // Multi-Window Support: Local active workspace ID from URL
  // This allows each window to have its own active workspace, independent of other windows.
  // We use local React state instead of the shared Zustand store for URL-based selection.
  const [localActiveWorkspaceId, setLocalActiveWorkspaceId] = useState<
    string | null
  >(null);

  // Current window ID for conflict detection
  const [currentWindowId, setCurrentWindowId] = useState<number | null>(null);

  // Note-popout mode (dashboard.html?view=note&noteId=...): a lightweight
  // editor window. It must NEVER claim workspace ownership or sync tabs —
  // it would otherwise capture the popup window's tabs into the workspace.
  const popoutParams = new URLSearchParams(window.location.search);
  const isNotePopout =
    popoutParams.get("view") === "note" && !!popoutParams.get("noteId");

  // Initialize currentWindowId on mount
  useEffect(() => {
    chrome.windows.getCurrent().then((window) => {
      setCurrentWindowId(window.id ?? null);
    });
  }, []);

  // Effective active workspace ID: prefer local (URL-based) over shared (storage-based)
  const effectiveActiveWorkspaceId =
    localActiveWorkspaceId ?? activeWorkspaceId;
  // Ref for event handlers registered once (storage listener) — they must
  // resolve against THIS window's effective id, never the shared store id,
  // or a URL-pinned window would adopt another window's workspace.
  const effectiveActiveWorkspaceIdRef = useLatest(effectiveActiveWorkspaceId);

  // Relay import (#140): if this dashboard was opened from a relay link
  // (dashboard.html?relayId=…), redeem the grant, pull the shared space, and
  // pin THIS window to it. No-op without a relayId or a signed-in user.
  //
  // The imported space is shared — its tabs belong to the owner — so pinning to
  // it must NOT capture this window's unrelated tabs into it. We record the
  // freshly-imported id here and the sync effect below skips the ownership
  // claim/save for it (mirroring the non-destructive ?spaceId= URL pin).
  const justRelayImportedRef = React.useRef<string | null>(null);
  useRelayImport({
    loadWorkspaces,
    onImported: (workspaceId) => {
      justRelayImportedRef.current = workspaceId;
      setLocalActiveWorkspaceId(workspaceId);
    },
  });

  // Resource and Section - Now using extracted hook
  const {
    showAddResource,
    setShowAddResource,
    newResourceUrl,
    setNewResourceUrl,
    newResourceTitle,
    setNewResourceTitle,
    targetSectionId,
    setTargetSectionId,
    showAddSection,
    setShowAddSection,
    newSectionTitle,
    setNewSectionTitle,
    handleCreateSection,
    handleAddResource,
    handleOpenResource,
    // handleCloseTab removed - now using closeTabByUrl from useLiveTabs
  } = useResourceHandlers({
    activeWorkspace,
    setActiveWorkspaceData,
    loadWorkspaces,
  });

  // Modal State
  const [modalOpen, setModalOpen] = useState(false);
  const [modalType, setModalType] = useState<
    | "create"
    | "rename"
    | "rename-tab"
    | "rename-resource"
    | "delete-workspace"
    | "create-section"
  >("create");
  const [editingTabId, setEditingTabId] = useState<number | null>(null);
  const [editingResourceId, setEditingResourceId] = useState<{
    id: string;
    sectionId?: string;
  } | null>(null);
  const [modalInputValue, setModalInputValue] = useState("");
  const [modalUrlValue, setModalUrlValue] = useState("");
  const [deletingWorkspaceId, setDeletingWorkspaceId] = useState<string | null>(
    null,
  );

  // Account Settings State
  const [showAccountSettings, setShowAccountSettings] = useState(false);
  const [user, setUser] = useState<User | null>(null);
  const [showUserMenu, setShowUserMenu] = useState(false);

  // Command Palette State
  const [commandPaletteOpen, setCommandPaletteOpen] = useState(false);

  const [buildIdentity, setBuildIdentity] = useState<{
    channel: string;
    commit: string;
  } | null>(null);

  useEffect(() => {
    let cancelled = false;
    UpdateCheckService.getDisplayIdentity().then((identity) => {
      if (!cancelled && identity) {
        setBuildIdentity({
          channel: identity.channel,
          commit: identity.commit,
        });
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    // Render the cached user immediately, then re-project the authoritative
    // server profile over it so a name corrupted by an older mis-encoded login
    // (mojibake) self-heals here without a re-login. setCachedUser also fires
    // the storage listener below, keeping other open windows in sync.
    AuthService.getUser().then(setUser);
    ApiService.refreshCachedUser().then((refreshed) => {
      if (refreshed) setUser(refreshed);
    });
  }, []);

  const handleSignIn = async () => {
    try {
      await AuthService.login();
      // Reload so every surface (sync engine, workspaces, account UI)
      // rehydrates with the new session — mirrors the logout path.
      window.location.reload();
    } catch (error) {
      console.error("[Dashboard] Sign-in failed:", error);
    }
  };

  const handleLogout = async () => {
    // Reset in-memory sync state (static class survives in other open
    // extension pages that won't reload) and close the SSE stream
    await SyncService.clearQueue();
    SyncService.disconnectSSE();
    await AuthService.logout();
    window.location.reload();
  };

  // Notes and Tasks - Now using extracted hook
  const {
    showAddNote,
    setShowAddNote,
    newNoteTitle,
    setNewNoteTitle,
    newNoteContent,
    setNewNoteContent,
    handleAddNote,
    handleUpdateNote,
    handleDeleteNote,
    newTaskTitle,
    setNewTaskTitle,
    handleAddTask,
    handleToggleTask,
    handleDeleteTask,
  } = useNotesAndTasks({
    activeWorkspace,
    setActiveWorkspaceData,
  });

  // Menu state - Now using extracted hook
  const {
    collapsedSections,
    toggleSectionCollapse,
    openSectionMenuId,
    setOpenSectionMenuId,
    spacesMenuOpen,
    setSpacesMenuOpen,
    spaceGroupMenuId,
    setSpaceGroupMenuId,
    colorPickerGroupId,
    setColorPickerGroupId,
    workspaceMenuId,
    setWorkspaceMenuId,
    workspaceSectionPickerId,
    setWorkspaceSectionPickerId,
    workspaceColorPickerId,
    setWorkspaceColorPickerId,
    isEditingWorkspaceName,
    setIsEditingWorkspaceName,
    editingWorkspaceName,
    setEditingWorkspaceName,
    editingSectionId,
    setEditingSectionId,
    editingSectionName,
    setEditingSectionName,
    confirmModal,
    showConfirm,
    closeConfirm,
  } = useMenuState();

  // Memoize sorted workspaces to ensure consistent order for drag and drop
  // This fixes the issue where new workspaces can't be reordered until refresh
  const sortedWorkspaces = useMemo(() => {
    return [...workspaces].sort(
      (a, b) => (a.position || 0) - (b.position || 0),
    );
  }, [workspaces]);

  // Check if workspace list is completely empty
  const showWorkspaceEmptyState = useMemo(
    () => workspaces.length === 0 && spaceGroups.length === 0,
    [workspaces.length, spaceGroups.length],
  );

  // Helper to get sorted workspaces for a group (memoized to avoid recalculating on each render)
  const getWorkspacesByGroupId = useMemo(() => {
    const groupMap = new Map<string, typeof sortedWorkspaces>();
    sortedWorkspaces.forEach((ws) => {
      if (ws.groupId) {
        if (!groupMap.has(ws.groupId)) {
          groupMap.set(ws.groupId, []);
        }
        groupMap.get(ws.groupId)!.push(ws);
      }
    });
    return (groupId: string) => groupMap.get(groupId) || [];
  }, [sortedWorkspaces]);

  // Load initial data, then decide first-run onboarding from the loaded count.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      await loadWorkspaces();
      if (cancelled || onboardingCheckedRef.current) return;
      onboardingCheckedRef.current = true;
      try {
        const settings = await StorageService.getSettings();
        const count = useWorkspaceStore.getState().workspaces.length;
        if (shouldShowOnboarding(settings, count)) {
          setShowOnboarding(true);
        }
      } catch {
        // Non-blocking: never let onboarding detection break the dashboard.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [loadWorkspaces]);

  // URL-based workspace initialization moved below useWorkspaceSwitch to enable conflict detection

  // Update active workspace data when effective ID or workspaces change
  // IMPORTANT: Use effectiveActiveWorkspaceId (local) not activeWorkspaceId (shared)
  // This ensures each window's main content is driven by its own URL/local state
  useEffect(() => {
    if (effectiveActiveWorkspaceId) {
      const ws = sortedWorkspaces.find(
        (w) => w.id === effectiveActiveWorkspaceId,
      );
      setActiveWorkspaceData(ws || null);
    } else if (sortedWorkspaces.length > 0) {
      setActiveWorkspaceData(sortedWorkspaces[0]);
    }
  }, [effectiveActiveWorkspaceId, sortedWorkspaces]);

  // Listen for storage changes (background updates)
  useEffect(() => {
    const handleStorageChange = (changes: {
      [key: string]: chrome.storage.StorageChange;
    }) => {
      if (changes.tabula_workspaces) {
        if (changes.tabula_workspaces.newValue) {
          const nextWorkspaces = changes.tabula_workspaces
            .newValue as Workspace[];
          // Optimization: Update directly from payload to avoid async read delay
          // This fixes "Workspace does not show until refresh"
          useWorkspaceStore.setState({
            workspaces: nextWorkspaces,
          });
          // Refresh THIS window's workspace from the payload. Must use the
          // effective (URL-pinned) id — the shared store id may belong to a
          // different window, and adopting it here would poison
          // activeWorkspaceRef and redirect tab syncs at the wrong workspace.
          const effectiveId = effectiveActiveWorkspaceIdRef.current;
          if (effectiveId) {
            const ws = nextWorkspaces.find(
              (w: Workspace) => w.id === effectiveId,
            );
            if (ws) setActiveWorkspaceData(ws);
          }
        }
      }

      if (changes.tabula_active_workspace) {
        // Handle external active workspace change (e.g. from sidebar/service)
        useWorkspaceStore.setState({
          activeWorkspaceId: changes.tabula_active_workspace.newValue as
            | string
            | null
            | undefined,
        });
      }

      // Propagate auth changes across windows: logging out (or in) in one
      // window must not leave others operating on a dead session
      if (changes.tabula_access_token || changes.tabula_user) {
        const tokenChange = changes.tabula_access_token;
        if (tokenChange && !tokenChange.newValue) {
          // Logged out elsewhere — reset this window's UI state
          window.location.reload();
        } else {
          AuthService.getUser().then(setUser);
        }
      }
    };

    chrome.storage.onChanged.addListener(handleStorageChange);
    return () => chrome.storage.onChanged.removeListener(handleStorageChange);
  }, [loadWorkspaces]);

  // Real-time cross-device sync: when another device saves/deletes a
  // workspace or space group, the server pushes an SSE 'change' event —
  // refetch (the pull path merges with tombstone/version awareness).
  useEffect(() => {
    if (isNotePopout) return undefined;
    let reloadTimer: ReturnType<typeof setTimeout> | undefined;
    const unsubscribe = SyncService.subscribeToSSE(() => {
      // Coalesce bursts of remote changes into one refetch
      clearTimeout(reloadTimer);
      reloadTimer = setTimeout(() => loadWorkspaces(), 500);
    });
    return () => {
      clearTimeout(reloadTimer);
      unsubscribe();
    };
  }, [loadWorkspaces, isNotePopout]);

  // Listen for visibility change (refresh when switching back to dashboard)
  // Note: Tab syncing is handled by useTabSync via Chrome events.
  // We only load workspaces here, not sync tabs, to avoid race conditions.
  useEffect(() => {
    const handleVisibilityChange = async () => {
      if (document.visibilityState === "visible") {
        // Don't save tabs here - let useTabSync handle it via Chrome events
        // This avoids race conditions between multiple sync paths
        loadWorkspaces();
      }
    };

    const handleWindowFocus = async () => {
      // Don't save tabs here - let useTabSync handle it via Chrome events
      // Just reload workspaces to pick up any external changes
      loadWorkspaces();
    };

    document.addEventListener("visibilitychange", handleVisibilityChange);
    window.addEventListener("focus", handleWindowFocus);

    return () => {
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      window.removeEventListener("focus", handleWindowFocus);
    };
  }, [loadWorkspaces, activeWorkspaceId]);

  // Listen for tab changes (Live Sync)
  // Ref to track if we are currently switching workspaces
  const isSwitchingRef = React.useRef(false);

  // Use tab sync hook for real-time tab updates
  // Disabled in note popouts: the popup's tabs must never be captured as
  // workspace state.
  useTabSync({
    activeWorkspaceRef,
    isSwitchingRef,
    setActiveWorkspaceData,
    currentWindowId: currentWindowId ?? undefined,
    activeWorkspaceId: effectiveActiveWorkspaceId,
    enabled: !isNotePopout,
  });

  // Load workspaces on mount
  useEffect(() => {
    loadWorkspaces();
  }, [loadWorkspaces]);

  // Global keyboard shortcut for Command Palette (Cmd+K / Ctrl+K)
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Cmd+K on Mac, Ctrl+K on Windows/Linux
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setCommandPaletteOpen((prev) => !prev);
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, []);

  // Force sync on workspace switch/mount
  // NOTE: We must NOT sync immediately after switching workspaces, as this would
  // save the "old" tabs (that are about to be closed) to the new workspace.
  // Ownership rules:
  // - fail closed until this window's id is known
  // - if another live window owns the workspace, do NOT save this window's
  //   tabs into it (a freshly-opened dashboard window with no real tabs would
  //   wipe the workspace's saved tab list) — just refresh from storage
  // - if nobody owns it, claim it (a window that merely inherits the shared
  //   active workspace must still register so other windows' guards work)
  useEffect(() => {
    const sync = async () => {
      // Note popouts never own workspaces or capture tabs
      if (isNotePopout) return;
      // Skip if we're in the middle of switching workspaces
      if (isSwitchingRef.current) return;
      if (!effectiveActiveWorkspaceId || document.visibilityState !== "visible")
        return;
      if (!currentWindowId) return;

      // A relay-imported shared space: pin & display it, but do NOT capture this
      // window's unrelated tabs into it — that would overwrite the owner's saved
      // tab list (and, for an edit collaborator, PUT the clobber to everyone).
      // Skip the claim/save once; genuine later switches behave normally.
      if (effectiveActiveWorkspaceId === justRelayImportedRef.current) {
        justRelayImportedRef.current = null;
        loadWorkspaces();
        return;
      }

      const currentTab = await chrome.tabs.getCurrent();
      const claim = await WindowOwnershipService.tryClaimWorkspace(
        effectiveActiveWorkspaceId,
        currentWindowId,
        currentTab?.id ?? -1,
      );
      if (!claim.claimed) {
        // Another live window owns this workspace — never overwrite its tabs
        loadWorkspaces();
        return;
      }

      // We own it: ensure the saved tab list reflects this window's tabs
      await WorkspaceService.saveCurrentTabsToWorkspace(
        effectiveActiveWorkspaceId,
      );
      loadWorkspaces();
    };
    sync();
  }, [effectiveActiveWorkspaceId, currentWindowId, loadWorkspaces]);

  // Workspace Switching Logic - Now using extracted hook with conflict detection
  const { handleSwitch, conflict, clearConflict, forceSwitch } =
    useWorkspaceSwitch({
      activeWorkspaceId: effectiveActiveWorkspaceId, // Use effective ID for switch detection
      switchWorkspace,
      isSwitchingRef,
      setActiveWorkspaceData,
      setLocalActiveWorkspaceId, // Multi-window support
      currentWindowId: currentWindowId ?? undefined, // Conflict detection
      setActiveWorkspaceId: setActiveWorkspaceAction, // Pass store action for non-destructive switch
    });

  // Cross-device "Changes from your other device" prompt (Workona's "one
  // primary session per space"). Surfaces when this device is PASSIVE — the
  // space is live on another device (fresh foreign lease) — and the primary's
  // synced tabs differ from what's open here.
  const { conflictTabs: crossDeviceTabs, dismiss: dismissCrossDevice } =
    useCrossDeviceSession(activeWorkspace);

  const handleCrossDeviceApply = React.useCallback(
    async (selected: CrossDeviceTab[]) => {
      const ws = activeWorkspace;
      if (!ws) return;
      dismissCrossDevice();
      // Recover the full Tab records (groupId/pinned) for the chosen URLs, then
      // open them here and claim the lease (this device becomes the primary).
      const selectedUrls = new Set(selected.map((t) => t.url));
      const fullTabs = (ws.tabs || []).filter((t) => selectedUrls.has(t.url));
      await WorkspaceService.restoreWorkspaceTabs(ws.id, {
        closeCurrentTabs: true,
        tabs: fullTabs,
      });
      const fresh = await WorkspaceService.getWorkspaceById(ws.id);
      if (fresh) setActiveWorkspaceData(fresh);
    },
    [activeWorkspace, dismissCrossDevice],
  );

  const handleCrossDeviceKeepMine = React.useCallback(async () => {
    const ws = activeWorkspace;
    if (!ws) return;
    dismissCrossDevice();
    // Keep what's open here and make THIS device the primary going forward.
    await WorkspaceService.saveCurrentTabsToWorkspace(ws.id, { claim: true });
  }, [activeWorkspace, dismissCrossDevice]);

  // URL-based workspace initialization (Multi-Window support)
  // Reads ?spaceId= from URL on mount and pins THIS window to that workspace.
  // This is a lightweight, non-destructive update: it sets the local active
  // workspace (so each window/tab independently shows its URL-pinned space)
  // WITHOUT restoring browser tabs or claiming ownership — a full handleSwitch
  // here would close/open the user's tabs on every reload.
  const urlInitializedRef = React.useRef(false);
  useEffect(() => {
    // Only initialize once, after workspaces are loaded
    if (urlInitializedRef.current || sortedWorkspaces.length === 0) return;

    const urlSpaceId = getSpaceIdFromUrl();
    if (urlSpaceId) {
      const targetWorkspace = sortedWorkspaces.find(
        (ws) => ws.id === urlSpaceId,
      );
      if (targetWorkspace) {
        setLocalActiveWorkspaceId(urlSpaceId);
        setActiveWorkspaceData(targetWorkspace);
      }
    }
    urlInitializedRef.current = true;
  }, [sortedWorkspaces, setActiveWorkspaceData, setLocalActiveWorkspaceId]);

  // Drag and Drop Logic - Now using extracted hook
  const {
    activeId,
    sensors,
    sidebarSensors,
    handleDragStart,
    handleDragEnd,
    handleSidebarDragEnd,
  } = useDragAndDrop({
    activeWorkspace,
    setActiveWorkspaceData,
    workspaces: sortedWorkspaces, // Use sorted workspaces
    spaceGroups,
    reorderWorkspaces,
    reorderSpaceGroups,
    reorderSections,
    loadWorkspaces,
  });

  const handleEditResource = (
    resourceId: string,
    currentTitle: string,
    currentUrl: string,
    sectionId?: string,
  ) => {
    setEditingResourceId({ id: resourceId, sectionId });
    setModalInputValue(currentTitle);
    setModalUrlValue(currentUrl);
    setModalType("rename-resource");
    setModalOpen(true);
  };

  // Use workspace tabs for display (per-workspace isolation)
  // Keep closeTabByUrl from useLiveTabs for reliable tab closing
  const { closeTabByUrl, focusTabByUrl } = useLiveTabs({ autoRefresh: false });

  const activeTabs = activeWorkspace?.tabs || [];
  // resources array no longer used - all resources are in sections now
  const sections = activeWorkspace?.sections || [];
  const notes = activeWorkspace?.notes || [];
  const tasks = activeWorkspace?.tasks || [];
  const getModalTitle = () => {
    if (modalType === "create") return "New Workspace";
    if (modalType === "create-section") return "New Section";
    if (modalType === "rename-tab") return "Rename Tab";
    if (modalType === "rename-resource") return "Rename Resource";
    if (modalType === "delete-workspace") return "Delete Workspace";
    return "Rename Workspace";
  };

  // Check for Popout Mode (view=note)
  const searchParams = new URLSearchParams(window.location.search);
  const viewMode = searchParams.get("view");
  const noteId = searchParams.get("noteId");

  // If in Popout Mode, render focused note editor
  if (viewMode === "note" && noteId) {
    // We need to wait for workspace to load. `activeWorkspace` might be null initially.
    // But `loadWorkspaces` is called in useEffect.

    if (!activeWorkspace) {
      return (
        <div
          className="dashboard-container"
          style={{ alignItems: "center", justifyContent: "center" }}
        >
          <div className="text-secondary">Loading note...</div>
        </div>
      );
    }

    const note = activeWorkspace.notes.find((n) => n.id === noteId);

    if (!note) {
      return (
        <div
          className="dashboard-container"
          style={{ alignItems: "center", justifyContent: "center" }}
        >
          <div className="text-secondary">Note not found.</div>
        </div>
      );
    }

    return (
      <div
        className="dashboard-container"
        style={{
          display: "block",
          overflow: "auto",
          padding: "24px",
          background: "var(--color-bg-page)",
        }}
      >
        <div
          className="note-card"
          style={{
            maxWidth: "800px",
            margin: "0 auto",
            height: "calc(100vh - 48px)",
            display: "flex",
            flexDirection: "column",
          }}
        >
          <div className="note-header">
            <input
              className="note-title-display"
              value={note.title}
              onChange={(e) =>
                handleUpdateNote(note.id, e.target.value, note.content)
              }
              style={{ fontSize: "24px", marginBottom: "16px" }}
            />
          </div>
          {/* Direct NoteEditor for Popout Mode */}
          {/* We need to import NoteEditor here or expose it. It is not imported in Dashboard.tsx yet.
                To avoid import cycle or missing import, let's fix imports first. 
                Actually, I will import it in the top of the file in a separate edit, 
                OR I can reuse NotesPanel with single item. 
                Reusing NotesPanel is safer for now as it handles imports.
            */}
          <NotesPanel
            notes={[note]}
            workspaceId={activeWorkspace.id}
            showAddNote={false}
            newNoteTitle=""
            newNoteContent=""
            onShowAddNote={() => {}}
            onCancelAddNote={() => {}}
            onAddNote={() => {}}
            onUpdateNote={handleUpdateNote}
            onDeleteNote={handleDeleteNote}
            onNewNoteTitleChange={() => {}}
            onNewNoteContentChange={() => {}}
          />
          {/* Note: NotesPanel renders the list. Since we pass [note], it renders one card. 
                The card handles Delete and Update. 
                The only issue is double card nesting (note-card inside note-card).
                But technically NotesPanel renders the list of cards.
                So we wrap it in a container.
             */}
        </div>
      </div>
    );
  }

  return (
    <div className="dashboard-container">
      {/* Sidebar */}
      <div className="sidebar">
        {/* Header Row: Logo + Avatar - Now using extracted SidebarHeader + UserMenu */}
        <SidebarHeader>
          <UserMenu
            user={user}
            onSignIn={handleSignIn}
            showUserMenu={showUserMenu}
            onToggleUserMenu={() => setShowUserMenu(!showUserMenu)}
            onCloseUserMenu={() => setShowUserMenu(false)}
            onOpenSettings={() => {
              setShowUserMenu(false);
              setShowAccountSettings(true);
            }}
            onLogout={handleLogout}
          />
        </SidebarHeader>

        <DndContext
          sensors={sidebarSensors}
          collisionDetection={pointerWithin}
          onDragEnd={handleSidebarDragEnd}
          onDragStart={handleDragStart}
        >
          <div className="sidebar-nav">
            {/* Spaces Header - Now using extracted SpacesHeader component */}
            <SpacesHeader
              spacesMenuOpen={spacesMenuOpen}
              onToggleSpacesMenu={() => setSpacesMenuOpen(!spacesMenuOpen)}
              onNewSpace={() => {
                setSpacesMenuOpen(false);
                setModalType("create");
                setModalInputValue("");
                setModalOpen(true);
              }}
              onNewSection={() => {
                setSpacesMenuOpen(false);
                setModalType("create-section");
                setModalInputValue("");
                setModalOpen(true);
              }}
            />

            {/* Ungrouped Workspaces (including orphans) */}
            {showWorkspaceEmptyState ? (
              /* Empty state when no workspaces or groups exist */
              <div
                style={{
                  padding: "var(--spacing-xl) var(--spacing-lg)",
                  textAlign: "center",
                  color: "var(--color-text-secondary)",
                }}
                data-testid="workspace-empty-state"
              >
                <Icon
                  name="folder_open"
                  outlined
                  style={{
                    fontSize: "48px",
                    opacity: 0.3,
                    marginBottom: "var(--spacing-md)",
                  }}
                />
                <div
                  style={{
                    fontSize: "var(--font-size-base)",
                    marginBottom: "var(--spacing-sm)",
                  }}
                >
                  No spaces yet
                </div>
                <div
                  style={{
                    fontSize: "var(--font-size-sm)",
                    color: "var(--color-text-muted)",
                    marginBottom: "var(--spacing-md)",
                  }}
                >
                  Create your first space to organize tabs
                </div>
                <button
                  className="btn-primary"
                  style={{ fontSize: "var(--font-size-sm)" }}
                  onClick={() => {
                    setModalType("create");
                    setModalInputValue("");
                    setModalOpen(true);
                  }}
                  data-testid="empty-state-new-space-button"
                >
                  <Icon name="add" size="sm" style={{ marginRight: "4px" }} />
                  Get Started
                </button>
              </div>
            ) : (
              <DroppableContainer id="ungrouped-list" containerType="section">
                <SortableContext
                  id="ungrouped-list"
                  items={sortedWorkspaces
                    .filter(
                      (ws) =>
                        !ws.groupId ||
                        !spaceGroups.find((g) => g.id === ws.groupId),
                    )
                    .map((ws) => ws.id)}
                  strategy={verticalListSortingStrategy}
                >
                  {sortedWorkspaces
                    .filter(
                      (ws) =>
                        !ws.groupId ||
                        !spaceGroups.find((g) => g.id === ws.groupId),
                    )
                    .map((ws) => (
                      <SortableNavItem key={ws.id} id={ws.id}>
                        <WorkspaceMenuItem
                          workspace={ws}
                          isActive={effectiveActiveWorkspaceId === ws.id}
                          isMenuOpen={workspaceMenuId === ws.id}
                          colorPickerOpen={workspaceColorPickerId === ws.id}
                          sectionPickerOpen={workspaceSectionPickerId === ws.id}
                          spaceGroups={spaceGroups}
                          onSwitch={() => handleSwitch(ws.id)}
                          onToggleMenu={() => {
                            setWorkspaceMenuId(
                              workspaceMenuId === ws.id ? null : ws.id,
                            );
                            setWorkspaceSectionPickerId(null);
                          }}
                          onRename={() => {
                            setWorkspaceMenuId(null);
                            setModalType("rename");
                            setModalInputValue(ws.name);
                            setModalOpen(true);
                          }}
                          onDelete={() => {
                            setWorkspaceMenuId(null);
                            setDeletingWorkspaceId(ws.id);
                            setModalType("delete-workspace");
                            setModalOpen(true);
                          }}
                          onToggleColorPicker={() => {
                            setWorkspaceColorPickerId(
                              workspaceColorPickerId === ws.id ? null : ws.id,
                            );
                            setWorkspaceSectionPickerId(null);
                          }}
                          onToggleSectionPicker={() => {
                            setWorkspaceSectionPickerId(
                              workspaceSectionPickerId === ws.id ? null : ws.id,
                            );
                            setWorkspaceColorPickerId(null);
                          }}
                          onChangeColor={async (color) => {
                            await updateWorkspaceAction(ws.id, {
                              color: color ?? undefined,
                            });
                            setWorkspaceColorPickerId(null);
                            setWorkspaceMenuId(null);
                          }}
                          onMoveToSection={async (groupId) => {
                            await WorkspaceService.moveWorkspaceToGroup(
                              ws.id,
                              groupId,
                            );
                            setWorkspaceSectionPickerId(null);
                            setWorkspaceMenuId(null);
                            loadWorkspaces();
                          }}
                        />
                      </SortableNavItem>
                    ))}
                </SortableContext>
              </DroppableContainer>
            )}

            {/* Space Groups (Sections) */}
            <SortableContext
              items={spaceGroups.map((g) => g.id)}
              strategy={verticalListSortingStrategy}
            >
              {spaceGroups.map((group) => (
                <SortableNavItem
                  key={group.id}
                  id={group.id}
                  data={{ type: "SpaceGroup" }}
                >
                  <div style={{ marginTop: "8px" }}>
                    {/* Group Header */}
                    <DroppableContainer id={group.id} containerType="group">
                      <SidebarGroupHeader
                        group={group}
                        isMenuOpen={spaceGroupMenuId === group.id}
                        colorPickerOpen={colorPickerGroupId === group.id}
                        onToggleCollapse={() =>
                          toggleSpaceGroupCollapse(group.id)
                        }
                        onToggleMenu={() => {
                          setSpaceGroupMenuId(
                            spaceGroupMenuId === group.id ? null : group.id,
                          );
                          setColorPickerGroupId(null);
                        }}
                        onToggleColorPicker={() => {
                          setColorPickerGroupId(
                            colorPickerGroupId === group.id ? null : group.id,
                          );
                        }}
                        onRename={async () => {
                          setSpaceGroupMenuId(null);
                          // eslint-disable-next-line no-restricted-globals, no-alert
                          const newTitle = prompt(
                            "Rename section:",
                            group.title,
                          );
                          if (newTitle && newTitle !== group.title) {
                            await updateSpaceGroup(group.id, {
                              title: newTitle,
                            });
                          }
                        }}
                        onChangeColor={async (color) => {
                          // Pass null explicitly to clear color (not undefined which means "no change")
                          await updateSpaceGroup(group.id, {
                            color: color ?? null,
                          });
                          setColorPickerGroupId(null);
                          setSpaceGroupMenuId(null);
                        }}
                        onDelete={() => {
                          const groupId = group.id;
                          const groupTitle = group.title;
                          setSpaceGroupMenuId(null);
                          showConfirm(
                            "Delete Section",
                            `Delete section "${groupTitle}"? Spaces will become ungrouped.`,
                            () => {
                              deleteSpaceGroup(groupId);
                              closeConfirm();
                            },
                          );
                        }}
                      />
                    </DroppableContainer>

                    {/* Group Content */}
                    {!group.collapsed && (
                      <DroppableContainer
                        id={group.id}
                        className=""
                        containerType="group"
                      >
                        <SortableContext
                          items={getWorkspacesByGroupId(group.id).map(
                            (ws) => ws.id,
                          )}
                          strategy={verticalListSortingStrategy}
                        >
                          {getWorkspacesByGroupId(group.id).map((ws) => (
                            <SortableNavItem key={ws.id} id={ws.id}>
                              <WorkspaceMenuItem
                                workspace={ws}
                                isActive={effectiveActiveWorkspaceId === ws.id}
                                isMenuOpen={workspaceMenuId === ws.id}
                                colorPickerOpen={
                                  workspaceColorPickerId === ws.id
                                }
                                sectionPickerOpen={
                                  workspaceSectionPickerId === ws.id
                                }
                                spaceGroups={spaceGroups}
                                style={{ paddingLeft: "24px" }}
                                onSwitch={() => handleSwitch(ws.id)}
                                onToggleMenu={() => {
                                  setWorkspaceMenuId(
                                    workspaceMenuId === ws.id ? null : ws.id,
                                  );
                                  setWorkspaceSectionPickerId(null);
                                }}
                                onRename={() => {
                                  setWorkspaceMenuId(null);
                                  setModalType("rename");
                                  setModalInputValue(ws.name);
                                  setModalOpen(true);
                                }}
                                onDelete={() => {
                                  setWorkspaceMenuId(null);
                                  setDeletingWorkspaceId(ws.id);
                                  setModalType("delete-workspace");
                                  setModalOpen(true);
                                }}
                                onToggleColorPicker={() => {
                                  setWorkspaceColorPickerId(
                                    workspaceColorPickerId === ws.id
                                      ? null
                                      : ws.id,
                                  );
                                  setWorkspaceSectionPickerId(null);
                                }}
                                onToggleSectionPicker={() => {
                                  setWorkspaceSectionPickerId(
                                    workspaceSectionPickerId === ws.id
                                      ? null
                                      : ws.id,
                                  );
                                  setWorkspaceColorPickerId(null);
                                }}
                                onChangeColor={async (color) => {
                                  await updateWorkspaceAction(ws.id, {
                                    color: color ?? undefined,
                                  });
                                  setWorkspaceColorPickerId(null);
                                  setWorkspaceMenuId(null);
                                }}
                                onMoveToSection={async (groupId) => {
                                  await WorkspaceService.moveWorkspaceToGroup(
                                    ws.id,
                                    groupId,
                                  );
                                  setWorkspaceSectionPickerId(null);
                                  setWorkspaceMenuId(null);
                                  loadWorkspaces();
                                }}
                              />
                            </SortableNavItem>
                          ))}
                        </SortableContext>
                        {getWorkspacesByGroupId(group.id).length === 0 && (
                          <div
                            style={{
                              padding: "var(--spacing-md) var(--spacing-lg)",
                              textAlign: "center",
                              color: "var(--color-text-muted)",
                              fontSize: "var(--font-size-sm)",
                              fontStyle: "italic",
                            }}
                          >
                            <Icon
                              name="folder_open"
                              outlined
                              size="sm"
                              style={{
                                opacity: 0.4,
                                marginRight: "4px",
                                verticalAlign: "middle",
                              }}
                            />
                            Empty section • Drag spaces here
                          </div>
                        )}
                      </DroppableContainer>
                    )}
                  </div>
                </SortableNavItem>
              ))}
            </SortableContext>
          </div>
          <GhostOverlay
            activeId={activeId}
            activeWorkspace={activeWorkspace}
            workspaces={workspaces}
            spaceGroups={spaceGroups}
          />
        </DndContext>

        <UpdateBanner />
        {/* Sync Status Indicator - Footer */}
        <div
          style={{
            padding: "12px 16px",
            borderTop: "1px solid var(--color-border)",
            marginTop: "auto",
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
          }}
        >
          <SyncStatusIndicator />
          <span
            style={{
              fontSize: "var(--font-size-xs)",
              color: "var(--color-text-muted)",
              opacity: 0.6,
            }}
            title="Extension Version"
          >
            v{chrome?.runtime?.getManifest?.()?.version || "dev"}
            {buildIdentity
              ? ` · ${buildIdentity.channel} · ${buildIdentity.commit.slice(0, 7)}`
              : ""}
          </span>
        </div>
      </div>

      {/* Main Content */}
      <div className="main-content">
        {activeWorkspace ? (
          <>
            <div className="header-section">
              {isEditingWorkspaceName ? (
                <input
                  type="text"
                  className="section-title"
                  value={editingWorkspaceName}
                  onChange={(e) => setEditingWorkspaceName(e.target.value)}
                  onBlur={() => {
                    if (
                      editingWorkspaceName.trim() &&
                      editingWorkspaceName !== activeWorkspace.name
                    ) {
                      updateWorkspaceAction(activeWorkspace.id, {
                        name: editingWorkspaceName.trim(),
                      });
                    }
                    setIsEditingWorkspaceName(false);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      if (
                        editingWorkspaceName.trim() &&
                        editingWorkspaceName !== activeWorkspace.name
                      ) {
                        updateWorkspaceAction(activeWorkspace.id, {
                          name: editingWorkspaceName.trim(),
                        });
                      }
                      setIsEditingWorkspaceName(false);
                    } else if (e.key === "Escape") {
                      setIsEditingWorkspaceName(false);
                    }
                  }}
                  autoFocus
                  style={{
                    background: "transparent",
                    border: "1px solid var(--color-accent-primary)",
                    borderRadius: "4px",
                    padding: "4px 8px",
                    fontSize: "inherit",
                    fontWeight: "inherit",
                    color: "inherit",
                    outline: "none",
                    width: "auto",
                    minWidth: "150px",
                  }}
                />
              ) : (
                <h1
                  className="section-title"
                  onClick={() => {
                    setEditingWorkspaceName(activeWorkspace.name);
                    setIsEditingWorkspaceName(true);
                  }}
                  style={{ cursor: "pointer" }}
                  title="Click to rename"
                >
                  {activeWorkspace.name}
                </h1>
              )}
              <div
                className="flex gap-sm items-center"
                style={{ flex: 1, justifyContent: "center" }}
              >
                <div
                  className="search-bar"
                  onClick={() => setCommandPaletteOpen(true)}
                  role="button"
                  tabIndex={0}
                  title="Search across all spaces (Cmd+K)"
                >
                  <Icon name="search" size="sm" />
                  <span>Search across all spaces...</span>
                  <span className="search-shortcut">Cmd+K</span>
                </div>
              </div>
              <div
                className="flex gap-sm"
                style={{ minWidth: "80px", justifyContent: "flex-end" }}
              >
                {/* Share — hidden until sharing ships (M2: #139/#140). See #137. */}
                {FEATURE_FLAGS.SHARING_ENABLED && (
                  <button className="btn btn-primary">Share</button>
                )}
              </div>
            </div>

            {/* Content Tabs */}
            <div className="content-tabs">
              <div
                className={`tab-item ${activeTab === "resources" ? "active" : ""}`}
                onClick={() => setActiveTab("resources")}
              >
                Resources
              </div>
              <div
                className={`tab-item ${activeTab === "notes" ? "active" : ""}`}
                onClick={() => setActiveTab("notes")}
              >
                Notes
              </div>
              <div
                className={`tab-item ${activeTab === "tasks" ? "active" : ""}`}
                onClick={() => setActiveTab("tasks")}
              >
                Tasks
              </div>
            </div>

            {/* Drag Context Wrapper - Moved to Top Level Grid */}
            <DndContext
              sensors={sensors}
              collisionDetection={pointerWithin}
              onDragStart={handleDragStart}
              onDragEnd={handleDragEnd}
            >
              <div className="content-grid">
                {/* Left Column: Resources OR Notes */}
                {/* Left Column: Resources OR Notes */}
                <div className="card-section">
                  {activeTab === "resources" && (
                    <>
                      {/* Add Section Form */}
                      {showAddSection && (
                        <div
                          className="list-item"
                          style={{ marginBottom: "16px" }}
                        >
                          <input
                            type="text"
                            className="input"
                            placeholder="Section Title"
                            value={newSectionTitle}
                            onChange={(e) => setNewSectionTitle(e.target.value)}
                            autoFocus
                            onKeyDown={(e) => {
                              if (e.key === "Enter") handleCreateSection();
                              if (e.key === "Escape") setShowAddSection(false);
                            }}
                          />
                          <div className="flex gap-sm">
                            <button
                              className="btn btn-sm btn-primary"
                              onClick={handleCreateSection}
                            >
                              Save
                            </button>
                            <button
                              className="btn btn-sm btn-secondary"
                              onClick={() => setShowAddSection(false)}
                            >
                              Cancel
                            </button>
                          </div>
                        </div>
                      )}

                      {/* Add Resource Form */}
                      {showAddResource && (
                        <div
                          className="list-item"
                          style={{
                            flexDirection: "column",
                            alignItems: "stretch",
                            gap: "8px",
                            marginBottom: "16px",
                          }}
                        >
                          <div style={{ fontSize: "12px", color: "#666" }}>
                            Adding to:{" "}
                            {targetSectionId
                              ? sections.find((s) => s.id === targetSectionId)
                                  ?.title
                              : sections[0]?.title || "Resources"}
                          </div>
                          <input
                            type="text"
                            className="input"
                            placeholder="Title"
                            value={newResourceTitle}
                            onChange={(e) =>
                              setNewResourceTitle(e.target.value)
                            }
                            autoFocus
                          />
                          <input
                            type="text"
                            className="input"
                            placeholder="URL"
                            value={newResourceUrl}
                            onChange={(e) => setNewResourceUrl(e.target.value)}
                          />
                          <div className="flex gap-sm justify-end">
                            <button
                              className="btn btn-sm btn-secondary"
                              onClick={() => setShowAddResource(false)}
                            >
                              Cancel
                            </button>
                            <button
                              className="btn btn-sm btn-primary"
                              disabled={!newResourceUrl}
                              onClick={handleAddResource}
                            >
                              Save
                            </button>
                          </div>
                        </div>
                      )}

                      {/* Sections */}
                      <SortableContext
                        items={sections.map((s) => s.id)}
                        strategy={verticalListSortingStrategy}
                      >
                        {sections.map((section) => (
                          <div
                            key={section.id}
                            style={{ marginBottom: "16px" }}
                          >
                            {/* Sortable Section Wrapper */}
                            <SortableNavItem
                              id={section.id}
                              data={{ type: "Section" }}
                            >
                              <ResourceSection
                                key={section.id}
                                section={section}
                                activeWorkspace={activeWorkspace!}
                                collapsedSections={collapsedSections}
                                toggleSectionCollapse={toggleSectionCollapse}
                                openSectionMenuId={openSectionMenuId}
                                setOpenSectionMenuId={setOpenSectionMenuId}
                                onToggleSectionMenu={(id) =>
                                  setOpenSectionMenuId(id)
                                }
                                editingSectionId={editingSectionId}
                                setEditingSectionId={setEditingSectionId}
                                editingSectionName={editingSectionName}
                                setEditingSectionName={setEditingSectionName}
                                setWorkspaceSectionPickerId={
                                  setWorkspaceSectionPickerId
                                }
                                setTargetSectionId={setTargetSectionId}
                                setShowAddResource={setShowAddResource}
                                setActiveWorkspaceData={setActiveWorkspaceData}
                                handleOpenResource={handleOpenResource}
                                handleEditResource={handleEditResource}
                                showConfirm={showConfirm}
                                closeConfirm={closeConfirm}
                                loadWorkspaces={loadWorkspaces}
                              />
                            </SortableNavItem>
                          </div>
                        ))}
                      </SortableContext>

                      {/* Add Section Button at Bottom */}
                      {!showAddSection && (
                        <button
                          className="btn btn-sm btn-shaded"
                          style={{ width: "100%", marginTop: "8px" }}
                          onClick={() => setShowAddSection(true)}
                        >
                          <Icon name="add" size="sm" />
                          RESOURCE SECTION
                        </button>
                      )}

                      <GhostOverlay
                        activeId={activeId}
                        activeWorkspace={activeWorkspace}
                        workspaces={sortedWorkspaces}
                        spaceGroups={spaceGroups}
                      />
                    </>
                  )}
                  {activeTab === "notes" && (
                    /* NOTES TAB - Now using extracted NotesPanel component */
                    <NotesPanel
                      notes={notes}
                      workspaceId={activeWorkspace?.id}
                      showAddNote={showAddNote}
                      newNoteTitle={newNoteTitle}
                      newNoteContent={newNoteContent}
                      onShowAddNote={() => setShowAddNote(true)}
                      onCancelAddNote={() => setShowAddNote(false)}
                      onAddNote={handleAddNote}
                      onUpdateNote={handleUpdateNote}
                      onDeleteNote={handleDeleteNote}
                      onNewNoteTitleChange={setNewNoteTitle}
                      onNewNoteContentChange={setNewNoteContent}
                    />
                  )}
                  {activeTab === "tasks" && (
                    /* TASKS TAB - Now using extracted TasksPanel component */
                    <TasksPanel
                      tasks={tasks}
                      newTaskTitle={newTaskTitle}
                      onNewTaskTitleChange={setNewTaskTitle}
                      onAddTask={handleAddTask}
                      onToggleTask={handleToggleTask}
                      onDeleteTask={handleDeleteTask}
                    />
                  )}
                </div>

                {/* Right Column: Active Tabs - Now using extracted OpenTabsPanel */}
                <OpenTabsPanel
                  activeTabs={activeTabs}
                  tabGroups={activeWorkspace?.tabGroups || []}
                  onCloseTab={async (_tabId, tabUrl) => {
                    // Use URL-based close for bulletproof reliability
                    await closeTabByUrl(tabUrl);
                    // Update workspace data to remove the tab
                    if (activeWorkspace) {
                      const newTabs = activeWorkspace.tabs.filter(
                        (t) => t.url !== tabUrl,
                      );
                      setActiveWorkspaceData({
                        ...activeWorkspace,
                        tabs: newTabs,
                      });
                      await WorkspaceService.updateWorkspace(
                        activeWorkspace.id,
                        { tabs: newTabs },
                      );
                    }
                  }}
                  onEditTab={(tab) => {
                    if (tab.id) {
                      setEditingTabId(tab.id);
                      setModalInputValue(tab.title);
                      setModalUrlValue(tab.url);
                      setModalType("rename-tab");
                      setModalOpen(true);
                    }
                  }}
                  onActivateTab={async (_tabId, tab) => {
                    // Use URL-based focus for reliability
                    if (tab?.url) {
                      await focusTabByUrl(tab.url);
                    }
                  }}
                />
              </div>
            </DndContext>
          </>
        ) : (
          <div
            style={{
              display: "flex",
              justifyContent: "center",
              alignItems: "center",
              height: "100%",
            }}
          >
            <p>Select or create a workspace to get started.</p>
          </div>
        )}
      </div>
      <Modal
        isOpen={modalOpen && modalType !== "delete-workspace"}
        onClose={() => setModalOpen(false)}
        title={getModalTitle()}
        footer={
          <>
            <button
              className="btn btn-secondary"
              onClick={() => setModalOpen(false)}
            >
              Cancel
            </button>
            <button
              className="btn btn-primary"
              onClick={async () => {
                if (!modalInputValue.trim()) return;

                if (modalType === "create") {
                  // Use store action which handles deduplication
                  const newWs = await createWorkspaceAction({
                    name: modalInputValue,
                  });
                  // Optionally set active if needed, though most users might want to stay on current
                  if (!activeWorkspaceId) {
                    setActiveWorkspaceAction(newWs.id);
                  }
                } else if (
                  modalType === "rename-tab" &&
                  editingTabId &&
                  activeWorkspace
                ) {
                  const newTabs = activeWorkspace.tabs.map((t) =>
                    t.id === editingTabId
                      ? { ...t, title: modalInputValue, url: modalUrlValue }
                      : t,
                  );
                  setActiveWorkspaceData({ ...activeWorkspace, tabs: newTabs });
                  await WorkspaceService.updateWorkspace(activeWorkspace.id, {
                    tabs: newTabs,
                  });
                } else if (
                  modalType === "rename-resource" &&
                  editingResourceId &&
                  activeWorkspace
                ) {
                  if (editingResourceId.sectionId) {
                    await WorkspaceService.updateResourceInSection(
                      activeWorkspace.id,
                      editingResourceId.sectionId,
                      editingResourceId.id,
                      { title: modalInputValue, url: modalUrlValue },
                    );
                  }
                  loadWorkspaces();
                } else if (modalType === "create-section") {
                  if (modalInputValue) {
                    await createSpaceGroup(modalInputValue);
                  }
                  setModalOpen(false);
                } else if (activeWorkspace) {
                  await updateWorkspaceAction(activeWorkspace.id, {
                    name: modalInputValue,
                  });
                }
                setModalOpen(false);
              }}
            >
              {modalType === "create" || modalType === "create-section"
                ? "Create"
                : "Save"}
            </button>
          </>
        }
      >
        <div>
          <label className="label">
            {(() => {
              if (modalType === "rename-tab" || modalType === "rename-resource")
                return "Title";
              if (modalType === "create-section") return "Section Name";
              return "Workspace Name";
            })()}
          </label>
          <input
            type="text"
            className="input"
            value={modalInputValue}
            onChange={(e) => setModalInputValue(e.target.value)}
            placeholder="Enter name..."
            autoFocus
          />
        </div>
        {/* Show URL input only for rename-tab and rename-resource */}
        {(modalType === "rename-tab" || modalType === "rename-resource") && (
          <div style={{ marginTop: "12px" }}>
            <label className="label">URL</label>
            <input
              type="text"
              className="input"
              value={modalUrlValue}
              onChange={(e) => setModalUrlValue(e.target.value)}
              placeholder="Enter URL..."
            />
          </div>
        )}
      </Modal>

      {/* Delete Workspace Confirmation Modal */}
      <Modal
        isOpen={modalOpen && modalType === "delete-workspace"}
        onClose={() => {
          setModalOpen(false);
          setDeletingWorkspaceId(null);
        }}
        title="Delete Workspace"
        footer={
          <>
            <button
              className="btn btn-secondary"
              onClick={() => {
                setModalOpen(false);
                setDeletingWorkspaceId(null);
              }}
            >
              Cancel
            </button>
            <button
              className="btn btn-primary"
              style={{ backgroundColor: "#dc2626" }}
              onClick={async () => {
                if (deletingWorkspaceId) {
                  await deleteWorkspaceAction(deletingWorkspaceId);
                  setDeletingWorkspaceId(null);
                  setModalOpen(false);
                }
              }}
            >
              Delete
            </button>
          </>
        }
      >
        <p style={{ marginBottom: "8px" }}>
          Are you sure you want to delete this workspace?
        </p>
        <p style={{ color: "#666", fontSize: "14px" }}>
          This action cannot be undone. All saved tabs, resources, notes, and
          tasks in this workspace will be permanently deleted.
        </p>
      </Modal>

      {/* Account Settings Modal */}
      {showAccountSettings && (
        <AccountSettings
          onClose={() => setShowAccountSettings(false)}
          theme={theme}
          setTheme={setTheme}
          onReplayOnboarding={() => setShowOnboarding(true)}
        />
      )}

      {/* Workspace Conflict Resolution Popover */}
      {conflict && currentWindowId && (
        <TabConflictPopover
          ownerRecord={conflict.ownerRecord}
          currentWindowId={currentWindowId}
          onIgnore={clearConflict}
          onMoveComplete={() => {
            clearConflict();
            // After moving tabs, force switch to the target workspace (adopt mode, do not restore)
            forceSwitch(conflict.targetWorkspaceId, { restore: false });
          }}
        />
      )}

      {/* Cross-device "Changes from your other device" prompt */}
      {crossDeviceTabs && (
        <CrossDeviceSessionPopover
          serverTabs={crossDeviceTabs}
          onApply={handleCrossDeviceApply}
          onKeepMine={handleCrossDeviceKeepMine}
        />
      )}

      {/* Confirmation Modal */}
      <ConfirmModal
        open={confirmModal.open}
        title={confirmModal.title}
        message={confirmModal.message}
        onConfirm={confirmModal.onConfirm}
        onCancel={closeConfirm}
      />

      {/* Command Palette */}
      <CommandPalette
        isOpen={commandPaletteOpen}
        onClose={() => setCommandPaletteOpen(false)}
        onSwitchWorkspace={handleSwitch}
      />

      {/* First-run onboarding (#138) */}
      <OnboardingModal
        isOpen={showOnboarding}
        onSkip={finishOnboarding}
        onComplete={finishOnboarding}
        onCreateSpace={handleOnboardingCreateSpace}
        onAddResource={handleOnboardingAddResource}
        onSaveTabs={handleOnboardingSaveTabs}
      />
    </div>
  );
};
