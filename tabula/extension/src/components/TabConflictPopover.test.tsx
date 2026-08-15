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
/**
 * Unit tests for TabConflictPopover Component
 */

import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { TabConflictPopover } from "./TabConflictPopover";
import {
  WindowOwnershipService,
  WindowOwnershipRecord,
} from "../services/windowOwnership";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";

// Mock feature flag
jest.mock("../lib/flags/use-feature-flag", () => ({
  useFeatureFlag: jest.fn(() => false),
}));

// Mock the WindowOwnershipService
jest.mock("../services/windowOwnership", () => ({
  WindowOwnershipService: {
    getOwnerWindowTabs: jest.fn(),
    focusOwnerWindow: jest.fn(),
    moveTabsToCurrentWindow: jest.fn(),
    registerWorkspaceOwnership: jest.fn(),
  },
}));

// Mock chrome.tabs.getCurrent
Object.assign(globalThis, {
  chrome: {
    tabs: {
      getCurrent: jest.fn(() => Promise.resolve({ id: 999 })),
    },
  },
});

const mockOwnerRecord: WindowOwnershipRecord = {
  workspaceId: "ws1",
  windowId: 1,
  tabId: 100,
  lastActive: Date.now(),
};

const mockTabs: chrome.tabs.Tab[] = [
  {
    id: 101,
    windowId: 1,
    title: "Google",
    url: "https://google.com",
    favIconUrl: "",
  } as any,
  {
    id: 102,
    windowId: 1,
    title: "GitHub",
    url: "https://github.com",
    favIconUrl: "",
  } as any,
  {
    id: 103,
    windowId: 1,
    title: "MDN",
    url: "https://mdn.com",
    favIconUrl: "",
  } as any,
];

describe("TabConflictPopover", () => {
  const mockOnIgnore = jest.fn();
  const mockOnMoveComplete = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (useFeatureFlag as unknown as jest.Mock).mockReturnValue(false);
    (WindowOwnershipService.getOwnerWindowTabs as jest.Mock).mockResolvedValue(
      mockTabs,
    );
  });

  it("should render header with correct title", async () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    expect(screen.getByText("Tabs from another window")).toBeInTheDocument();
  });

  it("should render Go to window button", async () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    expect(screen.getByText("Go to window")).toBeInTheDocument();
  });

  it("should load and display tabs from owner window", async () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Google")).toBeInTheDocument();
      expect(screen.getByText("GitHub")).toBeInTheDocument();
      expect(screen.getByText("MDN")).toBeInTheDocument();
    });
  });

  it("should show loading state while fetching tabs", () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    expect(screen.getByText("Loading tabs...")).toBeInTheDocument();
  });

  it("should show empty state when no tabs", async () => {
    (WindowOwnershipService.getOwnerWindowTabs as jest.Mock).mockResolvedValue(
      [],
    );

    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("No tabs to move")).toBeInTheDocument();
    });
  });

  it("should call onIgnore when Ignore button clicked", async () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Google")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Ignore"));
    expect(mockOnIgnore).toHaveBeenCalled();
  });

  it("should call focusOwnerWindow when Go to window clicked", async () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    fireEvent.click(screen.getByText("Go to window"));

    await waitFor(() => {
      expect(WindowOwnershipService.focusOwnerWindow).toHaveBeenCalledWith(
        mockOwnerRecord,
      );
    });
    expect(mockOnIgnore).toHaveBeenCalled();
  });

  it("should select all tabs by default", async () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Move 3 tabs here")).toBeInTheDocument();
    });
  });

  it("should toggle tab selection on click", async () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Google")).toBeInTheDocument();
    });

    // Click to deselect Google
    fireEvent.click(screen.getByText("Google"));

    await waitFor(() => {
      expect(screen.getByText("Move 2 tabs here")).toBeInTheDocument();
    });
  });

  it("should move selected tabs when Move button clicked", async () => {
    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Move 3 tabs here")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Move 3 tabs here"));

    await waitFor(() => {
      expect(
        WindowOwnershipService.moveTabsToCurrentWindow,
      ).toHaveBeenCalledWith([101, 102, 103], 2);
      expect(
        WindowOwnershipService.registerWorkspaceOwnership,
      ).toHaveBeenCalled();
      expect(mockOnMoveComplete).toHaveBeenCalled();
    });
  });

  it("should disable Move button when no tabs selected", async () => {
    (WindowOwnershipService.getOwnerWindowTabs as jest.Mock).mockResolvedValue([
      {
        id: 101,
        windowId: 1,
        title: "Google",
        url: "https://google.com",
      } as any,
    ]);

    render(
      <TabConflictPopover
        ownerRecord={mockOwnerRecord}
        currentWindowId={2}
        onIgnore={mockOnIgnore}
        onMoveComplete={mockOnMoveComplete}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Google")).toBeInTheDocument();
    });

    // Deselect the only tab
    fireEvent.click(screen.getByText("Google"));

    await waitFor(() => {
      const moveButton = screen.getByText("Move 0 tabs here");
      expect(moveButton).toBeDisabled();
    });
  });

  describe("when design system is enabled", () => {
    beforeEach(() => {
      (useFeatureFlag as unknown as jest.Mock).mockReturnValue(true);
    });

    it("should render design system tab conflict popover", async () => {
      render(
        <TabConflictPopover
          ownerRecord={mockOwnerRecord}
          currentWindowId={2}
          onIgnore={mockOnIgnore}
          onMoveComplete={mockOnMoveComplete}
        />,
      );

      await waitFor(() => {
        expect(
          screen.getByText("Tabs from another window"),
        ).toBeInTheDocument();
        expect(screen.getByText("Go to window")).toBeInTheDocument();
        expect(screen.getByText("Google")).toBeInTheDocument();
        expect(screen.getByText("Move 3 tabs here")).toBeInTheDocument();
      });
    });
  });
});
