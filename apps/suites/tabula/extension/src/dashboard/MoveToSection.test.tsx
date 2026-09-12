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
/* eslint-disable no-console */
import { render, screen, fireEvent } from "@testing-library/react";
import { Dashboard } from "./Dashboard";
import { useWorkspaceStore } from "../stores/workspace";
import { WorkspaceService } from "../services/workspace";

// Mock dependencies
jest.mock("../stores/workspace");
jest.mock("../services/workspace");
jest.mock("../services/auth", () => ({
  AuthService: {
    getUser: jest.fn().mockResolvedValue(null),
    getToken: jest.fn().mockResolvedValue(null),
  },
}));
jest.mock("../services/sync", () => ({
  SyncService: {
    initialize: jest.fn(),
    enqueue: jest.fn(),
    subscribe: jest.fn().mockReturnValue(() => {}), // Return unsubscription function
    subscribeToSSE: jest.fn().mockReturnValue(() => {}),
  },
}));
jest.mock("../hooks/useTheme", () => ({
  useTheme: () => ({ theme: "dark", setTheme: jest.fn() }),
}));

// Mock chrome global
const mockChrome = {
  storage: {
    onChanged: {
      addListener: jest.fn(),
      removeListener: jest.fn(),
    },
    local: {
      get: jest.fn(),
      set: jest.fn(),
    },
  },
  runtime: {
    sendMessage: jest.fn(),
  },
  tabs: {
    onCreated: { addListener: jest.fn(), removeListener: jest.fn() },
    onUpdated: { addListener: jest.fn(), removeListener: jest.fn() },
    onRemoved: { addListener: jest.fn(), removeListener: jest.fn() },
    onMoved: { addListener: jest.fn(), removeListener: jest.fn() },
    onActivated: { addListener: jest.fn(), removeListener: jest.fn() },
    onDetached: { addListener: jest.fn(), removeListener: jest.fn() },
    onAttached: { addListener: jest.fn(), removeListener: jest.fn() },
    query: jest.fn().mockResolvedValue([]),
    getCurrent: jest.fn().mockResolvedValue({ id: 456 }),
  },
  tabGroups: {
    onCreated: { addListener: jest.fn(), removeListener: jest.fn() },
    onUpdated: { addListener: jest.fn(), removeListener: jest.fn() },
    onRemoved: { addListener: jest.fn(), removeListener: jest.fn() },
    query: jest.fn().mockResolvedValue([]),
  },
  windows: {
    getCurrent: jest.fn().mockResolvedValue({ id: 123 }),
  },
};
(globalThis as any).chrome = mockChrome;

// Mock hook implementations
const mockUseWorkspaceStore = useWorkspaceStore as unknown as jest.Mock;

describe("MoveToSection Feature", () => {
  const mockWorkspaces = [
    {
      id: "ws-1",
      name: "Workspace 1",
      groupId: "group-1", // Initially in a group
      tabs: [],
      sections: [],
    },
  ];

  const mockSpaceGroups = [
    {
      id: "group-1",
      title: "Group 1",
      collapsed: false,
    },
  ];

  const mockStore = {
    workspaces: mockWorkspaces,
    spaceGroups: mockSpaceGroups,
    activeWorkspaceId: "ws-1",
    loadWorkspaces: jest.fn(),
    createWorkspace: jest.fn(),
    updateWorkspace: jest.fn(),
    switchWorkspace: jest.fn(),
    deleteWorkspace: jest.fn(),
    createSpaceGroup: jest.fn(),
    deleteSpaceGroup: jest.fn(),
    updateSpaceGroup: jest.fn(),
    toggleSpaceGroupCollapse: jest.fn(),
    reorderWorkspaces: jest.fn(),
    reorderSpaceGroups: jest.fn(),
    reorderSections: jest.fn(),
    setActiveWorkspace: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockUseWorkspaceStore.mockReturnValue(mockStore);
    (WorkspaceService.moveWorkspaceToGroup as jest.Mock).mockResolvedValue({});
  });

  it('should call moveWorkspaceToGroup with null when "No section" is selected', async () => {
    render(<Dashboard />);

    // 1. Open the menu for Workspace 1
    // The menu button is usually hidden until hover, but we can verify clicking it opens the menu
    // We need to find the specific menu button for ws-1
    // In SortableNavItem, the WorkspaceMenuItem has a menu button
    const menuButtons = screen.getAllByRole("button", {
      name: "Space options",
    });
    fireEvent.click(menuButtons[0]);

    // 2. Click "Move to section"
    const moveToSectionOption = screen.getByText("Move to section");
    fireEvent.click(moveToSectionOption);

    // 3. Click "No section"
    const noSectionOption = screen.getByText("No section");
    fireEvent.click(noSectionOption);

    // 4. Verify WorkspaceService.moveWorkspaceToGroup was called correctly
    expect(WorkspaceService.moveWorkspaceToGroup).toHaveBeenCalledWith(
      "ws-1",
      null,
    );

    // 5. Verify loadWorkspaces is called to refresh the UI
    expect(mockStore.loadWorkspaces).toHaveBeenCalled();
  });
});
