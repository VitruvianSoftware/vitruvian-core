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

import React, { useRef } from "react";
import { User } from "../services/auth";
import { Icon } from "../components/icons";
import { MenuOverlay } from "./MenuOverlay";
import { Button } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

export interface UserMenuProps {
  user: User | null;
  showUserMenu: boolean;
  onToggleUserMenu: () => void;
  onCloseUserMenu: () => void;
  onOpenSettings: () => void;
  onLogout: () => void;
  onSignIn: () => void;
}

export const UserMenu: React.FC<UserMenuProps> = ({
  user,
  showUserMenu,
  onToggleUserMenu,
  onCloseUserMenu,
  onOpenSettings,
  onLogout,
  onSignIn,
}) => {
  const menuRef = useRef<HTMLDivElement>(null);
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  const getUserInitials = () => {
    if (!user || !user.name) return "U";
    return user.name
      .split(" ")
      .map((n) => n[0])
      .join("")
      .substring(0, 2)
      .toUpperCase();
  };

  // Signed-out: clear call to action and settings access
  if (!user) {
    if (useDesignSystem) {
      return (
        <div
          style={{ display: "flex", alignItems: "center", gap: "6px" }}
          ref={menuRef}
        >
          <Button
            variant="ghost"
            size="sm"
            onClick={onOpenSettings}
            title="Settings"
          >
            <Icon name="settings" size="sm" />
          </Button>
          <Button
            variant="solid"
            size="sm"
            onClick={onSignIn}
            title="Sign in to sync your spaces across devices"
          >
            Sign in
          </Button>
        </div>
      );
    }

    return (
      <div
        style={{ display: "flex", alignItems: "center", gap: "8px" }}
        ref={menuRef}
      >
        <button
          className="btn btn-secondary"
          style={{
            padding: "4px 8px",
            display: "flex",
            alignItems: "center",
          }}
          onClick={onOpenSettings}
          title="Settings"
        >
          <Icon name="settings" size="sm" />
        </button>
        <button
          className="btn btn-primary"
          style={{ padding: "4px 12px", fontSize: "12px" }}
          onClick={onSignIn}
          title="Sign in to sync your spaces across devices"
        >
          Sign in
        </button>
      </div>
    );
  }

  return (
    <div
      style={{ display: "flex", alignItems: "center", gap: "8px" }}
      ref={menuRef}
    >
      {/* User Avatar */}
      <div
        style={{
          cursor: "pointer",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
        onClick={onToggleUserMenu}
        title="Account & Settings"
      >
        {user?.picture ? (
          <img
            src={user.picture}
            alt={user.name || "User"}
            style={{
              width: "28px",
              height: "28px",
              borderRadius: useDesignSystem ? "2px" : "50%",
              border: useDesignSystem
                ? "1px solid var(--color-border)"
                : undefined,
              objectFit: "cover",
            }}
          />
        ) : (
          <div
            style={{
              width: "28px",
              height: "28px",
              borderRadius: useDesignSystem ? "2px" : "50%",
              backgroundColor: "var(--color-primary)",
              border: useDesignSystem
                ? "1px solid var(--color-border)"
                : undefined,
              color: "white",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: "12px",
              fontWeight: 600,
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
            }}
          >
            {getUserInitials()}
          </div>
        )}
      </div>

      {/* User Dropdown Menu */}
      {showUserMenu && <MenuOverlay onClose={onCloseUserMenu} zIndex={999} />}
      {showUserMenu && (
        <div
          className="dropdown-menu glass-menu"
          style={{
            position: "absolute",
            top: "100%",
            right: "16px",
            marginTop: "4px",
            minWidth: "200px",
            zIndex: 1000,
            borderRadius: useDesignSystem ? "0" : undefined,
            border: useDesignSystem
              ? "1px solid var(--glass-border)"
              : undefined,
            fontFamily: useDesignSystem
              ? "var(--font-mono, monospace)"
              : undefined,
          }}
        >
          {/* User Info Header */}
          <div style={{ padding: "12px 16px 8px 16px" }}>
            <div
              style={{
                fontWeight: 600,
                fontSize: "14px",
                color: "var(--color-text-primary)",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
                marginBottom: "2px",
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {user?.name || "Account"}
            </div>
            <div
              style={{
                fontSize: "12px",
                color: "var(--color-text-secondary)",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {user?.email}
            </div>
          </div>

          <div className="dropdown-divider" />

          {/* Settings Option */}
          <div className="dropdown-item" onClick={onOpenSettings}>
            <Icon name="settings" size="sm" />
            Settings
          </div>

          <div className="dropdown-divider" />

          {/* Sign Out Option */}
          <div className="dropdown-item" onClick={onLogout}>
            <Icon name="logout" size="sm" />
            Log out
          </div>
        </div>
      )}
    </div>
  );
};
