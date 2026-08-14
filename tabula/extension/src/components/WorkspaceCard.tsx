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

import React from "react";
import type { Workspace } from "../types";
import { Plate, Button } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

interface WorkspaceCardProps {
  workspace: Workspace;
  isActive: boolean;
  onSaveTabs: () => void;
  onRestoreTabs: () => void;
  onSwitch: () => void;
  onEdit: () => void;
  onDelete: () => void;
}

export const WorkspaceCard: React.FC<WorkspaceCardProps> = ({
  workspace,
  isActive,
  onSaveTabs,
  onRestoreTabs,
  onSwitch,
  onEdit,
  onDelete,
}) => {
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  const content = (
    <>
      <div className="flex items-center" style={{ marginBottom: "12px" }}>
        <span style={{ fontSize: "24px", marginRight: "12px" }}>
          {workspace.icon}
        </span>
        <div style={{ flex: 1 }}>
          <div
            className="flex items-center gap-xs"
            style={{ marginBottom: "2px" }}
          >
            <span style={{ fontWeight: "600", fontSize: "15px" }}>
              {workspace.name}
            </span>
            {isActive && (
              <span
                style={{
                  fontSize: "10px",
                  backgroundColor: "var(--color-btn-shaded-bg)",
                  color: "var(--color-primary)",
                  padding: "2px 6px",
                  borderRadius: "4px",
                  fontWeight: "600",
                  letterSpacing: "0.5px",
                }}
              >
                ACTIVE
              </span>
            )}
          </div>
          <div
            style={{ fontSize: "12px", color: "var(--color-text-secondary)" }}
          >
            {workspace.tabs.length} tabs
          </div>
        </div>
      </div>

      {workspace.description && (
        <div
          style={{
            fontSize: "13px",
            color: "var(--color-text-secondary)",
            marginBottom: "16px",
            lineHeight: "1.4",
          }}
        >
          {workspace.description}
        </div>
      )}

      <div className="flex gap-sm">
        {useDesignSystem ? (
          <>
            <Button onClick={onSaveTabs} variant="secondary" size="small">
              Save Tabs
            </Button>
            <Button
              onClick={onRestoreTabs}
              variant="secondary"
              size="small"
              disabled={workspace.tabs.length === 0}
            >
              Restore
            </Button>
            {!isActive && (
              <Button
                onClick={onSwitch}
                variant="primary"
                size="small"
                disabled={workspace.tabs.length === 0}
              >
                Switch
              </Button>
            )}
            <div style={{ flex: 1 }}></div>
            <Button onClick={onEdit} variant="secondary" size="small">
              Edit
            </Button>
            <Button onClick={onDelete} variant="danger" size="small">
              Delete
            </Button>
          </>
        ) : (
          <>
            <button
              type="button"
              onClick={onSaveTabs}
              className="btn btn-secondary btn-sm"
            >
              Save Tabs
            </button>
            <button
              type="button"
              onClick={onRestoreTabs}
              className="btn btn-secondary btn-sm"
              disabled={workspace.tabs.length === 0}
            >
              Restore
            </button>
            {!isActive && (
              <button
                type="button"
                onClick={onSwitch}
                className="btn btn-primary btn-sm"
                disabled={workspace.tabs.length === 0}
              >
                Switch
              </button>
            )}
            <div style={{ flex: 1 }}></div>
            <button
              type="button"
              onClick={onEdit}
              className="btn btn-secondary btn-sm"
            >
              Edit
            </button>
            <button
              type="button"
              onClick={onDelete}
              className="btn btn-danger btn-sm"
            >
              Delete
            </button>
          </>
        )}
      </div>
    </>
  );

  const style = {
    marginBottom: "8px",
    border: isActive ? "2px solid var(--color-primary)" : undefined,
    backgroundColor: isActive
      ? "var(--color-bg-card-hover)"
      : "var(--color-bg-card)",
  };

  if (useDesignSystem) {
    return (
      <Plate
        live
        enter
        {...({
          className: "card",
          style: style,
        } as any)}
      >
        {content}
      </Plate>
    );
  }

  return (
    <div className="card" style={style}>
      {content}
    </div>
  );
};
