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
import { useWorkspaceSwitch } from "./useWorkspaceSwitch";
import { WorkspaceService } from "../../services/workspace";
import { WindowOwnershipService } from "../../services/windowOwnership";

jest.mock("../../services/workspace");
jest.mock("../../services/windowOwnership", () => ({
  WindowOwnershipService: {
    tryClaimWorkspace: jest.fn(),
    registerWorkspaceOwnership: jest.fn(),
    isWorkspaceOwnedByOtherWindow: jest.fn(),
    clearWorkspaceOwnership: jest.fn(),
  },
}));

// chrome.tabs.getCurrent is used to resolve the dashboard tab for claims
(globalThis as any).chrome = {
  ...(globalThis as any).chrome,
  tabs: {
    ...(globalThis as any).chrome?.tabs,
    getCurrent: jest.fn().mockResolvedValue({ id: 42 }),
  },
};

describe("useWorkspaceSwitch", () => {
  let mockSwitchWorkspace: jest.Mock;
  let mockIsSwitchingRef: { current: boolean };
  let mockSetActiveWorkspaceData: jest.Mock;
  let mockSetActiveWorkspaceId: jest.Mock;

  const renderSwitchHook = (overrides: Record<string, unknown> = {}) =>
    renderHook(() =>
      useWorkspaceSwitch({
        activeWorkspaceId: "ws1",
        switchWorkspace: mockSwitchWorkspace,
        isSwitchingRef: mockIsSwitchingRef as any,
        setActiveWorkspaceData: mockSetActiveWorkspaceData,
        setActiveWorkspaceId: mockSetActiveWorkspaceId,
        ...overrides,
      } as any),
    );

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
    mockSetActiveWorkspaceData = jest.fn();
    mockSetActiveWorkspaceId = jest.fn();
    mockSwitchWorkspace = jest.fn().mockResolvedValue(undefined);
    mockIsSwitchingRef = { current: false };
    ((globalThis as any).chrome.tabs.getCurrent as jest.Mock).mockResolvedValue(
      { id: 42 },
    );
    // Mock getWorkspaceById to return a workspace with fresh tabs
    (WorkspaceService.getWorkspaceById as jest.Mock).mockResolvedValue({
      id: "ws2",
      name: "Test Workspace",
      tabs: [{ id: 999, url: "https://example.com" }],
    });
    (WindowOwnershipService.tryClaimWorkspace as jest.Mock).mockResolvedValue({
      claimed: true,
    });
    (
      WindowOwnershipService.registerWorkspaceOwnership as jest.Mock
    ).mockResolvedValue(undefined);
    (
      WindowOwnershipService.isWorkspaceOwnedByOtherWindow as jest.Mock
    ).mockResolvedValue(null);
    (
      WindowOwnershipService.clearWorkspaceOwnership as jest.Mock
    ).mockResolvedValue(undefined);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it("should not switch if target id matches active workspace id", async () => {
    const { result } = renderSwitchHook();

    await act(async () => {
      await result.current.handleSwitch("ws1");
    });

    expect(mockSwitchWorkspace).not.toHaveBeenCalled();
  });

  it("should not switch if already switching", async () => {
    mockIsSwitchingRef.current = true;
    const { result } = renderSwitchHook();

    await act(async () => {
      await result.current.handleSwitch("ws2");
    });

    expect(mockSwitchWorkspace).not.toHaveBeenCalled();
  });

  it("should perform switch sequence correctly", async () => {
    const { result } = renderSwitchHook();

    await act(async () => {
      await result.current.handleSwitch("ws2");
    });

    // 1. Save current tabs
    expect(WorkspaceService.saveCurrentTabsToWorkspace).toHaveBeenCalledWith(
      "ws1",
    );

    // 2. switchWorkspace called
    expect(mockSwitchWorkspace).toHaveBeenCalledWith("ws2");

    expect(mockIsSwitchingRef.current).toBe(true); // It should still be true because of setTimeout(..., 500)

    // Advance timer
    act(() => {
      jest.advanceTimersByTime(500);
    });

    expect(mockIsSwitchingRef.current).toBe(false);
  });

  it("should reset switching ref even if switch fails", async () => {
    mockSwitchWorkspace.mockRejectedValue(new Error("Switch failed"));
    const { result } = renderSwitchHook();

    await act(async () => {
      try {
        await result.current.handleSwitch("ws2");
      } catch (e) {
        // Expected error
      }
    });

    expect(mockIsSwitchingRef.current).toBe(true);

    act(() => {
      jest.advanceTimersByTime(500);
    });

    expect(mockIsSwitchingRef.current).toBe(false);
  });

  describe("ownership claim (multi-window)", () => {
    it("claims the workspace atomically BEFORE switching", async () => {
      const { result } = renderSwitchHook({ currentWindowId: 7 });

      await act(async () => {
        await result.current.handleSwitch("ws2");
      });

      expect(WindowOwnershipService.tryClaimWorkspace).toHaveBeenCalledWith(
        "ws2",
        7,
        42,
      );
      // Claim must precede the actual switch
      const claimOrder = (WindowOwnershipService.tryClaimWorkspace as jest.Mock)
        .mock.invocationCallOrder[0];
      const switchOrder = mockSwitchWorkspace.mock.invocationCallOrder[0];
      expect(claimOrder).toBeLessThan(switchOrder);
    });

    it("shows the conflict popover and does NOT switch when the claim is rejected", async () => {
      const owner = {
        workspaceId: "ws2",
        windowId: 99,
        tabId: 1,
        lastActive: Date.now(),
      };
      (WindowOwnershipService.tryClaimWorkspace as jest.Mock).mockResolvedValue(
        {
          claimed: false,
          owner,
        },
      );
      const { result } = renderSwitchHook({ currentWindowId: 7 });

      await act(async () => {
        await result.current.handleSwitch("ws2");
      });

      expect(mockSwitchWorkspace).not.toHaveBeenCalled();
      expect(result.current.conflict).toEqual({
        targetWorkspaceId: "ws2",
        ownerRecord: owner,
      });
    });

    it("re-claims idempotently when clicking the already-active workspace", async () => {
      const { result } = renderSwitchHook({ currentWindowId: 7 });

      await act(async () => {
        await result.current.handleSwitch("ws1");
      });

      expect(WindowOwnershipService.tryClaimWorkspace).toHaveBeenCalledWith(
        "ws1",
        7,
        42,
      );
      expect(mockSwitchWorkspace).not.toHaveBeenCalled();
    });

    it("does not save the departing workspace when another live window owns it", async () => {
      (
        WindowOwnershipService.isWorkspaceOwnedByOtherWindow as jest.Mock
      ).mockResolvedValue({
        workspaceId: "ws1",
        windowId: 99,
        tabId: 1,
        lastActive: Date.now(),
      });
      const { result } = renderSwitchHook({ currentWindowId: 7 });

      await act(async () => {
        await result.current.handleSwitch("ws2");
      });

      expect(
        WorkspaceService.saveCurrentTabsToWorkspace,
      ).not.toHaveBeenCalledWith("ws1");
      expect(mockSwitchWorkspace).toHaveBeenCalledWith("ws2");
    });

    it("releases the claim when the switch fails", async () => {
      mockSwitchWorkspace.mockRejectedValue(new Error("Switch failed"));
      const { result } = renderSwitchHook({ currentWindowId: 7 });

      await act(async () => {
        try {
          await result.current.handleSwitch("ws2");
        } catch (e) {
          // Expected error
        }
      });

      expect(
        WindowOwnershipService.clearWorkspaceOwnership,
      ).toHaveBeenCalledWith("ws2", 7);
    });

    it("forceSwitch registers take-over ownership before performing the switch", async () => {
      const { result } = renderSwitchHook({ currentWindowId: 7 });

      await act(async () => {
        await result.current.forceSwitch("ws2");
      });

      expect(
        WindowOwnershipService.registerWorkspaceOwnership,
      ).toHaveBeenCalledWith("ws2", 7, 42);
      const registerOrder = (
        WindowOwnershipService.registerWorkspaceOwnership as jest.Mock
      ).mock.invocationCallOrder[0];
      const switchOrder = mockSwitchWorkspace.mock.invocationCallOrder[0];
      expect(registerOrder).toBeLessThan(switchOrder);
    });
  });
});
