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
 * Unit tests for router utilities
 */
/* eslint-disable @typescript-eslint/no-explicit-any */

import {
  getSpaceIdFromUrl,
  setSpaceIdInUrl,
  clearSpaceIdFromUrl,
  getDashboardUrlWithSpace,
} from "./router";

describe("router", () => {
  // Store original location
  const originalLocation = window.location;
  const originalHistoryPushState = window.history.pushState;

  beforeEach(() => {
    // Reset location mock before each test
    delete (window as any).location;
    (window as any).location = new URL(
      "chrome-extension://test-id/dashboard.html",
    );

    // Mock history.pushState
    window.history.pushState = jest.fn();

    // Mock chrome.runtime.getURL
    (globalThis as any).chrome = {
      runtime: {
        getURL: jest.fn((path: string) => `chrome-extension://test-id/${path}`),
      },
    };
  });

  afterEach(() => {
    // Restore original location
    (window as any).location = originalLocation;
    window.history.pushState = originalHistoryPushState;
  });

  describe("getSpaceIdFromUrl", () => {
    it("should return null when no spaceId param exists", () => {
      (window as any).location = new URL(
        "chrome-extension://test-id/dashboard.html",
      );
      expect(getSpaceIdFromUrl()).toBeNull();
    });

    it("should return spaceId when param exists", () => {
      (window as any).location = new URL(
        "chrome-extension://test-id/dashboard.html?spaceId=workspace-123",
      );
      expect(getSpaceIdFromUrl()).toBe("workspace-123");
    });

    it("should return spaceId with other params present", () => {
      (window as any).location = new URL(
        "chrome-extension://test-id/dashboard.html?view=note&spaceId=workspace-456&noteId=abc",
      );
      expect(getSpaceIdFromUrl()).toBe("workspace-456");
    });
  });

  describe("setSpaceIdInUrl", () => {
    it("should update URL with spaceId", () => {
      (window as any).location = new URL(
        "chrome-extension://test-id/dashboard.html",
      );
      setSpaceIdInUrl("workspace-789");

      expect(window.history.pushState).toHaveBeenCalledWith(
        { spaceId: "workspace-789" },
        "",
        expect.stringContaining("spaceId=workspace-789"),
      );
    });
  });

  describe("clearSpaceIdFromUrl", () => {
    it("should remove spaceId from URL", () => {
      (window as any).location = new URL(
        "chrome-extension://test-id/dashboard.html?spaceId=workspace-123",
      );

      clearSpaceIdFromUrl();

      // Verify pushState was called without spaceId
      expect(window.history.pushState).toHaveBeenCalledWith(
        {},
        "",
        expect.any(String),
      );
      const calledUrl = (window.history.pushState as jest.Mock).mock
        .calls[0][2];
      expect(calledUrl).not.toContain("spaceId");
    });
  });

  describe("getDashboardUrlWithSpace", () => {
    it("should generate correct dashboard URL with spaceId", () => {
      const url = getDashboardUrlWithSpace("my-workspace");

      expect(url).toBe(
        "chrome-extension://test-id/dashboard.html?spaceId=my-workspace",
      );
      expect(chrome.runtime.getURL).toHaveBeenCalledWith("dashboard.html");
    });
  });
});
