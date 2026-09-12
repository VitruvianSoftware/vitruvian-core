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

/* eslint-disable @typescript-eslint/no-explicit-any */
import { renderHook, act } from "@testing-library/react";
import { useResourceHandlers } from "./useResourceHandlers";
import { WorkspaceService } from "../../services/workspace";
import { TabService } from "../../services/tabs";
import { StorageService } from "../../services/storage";

// Mock WorkspaceService
jest.mock("../../services/workspace", () => ({
  WorkspaceService: {
    addResource: jest.fn(),
    addResourceToSection: jest.fn(),
    addSection: jest.fn(),
    updateWorkspace: jest.fn(),
    saveCurrentTabsToWorkspace: jest.fn(),
    getActiveWorkspace: jest.fn(),
  },
}));

// Mock TabService
jest.mock("../../services/tabs", () => ({
  TabService: {
    getCurrentTabs: jest.fn().mockResolvedValue([]),
    activateTab: jest.fn(),
    closeTabs: jest.fn(),
  },
}));

// Mock StorageService
jest.mock("../../services/storage", () => ({
  StorageService: {
    getSettings: jest.fn().mockResolvedValue({ tabCloseMode: "idOnly" }),
  },
}));

// Mock chrome.tabs
const mockCreate = jest.fn();
const mockRemove = jest.fn();

(globalThis as any).chrome = {
  tabs: {
    create: mockCreate.mockResolvedValue({
      id: 999,
      url: "http://test.com",
      title: "Test",
    }),
    remove: mockRemove,
    query: jest.fn().mockResolvedValue([]),
  },
} as any;

describe("useResourceHandlers", () => {
  const mockSetActiveWorkspaceData = jest.fn();
  const mockLoadWorkspaces = jest.fn();
  const activeWorkspace = {
    id: "ws1",
    sections: [{ id: "sec1", resources: [] }],
    tabs: [],
    resources: [], // old field
  } as any;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should initialize with default state", () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    expect(result.current.showAddResource).toBe(false);
    expect(result.current.showAddSection).toBe(false);
    expect(result.current.newResourceTitle).toBe("");
    expect(result.current.newResourceUrl).toBe("");
    expect(result.current.newSectionTitle).toBe("");
    expect(result.current.targetSectionId).toBeNull();
  });

  it("should handle open resource in new tab", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleOpenResource("https://example.com");
    });

    expect(mockCreate).toHaveBeenCalledWith({
      url: "https://example.com",
      active: true,
    });
    expect(WorkspaceService.saveCurrentTabsToWorkspace).toHaveBeenCalled();
  });

  it("should handle close tab", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCloseTab(123, "https://example.com");
    });

    expect(TabService.closeTabs).toHaveBeenCalledWith([123]);
    expect(WorkspaceService.updateWorkspace).toHaveBeenCalled();
  });

  it("should create section", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    act(() => {
      result.current.setNewSectionTitle("New Section");
    });

    (WorkspaceService.addSection as jest.Mock).mockResolvedValue({
      id: "sec2",
    });

    await act(async () => {
      await result.current.handleCreateSection();
    });

    expect(WorkspaceService.addSection).toHaveBeenCalledWith(
      "ws1",
      "New Section",
    );
    expect(mockSetActiveWorkspaceData).toHaveBeenCalled();
    expect(result.current.showAddSection).toBe(false);
    expect(result.current.newSectionTitle).toBe("");
  });

  it("should handle add resource to section", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    act(() => {
      result.current.setNewResourceTitle("Res 1");
      result.current.setNewResourceUrl("http://test.com");
      result.current.setTargetSectionId("sec1");
    });

    (WorkspaceService.addResourceToSection as jest.Mock).mockResolvedValue({
      id: "res1",
    });

    await act(async () => {
      await result.current.handleAddResource();
    });

    expect(WorkspaceService.addResourceToSection).toHaveBeenCalledWith(
      "ws1",
      "sec1",
      {
        title: "Res 1",
        url: "http://test.com",
      },
    );
    expect(mockLoadWorkspaces).toHaveBeenCalled();
    expect(result.current.showAddResource).toBe(false);
  });

  it("should handle add resource (no section)", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    act(() => {
      result.current.setNewResourceTitle("Res 1");
      result.current.setNewResourceUrl("http://test.com");
      result.current.setTargetSectionId(null);
    });

    (WorkspaceService.addResource as jest.Mock).mockResolvedValue({
      id: "res1",
    });

    await act(async () => {
      await result.current.handleAddResource();
    });

    expect(WorkspaceService.addResource).toHaveBeenCalledWith("ws1", {
      title: "Res 1",
      url: "http://test.com",
    });
  });

  it("should not create section if title empty", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCreateSection();
    });

    expect(WorkspaceService.addSection).not.toHaveBeenCalled();
  });

  it("should not add resource if url mock", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    // Title set but no URL
    act(() => {
      result.current.setNewResourceTitle("Res 1");
    });

    await act(async () => {
      await result.current.handleAddResource();
    });

    expect(WorkspaceService.addResource).not.toHaveBeenCalled();
    expect(WorkspaceService.addResourceToSection).not.toHaveBeenCalled();
  });

  it("should activate existing tab when resource already open", async () => {
    const existingTab = { id: 123, url: "https://example.com" };
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([existingTab]);

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleOpenResource("https://example.com");
    });

    expect(TabService.activateTab).toHaveBeenCalledWith(123);
    expect(mockCreate).not.toHaveBeenCalled();
  });

  it("should activate existing tab with trailing slash", async () => {
    const existingTab = { id: 456, url: "https://example.com/" };
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([existingTab]);

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleOpenResource("https://example.com");
    });

    expect(TabService.activateTab).toHaveBeenCalledWith(456);
  });

  it("should handle close tab in hybrid mode with URL matching", async () => {
    // Set up hybrid mode
    (StorageService.getSettings as jest.Mock).mockResolvedValue({
      tabCloseMode: "hybrid",
    });

    const matchingTab = { id: 789, url: "https://test.com" };
    (globalThis as any).chrome.tabs.query.mockResolvedValue([matchingTab]);

    const workspaceWithTabs = {
      ...activeWorkspace,
      tabs: [{ id: 123, url: "https://test.com" }],
    };

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace: workspaceWithTabs,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCloseTab(123, "https://test.com");
    });

    expect(TabService.closeTabs).toHaveBeenCalledWith([789]);
  });

  it("should handle close tab in hybrid mode with multiple matches", async () => {
    (StorageService.getSettings as jest.Mock).mockResolvedValue({
      tabCloseMode: "hybrid",
    });

    const matchingTabs = [
      { id: 111, url: "https://test.com" },
      { id: 222, url: "https://test.com" },
    ];
    (globalThis as any).chrome.tabs.query.mockResolvedValue(matchingTabs);

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCloseTab(123, "https://test.com");
    });

    // Should close the first match
    expect(TabService.closeTabs).toHaveBeenCalledWith([111]);
  });

  it("should handle close tab in hybrid mode with no matches", async () => {
    (StorageService.getSettings as jest.Mock).mockResolvedValue({
      tabCloseMode: "hybrid",
    });

    (globalThis as any).chrome.tabs.query.mockResolvedValue([]);

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCloseTab(123, "https://test.com");
    });

    // Should not call closeTabs since no matches
    expect(TabService.closeTabs).not.toHaveBeenCalled();
  });

  it("should not close tab if no active workspace", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace: null,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCloseTab(123, "https://test.com");
    });

    expect(TabService.closeTabs).not.toHaveBeenCalled();
    expect(WorkspaceService.updateWorkspace).not.toHaveBeenCalled();
  });

  it("should handle error when closing tab by ID", async () => {
    (StorageService.getSettings as jest.Mock).mockResolvedValue({
      tabCloseMode: "idOnly",
    });

    (TabService.closeTabs as jest.Mock).mockRejectedValue(
      new Error("Tab not found"),
    );

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCloseTab(123, "https://test.com");
    });

    // Should still update workspace even if tab close failed
    expect(WorkspaceService.updateWorkspace).toHaveBeenCalled();
  });

  it("should handle error in hybrid mode URL matching", async () => {
    (StorageService.getSettings as jest.Mock).mockResolvedValue({
      tabCloseMode: "hybrid",
    });

    (globalThis as any).chrome.tabs.query.mockRejectedValue(
      new Error("Query failed"),
    );

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCloseTab(123, "https://test.com");
    });

    // Should still update workspace
    expect(WorkspaceService.updateWorkspace).toHaveBeenCalled();
  });

  it("should handle invalid URL in handleOpenResource", async () => {
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([]);
    mockCreate.mockResolvedValue({ id: 888, url: "invalid-url", title: "" });

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleOpenResource("invalid-url");
    });

    // Should still create tab but use fallback title
    expect(mockCreate).toHaveBeenCalledWith({
      url: "invalid-url",
      active: true,
    });
  });

  it("should handle close tab error in hybrid mode", async () => {
    (StorageService.getSettings as jest.Mock).mockResolvedValue({
      tabCloseMode: "hybrid",
    });

    // Mock query to throw
    (globalThis as any).chrome.tabs.query.mockRejectedValue(
      new Error("Query failed"),
    );

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      await result.current.handleCloseTab(123, "https://test.com");
    });

    // Should not throw and should update workspace
    expect(WorkspaceService.updateWorkspace).toHaveBeenCalled();
  });

  it("should handle close tab with empty tabUrl in hybrid mode", async () => {
    (StorageService.getSettings as jest.Mock).mockResolvedValue({
      tabCloseMode: "hybrid",
    });

    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      // Empty URL should use ID fallback
      await result.current.handleCloseTab(123, "");
    });

    // Update should be called
    expect(WorkspaceService.updateWorkspace).toHaveBeenCalled();
  });

  it("should set default resource title when not provided", async () => {
    const { result } = renderHook(() =>
      useResourceHandlers({
        activeWorkspace,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        loadWorkspaces: mockLoadWorkspaces,
      }),
    );

    await act(async () => {
      result.current.setNewResourceUrl("http://test.com");
      // Don't set title
    });

    await act(async () => {
      await result.current.handleAddResource();
    });

    expect(WorkspaceService.addResource).toHaveBeenCalledWith("ws1", {
      title: "New Resource", // Default title
      url: "http://test.com",
    });
  });
});
