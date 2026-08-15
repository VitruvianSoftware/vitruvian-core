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

import React, { useEffect, useState } from "react";
import { useWorkspaceStore } from "../stores/workspace";
import { WorkspaceCard } from "../components/WorkspaceCard";
import { WorkspaceForm } from "../components/WorkspaceForm";
import { Login } from "../components/Login";
import { AccountSettings } from "../components/AccountSettings";
import { AuthService, type User } from "../services/auth";
import { ApiService } from "../services/api";
import { SyncService } from "../services/sync";
import { WindowOwnershipService } from "../services/windowOwnership";
import type { Workspace, WorkspaceCreateInput } from "../types";
import { Icon } from "../components/icons";
import { useTheme } from "../hooks/useTheme";
import { ConfirmModal } from "../dashboard/ConfirmModal";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";
import { Button } from "@vitruviansoftware/design-system";

// Import styles
import "../styles/global.css";
import "../styles/components.css";

type View = "list" | "create" | "edit"; // Removed 'settings' from View type
type AuthView = "login" | "app";

/**
 * Main popup component for Tabula extension
 */
const Popup: React.FC = () => {
  const {
    workspaces: storeWorkspaces,
    activeWorkspaceId,
    loading,
    error,
    loadWorkspaces,
    createWorkspace,
    updateWorkspace,
    deleteWorkspace,
    saveCurrentTabs,
    restoreTabs,
    switchWorkspace,
  } = useWorkspaceStore();

  // Defensive fallback to ensure workspaces is always an array
  const workspaces = storeWorkspaces || [];

  const [authView, setAuthView] = useState<AuthView>("login"); // Default to login while checking
  const [user, setUser] = useState<User | null>(null);
  const [view, setView] = useState<View>("list");
  const [editingWorkspace, setEditingWorkspace] = useState<Workspace | null>(
    null,
  );
  const [initLoading, setInitLoading] = useState(true);
  const [showAccountSettings, setShowAccountSettings] = useState(false);
  const [deleteConfirmOpen, setDeleteConfirmOpen] = useState(false);
  const [workspaceToDelete, setWorkspaceToDelete] = useState<string | null>(
    null,
  );
  const [ownershipNotice, setOwnershipNotice] = useState<string | null>(null);
  /* eslint-disable-next-line @typescript-eslint/no-explicit-any */
  const { theme, setTheme } = useTheme();
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  // Check auth status on mount
  useEffect(() => {
    const checkAuth = async () => {
      try {
        const storedUser = await AuthService.getUser();
        if (storedUser) {
          setUser(storedUser);
          setAuthView("app");
          loadWorkspaces();
          // Re-project the authoritative server profile over the cached user so
          // a name corrupted by an older mis-encoded login (mojibake) self-heals
          // without a re-login. Best-effort; never throws.
          ApiService.refreshCachedUser().then((refreshed) => {
            if (refreshed) setUser(refreshed);
          });
        } else {
          setAuthView("login");
        }
      } catch (e) {
        console.error("Auth check failed", e);
      } finally {
        setInitLoading(false);
      }
    };
    checkAuth();
  }, [loadWorkspaces]);

  const handleLoginSuccess = async () => {
    const storedUser = await AuthService.getUser();
    setUser(storedUser);
    setAuthView("app");
    loadWorkspaces();
  };

  const handleLogout = async () => {
    // The popup never reloads, so SyncService's static state would otherwise
    // survive logout — reset it and close the SSE stream before clearing auth.
    await SyncService.clearQueue();
    SyncService.disconnectSSE();
    await AuthService.logout();
    setUser(null);
    setAuthView("login");
  };

  const handleCreateWorkspace = async (input: WorkspaceCreateInput) => {
    try {
      await createWorkspace(input);
      setView("list");
    } catch (err) {
      // Error is handled by store
    }
  };

  const handleUpdateWorkspace = async (input: WorkspaceCreateInput) => {
    if (!editingWorkspace) return;
    try {
      await updateWorkspace(editingWorkspace.id, input);
      setView("list");
      setEditingWorkspace(null);
    } catch (err) {
      // Error is handled by store
    }
  };

  const handleDeleteWorkspace = async (id: string) => {
    setWorkspaceToDelete(id);
    setDeleteConfirmOpen(true);
  };

  const handleConfirmDelete = async () => {
    if (workspaceToDelete) {
      try {
        await deleteWorkspace(workspaceToDelete);
      } catch (err) {
        // Error is handled by store
      } finally {
        setDeleteConfirmOpen(false);
        setWorkspaceToDelete(null);
      }
    }
  };

  const handleEdit = (workspace: Workspace) => {
    setEditingWorkspace(workspace);
    setView("edit");
  };

  const renderHeader = () => (
    <div
      className="popup-header"
      style={{
        marginBottom: "16px",
        paddingBottom: "16px",
        borderBottom: useDesignSystem
          ? "1px solid var(--color-text, #1f1d1a)"
          : "1px solid var(--color-border)",
      }}
    >
      {/* Top row: Branding and User Info */}
      <div
        className="flex justify-between items-center"
        style={{ marginBottom: "12px" }}
      >
        <div className="flex items-center gap-sm">
          <h1
            className={useDesignSystem ? undefined : "text-primary"}
            style={
              useDesignSystem
                ? {
                    fontSize: "18px",
                    fontWeight: 700,
                    fontFamily: "var(--font-mono, monospace)",
                    letterSpacing: "-0.02em",
                    color: "var(--color-text, #1f1d1a)",
                    margin: 0,
                  }
                : {
                    fontSize: "20px",
                    fontWeight: "700",
                    letterSpacing: "-0.3px",
                  }
            }
          >
            Tabula
          </h1>
        </div>

        {user && (
          <div
            className="flex items-center gap-xs"
            style={
              useDesignSystem
                ? {
                    padding: "3px 8px",
                    borderRadius: "0",
                    backgroundColor:
                      "var(--color-bg-card-hover, rgba(0,0,0,0.04))",
                    border: "1px solid var(--color-text, #1f1d1a)",
                    maxWidth: "140px",
                  }
                : {
                    padding: "4px 10px",
                    borderRadius: "16px",
                    backgroundColor: "var(--color-bg-card-hover)",
                    border: "1px solid var(--color-border)",
                    maxWidth: "140px",
                  }
            }
          >
            <span
              style={{
                width: "6px",
                height: "6px",
                borderRadius: useDesignSystem ? "0" : "50%",
                backgroundColor: useDesignSystem
                  ? "var(--color-text, #1f1d1a)"
                  : "var(--color-accent-success)",
                flexShrink: 0,
              }}
            />
            <span
              className="text-ellipsis"
              style={{
                fontSize: "11px",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
                color: useDesignSystem
                  ? "var(--color-text, #1f1d1a)"
                  : "var(--color-text-secondary)",
                fontWeight: "500",
              }}
            >
              {user.name}
            </span>
          </div>
        )}
      </div>

      {/* Bottom row: Actions */}
      <div className="flex justify-between items-center">
        {useDesignSystem ? (
          <Button
            variant="secondary"
            size="sm"
            onClick={() =>
              chrome.tabs.create({
                url: "dashboard.html",
                pinned: true,
                active: true,
              })
            }
          >
            <Icon name="dashboard" size="sm" />
            <span style={{ marginLeft: "6px" }}>Dashboard</span>
          </Button>
        ) : (
          <button
            className="btn btn-secondary"
            style={{
              fontSize: "12px",
              padding: "6px 12px",
              borderRadius: "6px",
            }}
            onClick={() =>
              chrome.tabs.create({
                url: "dashboard.html",
                pinned: true,
                active: true,
              })
            }
          >
            <Icon name="dashboard" size="sm" />
            <span style={{ marginLeft: "6px" }}>Dashboard</span>
          </button>
        )}

        <div className="flex items-center gap-xs">
          {view === "list" &&
            (useDesignSystem ? (
              <Button
                variant="primary"
                size="sm"
                onClick={() => setView("create")}
                disabled={workspaces.length >= 10}
              >
                <span style={{ marginRight: "4px" }}>+</span> New Space
              </Button>
            ) : (
              <button
                type="button"
                onClick={() => setView("create")}
                className="btn btn-primary"
                disabled={workspaces.length >= 10}
                style={{
                  fontSize: "12px",
                  padding: "6px 12px",
                  borderRadius: "6px",
                }}
              >
                <span style={{ marginRight: "4px" }}>+</span> New Space
              </button>
            ))}
          {useDesignSystem ? (
            <>
              <Button
                variant="secondary"
                size="sm"
                onClick={() => setShowAccountSettings(true)}
                title="Settings"
              >
                <Icon name="settings" size="sm" />
              </Button>
              <Button
                variant="secondary"
                size="sm"
                onClick={handleLogout}
                title="Sign out"
              >
                <Icon name="logout" size="sm" />
              </Button>
            </>
          ) : (
            <>
              <button
                type="button"
                onClick={() => setShowAccountSettings(true)}
                className="btn btn-secondary"
                title="Settings"
                style={{
                  padding: "6px 8px",
                  borderRadius: "6px",
                }}
              >
                <Icon name="settings" size="sm" />
              </button>
              <button
                type="button"
                onClick={handleLogout}
                className="btn btn-secondary"
                title="Sign out"
                style={{
                  padding: "6px 8px",
                  borderRadius: "6px",
                }}
              >
                <Icon name="logout" size="sm" />
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );

  // Ownership-aware actions: a workspace that is live in another window must
  // not be overwritten with (or switched onto) this window's tabs — that
  // would silently erase the owner's state on its next sync.
  const handleSaveTabs = async (workspaceId: string) => {
    setOwnershipNotice(null);
    const win = await chrome.windows.getCurrent();
    if (win.id) {
      const owner = await WindowOwnershipService.isWorkspaceOwnedByOtherWindow(
        workspaceId,
        win.id,
      );
      if (owner) {
        setOwnershipNotice(
          "This workspace is live in another window — switching to that window instead of overwriting it.",
        );
        await WindowOwnershipService.focusOwnerWindow(owner).catch(
          () => undefined,
        );
        return;
      }
    }
    await saveCurrentTabs(workspaceId);
  };

  const handleSwitchTo = async (workspaceId: string) => {
    setOwnershipNotice(null);
    const win = await chrome.windows.getCurrent();
    if (win.id) {
      const claim = await WindowOwnershipService.tryClaimWorkspace(
        workspaceId,
        win.id,
        -1,
      );
      if (!claim.claimed) {
        setOwnershipNotice(
          "This workspace is already open in another window — focusing it.",
        );
        await WindowOwnershipService.focusOwnerWindow(claim.owner).catch(
          () => undefined,
        );
        return;
      }
    }
    await switchWorkspace(workspaceId);
  };

  const renderList = () => (
    <>
      <div
        style={{
          marginBottom: "12px",
          fontSize: "11px",
          fontFamily: useDesignSystem
            ? "var(--font-mono, monospace)"
            : undefined,
          color: useDesignSystem
            ? "var(--color-text-dim, #736d64)"
            : "var(--color-text-secondary)",
          textTransform: useDesignSystem ? "uppercase" : undefined,
        }}
      >
        {workspaces.length} / 10 workspaces used
      </div>

      {ownershipNotice && (
        <div
          className="card"
          role="status"
          style={{
            marginBottom: "12px",
            padding: "10px 12px",
            fontSize: "12px",
            color: "var(--color-text-secondary)",
            borderColor: "var(--color-primary)",
          }}
        >
          {ownershipNotice}
        </div>
      )}

      {workspaces.length === 0 ? (
        <div
          className={useDesignSystem ? undefined : "card bg-card-hover"}
          style={
            useDesignSystem
              ? {
                  textAlign: "center",
                  padding: "36px 20px",
                  color: "var(--color-text-dim, #736d64)",
                  border: "1px dashed var(--color-text, #1f1d1a)",
                  backgroundColor: "var(--color-bg, #fbf7ee)",
                  fontFamily: "var(--font-mono, monospace)",
                }
              : {
                  textAlign: "center",
                  padding: "40px 24px",
                  color: "var(--color-text-secondary)",
                  borderStyle: "dashed",
                }
          }
        >
          <p
            className="text-main"
            style={{ marginBottom: "8px", fontWeight: "500" }}
          >
            No workspaces yet
          </p>
          <p style={{ fontSize: "12px" }}>
            Create a space to organize your tabs!
          </p>
        </div>
      ) : (
        <div style={{ maxHeight: "420px", overflowY: "auto" }}>
          {workspaces.map((workspace) => (
            <WorkspaceCard
              key={workspace.id}
              workspace={workspace}
              isActive={workspace.id === activeWorkspaceId}
              onSaveTabs={() => handleSaveTabs(workspace.id)}
              onRestoreTabs={() =>
                restoreTabs(workspace.id, { inNewWindow: true })
              }
              onSwitch={() => handleSwitchTo(workspace.id)}
              onEdit={() => handleEdit(workspace)}
              onDelete={() => handleDeleteWorkspace(workspace.id)}
            />
          ))}
        </div>
      )}
    </>
  );

  const renderForm = () => (
    <WorkspaceForm
      workspace={view === "edit" ? editingWorkspace || undefined : undefined}
      onSubmit={view === "edit" ? handleUpdateWorkspace : handleCreateWorkspace}
      onCancel={() => {
        setView("list");
        setEditingWorkspace(null);
      }}
    />
  );

  if (initLoading) {
    return (
      <div style={{ padding: "40px", textAlign: "center", color: "#6B7280" }}>
        Loading Tabula...
      </div>
    );
  }

  // Auth Views
  if (authView === "login") {
    return (
      <div
        data-design-system={useDesignSystem ? "true" : "false"}
        style={{
          padding: "24px",
          width: "360px",
          backgroundColor: useDesignSystem
            ? "var(--color-bg, #fbf7ee)"
            : undefined,
          fontFamily: "var(--font-family)",
        }}
      >
        <h1
          style={{
            textAlign: "center",
            color: useDesignSystem
              ? "var(--color-text, #1f1d1a)"
              : "var(--color-primary)",
            fontFamily: useDesignSystem
              ? "var(--font-mono, monospace)"
              : undefined,
            marginBottom: "24px",
          }}
        >
          Tabula
        </h1>
        <Login onSuccess={handleLoginSuccess} />
      </div>
    );
  }

  // App View
  return (
    <div
      className={useDesignSystem ? undefined : "bg-page text-main"}
      data-design-system={useDesignSystem ? "true" : "false"}
      style={{
        width: "400px",
        minHeight: "400px",
        maxHeight: "600px",
        padding: "20px",
        backgroundColor: useDesignSystem
          ? "var(--color-bg, #fbf7ee)"
          : undefined,
        color: useDesignSystem ? "var(--color-text, #1f1d1a)" : undefined,
        fontFamily: "var(--font-family)",
      }}
    >
      {showAccountSettings ? (
        <AccountSettings
          onClose={() => setShowAccountSettings(false)}
          theme={theme}
          setTheme={setTheme}
          variant="popup"
        />
      ) : (
        <>
          {renderHeader()}

          {error && <div className="error-message">{error}</div>}

          {loading && (
            <div
              style={{ textAlign: "center", padding: "24px", color: "#6B7280" }}
            >
              Syncing...
            </div>
          )}

          {!loading && view === "list" && renderList()}
          {!loading && (view === "create" || view === "edit") && renderForm()}
        </>
      )}

      {/* Delete Confirmation Modal */}
      <ConfirmModal
        open={deleteConfirmOpen}
        title="Delete Workspace"
        message="Are you sure you want to delete this workspace? This action cannot be undone."
        onConfirm={handleConfirmDelete}
        onCancel={() => {
          setDeleteConfirmOpen(false);
          setWorkspaceToDelete(null);
        }}
      />
    </div>
  );
};

export default Popup;
