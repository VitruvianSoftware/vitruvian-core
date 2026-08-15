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
import { UpdateCheckService } from "../services/updateCheck";
import type { Channel } from "../services/updateCheck";
import { useFeatureFlag, setFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";
import {
  Button,
  Input,
  Tag,
  Label,
  Switch,
  Segmented,
} from "@vitruviansoftware/design-system";

interface AccountSettingsProps {
  onClose: () => void;
  theme: string;
  setTheme: (theme: "system" | "light" | "dark") => void;
  /** 'popup' uses compact single-column layout, 'modal' uses sidebar layout */
  variant?: "popup" | "modal";
  /** Replay the first-run onboarding flow (#138). Hidden when omitted. */
  onReplayOnboarding?: () => void;
}

export const AccountSettings: React.FC<AccountSettingsProps> = ({
  onClose,
  theme,
  setTheme,
  variant = "modal",
  onReplayOnboarding,
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

  const [devIdentity, setDevIdentity] = useState<{
    channel: Channel;
    commit: string;
    version: string;
  } | null>(null);
  const [selectedChannel, setSelectedChannel] = useState<string | null>(null);
  const [copiedCommand, setCopiedCommand] = useState(false);
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  useEffect(() => {
    let cancelled = false;
    UpdateCheckService.getDisplayIdentity().then((identity) => {
      if (!cancelled) setDevIdentity(identity);
    });
    return () => {
      cancelled = true;
    };
  }, []);

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
      if (!(await AuthService.hasSession())) {
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

  const hasAttemptedBackupsLoad = React.useRef(false);

  useEffect(() => {
    if (activeTab === "backups" && user && !hasAttemptedBackupsLoad.current) {
      hasAttemptedBackupsLoad.current = true;
      loadBackups();
    }
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

      const forceRemoteUntil = Date.now() + 30000;
      await chrome.storage.local.set({
        tabula_force_remote_until: forceRemoteUntil,
      });

      await SyncService.clearQueue();

      await ApiService.restoreBackup(backupId);

      const restoredWorkspaces = await ApiService.getWorkspaces();
      await StorageService.saveWorkspaces(restoredWorkspaces);

      const currentBrowserTabs = await TabService.getCurrentTabs();
      const currentUrls = new Set(currentBrowserTabs.map((t) => t.url));

      const activeStoredWorkspace = await StorageService.getActiveWorkspaceId();
      let restoredWorkspace = restoredWorkspaces.find(
        (ws) => ws.id === activeStoredWorkspace,
      );

      if (!restoredWorkspace?.tabs || restoredWorkspace.tabs.length === 0) {
        restoredWorkspace = restoredWorkspaces.find(
          (ws) => ws.tabs && ws.tabs.length > 0,
        );
      }

      if (restoredWorkspace?.tabs && restoredWorkspace.tabs.length > 0) {
        const tabsToOpen: Tab[] = restoredWorkspace.tabs.filter(
          (tab) => tab.url && !currentUrls.has(tab.url),
        );

        if (tabsToOpen.length > 0) {
          await TabService.openTabs(tabsToOpen);
          await new Promise<void>((resolve) => {
            setTimeout(resolve, 500);
          });
        }
      }

      await chrome.storage.local.set({
        tabula_force_remote_until: Date.now() + 30000,
      });

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
            fontFamily: useDesignSystem
              ? "var(--font-mono, monospace)"
              : undefined,
          }}
        >
          <p>Loading...</p>
        </div>
      </Wrapper>
    );
  }

  if (error && !user) {
    return (
      <Wrapper title="Account Settings">
        <div style={{ padding: "24px" }}>
          <div
            style={{
              padding: "12px",
              backgroundColor: useDesignSystem
                ? "rgba(185, 28, 28, 0.08)"
                : "#FEE2E2",
              color: "#991B1B",
              borderRadius: useDesignSystem ? "0" : "4px",
              border: useDesignSystem ? "1px solid #b91c1c" : undefined,
              marginBottom: "16px",
            }}
          >
            {error}
          </div>
          <div style={{ display: "flex", gap: "8px" }}>
            {useDesignSystem ? (
              <>
                <Button variant="primary" onClick={handleSignIn}>
                  Sign in again
                </Button>
                <Button variant="secondary" onClick={loadUserProfile}>
                  Retry
                </Button>
              </>
            ) : (
              <>
                <>
                  {useDesignSystem ? (
                    <Button variant="primary" onClick={handleSignIn}>
                      Sign in again
                    </Button>
                  ) : (
                    <button className="btn btn-primary" onClick={handleSignIn}>
                      Sign in again
                    </button>
                  )}
                </>
                <>
                  {useDesignSystem ? (
                    <Button variant="secondary" onClick={loadUserProfile}>
                      Retry
                    </Button>
                  ) : (
                    <button
                      className="btn btn-secondary"
                      onClick={loadUserProfile}
                    >
                      Retry
                    </button>
                  )}
                </>
              </>
            )}
          </div>
        </div>
      </Wrapper>
    );
  }

  const renderSignedOutPrompt = (message: string) => (
    <section>
      <p style={{ fontWeight: 600, marginBottom: "8px" }}>
        You&apos;re not signed in
      </p>
      <p
        style={{
          color: useDesignSystem
            ? "var(--color-text-secondary)"
            : "var(--color-text-secondary)",
          marginBottom: "16px",
        }}
      >
        {message}
      </p>
      {useDesignSystem ? (
        <Button variant="primary" onClick={handleSignIn}>
          Sign in
        </Button>
      ) : (
        <button className="btn btn-primary" onClick={handleSignIn}>
          Sign in
        </button>
      )}
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
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
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
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
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
              color: useDesignSystem
                ? "var(--color-text-secondary)"
                : "var(--color-text-secondary)",
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
              textTransform: useDesignSystem ? "uppercase" : undefined,
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
            {/* Avatar */}
            <div
              style={{
                width: variant === "popup" ? "48px" : "64px",
                height: variant === "popup" ? "48px" : "64px",
                borderRadius: useDesignSystem ? "0" : "50%",
                backgroundColor: "var(--color-primary)",
                border: useDesignSystem
                  ? "1px solid var(--color-border)"
                  : "none",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: variant === "popup" ? "18px" : "24px",
                fontWeight: "bold",
                color: "white",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
                flexShrink: 0,
              }}
            >
              {user.name.charAt(0).toUpperCase()}
            </div>

            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ marginBottom: "6px" }}>
                {useDesignSystem ? (
                  <Label style={{ display: "block", marginBottom: "2px" }}>
                    Name
                  </Label>
                ) : (
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
                )}
                {isEditing ? (
                  <div style={{ display: "flex", gap: "6px" }}>
                    {useDesignSystem ? (
                      <>
                        <Input
                          value={editedName}
                          onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                            setEditedName(e.target.value)
                          }
                          style={{ flex: 1, minWidth: 0 }}
                        />
                        <Button
                          variant="primary"
                          size="sm"
                          onClick={handleSaveName}
                          disabled={loading}
                        >
                          Save
                        </Button>
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => {
                            setIsEditing(false);
                            setEditedName(user.name);
                          }}
                          disabled={loading}
                        >
                          Cancel
                        </Button>
                      </>
                    ) : (
                      <>
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
                        <>
                          {useDesignSystem ? (
                            <Button
                              variant="primary"
                              size="sm"
                              onClick={handleSaveName}
                              disabled={loading}
                            >
                              Save
                            </Button>
                          ) : (
                            <button
                              className="btn btn-sm btn-primary"
                              onClick={handleSaveName}
                              disabled={loading}
                            >
                              Save
                            </button>
                          )}
                        </>
                        <>
                          {useDesignSystem ? (
                            <Button
                              variant="primary"
                              size="sm"
                              onClick={() => {
                                setIsEditing(false);
                                setEditedName(user.name);
                              }}
                              disabled={loading}
                            >
                              Cancel
                            </Button>
                          ) : (
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
                          )}
                        </>
                      </>
                    )}
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
                        fontFamily: useDesignSystem
                          ? "var(--font-mono, monospace)"
                          : undefined,
                      }}
                    >
                      {user.name}
                    </span>
                    <>
                      {useDesignSystem ? (
                        <Button
                          variant="primary"
                          onClick={() => setIsEditing(true)}
                          title="Edit name"
                        >
                          {" "}
                          <Icon name="edit" size="sm" />{" "}
                        </Button>
                      ) : (
                        <button
                          className="btn-icon"
                          onClick={() => setIsEditing(true)}
                          title="Edit name"
                        >
                          <Icon name="edit" size="sm" />
                        </button>
                      )}
                    </>
                  </div>
                )}
              </div>

              <div>
                {useDesignSystem ? (
                  <Label style={{ display: "block", marginBottom: "2px" }}>
                    Email
                  </Label>
                ) : (
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
                )}
                <span
                  className="text-ellipsis"
                  style={{
                    fontSize: "13px",
                    display: "block",
                    fontFamily: useDesignSystem
                      ? "var(--font-mono, monospace)"
                      : undefined,
                  }}
                >
                  {user.email}
                </span>
              </div>
            </div>
          </div>

          <div>
            {useDesignSystem ? (
              <Label style={{ display: "block", marginBottom: "4px" }}>
                Plan
              </Label>
            ) : (
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
            )}
            {useDesignSystem ? (
              <Tag tone="accent">
                <span style={{ textTransform: "capitalize" }}>{user.tier}</span>
              </Tag>
            ) : (
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
            )}
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
              color: useDesignSystem
                ? "var(--color-text-secondary)"
                : "var(--color-text-secondary)",
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
              textTransform: useDesignSystem ? "uppercase" : undefined,
            }}
          >
            Password
          </h3>
          {useDesignSystem ? (
            <Button
              variant="secondary"
              size="sm"
              onClick={handleChangePassword}
            >
              Change Password
            </Button>
          ) : (
            <button
              className="btn btn-secondary btn-sm"
              onClick={handleChangePassword}
              style={{ fontSize: "12px" }}
            >
              Change Password
            </button>
          )}
        </section>

        {/* Danger Zone */}
        {variant === "modal" && (
          <section
            style={{
              marginTop: "48px",
              padding: "16px",
              border: useDesignSystem
                ? "2px solid #b91c1c"
                : "1px solid #FCA5A5",
              borderRadius: useDesignSystem ? "0" : "8px",
              backgroundColor: useDesignSystem
                ? "rgba(185, 28, 28, 0.04)"
                : "#FEF2F2",
            }}
          >
            <h3
              style={{
                fontSize: "14px",
                fontWeight: "600",
                marginBottom: "8px",
                color: "#991B1B",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
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
            {useDesignSystem ? (
              <Button
                variant="danger"
                onClick={() => setShowDeleteConfirm(true)}
                disabled={loading}
              >
                Delete Account
              </Button>
            ) : (
              <button
                className="btn btn-danger"
                onClick={() => setShowDeleteConfirm(true)}
                disabled={loading}
              >
                Delete Account
              </button>
            )}
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
          style={{
            fontSize: "18px",
            fontWeight: "bold",
            marginBottom: "24px",
            fontFamily: useDesignSystem
              ? "var(--font-mono, monospace)"
              : undefined,
          }}
        >
          Preferences
        </h2>
      )}

      {onReplayOnboarding && (
        <section
          style={{ marginBottom: variant === "popup" ? "16px" : "24px" }}
        >
          <h3
            style={{
              fontSize: variant === "popup" ? "12px" : "14px",
              fontWeight: "600",
              marginBottom: variant === "popup" ? "12px" : "16px",
              color: useDesignSystem
                ? "var(--color-text-secondary)"
                : "var(--color-text-secondary)",
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
              textTransform: useDesignSystem ? "uppercase" : undefined,
            }}
          >
            Getting started
          </h3>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              padding: variant === "popup" ? "10px" : "12px",
              border: "1px solid var(--color-border)",
              borderRadius: useDesignSystem ? "0" : "8px",
              backgroundColor: useDesignSystem
                ? "var(--color-bg-card)"
                : undefined,
              gap: "12px",
            }}
          >
            <div style={{ minWidth: 0 }}>
              <div
                style={{
                  fontWeight: "500",
                  fontSize: variant === "popup" ? "13px" : "14px",
                  marginBottom: "2px",
                  fontFamily: useDesignSystem
                    ? "var(--font-mono, monospace)"
                    : undefined,
                }}
              >
                Replay onboarding
              </div>
              <div
                style={{
                  fontSize: "11px",
                  color: useDesignSystem
                    ? "var(--color-text-secondary)"
                    : "var(--color-text-secondary)",
                }}
              >
                Walk through creating a space, adding a resource, and saving
                tabs.
              </div>
            </div>
            {useDesignSystem ? (
              <Button
                variant="secondary"
                size="sm"
                onClick={() => {
                  onReplayOnboarding();
                  onClose();
                }}
              >
                Show me
              </Button>
            ) : (
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => {
                  onReplayOnboarding();
                  onClose();
                }}
              >
                Show me
              </button>
            )}
          </div>
        </section>
      )}

      <section>
        <h3
          style={{
            fontSize: variant === "popup" ? "12px" : "14px",
            fontWeight: "600",
            marginBottom: variant === "popup" ? "12px" : "16px",
            color: useDesignSystem
              ? "var(--color-text-secondary)"
              : "var(--color-text-secondary)",
            fontFamily: useDesignSystem
              ? "var(--font-mono, monospace)"
              : undefined,
            textTransform: useDesignSystem ? "uppercase" : undefined,
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
            borderRadius: useDesignSystem ? "0" : "8px",
            backgroundColor: useDesignSystem
              ? "var(--color-bg-card)"
              : undefined,
            gap: "12px",
          }}
        >
          <div style={{ minWidth: 0 }}>
            <div
              style={{
                fontWeight: "500",
                fontSize: variant === "popup" ? "13px" : "14px",
                marginBottom: "2px",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
              }}
            >
              Theme
            </div>
            <div
              style={{
                fontSize: "11px",
                color: useDesignSystem
                  ? "var(--color-text-secondary)"
                  : "var(--color-text-secondary)",
                textTransform: "capitalize",
              }}
            >
              {theme}
            </div>
          </div>

          {useDesignSystem ? (
            <Segmented
              name="theme"
              options={[
                { value: "system", label: "System" },
                { value: "light", label: "Light" },
                { value: "dark", label: "Dark" },
              ]}
              value={theme}
              onValueChange={(val) =>
                setTheme(val as "system" | "light" | "dark")
              }
            />
          ) : (
            <div
              style={{
                display: "flex",
                gap: "4px",
                backgroundColor: "var(--color-btn-shaded-bg)",
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
                    backgroundColor:
                      theme === t ? "var(--color-bg-card)" : "transparent",
                    color:
                      theme === t
                        ? "var(--color-primary)"
                        : "var(--color-text-secondary)",
                    boxShadow:
                      theme === t ? "0 1px 2px rgba(0,0,0,0.1)" : "none",
                    fontWeight: theme === t ? 500 : 400,
                    textTransform: "capitalize",
                  }}
                >
                  {t}
                </button>
              ))}
            </div>
          )}
        </div>
      </section>

      {devIdentity && (
        <section style={{ marginTop: variant === "popup" ? "16px" : "24px" }}>
          <h3
            style={{
              fontSize: variant === "popup" ? "12px" : "14px",
              fontWeight: "600",
              marginBottom: variant === "popup" ? "12px" : "16px",
              color: useDesignSystem
                ? "var(--color-text-secondary)"
                : "var(--color-text-secondary)",
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
              textTransform: useDesignSystem ? "uppercase" : undefined,
            }}
          >
            Developer
          </h3>

          <div
            style={{
              padding: variant === "popup" ? "10px" : "12px",
              border: "1px solid var(--color-border)",
              borderRadius: useDesignSystem ? "0" : "8px",
              backgroundColor: useDesignSystem
                ? "var(--color-bg-card)"
                : undefined,
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: "12px",
              }}
            >
              <div style={{ minWidth: 0 }}>
                <div
                  style={{
                    fontWeight: "500",
                    fontSize: variant === "popup" ? "13px" : "14px",
                    marginBottom: "2px",
                    fontFamily: useDesignSystem
                      ? "var(--font-mono, monospace)"
                      : undefined,
                  }}
                >
                  Release channel
                </div>
                <div
                  style={{
                    fontSize: "11px",
                    color: useDesignSystem
                      ? "var(--color-text-secondary)"
                      : "var(--color-text-secondary)",
                    fontFamily: useDesignSystem
                      ? "var(--font-mono, monospace)"
                      : undefined,
                  }}
                >
                  {devIdentity.channel} · v{devIdentity.version} ·{" "}
                  {devIdentity.commit.slice(0, 7)}
                </div>
              </div>

              {useDesignSystem ? (
                <Segmented
                  name="channel"
                  options={[
                    { value: "alpha", label: "Alpha" },
                    { value: "beta", label: "Beta" },
                    { value: "stable", label: "Stable" },
                  ]}
                  value={selectedChannel ?? devIdentity.channel}
                  onValueChange={(val) => {
                    setSelectedChannel(val);
                    setCopiedCommand(false);
                  }}
                />
              ) : (
                <div
                  style={{
                    display: "flex",
                    gap: "4px",
                    backgroundColor: "var(--color-btn-shaded-bg)",
                    padding: "3px",
                    borderRadius: "6px",
                    flexShrink: 0,
                  }}
                >
                  {(["alpha", "beta", "stable"] as const).map((ch) => (
                    <button
                      key={ch}
                      aria-pressed={
                        (selectedChannel ?? devIdentity.channel) === ch
                      }
                      onClick={() => {
                        setSelectedChannel(ch);
                        setCopiedCommand(false);
                      }}
                      style={{
                        padding: "4px 10px",
                        fontSize: "12px",
                        border: "none",
                        borderRadius: "4px",
                        cursor: "pointer",
                        backgroundColor:
                          (selectedChannel ?? devIdentity.channel) === ch
                            ? "var(--color-bg-card)"
                            : "transparent",
                        color:
                          (selectedChannel ?? devIdentity.channel) === ch
                            ? "var(--color-primary)"
                            : "var(--color-text-secondary)",
                        boxShadow:
                          (selectedChannel ?? devIdentity.channel) === ch
                            ? "0 1px 2px rgba(0,0,0,0.1)"
                            : "none",
                        fontWeight:
                          (selectedChannel ?? devIdentity.channel) === ch
                            ? 500
                            : 400,
                      }}
                    >
                      {ch}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {selectedChannel === "stable" && (
              <div
                style={{
                  marginTop: "10px",
                  fontSize: "12px",
                  color: useDesignSystem
                    ? "var(--color-text-secondary)"
                    : "var(--color-text-secondary)",
                }}
              >
                The stable channel arrives with the Web Store listing (M3).
              </div>
            )}

            {selectedChannel &&
              selectedChannel !== "stable" &&
              selectedChannel !== devIdentity.channel && (
                <div
                  style={{
                    marginTop: "10px",
                    display: "flex",
                    alignItems: "center",
                    gap: "8px",
                  }}
                >
                  <code
                    style={{
                      flex: 1,
                      fontSize: "12px",
                      padding: "6px 8px",
                      backgroundColor: useDesignSystem
                        ? "var(--color-bg-card-hover, rgba(0,0,0,0.04))"
                        : "var(--color-bg-card-hover)",
                      border: useDesignSystem
                        ? "1px solid var(--border-hairline, rgba(0,0,0,0.15))"
                        : "none",
                      borderRadius: useDesignSystem ? "0" : "4px",
                      overflowX: "auto",
                      whiteSpace: "nowrap",
                      fontFamily: "var(--font-mono, monospace)",
                    }}
                  >
                    tabcli ext update --channel {selectedChannel}
                  </code>
                  {useDesignSystem ? (
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => {
                        navigator.clipboard
                          ?.writeText(
                            `tabcli ext update --channel ${selectedChannel}`,
                          )
                          .then(() => setCopiedCommand(true))
                          .catch(() => undefined);
                      }}
                    >
                      {copiedCommand ? "Copied!" : "Copy"}
                    </Button>
                  ) : (
                    <button
                      type="button"
                      onClick={() => {
                        navigator.clipboard
                          ?.writeText(
                            `tabcli ext update --channel ${selectedChannel}`,
                          )
                          .then(() => setCopiedCommand(true))
                          .catch(() => undefined);
                      }}
                      style={{
                        padding: "4px 10px",
                        fontSize: "12px",
                        border: "1px solid var(--color-border)",
                        borderRadius: "4px",
                        cursor: "pointer",
                        backgroundColor: "transparent",
                        color: "var(--color-text-primary)",
                        flexShrink: 0,
                      }}
                    >
                      {copiedCommand ? "Copied!" : "Copy"}
                    </button>
                  )}
                </div>
              )}

            <div
              style={{
                marginTop: "16px",
                paddingTop: "16px",
                borderTop: useDesignSystem
                  ? "1px solid var(--border-hairline, rgba(0,0,0,0.15))"
                  : "1px solid var(--color-border)",
              }}
            >
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                }}
              >
                <div>
                  <div
                    style={{
                      fontWeight: 500,
                      fontSize: "13px",
                      fontFamily: useDesignSystem
                        ? "var(--font-mono, monospace)"
                        : undefined,
                    }}
                  >
                    Vitruvian Design System (Preview)
                  </div>
                  <div
                    style={{
                      fontSize: "11px",
                      color: useDesignSystem
                        ? "var(--color-text-secondary)"
                        : "var(--color-text-secondary)",
                    }}
                  >
                    Replaces Workona-style UI with the new system.
                  </div>
                </div>
                {useDesignSystem ? (
                  <Switch
                    label={useDesignSystem ? "On" : "Off"}
                    checked={useDesignSystem}
                    onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                      setFeatureFlag(
                        FEATURE_FLAGS.USE_DESIGN_SYSTEM,
                        e.target.checked,
                      )
                    }
                  />
                ) : (
                  <label
                    style={{
                      display: "flex",
                      alignItems: "center",
                      cursor: "pointer",
                    }}
                  >
                    <input
                      type="checkbox"
                      checked={useDesignSystem}
                      onChange={(e) =>
                        setFeatureFlag(
                          FEATURE_FLAGS.USE_DESIGN_SYSTEM,
                          e.target.checked,
                        )
                      }
                      style={{ marginRight: "8px" }}
                    />
                    <span
                      style={{
                        fontSize: "12px",
                        color: "var(--color-text-secondary)",
                      }}
                    >
                      {useDesignSystem ? "On" : "Off"}
                    </span>
                  </label>
                )}
              </div>
            </div>
          </div>
        </section>
      )}
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
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
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
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
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
                backgroundColor: useDesignSystem
                  ? "var(--color-bg-card)"
                  : "var(--color-btn-shaded-bg)",
                border: useDesignSystem
                  ? "1px solid var(--color-border)"
                  : "none",
                borderRadius: useDesignSystem ? "0" : "8px",
              }}
            >
              <div
                data-testid="backup-count"
                style={{
                  fontSize: "24px",
                  fontWeight: "bold",
                  fontFamily: useDesignSystem
                    ? "var(--font-mono, monospace)"
                    : undefined,
                }}
              >
                {backupStats?.totalBackups || 0}
              </div>
              <div
                style={{
                  fontSize: "12px",
                  color: useDesignSystem
                    ? "var(--color-text-secondary)"
                    : "var(--color-text-secondary)",
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
                backgroundColor: useDesignSystem
                  ? "var(--color-bg-card)"
                  : "var(--color-btn-shaded-bg)",
                border: useDesignSystem
                  ? "1px solid var(--color-border)"
                  : "none",
                borderRadius: useDesignSystem ? "0" : "8px",
              }}
            >
              <div
                data-testid="storage-used"
                style={{
                  fontSize: "24px",
                  fontWeight: "bold",
                  fontFamily: useDesignSystem
                    ? "var(--font-mono, monospace)"
                    : undefined,
                }}
              >
                {backupStats
                  ? `${(backupStats.totalSizeBytes / 1024).toFixed(1)} KB`
                  : "0 KB"}
              </div>
              <div
                style={{
                  fontSize: "12px",
                  color: useDesignSystem
                    ? "var(--color-text-secondary)"
                    : "var(--color-text-secondary)",
                }}
              >
                Storage Used
              </div>
            </div>
          </div>

          {useDesignSystem ? (
            <Button
              variant="primary"
              onClick={handleCreateBackup}
              disabled={backupsLoading}
              style={{ marginBottom: "16px" }}
            >
              {backupsLoading ? "Creating..." : "Create Backup Now"}
            </Button>
          ) : (
            <button
              className="btn btn-primary"
              onClick={handleCreateBackup}
              disabled={backupsLoading}
              style={{ marginBottom: "16px" }}
            >
              {backupsLoading ? "Creating..." : "Create Backup Now"}
            </button>
          )}
        </section>

        {/* Backup List */}
        <section>
          <h3
            style={{
              fontSize: variant === "popup" ? "12px" : "14px",
              fontWeight: "600",
              marginBottom: "12px",
              color: useDesignSystem
                ? "var(--color-text-secondary)"
                : "var(--color-text-secondary)",
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
              textTransform: useDesignSystem ? "uppercase" : undefined,
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
                    color: useDesignSystem
                      ? "var(--color-text-secondary)"
                      : "var(--color-text-secondary)",
                    fontFamily: useDesignSystem
                      ? "var(--font-mono, monospace)"
                      : undefined,
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
                    color: useDesignSystem
                      ? "var(--color-text-secondary)"
                      : "var(--color-text-secondary)",
                    fontFamily: useDesignSystem
                      ? "var(--font-mono, monospace)"
                      : undefined,
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
                      borderRadius: useDesignSystem ? "0" : "8px",
                      backgroundColor: useDesignSystem
                        ? "var(--color-bg-card)"
                        : undefined,
                      gap: "12px",
                    }}
                  >
                    <div style={{ flex: 1 }}>
                      <div
                        style={{
                          fontSize: "13px",
                          fontWeight: "500",
                          fontFamily: useDesignSystem
                            ? "var(--font-mono, monospace)"
                            : undefined,
                        }}
                      >
                        {backup.workspaceName || "All Workspaces"}
                      </div>
                      <div
                        style={{
                          fontSize: "11px",
                          color: useDesignSystem
                            ? "var(--color-text-secondary)"
                            : "var(--color-text-secondary)",
                        }}
                      >
                        {new Date(backup.createdAt).toLocaleString()} •{" "}
                        {backup.sizeBytes
                          ? `${(backup.sizeBytes / 1024).toFixed(1)} KB`
                          : "N/A"}
                      </div>
                    </div>
                    {useDesignSystem ? (
                      <>
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleRestoreBackup(backup.id)}
                          disabled={backupsLoading}
                          title="Restore this backup"
                        >
                          Restore
                        </Button>
                        <Button
                          variant="danger"
                          size="sm"
                          onClick={() => handleDeleteBackup(backup.id)}
                          disabled={backupsLoading}
                          title="Delete this backup"
                          style={{ padding: "4px 8px" }}
                        >
                          <Icon name="delete" size="sm" />
                        </Button>
                      </>
                    ) : (
                      <>
                        <>
                          {useDesignSystem ? (
                            <Button
                              variant="secondary"
                              size="sm"
                              onClick={() => handleRestoreBackup(backup.id)}
                              disabled={backupsLoading}
                              title="Restore this backup"
                            >
                              Restore
                            </Button>
                          ) : (
                            <button
                              className="btn btn-sm btn-secondary"
                              onClick={() => handleRestoreBackup(backup.id)}
                              disabled={backupsLoading}
                              title="Restore this backup"
                            >
                              Restore
                            </button>
                          )}
                        </>
                        <>
                          {useDesignSystem ? (
                            <Button
                              variant="danger"
                              size="sm"
                              onClick={() => handleDeleteBackup(backup.id)}
                              disabled={backupsLoading}
                              title="Delete this backup"
                              style={{ padding: "4px 8px" }}
                            >
                              <Icon name="delete" size="sm" />
                            </Button>
                          ) : (
                            <button
                              className="btn btn-sm btn-danger"
                              onClick={() => handleDeleteBackup(backup.id)}
                              disabled={backupsLoading}
                              title="Delete this backup"
                              style={{ padding: "4px 8px" }}
                            >
                              <Icon name="delete" size="sm" />
                            </button>
                          )}
                        </>
                      </>
                    )}
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
              backgroundColor: useDesignSystem
                ? "var(--color-bg-card)"
                : "var(--color-btn-shaded-bg)",
              border: useDesignSystem
                ? "1px solid var(--color-border)"
                : "none",
              borderRadius: useDesignSystem ? "0" : "8px",
              fontSize: "12px",
              color: useDesignSystem
                ? "var(--color-text-secondary)"
                : "var(--color-text-secondary)",
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
            marginBottom: "16px",
          }}
        >
          {useDesignSystem ? (
            <Button
              variant="ghost"
              size="sm"
              onClick={onClose}
              title="Back"
              style={{ padding: "4px" }}
            >
              <Icon name="arrow_back" size="sm" />
            </Button>
          ) : (
            <button
              className="btn btn-sm btn-secondary"
              onClick={onClose}
              title="Back"
              style={{
                padding: "4px 8px",
                display: "flex",
                alignItems: "center",
              }}
            >
              <Icon name="arrow_back" size="sm" />
            </button>
          )}
          <h2
            style={{
              fontSize: "16px",
              fontWeight: "600",
              flex: 1,
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
              color: useDesignSystem ? "var(--color-text-primary)" : undefined,
              margin: 0,
            }}
          >
            Settings
          </h2>
        </div>

        {/* Horizontal Tabs */}
        <div
          style={{
            display: "flex",
            gap: "4px",
            marginBottom: "16px",
            backgroundColor: useDesignSystem
              ? "transparent"
              : "var(--color-bg-card-hover)",
            padding: useDesignSystem ? "0" : "3px",
            borderRadius: useDesignSystem ? "0" : "8px",
          }}
        >
          {(
            [
              { id: "account", label: "Account", icon: "person" },
              { id: "preferences", label: "Preferences", icon: "settings" },
              { id: "backups", label: "Backups", icon: "backup" },
            ] as const
          ).map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              style={{
                flex: 1,
                padding: "8px 12px",
                border: useDesignSystem
                  ? activeTab === tab.id
                    ? "1px solid var(--color-accent-primary)"
                    : "1px solid transparent"
                  : "none",
                borderRadius: useDesignSystem ? "0" : "6px",
                fontSize: "12px",
                fontWeight: "500",
                cursor: "pointer",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
                textTransform: useDesignSystem ? "uppercase" : undefined,
                backgroundColor:
                  activeTab === tab.id
                    ? useDesignSystem
                      ? "var(--color-accent-primary)"
                      : "var(--color-bg-card)"
                    : "transparent",
                color:
                  activeTab === tab.id
                    ? useDesignSystem
                      ? "white"
                      : "var(--color-text-primary)"
                    : useDesignSystem
                      ? "var(--color-text-secondary)"
                      : "var(--color-text-secondary)",
                boxShadow:
                  !useDesignSystem && activeTab === tab.id
                    ? "var(--shadow-card)"
                    : "none",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: "6px",
              }}
            >
              <Icon name={tab.icon} size="sm" />
              {tab.label}
            </button>
          ))}
        </div>

        {/* Error Display */}
        {error && (
          <div
            style={{
              padding: "8px 12px",
              backgroundColor: useDesignSystem
                ? "rgba(185, 28, 28, 0.08)"
                : "#FEE2E2",
              color: "#991B1B",
              borderRadius: useDesignSystem ? "0" : "6px",
              border: useDesignSystem ? "1px solid #b91c1c" : undefined,
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
                {useDesignSystem ? (
                  <>
                    <Button
                      variant="secondary"
                      onClick={() => setShowDeleteConfirm(false)}
                      disabled={loading}
                    >
                      Cancel
                    </Button>
                    <Button
                      variant="danger"
                      onClick={handleDeleteAccount}
                      disabled={loading}
                    >
                      {loading ? "Deleting..." : "Delete"}
                    </Button>
                  </>
                ) : (
                  <>
                    <>
                      {useDesignSystem ? (
                        <Button
                          variant="secondary"
                          onClick={() => setShowDeleteConfirm(false)}
                          disabled={loading}
                        >
                          Cancel
                        </Button>
                      ) : (
                        <button
                          className="btn btn-secondary"
                          onClick={() => setShowDeleteConfirm(false)}
                          disabled={loading}
                        >
                          Cancel
                        </button>
                      )}
                    </>
                    <>
                      {useDesignSystem ? (
                        <Button
                          variant="danger"
                          onClick={handleDeleteAccount}
                          disabled={loading}
                        >
                          {loading ? "Deleting..." : "Delete"}
                        </Button>
                      ) : (
                        <button
                          className="btn btn-danger"
                          onClick={handleDeleteAccount}
                          disabled={loading}
                        >
                          {loading ? "Deleting..." : "Delete"}
                        </button>
                      )}
                    </>
                  </>
                )}
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
            backgroundColor: useDesignSystem
              ? "transparent"
              : "var(--color-btn-shaded-bg)",
          }}
        >
          <nav>
            {(
              [
                { id: "account", label: "Account", icon: "person" },
                { id: "preferences", label: "Preferences", icon: "settings" },
                { id: "backups", label: "Backups", icon: "backup" },
              ] as const
            ).map((tab) => (
              <button
                key={tab.id}
                className={`nav-item ${activeTab === tab.id ? "active" : ""}`}
                onClick={() => setActiveTab(tab.id)}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "8px",
                  width: "100%",
                  padding: "8px 12px",
                  border: useDesignSystem
                    ? activeTab === tab.id
                      ? "1px solid var(--color-accent-primary)"
                      : "1px solid transparent"
                    : "none",
                  background:
                    activeTab === tab.id
                      ? useDesignSystem
                        ? "var(--color-primary-light)"
                        : "var(--color-primary-light)"
                      : "transparent",
                  color:
                    activeTab === tab.id
                      ? useDesignSystem
                        ? "var(--color-text-primary)"
                        : undefined
                      : undefined,
                  borderRadius: useDesignSystem ? "0" : "4px",
                  cursor: "pointer",
                  fontSize: "14px",
                  fontFamily: useDesignSystem
                    ? "var(--font-mono, monospace)"
                    : undefined,
                  marginBottom: "4px",
                }}
              >
                <Icon name={tab.icon} size="sm" />
                {tab.label}
              </button>
            ))}
          </nav>
        </div>

        {/* Main Content */}
        <div style={{ flex: 1, padding: "24px", overflowY: "auto" }}>
          {error && (
            <div
              style={{
                padding: "12px",
                backgroundColor: useDesignSystem
                  ? "rgba(185, 28, 28, 0.08)"
                  : "#FEE2E2",
                color: "#991B1B",
                borderRadius: useDesignSystem ? "0" : "4px",
                border: useDesignSystem ? "1px solid #b91c1c" : undefined,
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
              {useDesignSystem ? (
                <>
                  <Button
                    variant="secondary"
                    onClick={() => setShowDeleteConfirm(false)}
                    disabled={loading}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteAccount}
                    disabled={loading}
                  >
                    {loading ? "Deleting..." : "Delete My Account"}
                  </Button>
                </>
              ) : (
                <>
                  <>
                    {useDesignSystem ? (
                      <Button
                        variant="secondary"
                        onClick={() => setShowDeleteConfirm(false)}
                        disabled={loading}
                      >
                        Cancel
                      </Button>
                    ) : (
                      <button
                        className="btn btn-secondary"
                        onClick={() => setShowDeleteConfirm(false)}
                        disabled={loading}
                      >
                        Cancel
                      </button>
                    )}
                  </>
                  <>
                    {useDesignSystem ? (
                      <Button
                        variant="danger"
                        onClick={handleDeleteAccount}
                        disabled={loading}
                      >
                        {loading ? "Deleting..." : "Delete My Account"}
                      </Button>
                    ) : (
                      <button
                        className="btn btn-danger"
                        onClick={handleDeleteAccount}
                        disabled={loading}
                      >
                        {loading ? "Deleting..." : "Delete My Account"}
                      </button>
                    )}
                  </>
                </>
              )}
            </div>
          </div>
        </Modal>
      )}
    </Modal>
  );
};
