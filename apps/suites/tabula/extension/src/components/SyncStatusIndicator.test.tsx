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
import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom";
import { SyncStatusIndicator } from "./SyncStatusIndicator";
import { useSyncStore } from "../stores/sync";

// Mock useSyncStore
jest.mock("../stores/sync", () => ({
  useSyncStore: jest.fn(),
}));

jest.mock("../lib/flags/use-feature-flag", () => ({
  useFeatureFlag: jest.fn(() => false),
}));

import { useFeatureFlag } from "../lib/flags/use-feature-flag";

describe("SyncStatusIndicator", () => {
  const mockRetrySync = jest.fn();
  const mockInitialize = jest.fn();

  const getDefaultState = () => ({
    status: "idle" as const,
    pendingCount: 0,
    lastSyncAt: Date.now(),
    lastError: null,
    isOnline: true,
    retrySync: mockRetrySync,
    initialize: mockInitialize,
  });

  beforeEach(() => {
    jest.clearAllMocks();
    (useSyncStore as unknown as jest.Mock).mockReturnValue(getDefaultState());
    (useFeatureFlag as unknown as jest.Mock).mockReturnValue(false);
  });

  it("should render synced state", () => {
    render(<SyncStatusIndicator />);
    expect(screen.getByText("check_circle")).toBeInTheDocument();
  });

  it("should render syncing state", () => {
    (useSyncStore as unknown as jest.Mock).mockReturnValue({
      ...getDefaultState(),
      status: "syncing",
      pendingCount: 3,
    });

    render(<SyncStatusIndicator />);
    expect(screen.getByText("sync")).toBeInTheDocument();
    expect(screen.getByText("Syncing...")).toBeInTheDocument();
  });

  it("should render error state", () => {
    (useSyncStore as unknown as jest.Mock).mockReturnValue({
      ...getDefaultState(),
      status: "error",
      lastError: "Network error",
    });

    render(<SyncStatusIndicator />);
    expect(screen.getByText("error")).toBeInTheDocument();
    expect(screen.getByText("Sync failed")).toBeInTheDocument();
  });

  it("should render offline state", () => {
    (useSyncStore as unknown as jest.Mock).mockReturnValue({
      ...getDefaultState(),
      status: "offline",
      isOnline: false,
    });

    render(<SyncStatusIndicator />);
    expect(screen.getByText("cloud_off")).toBeInTheDocument();
  });

  it("should show pending count badge", () => {
    (useSyncStore as unknown as jest.Mock).mockReturnValue({
      ...getDefaultState(),
      pendingCount: 5,
    });

    render(<SyncStatusIndicator />);
    expect(screen.getByText("5")).toBeInTheDocument();
  });

  it("should call retrySync when clicked in error state", () => {
    (useSyncStore as unknown as jest.Mock).mockReturnValue({
      ...getDefaultState(),
      status: "error",
    });

    render(<SyncStatusIndicator />);

    const indicator = screen.getByText("error").closest("div")?.parentElement;
    fireEvent.click(indicator!);

    expect(mockRetrySync).toHaveBeenCalled();
  });

  it("should call initialize on mount", () => {
    render(<SyncStatusIndicator />);
    expect(mockInitialize).toHaveBeenCalled();
  });

  it("should show cloud_upload when idle with pending items", () => {
    (useSyncStore as unknown as jest.Mock).mockReturnValue({
      ...getDefaultState(),
      pendingCount: 2,
    });

    render(<SyncStatusIndicator />);
    expect(screen.getByText("cloud_upload")).toBeInTheDocument();
  });

  describe("when design system is enabled", () => {
    beforeEach(() => {
      (useFeatureFlag as unknown as jest.Mock).mockReturnValue(true);
    });

    it("should render synced state with design system components", () => {
      render(<SyncStatusIndicator />);
      expect(screen.getByText("check_circle")).toBeInTheDocument();
    });

    it("should render error state with discard button in DS mode", () => {
      const mockDiscardFailed = jest.fn();
      (useSyncStore as unknown as jest.Mock).mockReturnValue({
        ...getDefaultState(),
        status: "error",
        lastError: "Failed to reach server",
        discardFailed: mockDiscardFailed,
      });

      render(<SyncStatusIndicator />);
      expect(screen.getByText("error")).toBeInTheDocument();
      expect(screen.getByText("Sync failed")).toBeInTheDocument();

      const discardBtn = screen.getByText("Discard");
      expect(discardBtn).toBeInTheDocument();
      fireEvent.click(discardBtn);
      expect(mockDiscardFailed).toHaveBeenCalled();
    });

    it("should render pending tag in DS mode", () => {
      (useSyncStore as unknown as jest.Mock).mockReturnValue({
        ...getDefaultState(),
        pendingCount: 4,
      });

      render(<SyncStatusIndicator />);
      expect(screen.getByText("4")).toBeInTheDocument();
    });
  });
});
