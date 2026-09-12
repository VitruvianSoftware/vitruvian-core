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
import { DragOverlay } from "@dnd-kit/core";
import type { Workspace, SpaceGroup } from "../types";
import { Icon } from "../components/icons";

interface GhostOverlayProps {
  activeId: string | null;
  activeWorkspace: Workspace | null;
  workspaces: Workspace[];
  spaceGroups: SpaceGroup[];
}

export const GhostOverlay: React.FC<GhostOverlayProps> = ({
  activeId,
  activeWorkspace,
  workspaces,
  spaceGroups,
}) => {
  if (!activeId) return null;

  // Helper to find the active item details
  const getItemDetails = () => {
    // 1. Check Workspaces
    const workspace = workspaces.find((w) => w.id === activeId);
    if (workspace) {
      return {
        type: "Workspace",
        title: workspace.name,
        icon: workspace.icon || "📁",
        subtitle: `${workspace.tabs?.length || 0} tabs`,
        isGroup: false,
      };
    }

    // 2. Check Space Groups
    const group = spaceGroups.find((g) => g.id === activeId);
    if (group) {
      return {
        type: "Section",
        title: group.title,
        icon: "folder_open", // or dynamic icon if groups have them
        subtitle: "Space Group",
        isGroup: true,
      };
    }

    // 3. Check Resources (in active workspace)
    if (activeWorkspace?.sections) {
      // Find section containing the resource
      const sectionWithResource = activeWorkspace.sections.find((s) => {
        // Check if it's the section itself
        if (s.id === activeId) return true;
        // Check if resource is in section
        return s.resources.some((r) => r.id === activeId);
      });

      if (sectionWithResource) {
        if (sectionWithResource.id === activeId) {
          return {
            type: "Section",
            title: sectionWithResource.title,
            icon: "dns",
            subtitle: `${sectionWithResource.resources.length} resources`,
            isGroup: true,
          };
        }

        const resource = sectionWithResource.resources.find(
          (r) => r.id === activeId,
        );
        if (resource) {
          return {
            type: "Resource",
            title: resource.title,
            icon: resource.faviconUrl || "link",
            subtitle: resource.url,
            isGroup: false,
            isUrlIcon: !!resource.faviconUrl,
          };
        }
      }
    }

    // 4. Check Tabs (in active workspace)
    if (activeWorkspace?.tabs) {
      const tabIdStr = activeId.replace("tab-", "");
      const tab = activeWorkspace.tabs.find((t) => t.id === Number(tabIdStr));
      if (tab) {
        return {
          type: "Tab",
          title: tab.title,
          icon: tab.favIconUrl || "public",
          subtitle: tab.url,
          isGroup: false,
          isUrlIcon: !!tab.favIconUrl,
        };
      }
    }

    return null;
  };

  const item = getItemDetails();

  if (!item) return null;

  // Render the "Ghost" card
  return (
    <DragOverlay
      dropAnimation={{
        duration: 250,
        easing: "cubic-bezier(0.18, 0.67, 0.6, 1.22)",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          padding: "10px 16px", // Match .list-item padding
          background: "var(--color-bg-card)", // Match theme
          borderRadius: "8px",
          border: "1px solid var(--color-border)",
          width: "300px", // Fixed width for consistent drag feel, or use auto
          boxShadow:
            "0 20px 25px -5px rgb(0 0 0 / 0.1), 0 10px 10px -5px rgb(0 0 0 / 0.04)", // Deep shadow
          transform: "scale(1.05)", // Slight lift
          opacity: 0.95, // High opacity
          cursor: "grabbing",
          pointerEvents: "none",
        }}
      >
        {/* Icon */}
        <div
          style={{
            marginRight: "12px",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            width: "20px",
            height: "20px",
            fontSize: "20px", // for emoji
          }}
        >
          {item.isUrlIcon ? (
            <img
              src={item.icon}
              alt=""
              style={{ width: "16px", height: "16px" }}
            />
          ) : (
            <span
              style={{ fontSize: item.type === "Workspace" ? "20px" : "18px" }}
            >
              {item.type === "Workspace" ? (
                item.icon
              ) : (
                <Icon name={item.icon} size="sm" />
              )}
            </span>
          )}
        </div>

        {/* Content */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            style={{
              fontWeight: 500,
              fontSize: "14px",
              color: "var(--color-text-primary)",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {item.title}
          </div>
          {item.subtitle && (
            <div
              style={{
                fontSize: "12px",
                color: "var(--color-text-secondary)",
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {item.subtitle}
            </div>
          )}
        </div>
      </div>
    </DragOverlay>
  );
};
