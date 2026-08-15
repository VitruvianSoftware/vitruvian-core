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
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import type { Tab } from "../types";
import { Icon } from "../components/icons";
import { getFaviconSrc } from "../utils/favicon";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

export interface DraggableTabItemProps {
  tab: Tab;
  onClose: () => void;
  onEdit: () => void;
  onActivate: () => void;
}

/**
 * Sortable Tab Item Component for "Open Tabs"
 * We use a different component to distinguish types in drag handling
 */
export const DraggableTabItem: React.FC<DraggableTabItemProps> = ({
  tab,
  onClose,
  onEdit,
  onActivate,
}) => {
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({
    id: `tab-${tab.id}`,
    data: { type: "tab", tab },
  });

  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
    ...(useDesignSystem
      ? {
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "8px 12px",
          marginBottom: "4px",
          backgroundColor: "var(--paper, #fbf7ee)",
          border: "1px solid var(--border-hairline, rgba(0,0,0,0.1))",
          borderRadius: "0",
        }
      : {}),
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="list-item"
      data-testid="tab-item"
    >
      {/* Draggable area - only this part gets drag listeners */}
      <div
        {...attributes}
        {...listeners}
        style={{
          display: "flex",
          alignItems: "center",
          flex: 1,
          cursor: "grab",
          minWidth: 0,
        }}
        data-testid="tab-drag-handle"
      >
        <img
          src={getFaviconSrc(tab)}
          className="item-icon"
          style={
            useDesignSystem
              ? {
                  width: "16px",
                  height: "16px",
                  marginRight: "10px",
                  flexShrink: 0,
                }
              : undefined
          }
          alt=""
        />
        <div
          className="item-content"
          style={
            useDesignSystem
              ? { flex: 1, minWidth: 0, overflow: "hidden" }
              : undefined
          }
        >
          <div
            className="item-title"
            style={
              useDesignSystem
                ? {
                    fontSize: "13px",
                    fontWeight: 500,
                    color: "var(--ink, #1f1d1a)",
                    whiteSpace: "nowrap",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                  }
                : undefined
            }
          >
            {tab.title}
          </div>
          <div
            className="item-subtitle"
            style={
              useDesignSystem
                ? {
                    fontSize: "11px",
                    fontFamily: "var(--font-mono, monospace)",
                    color: "var(--paper-dim, #736d64)",
                    whiteSpace: "nowrap",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                  }
                : undefined
            }
          >
            {tab.url}
          </div>
        </div>
      </div>
      {/* Action buttons - outside of drag listeners */}
      <div
        className="item-actions"
        style={
          useDesignSystem
            ? { display: "flex", alignItems: "center", gap: "4px" }
            : undefined
        }
      >
        <button
          className={useDesignSystem ? "btn-icon" : "btn-icon"}
          style={
            useDesignSystem
              ? {
                  padding: "4px",
                  color: "var(--ink, #1f1d1a)",
                  background: "none",
                  border: "none",
                  cursor: "pointer",
                }
              : undefined
          }
          onClick={(e) => {
            e.stopPropagation();
            onActivate();
          }}
          title="Focus Tab"
        >
          <Icon name="open_in_new" size="sm" />
        </button>
        <button
          className={useDesignSystem ? "btn-icon" : "btn-icon"}
          style={
            useDesignSystem
              ? {
                  padding: "4px",
                  color: "var(--ink, #1f1d1a)",
                  background: "none",
                  border: "none",
                  cursor: "pointer",
                }
              : undefined
          }
          onClick={(e) => {
            e.stopPropagation();
            onEdit();
          }}
          title="Edit"
        >
          <Icon name="edit" size="sm" />
        </button>
        <button
          className={useDesignSystem ? "btn-icon danger" : "btn-icon danger"}
          style={
            useDesignSystem
              ? {
                  padding: "4px",
                  color: "var(--accent, #991b1b)",
                  background: "none",
                  border: "none",
                  cursor: "pointer",
                }
              : undefined
          }
          onClick={(e) => {
            e.stopPropagation();
            onClose();
          }}
          title="Close Tab"
        >
          <Icon name="close" size="sm" />
        </button>
      </div>
    </div>
  );
};
