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
 * SyncStatusIndicator - Visual indicator for sync status
 *
 * Displays current sync state with appropriate icons and colors:
 * - idle/synced: Green checkmark
 * - syncing: Spinning sync icon
 * - error: Red warning with retry option
 * - offline: Gray cloud with slash
 */

import React, { useEffect } from "react";
import { useSyncStore } from "../stores/sync";
import { Icon } from "./icons";
import { Status, type Signal, Tag } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

export const SyncStatusIndicator: React.FC = () => {
  const {
    status,
    pendingCount,
    lastSyncAt,
    lastError,
    isOnline,
    retrySync,
    discardFailed,
    initialize,
  } = useSyncStore();
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  // Initialize sync store on mount (subscribes to SyncService state changes)
  useEffect(() => {
    initialize();
  }, [initialize]);

  // Format last sync time
  const formatLastSync = (): string => {
    if (!lastSyncAt) return "Never synced";
    const diff = Date.now() - lastSyncAt;
    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (seconds < 60) return "Just now";
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    return new Date(lastSyncAt).toLocaleDateString();
  };

  // Get status color
  const getStatusColor = (): string => {
    switch (status) {
      case "syncing":
        return useDesignSystem
          ? "var(--accent-2, #1d4ed8)"
          : "var(--color-accent-primary)";
      case "error":
        return useDesignSystem
          ? "var(--accent, #991b1b)"
          : "var(--color-accent-danger)";
      case "offline":
        return useDesignSystem
          ? "var(--paper-dim, #736d64)"
          : "var(--color-text-secondary)";
      default:
        return useDesignSystem
          ? "var(--accent-success, #166534)"
          : "var(--color-accent-success, #22c55e)";
    }
  };

  const getSignal = (): Signal => {
    if (!isOnline || status === "offline") return "idle";
    if (status === "error") return "crit";
    if (status === "syncing") return "run";
    if (pendingCount > 0) return "warn";
    return "ok";
  };

  // Get tooltip text
  const getTooltip = (): string => {
    if (!isOnline) return "Offline - changes will sync when connected";
    if (status === "syncing")
      return `Syncing ${pendingCount} item${pendingCount !== 1 ? "s" : ""}...`;
    if (status === "error")
      return `Sync failed: ${lastError || "Unknown error"}. Click to retry.`;
    if (pendingCount > 0)
      return `${pendingCount} pending sync${pendingCount !== 1 ? "s" : ""}`;
    return `Synced: ${formatLastSync()}`;
  };

  // Handle click (retry if error)
  const handleClick = (): void => {
    if (status === "error") {
      retrySync();
    }
  };

  if (useDesignSystem) {
    return (
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "6px",
          padding: "3px 6px",
          border: "1px solid var(--border-hairline, rgba(0,0,0,0.1))",
          backgroundColor: "var(--ink-2, #ffffff)",
          cursor: status === "error" ? "pointer" : "default",
          fontSize: "11px",
          fontFamily: "var(--font-mono, monospace)",
        }}
        onClick={handleClick}
        title={getTooltip()}
      >
        <Status signal={getSignal()}>
          {/* Status Icon */}
          <div
            style={{
              width: "14px",
              height: "14px",
              display: "inline-flex",
              alignItems: "center",
              justifyContent: "center",
              color: getStatusColor(),
              marginRight: "4px",
            }}
          >
            {status === "syncing" && (
              <div style={{ animation: "spin 1s linear infinite" }}>
                <Icon name="sync" size="sm" />
              </div>
            )}
            {status === "idle" && pendingCount === 0 && (
              <Icon name="check_circle" size="sm" />
            )}
            {status === "idle" && pendingCount > 0 && (
              <Icon name="cloud_upload" size="sm" />
            )}
            {status === "error" && <Icon name="error" size="sm" />}
            {status === "offline" && <Icon name="cloud_off" size="sm" />}
          </div>

          {(status === "syncing" || status === "error") && (
            <span>
              {status === "syncing" && "Syncing..."}
              {status === "error" && "Sync failed"}
            </span>
          )}
        </Status>

        {status === "error" && (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              discardFailed();
            }}
            title="Discard the failed changes so the rest of the queue can sync"
            style={{
              fontSize: "9px",
              fontFamily: "var(--font-mono, monospace)",
              background: "transparent",
              border: "1px solid var(--accent, #991b1b)",
              color: "var(--accent, #991b1b)",
              padding: "1px 4px",
              cursor: "pointer",
              whiteSpace: "nowrap",
            }}
          >
            Discard
          </button>
        )}

        {pendingCount > 0 && status !== "syncing" && (
          <Tag tone="warn">{pendingCount}</Tag>
        )}

        <style>
          {`
            @keyframes spin {
              from { transform: rotate(0deg); }
              to { transform: rotate(360deg); }
            }
          `}
        </style>
      </div>
    );
  }

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: "6px",
        padding: "4px 8px",
        borderRadius: "4px",
        cursor: status === "error" ? "pointer" : "default",
        transition: "background-color 0.2s",
      }}
      onClick={handleClick}
      title={getTooltip()}
    >
      {/* Status Icon */}
      <div
        style={{
          width: "16px",
          height: "16px",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: getStatusColor(),
        }}
      >
        {status === "syncing" && (
          <div
            style={{
              animation: "spin 1s linear infinite",
            }}
          >
            <Icon name="sync" size="sm" />
          </div>
        )}
        {status === "idle" && pendingCount === 0 && (
          <Icon name="check_circle" size="sm" />
        )}
        {status === "idle" && pendingCount > 0 && (
          <Icon name="cloud_upload" size="sm" />
        )}
        {status === "error" && <Icon name="error" size="sm" />}
        {status === "offline" && <Icon name="cloud_off" size="sm" />}
      </div>

      {/* Status Text (only show on error or syncing) */}
      {(status === "syncing" || status === "error") && (
        <span
          style={{
            fontSize: "12px",
            color: getStatusColor(),
            whiteSpace: "nowrap",
          }}
        >
          {status === "syncing" && "Syncing..."}
          {status === "error" && "Sync failed"}
        </span>
      )}

      {/* Escape hatch for permanently-failing operations */}
      {status === "error" && (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            discardFailed();
          }}
          title="Discard the failed changes so the rest of the queue can sync"
          style={{
            fontSize: "10px",
            background: "transparent",
            border: "1px solid var(--color-text-secondary)",
            borderRadius: "4px",
            color: "var(--color-text-secondary)",
            padding: "1px 6px",
            cursor: "pointer",
            whiteSpace: "nowrap",
          }}
        >
          Discard failed
        </button>
      )}

      {/* Pending count badge */}
      {pendingCount > 0 && status !== "syncing" && (
        <span
          style={{
            fontSize: "10px",
            backgroundColor: "var(--color-bg-tertiary)",
            color: "var(--color-text-secondary)",
            padding: "1px 5px",
            borderRadius: "10px",
            fontWeight: 500,
          }}
        >
          {pendingCount}
        </span>
      )}

      {/* Add spin animation style */}
      <style>
        {`
          @keyframes spin {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
          }
        `}
      </style>
    </div>
  );
};
