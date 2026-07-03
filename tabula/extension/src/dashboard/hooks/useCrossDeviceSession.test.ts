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

import { renderHook, waitFor, act } from "@testing-library/react";
import { useCrossDeviceSession } from "./useCrossDeviceSession";
import type { Workspace } from "../../types";

// Keep the hook's lease window deterministic without importing useTabSync's deps.
jest.mock("../../hooks/useTabSync", () => ({
  ACTIVE_DEVICE_STALE_MS: 2 * 60 * 1000,
}));
jest.mock("../../services/deviceId", () => ({ getDeviceId: jest.fn() }));
jest.mock("../../services/tabs", () => ({
  TabService: { getCurrentTabs: jest.fn() },
}));

import { getDeviceId } from "../../services/deviceId";
import { TabService } from "../../services/tabs";

const ME = "this-device";

const makeWorkspace = (overrides: Partial<Workspace> = {}): Workspace => ({
  id: "ws1",
  name: "Test",
  position: 0,
  tabs: [{ url: "https://primary.com", title: "Primary" }],
  resources: [],
  sections: [],
  notes: [],
  tasks: [],
  createdAt: Date.now(),
  updatedAt: Date.now(),
  ...overrides,
});

describe("useCrossDeviceSession", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (getDeviceId as jest.Mock).mockResolvedValue(ME);
    // Live browser tabs differ from the primary's by default.
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
      { url: "https://mine.com", title: "Mine" },
    ]);
  });

  it("offers the primary's tabs when the space is live on another device and tabs differ", async () => {
    const ws = makeWorkspace({
      activeDeviceId: "other-device",
      activeDeviceSeenAt: new Date().toISOString(),
    });
    const { result } = renderHook(() => useCrossDeviceSession(ws));

    await waitFor(() => expect(result.current.conflictTabs).not.toBeNull());
    expect(result.current.conflictTabs?.map((t) => t.url)).toEqual([
      "https://primary.com",
    ]);
  });

  it("does NOT prompt when this device holds the lease", async () => {
    const ws = makeWorkspace({
      activeDeviceId: ME,
      activeDeviceSeenAt: new Date().toISOString(),
    });
    const { result } = renderHook(() => useCrossDeviceSession(ws));
    await waitFor(() => expect(getDeviceId).toHaveBeenCalled());
    expect(result.current.conflictTabs).toBeNull();
  });

  it("does NOT prompt when the foreign lease is stale", async () => {
    const ws = makeWorkspace({
      activeDeviceId: "other-device",
      activeDeviceSeenAt: new Date(Date.now() - 3 * 60 * 1000).toISOString(),
    });
    const { result } = renderHook(() => useCrossDeviceSession(ws));
    // Stale lease short-circuits before getCurrentTabs is consulted.
    await waitFor(() =>
      expect(TabService.getCurrentTabs).not.toHaveBeenCalled(),
    );
    expect(result.current.conflictTabs).toBeNull();
  });

  it("does NOT prompt when the live tabs already match the primary's", async () => {
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
      { url: "https://primary.com", title: "Primary" },
    ]);
    const ws = makeWorkspace({
      activeDeviceId: "other-device",
      activeDeviceSeenAt: new Date().toISOString(),
    });
    const { result } = renderHook(() => useCrossDeviceSession(ws));
    await waitFor(() => expect(TabService.getCurrentTabs).toHaveBeenCalled());
    expect(result.current.conflictTabs).toBeNull();
  });

  it("dismiss() suppresses the same divergence", async () => {
    const ws = makeWorkspace({
      activeDeviceId: "other-device",
      activeDeviceSeenAt: new Date().toISOString(),
    });
    const { result } = renderHook(() => useCrossDeviceSession(ws));
    await waitFor(() => expect(result.current.conflictTabs).not.toBeNull());
    act(() => result.current.dismiss());
    expect(result.current.conflictTabs).toBeNull();
  });
});
