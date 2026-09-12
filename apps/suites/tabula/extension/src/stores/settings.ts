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
 * Settings store using Zustand
 */

import { create } from "zustand";
import type { ExtensionSettings } from "../types";
import { StorageService } from "../services/storage";

interface SettingsStore {
  settings: ExtensionSettings;
  loading: boolean;
  error: string | null;

  // Actions
  loadSettings: () => Promise<void>;
  updateSettings: (settings: Partial<ExtensionSettings>) => Promise<void>;
}

export const useSettingsStore = create<SettingsStore>((set, get) => ({
  settings: {
    autoSuspend: false,
    suspendAfterMinutes: 30,
    syncEnabled: false,
    theme: "auto",
    autoSave: true,
    tabCloseMode: "hybrid",
    onboardingCompleted: false,
  },
  loading: false,
  error: null,

  loadSettings: async () => {
    set({ loading: true, error: null });
    try {
      const settings = await StorageService.getSettings();
      set({ settings, loading: false });
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to load",
        loading: false,
      });
    }
  },

  updateSettings: async (updates: Partial<ExtensionSettings>) => {
    set({ loading: true, error: null });
    try {
      const newSettings = { ...get().settings, ...updates };
      await StorageService.saveSettings(newSettings);
      set({ settings: newSettings, loading: false });
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to update",
        loading: false,
      });
      throw error;
    }
  },
}));
