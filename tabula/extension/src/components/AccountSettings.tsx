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

import React, { useState, useEffect } from "react";
import { ApiService } from "../services/api";
import { AuthService } from "../services/auth";
import { StorageService } from "../services/storage";
import { SyncService } from "../services/sync";
import { TabService } from "../services/tabs";
import type { UserProfile, Tab } from "../types";
import { Icon } from "./icons";
import { Modal } from "./Modal";

interface AccountSettingsProps {
  onClose: () => void;
  theme: string;
  setTheme: (theme: "system" | "light" | "dark") => void;
  /** 'popup' uses compact single-column layout, 'modal' uses sidebar layout */
  variant?: "popup" | "modal";
}

export const AccountSettings: React.FC<AccountSettingsProps> = ({
  onClose,
  theme,
  setTheme,
  variant = "modal",
}) => {
  const [user, setUser] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isEditing, setIsEditing] = useState(false);
  const [editedName, setEditedName] = useState("");
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [activeTab, setActiveTab] = useState<
    "account" | "preferences" | "backups"
  >("account");

  // Backup state
  const [backups, setBackups] = useState<
    Array<{
      id: string;
      workspaceId: string | null;
      sizeBytes: number | null;
      createdAt: string;
      workspaceName?: string;
    }>
  >([]);
  const [backupsLoading, setBackupsLoading] = useState(false);
  const [backupStats, setBackupStats] = useState<{
    totalBackups: number;
    totalSizeBytes: number;
  } | null>(null);

  const loadUserProfile = async () => {
    try {
      setLoading(true);
      // No session: show the signed-out prompt instead of letting the
      // request 401 into an "Authentication failed" dead end.
      if (!(await AuthService.getToken())) {
        setUser(null);
        setError(null);
        return;
      }
      const profile = await ApiService.getUserProfile();
      setUser(profile);
      setEditedName(profile.name);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load profile");
    } finally {
      setLoading(false);
    }
  };

  const handleSignIn = async () => {
    try {
      await AuthService.login();
      window.location.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Sign-in failed");
    }
  };

  useEffect(() => {
    loadUserProfile();
  }, []);

  const handleSaveName = async () => {
    if (!user) return;

    try {
      setLoading(true);
      const updated = await ApiService.updateUserProfile({ name: editedName });
      setUser(updated);
      setIsEditing(false);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to update name");
    } finally {
      setLoading(false);
    }
  };

  const handleChangePassword = async () => {
    if (!user) return;

    try {
      const resetUrl = await ApiService.getPasswordResetUrl(user.email);
      // Open password reset in new window
      window.open(resetUrl, "_blank", "width=600,height=700");
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Failed to open password reset",
      );
    }
  };

  const handleDeleteAccount = async () => {
    try {
      setLoading(true);
      await ApiService.deleteUserAccount();
      await AuthService.logout();
      // Reload to show login screen
      window.location.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to delete account");
      setLoading(false);
    }
  };

  const loadBackups = async () => {
    try {
      setBackupsLoading(true);
      const [backupResult, stats] = await Promise.all([
        ApiService.getBackups({ limit: 20 }),
        ApiService.getBackupStats(),
      ]);
      setBackups(backupResult.backups);
      setBackupStats(stats);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load backups");
    } finally {
      setBackupsLoading(false);
    }
  };

  // Track if we've already attempted to load backups to prevent infinite retry loop
  const hasAttemptedBackupsLoad = React.useRef(false);

  // Load backups when backups tab is selected (only once per tab visit).
  // Signed out the tab shows a sign-in prompt, so there is nothing to load.
  useEffect(() => {
    if (activeTab === "backups" && user && !hasAttemptedBackupsLoad.current) {
      hasAttemptedBackupsLoad.current = true;
      loadBackups();
    }
    // Reset when leaving backups tab so it reloads on next visit
    if (activeTab !== "backups") {
      hasAttemptedBackupsLoad.current = false;
    }
  }, [activeTab, user]);

  const handleCreateBackup = async () => {
    try {
      setBackupsLoading(true);
      await ApiService.createBackup({ type: "manual" });
      await loadBackups();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create backup");
      setBackupsLoading(false);
    }
  };

  const handleRestoreBackup = async (backupId: string) => {
    try {
      setBackupsLoading(true);

      // Suppress tab sync and LWW merging BEFORE anything changes — if the
      // flag were set only after tabs open (as before), a tab-sync firing
      // mid-restore would capture transitional state and clobber the restore.
      const forceRemoteUntil = Date.now() + 30000; // 30 seconds from now
      await chrome.storage.local.set({
        tabula_force_remote_until: forceRemoteUntil,
      });

      // Drop every queued (pre-restore) sync op: replaying them after the
      // restore would overwrite the restored server state with stale data.
      await SyncService.clearQueue();

      await ApiService.restoreBackup(backupId);

      // CRITICAL: Immediately fetch restored workspaces and save to local storage
      // This ensures local storage has the restored data BEFORE we reload
      const restoredWorkspaces = await ApiService.getWorkspaces();
      await StorageService.saveWorkspaces(restoredWorkspaces);

      // Get current browser tabs to determine which restored tabs need to be opened
      const currentBrowserTabs = await TabService.getCurrentTabs();
      const currentUrls = new Set(currentBrowserTabs.map((t) => t.url));

      // Find tabs from restored workspaces that aren't currently open in the browser
      // Try active workspace first, then fallback to first workspace with tabs
      const activeStoredWorkspace = await StorageService.getActiveWorkspaceId();
      let restoredWorkspace = restoredWorkspaces.find(
        (ws) => ws.id === activeStoredWorkspace,
      );

      // Fallback: if no matching workspace or it has no tabs, use first workspace with tabs
      if (!restoredWorkspace?.tabs || restoredWorkspace.tabs.length === 0) {
        restoredWorkspace = restoredWorkspaces.find(
          (ws) => ws.tabs && ws.tabs.length > 0,
        );
      }

      if (restoredWorkspace?.tabs && restoredWorkspace.tabs.length > 0) {
        // Filter to tabs not already open (by URL)
        const tabsToOpen: Tab[] = restoredWorkspace.tabs.filter(
          (tab) => tab.url && !currentUrls.has(tab.url),
        );

        if (tabsToOpen.length > 0) {
          await TabService.openTabs(tabsToOpen);
          // Wait for tabs to open before reload
          await new Promise<void>((resolve) => {
            setTimeout(resolve, 500);
          });
        }
      }

      // Refresh the force-remote window now that tabs are open (the original
      // 30s started before the restore; give the post-reload merge full
      // headroom too)
      await chrome.storage.local.set({
        tabula_force_remote_until: Date.now() + 30000,
      });

      // Reload page to reflect restored data
      window.location.reload();
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error("[handleRestoreBackup] Error:", err);
      setError(err instanceof Error ? err.message : "Failed to restore backup");
      setBackupsLoading(false);
    }
  };

  const handleDeleteBackup = async (backupId: string) => {
    try {
      setBackupsLoading(true);
      await ApiService.deleteBackup(backupId);
      await loadBackups();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to delete backup");
      setBackupsLoading(false);
    }
  };

  // Wrapper component based on variant
  const Wrapper: React.FC<{
    children: React.ReactNode;
    title?: string;
    size?: "small" | "large";
  }> =
    variant === "popup"
      ? ({ children }) => <>{children}</>
      : ({ children, title, size }) => (
          <Modal onClose={onClose} title={title || "Settings"} size={size}>
            {children}
          </Modal>
        );

  if (loading && !user) {
    return (
      <Wrapper title="Account Settings">
        <div
          style={{
            padding: "24px",
            textAlign: "center",
            minHeight: variant === "popup" ? "300px" : "auto",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <p>Loading...</p>
        </div>
      </Wrapper>
    );
  }

  if (error && !user) {
    // A token exists but the profile fetch failed (e.g. expired session) —
    // offer a fresh sign-in alongside retry so this isn't a dead end.
    return (
      <Wrapper title="Account Settings">
        <div style={{ padding: "24px" }}>
          <div
            style={{
              padding: "12px",
              backgroundColor: "#FEE2E2",
              color: "#991B1B",
              borderRadius: "4px",
              marginBottom: "16px",
            }}
          >
            {error}
          </div>
          <div style={{ display: "flex", gap: "8px" }}>
            <button className="btn btn-primary" onClick={handleSignIn}>
              Sign in again
            </button>
            <button className="btn btn-secondary" onClick={loadUserProfile}>
              Retry
            </button>
          </div>
        </div>
      </Wrapper>
    );
  }

  // Signed out (no token): the modal still renders — Preferences are local
  // and must stay usable — while the account-bound tabs show this prompt.
  const renderSignedOutPrompt = (message: string) => (
    <section>
      <p style={{ fontWeight: 600, marginBottom: "8px" }}>
        You&apos;re not signed in
      </p>
      <p
        style={{
          color: "var(--color-text-secondary)",
          marginBottom: "16px",
        }}
      >
        {message}
      </p>
      <button className="btn btn-primary" onClick={handleSignIn}>
        Sign in
      </button>
    </section>
  );

  // Shared tab content - Account
  const renderAccountContent = () => {
    if (!user) {
      return (
        <div>
          {variant === "modal" && (
            <h2
              style={{
                fontSize: "18px",
                fontWeight: "bold",
                marginBottom: "24px",
              }}
            >
              Account
            </h2>
          )}
          {renderSignedOutPrompt(
            "Your spaces work locally without an account. Sign in to sync " +
              "them across devices and enable backups.",
          )}
        </div>
      );
    }

    return (
      <div>
        {variant === "modal" && (
          <h2
            style={{
              fontSize: "18px",
              fontWeight: "bold",
              marginBottom: "24px",
            }}
          >
            Account
          </h2>
        )}

        {/* User Info Section */}
        <section
          style={{ marginBottom: variant === "popup" ? "20px" : "32px" }}
        >
          <h3
            style={{
              fontSize: variant === "popup" ? "12px" : "14px",
              fontWeight: "600",
              marginBottom: variant === "popup" ? "12px" : "16px",
              color: "var(--color-text-secondary)",
            }}
          >
            User Information
          </h3>

          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: variant === "popup" ? "12px" : "16px",
              marginBottom: "16px",
            }}
          >
            {/* Avatar Placeholder */}
            <div
              style={{
                width: variant === "popup" ? "48px" : "64px",
                height: variant === "popup" ? "48px" : "64px",
                borderRadius: "50%",
                backgroundColor: "var(--color-primary)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: variant === "popup" ? "18px" : "24px",
                fontWeight: "bold",
                color: "white",
                flexShrink: 0,
              }}
            >
              {user.name.charAt(0).toUpperCase()}
            </div>

            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ marginBottom: "6px" }}>
                <label
                  style={{
                    display: "block",
                    fontSize: "11px",
                    color: "var(--color-text-secondary)",
                    marginBottom: "2px",
                  }}
                >
                  Name
                </label>
                {isEditing ? (
                  <div style={{ display: "flex", gap: "6px" }}>
                    <input
                      type="text"
                      value={editedName}
                      onChange={(e) => setEditedName(e.target.value)}
                      style={{
                        flex: 1,
                        padding: "4px 8px",
                        border: "1px solid var(--color-border)",
                        borderRadius: "4px",
                        fontSize: "13px",
                        minWidth: 0,
                      }}
                    />
                    <button
                      className="btn btn-sm btn-primary"
                      onClick={handleSaveName}
                      disabled={loading}
                    >
                      Save
                    </button>
                    <button
                      className="btn btn-sm"
                      onClick={() => {
                        setIsEditing(false);
                        setEditedName(user.name);
                      }}
                      disabled={loading}
                    >
                      Cancel
                    </button>
                  </div>
                ) : (
                  <div
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: "6px",
                    }}
                  >
                    <span
                      className="text-ellipsis"
                      style={{
                        fontSize: "13px",
                        fontWeight: "500",
                        maxWidth: "150px",
                      }}
                    >
                      {user.name}
                    </span>
                    <button
                      className="btn-icon"
                      onClick={() => setIsEditing(true)}
                      title="Edit name"
                    >
                      <Icon name="edit" size="sm" />
                    </button>
                  </div>
                )}
              </div>

              <div>
                <label
                  style={{
                    display: "block",
                    fontSize: "11px",
                    color: "var(--color-text-secondary)",
                    marginBottom: "2px",
                  }}
                >
                  Email
                </label>
                <span
                  className="text-ellipsis"
                  style={{ fontSize: "13px", display: "block" }}
                >
                  {user.email}
                </span>
              </div>
            </div>
          </div>

          <div>
            <label
              style={{
                display: "block",
                fontSize: "11px",
                color: "var(--color-text-secondary)",
                marginBottom: "4px",
              }}
            >
              Plan
            </label>
            <span
              style={{
                display: "inline-block",
                padding: "2px 10px",
                backgroundColor: "var(--color-primary-light)",
                color: "var(--color-primary)",
                borderRadius: "12px",
                fontSize: "11px",
                fontWeight: "600",
                textTransform: "capitalize",
              }}
            >
              {user.tier}
            </span>
          </div>
        </section>

        {/* Password Section */}
        <section
          style={{ marginBottom: variant === "popup" ? "20px" : "32px" }}
        >
          <h3
            style={{
              fontSize: variant === "popup" ? "12px" : "14px",
              fontWeight: "600",
              marginBottom: variant === "popup" ? "8px" : "16px",
              color: "var(--color-text-secondary)",
            }}
          >
            Password
          </h3>
          <button
            className="btn btn-secondary btn-sm"
            onClick={handleChangePassword}
            style={{ fontSize: "12px" }}
          >
            Change Password
          </button>
        </section>

        {/* Danger Zone - Hidden in popup for space, only show in modal */}
        {variant === "modal" && (
          <section
            style={{
              marginTop: "48px",
              padding: "16px",
              border: "1px solid #FCA5A5",
              borderRadius: "8px",
              backgroundColor: "#FEF2F2",
            }}
          >
            <h3
              style={{
                fontSize: "14px",
                fontWeight: "600",
                marginBottom: "8px",
                color: "#991B1B",
              }}
            >
              Danger Zone
            </h3>
            <p
              style={{
                fontSize: "12px",
                color: "#991B1B",
                marginBottom: "12px",
              }}
            >
              Once you delete your account, there is no going back.
            </p>
            <button
              className="btn btn-danger"
              onClick={() => setShowDeleteConfirm(true)}
              disabled={loading}
            >
              Delete Account
            </button>
          </section>
        )}
      </div>
    );
  };

  // Shared tab content - Preferences
  const renderPreferencesContent = () => (
    <div>
      {variant === "modal" && (
        <h2
          style={{ fontSize: "18px", fontWeight: "bold", marginBottom: "24px" }}
        >
          Preferences
        </h2>
      )}

      <section>
        <h3
          style={{
            fontSize: variant === "popup" ? "12px" : "14px",
            fontWeight: "600",
            marginBottom: variant === "popup" ? "12px" : "16px",
            color: "var(--color-text-secondary)",
          }}
        >
          Appearance
        </h3>

        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            padding: variant === "popup" ? "10px" : "12px",
            border: "1px solid var(--color-border)",
            borderRadius: "8px",
            gap: "12px",
          }}
        >
          <div style={{ minWidth: 0 }}>
            <div
              style={{
                fontWeight: "500",
                fontSize: variant === "popup" ? "13px" : "14px",
                marginBottom: "2px",
              }}
            >
              Theme
            </div>
            <div
              style={{
                fontSize: "11px",
                color: "var(--color-text-secondary)",
                textTransform: "capitalize",
              }}
            >
              {theme}
            </div>
          </div>

          <div
            style={{
              display: "flex",
              gap: "4px",
              backgroundColor: "var(--color-bg-secondary)",
              padding: "3px",
              borderRadius: "6px",
              flexShrink: 0,
            }}
          >
            {(["system", "light", "dark"] as const).map((t) => (
              <button
                key={t}
                onClick={() => setTheme(t)}
                style={{
                  padding: "4px 10px",
                  border: "none",
                  borderRadius: "4px",
                  fontSize: "12px",
                  cursor: "pointer",
                  backgroundColor: theme === t ? "white" : "transparent",
                  color:
                    theme === t
                      ? "var(--color-primary)"
                      : "var(--color-text-secondary)",
                  boxShadow: theme === t ? "0 1px 2px rgba(0,0,0,0.1)" : "none",
                  fontWeight: theme === t ? 500 : 400,
                  textTransform: "capitalize",
                }}
              >
                {t}
              </button>
            ))}
          </div>
        </div>
      </section>
    </div>
  );

  // Shared tab content - Backups
  const renderBackupsContent = () => {
    if (!user) {
      return (
        <div>
          {variant === "modal" && (
            <h2
              style={{
                fontSize: "18px",
                fontWeight: "bold",
                marginBottom: "24px",
              }}
            >
              Backups
            </h2>
          )}
          {renderSignedOutPrompt(
            "Backups are stored in your account. Sign in to create and " +
              "restore them.",
          )}
        </div>
      );
    }

    return (
      <div>
        {variant === "modal" && (
          <h2
            style={{
              fontSize: "18px",
              fontWeight: "bold",
              marginBottom: "24px",
            }}
          >
            Backups
          </h2>
        )}

        {/* Backup Stats */}
        <section
          style={{ marginBottom: variant === "popup" ? "16px" : "24px" }}
        >
          <div
            style={{
              display: "flex",
              gap: "16px",
              flexWrap: "wrap",
              marginBottom: "16px",
            }}
          >
            <div
              data-testid="backup-stats-total"
              style={{
                flex: 1,
                minWidth: "120px",
                padding: "12px",
                backgroundColor: "var(--color-btn-shaded-bg)",
                borderRadius: "8px",
              }}
            >
              <div
                data-testid="backup-count"
                style={{ fontSize: "24px", fontWeight: "bold" }}
              >
                {backupStats?.totalBackups || 0}
              </div>
              <div
                style={{
                  fontSize: "12px",
                  color: "var(--color-text-secondary)",
                }}
              >
                Total Backups
              </div>
            </div>
            <div
              data-testid="backup-stats-storage"
              style={{
                flex: 1,
                minWidth: "120px",
                padding: "12px",
                backgroundColor: "var(--color-btn-shaded-bg)",
                borderRadius: "8px",
              }}
            >
              <div
                data-testid="storage-used"
                style={{ fontSize: "24px", fontWeight: "bold" }}
              >
                {backupStats
                  ? `${(backupStats.totalSizeBytes / 1024).toFixed(1)} KB`
                  : "0 KB"}
              </div>
              <div
                style={{
                  fontSize: "12px",
                  color: "var(--color-text-secondary)",
                }}
              >
                Storage Used
              </div>
            </div>
          </div>

          <button
            className="btn btn-primary"
            onClick={handleCreateBackup}
            disabled={backupsLoading}
            style={{ marginBottom: "16px" }}
          >
            {backupsLoading ? "Creating..." : "Create Backup Now"}
          </button>
        </section>

        {/* Backup List */}
        <section>
          <h3
            style={{
              fontSize: variant === "popup" ? "12px" : "14px",
              fontWeight: "600",
              marginBottom: "12px",
              color: "var(--color-text-secondary)",
            }}
          >
            Recent Backups
          </h3>

          {(() => {
            if (backupsLoading && backups.length === 0) {
              return (
                <div
                  style={{
                    textAlign: "center",
                    padding: "20px",
                    color: "var(--color-text-secondary)",
                  }}
                >
                  Loading backups...
                </div>
              );
            }
            if (backups.length === 0) {
              return (
                <div
                  style={{
                    textAlign: "center",
                    padding: "20px",
                    color: "var(--color-text-secondary)",
                  }}
                >
                  No backups yet. Create your first backup to protect your
                  workspaces.
                </div>
              );
            }
            return (
              <div
                style={{ display: "flex", flexDirection: "column", gap: "8px" }}
              >
                {backups.map((backup) => (
                  <div
                    key={backup.id}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      padding: "12px",
                      border: "1px solid var(--color-border)",
                      borderRadius: "8px",
                      gap: "12px",
                    }}
                  >
                    <div style={{ flex: 1 }}>
                      <div style={{ fontSize: "13px", fontWeight: "500" }}>
                        {backup.workspaceName || "All Workspaces"}
                      </div>
                      <div
                        style={{
                          fontSize: "11px",
                          color: "var(--color-text-secondary)",
                        }}
                      >
                        {new Date(backup.createdAt).toLocaleString()} •{" "}
                        {backup.sizeBytes
                          ? `${(backup.sizeBytes / 1024).toFixed(1)} KB`
                          : "N/A"}
                      </div>
                    </div>
                    <button
                      className="btn btn-sm btn-secondary"
                      onClick={() => handleRestoreBackup(backup.id)}
                      disabled={backupsLoading}
                      title="Restore this backup"
                    >
                      Restore
                    </button>
                    <button
                      className="btn btn-sm btn-danger"
                      onClick={() => handleDeleteBackup(backup.id)}
                      disabled={backupsLoading}
                      title="Delete this backup"
                      style={{ padding: "4px 8px" }}
                    >
                      <Icon name="delete" size="sm" />
                    </button>
                  </div>
                ))}
              </div>
            );
          })()}
        </section>

        {/* Tier Info */}
        <section style={{ marginTop: "24px" }}>
          <div
            style={{
              padding: "12px",
              backgroundColor: "var(--color-btn-shaded-bg)",
              borderRadius: "8px",
              fontSize: "12px",
              color: "var(--color-text-secondary)",
            }}
          >
            <strong>Backup Retention:</strong>{" "}
            {(() => {
              if (user?.tier === "free")
                return "30 days (upgrade to Pro for 90 days)";
              if (user?.tier === "pro") return "90 days";
              return "365 days";
            })()}
          </div>
        </section>
      </div>
    );
  };

  // Popup Layout - Compact with horizontal tabs
  if (variant === "popup") {
    return (
      <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
        {/* Header with back button */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "8px",
            paddingBottom: "12px",
            borderBottom: "1px solid var(--color-border)",
            marginBottom: "12px",
          }}
        >
          <button
            onClick={onClose}
            className="btn btn-secondary"
            style={{ padding: "4px 8px", borderRadius: "6px" }}
            title="Back"
          >
            <Icon name="arrow_back" size="sm" />
          </button>
          <h2 style={{ fontSize: "16px", fontWeight: "600", flex: 1 }}>
            Settings
          </h2>
        </div>

        {/* Horizontal Tabs */}
        <div
          style={{
            display: "flex",
            gap: "4px",
            marginBottom: "16px",
            backgroundColor: "var(--color-bg-card-hover)",
            padding: "3px",
            borderRadius: "8px",
          }}
        >
          <button
            onClick={() => setActiveTab("account")}
            style={{
              flex: 1,
              padding: "8px 12px",
              border: "none",
              borderRadius: "6px",
              fontSize: "12px",
              fontWeight: "500",
              cursor: "pointer",
              backgroundColor:
                activeTab === "account"
                  ? "var(--color-bg-card)"
                  : "transparent",
              color:
                activeTab === "account"
                  ? "var(--color-text-primary)"
                  : "var(--color-text-secondary)",
              boxShadow:
                activeTab === "account" ? "var(--shadow-card)" : "none",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: "6px",
            }}
          >
            <Icon name="person" size="sm" />
            Account
          </button>
          <button
            onClick={() => setActiveTab("preferences")}
            style={{
              flex: 1,
              padding: "8px 12px",
              border: "none",
              borderRadius: "6px",
              fontSize: "12px",
              fontWeight: "500",
              cursor: "pointer",
              backgroundColor:
                activeTab === "preferences"
                  ? "var(--color-bg-card)"
                  : "transparent",
              color:
                activeTab === "preferences"
                  ? "var(--color-text-primary)"
                  : "var(--color-text-secondary)",
              boxShadow:
                activeTab === "preferences" ? "var(--shadow-card)" : "none",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: "6px",
            }}
          >
            <Icon name="settings" size="sm" />
            Preferences
          </button>
          <button
            onClick={() => setActiveTab("backups")}
            style={{
              flex: 1,
              padding: "8px 12px",
              border: "none",
              borderRadius: "6px",
              fontSize: "12px",
              fontWeight: "500",
              cursor: "pointer",
              backgroundColor:
                activeTab === "backups"
                  ? "var(--color-bg-card)"
                  : "transparent",
              color:
                activeTab === "backups"
                  ? "var(--color-text-primary)"
                  : "var(--color-text-secondary)",
              boxShadow:
                activeTab === "backups" ? "var(--shadow-card)" : "none",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: "6px",
            }}
          >
            <Icon name="backup" size="sm" />
            Backups
          </button>
        </div>

        {/* Error Display */}
        {error && (
          <div
            style={{
              padding: "8px 12px",
              backgroundColor: "#FEE2E2",
              color: "#991B1B",
              borderRadius: "6px",
              marginBottom: "12px",
              fontSize: "12px",
            }}
          >
            {error}
          </div>
        )}

        {/* Content */}
        <div style={{ flex: 1, overflowY: "auto" }}>
          {activeTab === "account" && renderAccountContent()}
          {activeTab === "preferences" && renderPreferencesContent()}
          {activeTab === "backups" && renderBackupsContent()}
        </div>

        {/* Delete Confirmation Modal */}
        {showDeleteConfirm && (
          <Modal
            onClose={() => setShowDeleteConfirm(false)}
            title="Delete Account"
            size="small"
          >
            <div style={{ padding: "24px" }}>
              <p style={{ marginBottom: "16px", fontSize: "14px" }}>
                Are you sure you want to delete your account?
              </p>
              <div
                style={{
                  display: "flex",
                  gap: "8px",
                  justifyContent: "flex-end",
                }}
              >
                <button
                  className="btn btn-secondary"
                  onClick={() => setShowDeleteConfirm(false)}
                  disabled={loading}
                >
                  Cancel
                </button>
                <button
                  className="btn btn-danger"
                  onClick={handleDeleteAccount}
                  disabled={loading}
                >
                  {loading ? "Deleting..." : "Delete"}
                </button>
              </div>
            </div>
          </Modal>
        )}
      </div>
    );
  }

  // Modal Layout - Original sidebar design
  return (
    <Modal onClose={onClose} title="Settings" size="large">
      <div style={{ display: "flex", height: "500px" }}>
        {/* Sidebar Navigation */}
        <div
          style={{
            width: "200px",
            borderRight: "1px solid var(--color-border)",
            padding: "16px",
            backgroundColor: "var(--color-btn-shaded-bg)",
          }}
        >
          <nav>
            <button
              className={`nav-item ${activeTab === "account" ? "active" : ""}`}
              onClick={() => setActiveTab("account")}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "8px",
                width: "100%",
                padding: "8px 12px",
                border: "none",
                background:
                  activeTab === "account"
                    ? "var(--color-primary-light)"
                    : "transparent",
                borderRadius: "4px",
                cursor: "pointer",
                fontSize: "14px",
                marginBottom: "4px",
              }}
            >
              <Icon name="person" size="sm" />
              Account
            </button>
            <button
              className={`nav-item ${activeTab === "preferences" ? "active" : ""}`}
              onClick={() => setActiveTab("preferences")}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "8px",
                width: "100%",
                padding: "8px 12px",
                border: "none",
                background:
                  activeTab === "preferences"
                    ? "var(--color-primary-light)"
                    : "transparent",
                borderRadius: "4px",
                cursor: "pointer",
                fontSize: "14px",
              }}
            >
              <Icon name="settings" size="sm" />
              Preferences
            </button>
            <button
              className={`nav-item ${activeTab === "backups" ? "active" : ""}`}
              onClick={() => setActiveTab("backups")}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "8px",
                width: "100%",
                padding: "8px 12px",
                border: "none",
                background:
                  activeTab === "backups"
                    ? "var(--color-primary-light)"
                    : "transparent",
                borderRadius: "4px",
                cursor: "pointer",
                fontSize: "14px",
              }}
            >
              <Icon name="backup" size="sm" />
              Backups
            </button>
          </nav>
        </div>

        {/* Main Content */}
        <div style={{ flex: 1, padding: "24px", overflowY: "auto" }}>
          {error && (
            <div
              style={{
                padding: "12px",
                backgroundColor: "#FEE2E2",
                color: "#991B1B",
                borderRadius: "4px",
                marginBottom: "16px",
                fontSize: "14px",
              }}
            >
              {error}
            </div>
          )}

          {activeTab === "account" && renderAccountContent()}
          {activeTab === "preferences" && renderPreferencesContent()}
          {activeTab === "backups" && renderBackupsContent()}
        </div>
      </div>

      {/* Delete Confirmation Modal */}
      {showDeleteConfirm && (
        <Modal
          onClose={() => setShowDeleteConfirm(false)}
          title="Delete Account"
          size="small"
        >
          <div style={{ padding: "24px" }}>
            <p style={{ marginBottom: "16px", fontSize: "14px" }}>
              Are you sure you want to delete your account? This action cannot
              be undone.
            </p>
            <p
              style={{
                marginBottom: "24px",
                fontSize: "14px",
                fontWeight: "bold",
                color: "#991B1B",
              }}
            >
              All your data will be permanently deleted.
            </p>
            <div
              style={{
                display: "flex",
                gap: "8px",
                justifyContent: "flex-end",
              }}
            >
              <button
                className="btn btn-secondary"
                onClick={() => setShowDeleteConfirm(false)}
                disabled={loading}
              >
                Cancel
              </button>
              <button
                className="btn btn-danger"
                onClick={handleDeleteAccount}
                disabled={loading}
              >
                {loading ? "Deleting..." : "Delete My Account"}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </Modal>
  );
};
