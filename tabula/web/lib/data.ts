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
 * Data service for web dashboard
 *
 * Provides data access layer with clear feedback about
 * the current storage context and limitations.
 */

import type { Workspace, WorkspaceStats, DataSourceInfo } from "@/types";
// import { AuthService } from './auth';

// Storage key - must match extension
const STORAGE_KEY = "tabula_workspaces";
const API_URL = "http://localhost:8080/api/v1";

/**
 * Get information about the current data source
 */
export function getDataSourceInfo(): DataSourceInfo {
  // Check if running in extension context
  if (typeof chrome !== "undefined" && chrome.storage) {
    return {
      type: "chrome-storage",
      available: true,
      message: "Connected to Chrome extension storage",
    };
  }

  // Check API (Authenticated)
  if (typeof window !== "undefined" && localStorage.getItem("tabula_token")) {
    return {
      type: "api",
      available: true,
      message: "Connected to Tabula Cloud",
    };
  }

  // Check localStorage (explicit check for window availability)
  if (typeof window !== "undefined") {
    try {
      const hasData = window.localStorage.getItem(STORAGE_KEY) !== null;
      return {
        type: "local-storage",
        available: true,
        message: hasData
          ? "Using local browser storage (demo mode)"
          : "No workspace data found. Create workspaces in the Tabula extension.",
      };
    } catch (e) {
      // Access denied or not available
      console.warn("localStorage not available:", e);
    }
  }

  return {
    type: "none",
    available: false,
    message: "No storage available. Log in to view your workspaces.",
  };
}

/**
 * Fetch all workspaces from available storage
 */
export async function getWorkspaces(): Promise<Workspace[]> {
  // Check if running in extension context
  if (typeof chrome !== "undefined" && chrome.storage) {
    try {
      const result = await chrome.storage.local.get(STORAGE_KEY);
      return (result[STORAGE_KEY] as Workspace[]) || [];
    } catch (error) {
      console.error("[DataService] Failed to load from chrome.storage:", error);
    }
  }

  // API (Authenticated)
  if (typeof window !== "undefined") {
    const token = localStorage.getItem("tabula_token");
    if (token) {
      try {
        const res = await fetch(`${API_URL}/workspaces`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) throw new Error(`API Error: ${res.statusText}`);
        const { data } = await res.json();
        return data;
      } catch (error) {
        console.error("[DataService] Failed to load from API:", error);
      }
    }
  }

  // Fallback to localStorage
  if (typeof window !== "undefined") {
    try {
      const data = window.localStorage.getItem(STORAGE_KEY);
      return data ? JSON.parse(data) : [];
    } catch (error) {
      console.error("[DataService] Failed to parse localStorage data:", error);
    }
  }

  // Return empty array if no storage available
  return [];
}

/**
 * Get a single workspace by ID
 */
export async function getWorkspace(id: string): Promise<Workspace | null> {
  const workspaces = await getWorkspaces();
  return workspaces.find((w) => w.id === id) || null;
}

/**
 * Calculate aggregate statistics from workspaces
 */
export async function getStats(): Promise<WorkspaceStats> {
  const workspaces = await getWorkspaces();

  const stats: WorkspaceStats = {
    totalWorkspaces: workspaces.length,
    totalTabs: 0,
    totalResources: 0,
    totalNotes: 0,
    totalTasks: 0,
    completedTasks: 0,
  };

  workspaces.forEach((workspace) => {
    stats.totalTabs += workspace.tabs?.length || 0;
    stats.totalResources += workspace.resources?.length || 0;
    stats.totalNotes += workspace.notes?.length || 0;
    stats.totalTasks += workspace.tasks?.length || 0;
    stats.completedTasks +=
      workspace.tasks?.filter((t) => t.completed).length || 0;

    // Count resources in sections
    workspace.sections?.forEach((section) => {
      stats.totalResources += section.resources?.length || 0;
    });
  });

  return stats;
}

/**
 * Export workspaces to JSON or CSV format
 */
export async function exportWorkspaces(
  format: "json" | "csv",
): Promise<string> {
  const workspaces = await getWorkspaces();

  if (format === "json") {
    return JSON.stringify(workspaces, null, 2);
  }

  // CSV export
  const csvLines: string[] = [
    "Workspace Name,Description,Total Tabs,Total Resources,Total Notes,Total Tasks,Completed Tasks",
  ];

  workspaces.forEach((workspace) => {
    const tabs = workspace.tabs?.length || 0;
    const resources =
      (workspace.resources?.length || 0) +
      (workspace.sections?.reduce(
        (acc, s) => acc + (s.resources?.length || 0),
        0,
      ) || 0);
    const notes = workspace.notes?.length || 0;
    const tasks = workspace.tasks?.length || 0;
    const completed = workspace.tasks?.filter((t) => t.completed).length || 0;

    // Escape quotes in strings for CSV
    const escapedName = workspace.name.replace(/"/g, '""');
    const escapedDesc = (workspace.description || "").replace(/"/g, '""');

    csvLines.push(
      `"${escapedName}","${escapedDesc}",${tabs},${resources},${notes},${tasks},${completed}`,
    );
  });

  return csvLines.join("\n");
}

/**
 * Trigger file download in the browser
 */
export function downloadFile(
  content: string,
  filename: string,
  mimeType: string,
): void {
  if (typeof window === "undefined") {
    console.warn("[DataService] Cannot download file in server context");
    return;
  }

  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

/**
 * Seed local storage with demo data
 */
export function seedDemoData(): void {
  if (typeof window === "undefined" || !window.localStorage) return;

  const demoWorkspaces: Workspace[] = [
    {
      id: "demo-1",
      name: "Project Alpha",
      description: "Main development workspace",
      icon: "🚀",
      color: "blue",
      tabs: [
        { id: 1, url: "https://github.com", title: "GitHub", favIconUrl: "" },
        { id: 2, url: "https://linear.app", title: "Linear", favIconUrl: "" },
        { id: 3, url: "https://vercel.com", title: "Vercel", favIconUrl: "" },
      ],
      resources: [
        {
          id: "r1",
          url: "https://docs.github.com",
          title: "GitHub Docs",
          createdAt: Date.now(),
        },
      ],
      notes: [
        {
          id: "n1",
          title: "Daily Standup",
          content: "Discuss progress on features",
          updatedAt: Date.now(),
          createdAt: Date.now(),
        },
      ],
      tasks: [
        {
          id: "task1",
          title: "Implement auth",
          completed: true,
          createdAt: Date.now(),
        },
        {
          id: "task2",
          title: "Fix hydration error",
          completed: true,
          createdAt: Date.now(),
        },
        {
          id: "task3",
          title: "Deploy to staging",
          completed: false,
          createdAt: Date.now(),
        },
      ],
      sections: [],
      createdAt: Date.now(),
      updatedAt: Date.now(),
      position: 0,
    },
    {
      id: "demo-2",
      name: "Marketing",
      description: "Campaign resources",
      icon: "📢",
      color: "purple",
      tabs: [
        { id: 4, url: "https://twitter.com", title: "Twitter", favIconUrl: "" },
        {
          id: 5,
          url: "https://analytics.google.com",
          title: "Analytics",
          favIconUrl: "",
        },
      ],
      resources: [],
      notes: [],
      tasks: [
        {
          id: "task4",
          title: "Draft tweet",
          completed: false,
          createdAt: Date.now(),
        },
      ],
      sections: [],
      createdAt: Date.now(),
      updatedAt: Date.now(),
      position: 1,
    },
  ];

  localStorage.setItem(STORAGE_KEY, JSON.stringify(demoWorkspaces));

  // Dispatch storage event to notify other listeners/tabs
  window.dispatchEvent(new Event("storage"));
}

export const DataService = {
  getDataSourceInfo,
  getWorkspaces,
  getWorkspace,
  getStats,
  exportWorkspaces,
  downloadFile,
  seedDemoData,
};
