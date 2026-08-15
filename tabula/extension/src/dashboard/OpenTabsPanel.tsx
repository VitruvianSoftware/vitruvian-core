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

import React, { useMemo } from "react";
import {
  SortableContext,
  verticalListSortingStrategy,
  useSortable,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import type { Tab, TabGroup } from "../types";
import { DraggableTabItem } from "./DraggableTabItem";
import { DroppableContainer } from "./DroppableContainer";
import { Icon } from "../components/icons";
import { TabService } from "../services/tabs";
import { EmptyState } from "../components/EmptyState";
import { EmptyTabsIllustration } from "../components/illustrations/EmptyTabs";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

/**
 * Chrome tab group color mapping to CSS colors
 */
const GROUP_COLORS: Record<string, string> = {
  grey: "#5f6368",
  blue: "#1a73e8",
  red: "#d93025",
  yellow: "#f9ab00",
  green: "#188038",
  pink: "#e91e63",
  purple: "#9c27b0",
  cyan: "#00bcd4",
  orange: "#ff5722",
};

export interface OpenTabsPanelProps {
  activeTabs: Tab[];
  tabGroups?: TabGroup[];
  onCloseTab: (tabId: number, tabUrl: string) => void;
  onEditTab: (tab: Tab) => void;
  onActivateTab: (tabId: number, tab: Tab) => void;
}

/**
 * Represents either a group header or a tab in the render order
 */
type RenderItem =
  | {
      type: "group-header";
      group: TabGroup;
      tabCount: number;
      tabIds: number[];
      chromeGroupId?: number;
      isCollapsed: boolean;
    }
  | { type: "tab"; tab: Tab; groupId?: string; isGroupCollapsed: boolean };

/**
 * Draggable group header component
 */
interface DraggableGroupHeaderProps {
  group: TabGroup;
  tabCount: number;
  tabIds: number[];
  chromeGroupId?: number;
  isCollapsed: boolean;
  isFirst: boolean;
  onToggleCollapse: (newCollapsed: boolean) => void;
}

const DraggableGroupHeader: React.FC<DraggableGroupHeaderProps> = ({
  group,
  tabCount,
  tabIds,
  chromeGroupId,
  isCollapsed,
  isFirst,
  onToggleCollapse,
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
    id: `group-${group.id}`,
    data: { type: "tab-group", groupId: group.id, tabIds },
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={{
        ...style,
        display: "flex",
        alignItems: "center",
        padding: "8px 12px",
        cursor: "grab",
        borderRadius: useDesignSystem ? "0" : "6px",
        marginBottom: "4px",
        marginTop: isFirst ? 0 : "8px",
        backgroundColor: useDesignSystem
          ? "var(--color-bg, #fbf7ee)"
          : "var(--color-bg-tertiary)",
        border: useDesignSystem
          ? "1px solid var(--border-hairline, rgba(0,0,0,0.1))"
          : undefined,
        transition: "background-color 0.15s ease",
      }}
      {...attributes}
      {...listeners}
      onMouseEnter={(e) => {
        if (!isDragging) {
          e.currentTarget.style.backgroundColor = useDesignSystem
            ? "var(--color-bg-card-hover, rgba(0,0,0,0.04))"
            : "var(--color-bg-hover)";
        }
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.backgroundColor = useDesignSystem
          ? "var(--color-bg, #fbf7ee)"
          : "var(--color-bg-tertiary)";
      }}
    >
      <button
        type="button"
        data-testid="collapse-group-button"
        onClick={(e) => {
          e.stopPropagation();
          const newCollapsed = !isCollapsed;
          // Sync with Chrome tab group
          if (chromeGroupId !== undefined) {
            TabService.setTabGroupCollapsed(chromeGroupId, newCollapsed);
          }
          onToggleCollapse(newCollapsed);
        }}
        style={{
          background: "none",
          border: "none",
          padding: 0,
          cursor: "pointer",
          display: "flex",
          alignItems: "center",
        }}
      >
        <Icon
          name={isCollapsed ? "keyboard_arrow_right" : "keyboard_arrow_down"}
          size="sm"
          style={{
            marginRight: "6px",
            opacity: 0.7,
            color: useDesignSystem
              ? "var(--color-text, #1f1d1a)"
              : "var(--color-text-muted)",
          }}
        />
      </button>
      <span
        style={{
          width: "10px",
          height: "10px",
          borderRadius: useDesignSystem ? "0" : "50%",
          backgroundColor:
            GROUP_COLORS[group.color || "grey"] || GROUP_COLORS.grey,
          marginRight: "8px",
          flexShrink: 0,
        }}
      />
      <span
        style={{
          flex: 1,
          fontWeight: 600,
          fontFamily: useDesignSystem
            ? "var(--font-mono, monospace)"
            : undefined,
          fontSize: "12px",
          color: useDesignSystem
            ? "var(--color-text, #1f1d1a)"
            : "var(--color-text-primary)",
          overflow: "hidden",
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
        }}
      >
        {group.title || "Untitled"}
      </span>
      <span
        style={{
          fontSize: "11px",
          fontFamily: useDesignSystem
            ? "var(--font-mono, monospace)"
            : undefined,
          color: useDesignSystem
            ? "var(--color-text-dim, #736d64)"
            : "var(--color-text-muted)",
          marginLeft: "8px",
        }}
      >
        {tabCount}
      </span>
    </div>
  );
};

export const OpenTabsPanel: React.FC<OpenTabsPanelProps> = ({
  activeTabs,
  tabGroups = [],
  onCloseTab,
  onEditTab,
  onActivateTab,
}) => {
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  // Build a map of groupId -> TabGroup for quick lookup
  const groupMap = useMemo(() => {
    const map = new Map<string, TabGroup>();
    tabGroups.forEach((g) => map.set(g.id, g));
    return map;
  }, [tabGroups]);

  // Build render items preserving original tab order
  // Insert group headers when we first encounter a tab from that group
  const renderItems = useMemo((): RenderItem[] => {
    const items: RenderItem[] = [];
    const seenGroups = new Set<string>();

    // Count tabs per group and collect tab IDs for the header
    const groupTabCounts = new Map<string, number>();
    const groupTabIds = new Map<string, number[]>();
    activeTabs.forEach((tab) => {
      if (tab.groupId && groupMap.has(tab.groupId) && tab.id) {
        groupTabCounts.set(
          tab.groupId,
          (groupTabCounts.get(tab.groupId) || 0) + 1,
        );
        const ids = groupTabIds.get(tab.groupId) || [];
        ids.push(tab.id);
        groupTabIds.set(tab.groupId, ids);
      }
    });

    activeTabs.forEach((tab) => {
      const { groupId } = tab;
      const group = groupId ? groupMap.get(groupId) : undefined;

      // If this tab belongs to a group we haven't seen yet, insert the header
      if (group && !seenGroups.has(group.id)) {
        seenGroups.add(group.id);
        items.push({
          type: "group-header",
          group,
          tabCount: groupTabCounts.get(group.id) || 0,
          tabIds: groupTabIds.get(group.id) || [],
          chromeGroupId: group.chromeGroupId,
          isCollapsed: group.collapsed || false,
        });
      }

      items.push({
        type: "tab",
        tab,
        groupId: group?.id,
        isGroupCollapsed: group?.collapsed || false,
      });
    });

    return items;
  }, [activeTabs, groupMap]);

  // Build sortable items list (tab IDs + group IDs)
  const sortableItems = useMemo(() => {
    const items: string[] = [];
    const seenGroups = new Set<string>();

    activeTabs.forEach((tab) => {
      const group = tab.groupId ? groupMap.get(tab.groupId) : undefined;
      if (group && !seenGroups.has(group.id)) {
        seenGroups.add(group.id);
        items.push(`group-${group.id}`);
      }
      items.push(`tab-${tab.id}`);
    });

    return items;
  }, [activeTabs, groupMap]);

  return (
    <div className="card-section">
      <div className="section-header">
        <h3
          style={
            useDesignSystem
              ? {
                  fontFamily: "var(--font-mono, monospace)",
                  fontSize: "12px",
                  textTransform: "uppercase",
                  letterSpacing: "0.06em",
                  color: "var(--color-text-dim, #736d64)",
                  margin: 0,
                }
              : undefined
          }
        >
          Active Tabs
        </h3>
      </div>

      {/* Empty State */}
      {activeTabs.length === 0 && (
        <EmptyState
          illustration={<EmptyTabsIllustration />}
          title="No active tabs"
          description="Open tabs in this workspace to track your active context."
          style={{ padding: "48px 0" }}
        />
      )}

      <DroppableContainer
        id="active-tabs-root"
        containerType="section"
        style={{ display: "flex", flexDirection: "column" }}
      >
        <SortableContext
          items={sortableItems}
          strategy={verticalListSortingStrategy}
        >
          {(() => {
            // Helper to render a single item
            const renderItem = (item: RenderItem, index: number) => {
              if (item.type === "group-header") {
                const { group, tabCount, tabIds, isCollapsed } = item;
                return (
                  <DraggableGroupHeader
                    key={`header-${group.id}`}
                    group={group}
                    tabCount={tabCount}
                    tabIds={tabIds}
                    chromeGroupId={item.chromeGroupId}
                    isCollapsed={isCollapsed}
                    isFirst={index === 0}
                    onToggleCollapse={() => {
                      // Handled inside DraggableGroupHeader
                    }}
                  />
                );
              }

              const { tab, groupId, isGroupCollapsed } = item;
              const isGrouped = !!groupId;
              const group = groupId ? groupMap.get(groupId) : undefined;
              const groupColor = group
                ? GROUP_COLORS[group.color || "grey"] || GROUP_COLORS.grey
                : undefined;

              if (isGroupCollapsed) {
                return null;
              }

              return (
                <div
                  key={tab.url || tab.id}
                  style={{
                    borderLeft:
                      isGrouped && groupColor
                        ? `4px solid ${groupColor}`
                        : "4px solid transparent",
                  }}
                >
                  <DraggableTabItem
                    tab={tab}
                    onClose={() => tab.id && onCloseTab(tab.id, tab.url)}
                    onEdit={() => onEditTab(tab)}
                    onActivate={() => tab.id && onActivateTab(tab.id, tab)}
                  />
                </div>
              );
            };

            // Chunk the items
            const chunks: {
              type: "group" | "ungrouped";
              groupId?: string;
              items: RenderItem[];
            }[] = [];
            let currentChunk: RenderItem[] = [];
            let currentGroupId: string | null = null;

            renderItems.forEach((item) => {
              const itemGroupId =
                item.type === "group-header" ? item.group.id : item.groupId;

              const isNewGroupHeader = item.type === "group-header";
              if (isNewGroupHeader) {
                if (currentChunk.length > 0) {
                  chunks.push({
                    type: currentGroupId ? "group" : "ungrouped",
                    groupId: currentGroupId || undefined,
                    items: currentChunk,
                  });
                }
                currentChunk = [item];
                currentGroupId = item.group.id;
                return;
              }

              const effectiveGroupId = itemGroupId || null;

              if (effectiveGroupId === currentGroupId) {
                currentChunk.push(item);
              } else {
                if (currentChunk.length > 0) {
                  chunks.push({
                    type: currentGroupId ? "group" : "ungrouped",
                    groupId: currentGroupId || undefined,
                    items: currentChunk,
                  });
                }
                currentChunk = [item];
                currentGroupId = effectiveGroupId;
              }
            });

            if (currentChunk.length > 0) {
              chunks.push({
                type: currentGroupId ? "group" : "ungrouped",
                groupId: currentGroupId || undefined,
                items: currentChunk,
              });
            }

            return chunks.map((chunk, chunkIndex) => {
              const isLastChunk = chunkIndex === chunks.length - 1;
              const marginBottom = isLastChunk ? 0 : "24px";

              if (chunk.type === "group" && chunk.groupId) {
                return (
                  <DroppableContainer
                    key={chunk.groupId}
                    id={chunk.groupId}
                    containerType="group"
                    className="group-cluster tab-list tab-group-container"
                    style={{
                      display: "flex",
                      flexDirection: "column",
                      gap: "var(--spacing-xs, 8px)",
                      marginBottom,
                    }}
                  >
                    {chunk.items.map((item, i) => renderItem(item, i))}
                  </DroppableContainer>
                );
              }

              return (
                <div
                  key={`ungrouped-${chunkIndex}`}
                  className="ungrouped-cluster tab-list"
                  style={{
                    display: "flex",
                    flexDirection: "column",
                    gap: "var(--spacing-xs, 8px)",
                    marginBottom,
                  }}
                >
                  {chunk.items.map((item, i) => renderItem(item, i))}
                </div>
              );
            });
          })()}
        </SortableContext>
      </DroppableContainer>
    </div>
  );
};
