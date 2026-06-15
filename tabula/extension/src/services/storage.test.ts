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
 * Unit tests for StorageService
 */

import { StorageService } from "./storage";
import type { Workspace, ExtensionSettings } from "../types";

// Mock chrome.storage API
const mockStorage = {
  local: {
    get: jest.fn(),
    set: jest.fn(),
    remove: jest.fn(),
    clear: jest.fn(),
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = {
  storage: mockStorage,
};

describe("StorageService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("getWorkspaces", () => {
    it("should return empty array when no workspaces exist", async () => {
      mockStorage.local.get.mockResolvedValue({});
      const result = await StorageService.getWorkspaces();
      expect(result).toEqual([]);
    });

    it("should return workspaces from storage", async () => {
      const workspaces: Workspace[] = [
        {
          id: "ws1",
          name: "Test",
          tabs: [],
          resources: [],
          sections: [],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      mockStorage.local.get.mockResolvedValue({
        tabula_workspaces: workspaces,
      });
      const result = await StorageService.getWorkspaces();
      expect(result).toEqual(workspaces);
    });
  });

  describe("saveWorkspaces", () => {
    it("should save workspaces to storage", async () => {
      const workspaces: Workspace[] = [
        {
          id: "ws1",
          name: "Test",
          tabs: [],
          resources: [],
          sections: [],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      mockStorage.local.set.mockResolvedValue(undefined);
      await StorageService.saveWorkspaces(workspaces);
      expect(mockStorage.local.set).toHaveBeenCalledWith({
        tabula_workspaces: workspaces,
      });
    });
  });

  describe("getWorkspaceById", () => {
    it("should return workspace by id", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      mockStorage.local.get.mockResolvedValue({
        tabula_workspaces: [workspace],
      });
      const result = await StorageService.getWorkspaceById("ws1");
      expect(result).toEqual(workspace);
    });

    it("should return undefined for non-existent workspace", async () => {
      mockStorage.local.get.mockResolvedValue({ tabula_workspaces: [] });
      const result = await StorageService.getWorkspaceById("nonexistent");
      expect(result).toBeUndefined();
    });
  });

  describe("getSettings", () => {
    it("should return default settings when none exist", async () => {
      mockStorage.local.get.mockResolvedValue({});
      const result = await StorageService.getSettings();
      expect(result).toEqual({
        autoSave: true,
        autoSuspend: false,
        suspendAfterMinutes: 30,
        syncEnabled: false,
        theme: "auto",
        tabCloseMode: "hybrid",
        onboardingCompleted: false,
      });
    });

    it("should return saved settings", async () => {
      const settings: ExtensionSettings = {
        autoSuspend: true,
        suspendAfterMinutes: 60,
        syncEnabled: true,
        theme: "dark",
        autoSave: true,
        tabCloseMode: "hybrid",
      };
      mockStorage.local.get.mockResolvedValue({ tabula_settings: settings });
      const result = await StorageService.getSettings();
      expect(result).toEqual(settings);
    });
  });

  describe("saveSettings", () => {
    it("should save settings to storage", async () => {
      const settings: ExtensionSettings = {
        autoSuspend: true,
        suspendAfterMinutes: 60,
        syncEnabled: true,
        theme: "dark",
        autoSave: true,
        tabCloseMode: "hybrid",
      };
      mockStorage.local.set.mockResolvedValue(undefined);
      await StorageService.saveSettings(settings);
      expect(mockStorage.local.set).toHaveBeenCalledWith({
        tabula_settings: settings,
      });
    });
  });

  describe("clearAll", () => {
    it("should clear all storage", async () => {
      mockStorage.local.clear.mockResolvedValue(undefined);
      await StorageService.clearAll();
      expect(mockStorage.local.clear).toHaveBeenCalled();
    });

    it("should throw error on failure", async () => {
      mockStorage.local.clear.mockRejectedValue(new Error("Clear failed"));
      await expect(StorageService.clearAll()).rejects.toThrow("Clear failed");
    });
  });

  describe("getActiveWorkspaceId", () => {
    it("should return active workspace ID from storage", async () => {
      mockStorage.local.get.mockResolvedValue({
        tabula_active_workspace: "ws-123",
      });
      const result = await StorageService.getActiveWorkspaceId();
      expect(result).toBe("ws-123");
    });

    it("should return null when no active workspace", async () => {
      mockStorage.local.get.mockResolvedValue({});
      const result = await StorageService.getActiveWorkspaceId();
      expect(result).toBeNull();
    });

    it("should return null on error", async () => {
      mockStorage.local.get.mockRejectedValue(new Error("Storage error"));
      const result = await StorageService.getActiveWorkspaceId();
      expect(result).toBeNull();
    });
  });

  describe("setActiveWorkspaceId", () => {
    it("should set active workspace ID", async () => {
      mockStorage.local.set.mockResolvedValue(undefined);
      await StorageService.setActiveWorkspaceId("ws-456");
      expect(mockStorage.local.set).toHaveBeenCalledWith({
        tabula_active_workspace: "ws-456",
      });
    });

    it("should remove active workspace when null", async () => {
      mockStorage.local.remove.mockResolvedValue(undefined);
      await StorageService.setActiveWorkspaceId(null);
      expect(mockStorage.local.remove).toHaveBeenCalledWith(
        "tabula_active_workspace",
      );
    });

    it("should throw error on failure", async () => {
      mockStorage.local.set.mockRejectedValue(new Error("Set failed"));
      await expect(
        StorageService.setActiveWorkspaceId("ws-123"),
      ).rejects.toThrow("Set failed");
    });
  });

  describe("getSpaceGroups", () => {
    it("should return space groups from storage", async () => {
      const groups = [
        {
          id: "sg-1",
          title: "Group 1",
          collapsed: false,
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      mockStorage.local.get.mockResolvedValue({
        tabula_space_groups: groups,
      });
      const result = await StorageService.getSpaceGroups();
      expect(result).toEqual(groups);
    });

    it("should return empty array when no groups exist", async () => {
      mockStorage.local.get.mockResolvedValue({});
      const result = await StorageService.getSpaceGroups();
      expect(result).toEqual([]);
    });

    it("should return empty array on error", async () => {
      mockStorage.local.get.mockRejectedValue(new Error("Storage error"));
      const result = await StorageService.getSpaceGroups();
      expect(result).toEqual([]);
    });
  });

  describe("saveSpaceGroups", () => {
    it("should save space groups to storage", async () => {
      const groups = [
        {
          id: "sg-1",
          title: "Group 1",
          collapsed: false,
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      mockStorage.local.set.mockResolvedValue(undefined);
      await StorageService.saveSpaceGroups(groups);
      expect(mockStorage.local.set).toHaveBeenCalledWith({
        tabula_space_groups: groups,
      });
    });

    it("should throw error on failure", async () => {
      mockStorage.local.set.mockRejectedValue(new Error("Save failed"));
      await expect(StorageService.saveSpaceGroups([])).rejects.toThrow(
        "Save failed",
      );
    });
  });

  describe("error handling", () => {
    it("should return empty array when getWorkspaces fails", async () => {
      mockStorage.local.get.mockRejectedValue(new Error("Storage error"));
      const result = await StorageService.getWorkspaces();
      expect(result).toEqual([]);
    });

    it("should throw error when saveWorkspaces fails", async () => {
      mockStorage.local.set.mockRejectedValue(new Error("Save failed"));
      await expect(
        StorageService.saveWorkspaces([
          {
            id: "ws1",
            name: "Test",
            tabs: [],
            resources: [],
            sections: [],
            notes: [],
            tasks: [],
            position: 0,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        ]),
      ).rejects.toThrow("Save failed");
    });

    it("should return default settings when getSettings fails", async () => {
      mockStorage.local.get.mockRejectedValue(new Error("Storage error"));
      const result = await StorageService.getSettings();
      expect(result).toEqual({
        autoSuspend: false,
        suspendAfterMinutes: 30,
        syncEnabled: false,
        theme: "auto",
        autoSave: true,
        tabCloseMode: "hybrid",
        onboardingCompleted: false,
      });
    });

    it("should throw error when saveSettings fails", async () => {
      mockStorage.local.set.mockRejectedValue(new Error("Save failed"));
      await expect(
        StorageService.saveSettings({
          autoSuspend: false,
          suspendAfterMinutes: 30,
          syncEnabled: false,
          theme: "auto",
          autoSave: true,
          tabCloseMode: "hybrid",
        }),
      ).rejects.toThrow("Save failed");
    });
  });
});
