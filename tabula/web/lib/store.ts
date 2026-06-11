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

"use client";

/**
 * Zustand store for web dashboard state management
 *
 * Provides centralized state for workspaces and stats,
 * consistent with the extension's state management patterns.
 */

import { create } from "zustand";
import type { Workspace, WorkspaceStats, DataSourceInfo } from "@/types";
import { AuthService, User } from "./auth";
import {
  getStats,
  getWorkspaces,
  getDataSourceInfo,
  seedDemoData,
} from "./data";

interface WorkspaceState {
  // Auth
  user: User | null;
  isAuthenticated: boolean;

  // Data
  workspaces: Workspace[];
  stats: WorkspaceStats | null;
  dataSource: DataSourceInfo | null;

  // Loading states
  loading: boolean;
  error: string | null;

  // Actions
  fetchWorkspaces: () => Promise<void>;
  fetchStats: () => Promise<void>;
  refresh: () => Promise<void>;
  seedDemoData: () => Promise<void>;
  login: () => Promise<void>;
  logout: () => void;
}

export const useWorkspaceStore = create<WorkspaceState>((set, get) => ({
  // Initial state
  user: AuthService.getUser(),
  isAuthenticated: !!AuthService.getToken(),
  workspaces: [],
  stats: null,
  dataSource: null,
  loading: true,
  error: null,

  // Fetch workspaces from data service
  fetchWorkspaces: async () => {
    try {
      set({ loading: true, error: null });
      const workspaces = await getWorkspaces();
      const dataSource = getDataSourceInfo();
      set({ workspaces, dataSource, loading: false });
    } catch (error) {
      set({
        error:
          error instanceof Error ? error.message : "Failed to load workspaces",
        loading: false,
      });
    }
  },

  // Fetch stats from data service
  fetchStats: async () => {
    try {
      set({ loading: true, error: null });
      set({ loading: true, error: null });
      const stats = await getStats();
      const dataSource = getDataSourceInfo();
      set({ stats, dataSource, loading: false });
      // set({ loading: false });
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to load stats",
        loading: false,
      });
    }
  },

  // Refresh all data
  refresh: async () => {
    const { fetchWorkspaces, fetchStats } = get();
    await Promise.all([fetchWorkspaces(), fetchStats()]);
  },

  // Seed demo data
  seedDemoData: async () => {
    seedDemoData();
    await get().refresh();
  },

  // Auth actions
  login: async () => {
    try {
      set({ loading: true, error: null });
      const { user } = await AuthService.login();
      set({ user, isAuthenticated: true, loading: false });

      // Refresh data after login
      const { refresh } = get();
      await refresh();
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Login failed",
        loading: false,
      });
    }
  },

  logout: () => {
    AuthService.logout();
    set({
      user: null,
      isAuthenticated: false,
      workspaces: [],
      stats: null,
      dataSource: null,
    });
    // Refresh to update data source info (back to demo/none)
    get().fetchWorkspaces();
  },
}));
