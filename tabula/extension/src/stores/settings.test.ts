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
 * Tests for settings Zustand store
 */

import { act } from "@testing-library/react";
import { useSettingsStore } from "./settings";
import { StorageService } from "../services/storage";
import type { ExtensionSettings } from "../types";

// Mock StorageService
jest.mock("../services/storage");

// Default settings
const defaultSettings: ExtensionSettings = {
  autoSuspend: false,
  suspendAfterMinutes: 30,
  syncEnabled: false,
  theme: "auto",
  autoSave: true,
  tabCloseMode: "hybrid",
};

describe("useSettingsStore", () => {
  beforeEach(() => {
    jest.clearAllMocks();

    // Reset store to initial state
    useSettingsStore.setState({
      settings: defaultSettings,
      loading: false,
      error: null,
    });

    // Default mock implementations
    (StorageService.getSettings as jest.Mock).mockResolvedValue(
      defaultSettings,
    );
    (StorageService.saveSettings as jest.Mock).mockResolvedValue(undefined);
  });

  describe("initial state", () => {
    it("should have default settings", () => {
      const state = useSettingsStore.getState();

      expect(state.settings.autoSuspend).toBe(false);
      expect(state.settings.suspendAfterMinutes).toBe(30);
      expect(state.settings.syncEnabled).toBe(false);
      expect(state.settings.theme).toBe("auto");
      expect(state.settings.autoSave).toBe(true);
    });

    it("should have loading false", () => {
      expect(useSettingsStore.getState().loading).toBe(false);
    });

    it("should have null error", () => {
      expect(useSettingsStore.getState().error).toBeNull();
    });
  });

  describe("loadSettings", () => {
    it("should load settings from storage", async () => {
      const customSettings: ExtensionSettings = {
        ...defaultSettings,
        autoSuspend: true,
        theme: "dark",
      };
      (StorageService.getSettings as jest.Mock).mockResolvedValue(
        customSettings,
      );

      await act(async () => {
        await useSettingsStore.getState().loadSettings();
      });

      expect(useSettingsStore.getState().settings.autoSuspend).toBe(true);
      expect(useSettingsStore.getState().settings.theme).toBe("dark");
    });

    it("should set loading to true while loading", async () => {
      let loadingDuringFetch = false;

      (StorageService.getSettings as jest.Mock).mockImplementation(async () => {
        loadingDuringFetch = useSettingsStore.getState().loading;
        return defaultSettings;
      });

      await act(async () => {
        await useSettingsStore.getState().loadSettings();
      });

      expect(loadingDuringFetch).toBe(true);
    });

    it("should set loading to false after loading", async () => {
      await act(async () => {
        await useSettingsStore.getState().loadSettings();
      });

      expect(useSettingsStore.getState().loading).toBe(false);
    });

    it("should set error on failure", async () => {
      (StorageService.getSettings as jest.Mock).mockRejectedValue(
        new Error("Storage error"),
      );

      await act(async () => {
        await useSettingsStore.getState().loadSettings();
      });

      expect(useSettingsStore.getState().error).toBe("Storage error");
      expect(useSettingsStore.getState().loading).toBe(false);
    });
  });

  describe("updateSettings", () => {
    it("should update settings and persist to storage", async () => {
      await act(async () => {
        await useSettingsStore.getState().updateSettings({ autoSuspend: true });
      });

      expect(useSettingsStore.getState().settings.autoSuspend).toBe(true);
      expect(StorageService.saveSettings).toHaveBeenCalledWith(
        expect.objectContaining({ autoSuspend: true }),
      );
    });

    it("should merge with existing settings", async () => {
      // First set some custom settings
      useSettingsStore.setState({
        settings: { ...defaultSettings, theme: "light" },
      });

      await act(async () => {
        await useSettingsStore.getState().updateSettings({ autoSuspend: true });
      });

      // Should keep existing theme while updating autoSuspend
      const { settings } = useSettingsStore.getState();
      expect(settings.autoSuspend).toBe(true);
      expect(settings.theme).toBe("light");
    });

    it("should set error on save failure", async () => {
      (StorageService.saveSettings as jest.Mock).mockRejectedValue(
        new Error("Save failed"),
      );

      await act(async () => {
        try {
          await useSettingsStore
            .getState()
            .updateSettings({ autoSuspend: true });
        } catch {
          // Expected to throw
        }
      });

      expect(useSettingsStore.getState().error).toBe("Save failed");
    });

    it("should handle non-Error object in save failure", async () => {
      (StorageService.saveSettings as jest.Mock).mockRejectedValue(
        "String error",
      );

      await act(async () => {
        try {
          await useSettingsStore
            .getState()
            .updateSettings({ autoSuspend: true });
        } catch {
          // Expected to throw
        }
      });

      expect(useSettingsStore.getState().error).toBe("Failed to update");
    });
  });

  describe("error handling edge cases", () => {
    it("should handle non-Error object in loadSettings", async () => {
      (StorageService.getSettings as jest.Mock).mockRejectedValue(
        "String error",
      );

      await act(async () => {
        await useSettingsStore.getState().loadSettings();
      });

      expect(useSettingsStore.getState().error).toBe("Failed to load");
      expect(useSettingsStore.getState().loading).toBe(false);
    });
  });
});
