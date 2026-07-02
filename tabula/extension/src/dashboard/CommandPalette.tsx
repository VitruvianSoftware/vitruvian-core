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

import React, { useState, useEffect, useRef, useMemo } from "react";
import { useWorkspaceStore } from "../stores/workspace";
import { Icon } from "../components/icons";
import "../styles/command-palette.css";

// Constants
const NOTE_PREVIEW_LENGTH = 100;
const SEARCH_SCORES = {
  EXACT_MATCH: 1000,
  STARTS_WITH: 500,
  CONTAINS: 100,
  SUBTITLE_MATCH: 50,
  WORKSPACE_MATCH: 25,
  WORKSPACE_TYPE_BOOST: 50,
} as const;

const SEARCH_HISTORY_KEY = "tabula_search_history";
const MAX_HISTORY_ITEMS = 10;

type FilterType = "all" | "workspace" | "resource" | "tab" | "note" | "task";

export interface SearchResult {
  id: string;
  type: "workspace" | "resource" | "tab" | "note" | "task";
  title: string;
  subtitle?: string;
  url?: string;
  workspaceId?: string;
  workspaceName?: string;
  sectionId?: string;
  icon?: string;
}

interface CommandPaletteProps {
  isOpen: boolean;
  onClose: () => void;
  /**
   * Conflict-aware workspace switch (Dashboard's handleSwitch). Falls back to
   * the raw store switch when not provided, but the raw path bypasses
   * multi-window ownership claims — always prefer passing this.
   */
  onSwitchWorkspace?: (id: string) => Promise<void>;
}

export const CommandPalette: React.FC<CommandPaletteProps> = ({
  isOpen,
  onClose,
  onSwitchWorkspace,
}) => {
  const { workspaces, switchWorkspace: storeSwitchWorkspace } =
    useWorkspaceStore();
  const switchWorkspace = onSwitchWorkspace ?? storeSwitchWorkspace;
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [activeFilter, setActiveFilter] = useState<FilterType>("all");
  const [searchHistory, setSearchHistory] = useState<string[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);
  const overlayRef = useRef<HTMLDivElement>(null);
  const resultsRef = useRef<HTMLDivElement>(null);

  // Build searchable index from workspace data
  const searchIndex = useMemo(() => {
    const results: SearchResult[] = [];

    workspaces.forEach((workspace) => {
      // Index workspace
      results.push({
        id: workspace.id,
        type: "workspace",
        title: workspace.name,
        subtitle: workspace.description || "Workspace",
        icon: workspace.icon,
      });

      // Index tabs (with safety check)
      if (workspace.tabs && Array.isArray(workspace.tabs)) {
        workspace.tabs.forEach((tab) => {
          // Use a stable ID: prefer tab.id, but ensure consistent fallback
          const stableId = tab.id
            ? `tab-${tab.id}`
            : `tab-url-${btoa(tab.url).substring(0, 16)}`;
          results.push({
            id: `${workspace.id}-${stableId}`,
            type: "tab",
            title: tab.title,
            subtitle: tab.url,
            url: tab.url,
            workspaceId: workspace.id,
            workspaceName: workspace.name,
          });
        });
      }

      // Index resources (root level) (with safety check)
      if (workspace.resources && Array.isArray(workspace.resources)) {
        workspace.resources.forEach((resource) => {
          results.push({
            id: `${workspace.id}-resource-${resource.id}`,
            type: "resource",
            title: resource.title,
            subtitle: resource.url,
            url: resource.url,
            workspaceId: workspace.id,
            workspaceName: workspace.name,
          });
        });
      }

      // Index resources in sections (with safety check)
      if (workspace.sections && Array.isArray(workspace.sections)) {
        workspace.sections.forEach((section) => {
          if (section.resources && Array.isArray(section.resources)) {
            section.resources.forEach((resource) => {
              results.push({
                id: `${workspace.id}-section-${section.id}-resource-${resource.id}`,
                type: "resource",
                title: resource.title,
                subtitle: `${section.title} • ${resource.url}`,
                url: resource.url,
                workspaceId: workspace.id,
                workspaceName: workspace.name,
                sectionId: section.id,
              });
            });
          }
        });
      }

      // Index notes (with safety check)
      if (workspace.notes && Array.isArray(workspace.notes)) {
        workspace.notes.forEach((note) => {
          results.push({
            id: `${workspace.id}-note-${note.id}`,
            type: "note",
            title: note.title,
            subtitle: note.content.slice(0, NOTE_PREVIEW_LENGTH),
            workspaceId: workspace.id,
            workspaceName: workspace.name,
          });
        });
      }

      // Index tasks (with safety check)
      if (workspace.tasks && Array.isArray(workspace.tasks)) {
        workspace.tasks.forEach((task) => {
          results.push({
            id: `${workspace.id}-task-${task.id}`,
            type: "task",
            title: task.title,
            subtitle: task.completed ? "Completed" : "Pending",
            workspaceId: workspace.id,
            workspaceName: workspace.name,
          });
        });
      }
    });

    return results;
  }, [workspaces]);

  // Filter and rank results based on search query
  const filteredResults = useMemo(() => {
    let results = searchIndex;

    // Apply type filter first
    if (activeFilter !== "all") {
      results = results.filter((result) => result.type === activeFilter);
    }

    if (!searchQuery.trim()) {
      return results.slice(0, 50); // Show first 50 results when no query
    }

    const query = searchQuery.toLowerCase();
    const scored = results
      .map((result) => {
        const titleLower = result.title.toLowerCase();
        const subtitleLower = result.subtitle?.toLowerCase() || "";
        const workspaceLower = result.workspaceName?.toLowerCase() || "";

        let score = 0;

        // Exact match in title
        if (titleLower === query) score += SEARCH_SCORES.EXACT_MATCH;
        // Title starts with query
        else if (titleLower.startsWith(query))
          score += SEARCH_SCORES.STARTS_WITH;
        // Title contains query
        else if (titleLower.includes(query)) score += SEARCH_SCORES.CONTAINS;

        // Check subtitle
        if (subtitleLower.includes(query))
          score += SEARCH_SCORES.SUBTITLE_MATCH;

        // Check workspace name
        if (workspaceLower.includes(query))
          score += SEARCH_SCORES.WORKSPACE_MATCH;

        // Boost workspaces in results only if they already have a match
        if (result.type === "workspace" && score > 0)
          score += SEARCH_SCORES.WORKSPACE_TYPE_BOOST;

        return { result, score };
      })
      .filter((item) => item.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 50)
      .map((item) => item.result);

    return scored;
  }, [searchQuery, searchIndex, activeFilter]);

  // Load search history from localStorage
  useEffect(() => {
    const loadHistory = async () => {
      try {
        const result = await chrome.storage.local.get(SEARCH_HISTORY_KEY);
        const history = result[SEARCH_HISTORY_KEY] as string[] | undefined;
        if (history) {
          setSearchHistory(history);
        }
      } catch (error) {
        console.error("Failed to load search history:", error);
      }
    };
    loadHistory();
  }, []);

  // Save search query to history
  const saveToHistory = async (query: string) => {
    if (!query.trim()) return;

    try {
      const updatedHistory = [
        query,
        ...searchHistory.filter((q) => q !== query),
      ].slice(0, MAX_HISTORY_ITEMS);

      setSearchHistory(updatedHistory);
      await chrome.storage.local.set({ [SEARCH_HISTORY_KEY]: updatedHistory });
    } catch (error) {
      console.error("Failed to save search history:", error);
    }
  };

  // Handle result selection
  const handleSelectResult = async (result: SearchResult) => {
    // Save the search query to history
    if (searchQuery.trim()) {
      await saveToHistory(searchQuery);
    }

    switch (result.type) {
      case "workspace":
        await switchWorkspace(result.id);
        break;
      case "resource":
      case "tab":
        if (result.url) {
          // Validate URL before opening to prevent malicious URLs
          try {
            const url = new URL(result.url);
            // Only allow http, https, and chrome-extension protocols
            if (
              ["http:", "https:", "chrome-extension:"].includes(url.protocol)
            ) {
              chrome.tabs.create({ url: result.url, active: true });
            }
          } catch (error) {
            // Invalid URL, ignore
            console.warn("Invalid URL in search result:", result.url);
          }
        }
        break;
      case "note":
      case "task":
        // Switch to workspace and select appropriate tab
        if (result.workspaceId) {
          await switchWorkspace(result.workspaceId);
          // The dashboard will need to handle showing the right tab
          // For now, just switch workspace
        }
        break;
      default:
        // Handle unknown types gracefully
        break;
    }
    onClose();
  };

  // Keyboard navigation
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      switch (e.key) {
        case "ArrowDown":
          e.preventDefault();
          setSelectedIndex((prev) =>
            Math.min(prev + 1, filteredResults.length - 1),
          );
          break;
        case "ArrowUp":
          e.preventDefault();
          setSelectedIndex((prev) => Math.max(prev - 1, 0));
          break;
        case "Enter":
          e.preventDefault();
          if (filteredResults[selectedIndex]) {
            handleSelectResult(filteredResults[selectedIndex]);
          }
          break;
        case "Escape":
          e.preventDefault();
          onClose();
          break;
        default:
          // Let other keys pass through
          break;
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, filteredResults, selectedIndex, onClose]);

  // Reset state when opened
  useEffect(() => {
    if (isOpen) {
      setSearchQuery("");
      setSelectedIndex(0);
      setTimeout(() => inputRef.current?.focus(), 50);
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "unset";
    }
  }, [isOpen]);

  // Scroll selected item into view
  useEffect(() => {
    if (resultsRef.current && selectedIndex >= 0) {
      const selectedElement = resultsRef.current.children[
        selectedIndex
      ] as HTMLElement;
      if (selectedElement && selectedElement.scrollIntoView) {
        selectedElement.scrollIntoView({
          block: "nearest",
          behavior: "smooth",
        });
      }
    }
  }, [selectedIndex]);

  // Handle overlay click
  const handleOverlayClick = (e: React.MouseEvent) => {
    if (e.target === overlayRef.current) {
      onClose();
    }
  };

  if (!isOpen) return null;

  // Get icon for result type
  const getResultIcon = (result: SearchResult) => {
    switch (result.type) {
      case "workspace":
        return "dashboard";
      case "resource":
        return "link";
      case "tab":
        return "tab";
      case "note":
        return "description";
      case "task":
        return "check_box";
      default:
        return "search";
    }
  };

  return (
    <div
      className="command-palette-overlay"
      ref={overlayRef}
      onClick={handleOverlayClick}
    >
      <div className="command-palette-container">
        <div className="command-palette-header">
          <Icon
            name="search"
            size="md"
            className="command-palette-search-icon"
          />
          <input
            ref={inputRef}
            type="text"
            className="command-palette-input"
            placeholder="Search workspaces, resources, tabs, notes, and tasks..."
            value={searchQuery}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              setSelectedIndex(0);
            }}
          />
          <kbd className="command-palette-kbd">ESC</kbd>
        </div>

        {/* Filter buttons */}
        <div className="command-palette-filters">
          {(
            [
              "all",
              "workspace",
              "resource",
              "tab",
              "note",
              "task",
            ] as FilterType[]
          ).map((filter) => (
            <button
              key={filter}
              type="button"
              className={`filter-button ${activeFilter === filter ? "active" : ""}`}
              onClick={() => {
                setActiveFilter(filter);
                setSelectedIndex(0);
              }}
            >
              {filter === "all"
                ? "All"
                : filter.charAt(0).toUpperCase() + filter.slice(1)}
            </button>
          ))}
        </div>

        <div className="command-palette-results" ref={resultsRef}>
          {!searchQuery.trim() && searchHistory.length > 0 && (
            <div className="search-history">
              <div className="search-history-header">Recent Searches</div>
              {searchHistory.map((query, index) => (
                <div
                  key={`${query}-${index}`}
                  className="search-history-item"
                  onClick={() => {
                    setSearchQuery(query);
                    setSelectedIndex(0);
                  }}
                >
                  <Icon name="history" size="sm" className="history-icon" />
                  <span>{query}</span>
                </div>
              ))}
            </div>
          )}
          {(searchQuery.trim() || !searchHistory.length) &&
            (filteredResults.length === 0 ? (
              <div className="command-palette-empty">
                <Icon name="search_off" size="lg" />
                <p>No results found</p>
              </div>
            ) : (
              filteredResults.map((result, index) => (
                <div
                  key={result.id}
                  className={`command-palette-result ${index === selectedIndex ? "selected" : ""}`}
                  onClick={() => handleSelectResult(result)}
                  onMouseEnter={() => setSelectedIndex(index)}
                >
                  <Icon
                    name={getResultIcon(result)}
                    size="md"
                    className="result-icon"
                    outlined
                  />
                  <div className="result-content">
                    <div className="result-title">{result.title}</div>
                    {result.subtitle && (
                      <div className="result-subtitle">{result.subtitle}</div>
                    )}
                    {result.workspaceName && result.type !== "workspace" && (
                      <div className="result-workspace">
                        in {result.workspaceName}
                      </div>
                    )}
                  </div>
                  <div className="result-type">{result.type}</div>
                </div>
              ))
            ))}
        </div>

        <div className="command-palette-footer">
          <div className="command-palette-hint">
            <kbd>↑</kbd>
            <kbd>↓</kbd>
            <span>to navigate</span>
            <kbd>↵</kbd>
            <span>to select</span>
          </div>
        </div>
      </div>
    </div>
  );
};
