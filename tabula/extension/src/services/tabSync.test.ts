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
 * Unit tests for TabSyncService
 */
import { TabSyncService } from "./tabSync";
import { TabService } from "./tabs";

// Mock TabService
jest.mock("./tabs", () => ({
  TabService: {
    moveTab: jest.fn(),
    addTabToGroup: jest.fn(),
    removeTabFromGroup: jest.fn(),
    closeTabs: jest.fn(),
    moveTabGroup: jest.fn(),
    setTabGroupCollapsed: jest.fn(),
    activateTab: jest.fn(),
    setPinned: jest.fn(),
    duplicateTab: jest.fn(),
  },
}));

describe("TabSyncService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("moveTab", () => {
    it("should delegate to TabService.moveTab", async () => {
      await TabSyncService.moveTab(123, 5);

      expect(TabService.moveTab).toHaveBeenCalledWith(123, 5);
    });
  });

  describe("addTabToGroup", () => {
    it("should delegate to TabService.addTabToGroup", async () => {
      await TabSyncService.addTabToGroup(123, 456);

      expect(TabService.addTabToGroup).toHaveBeenCalledWith(123, 456);
    });
  });

  describe("removeTabFromGroup", () => {
    it("should delegate to TabService.removeTabFromGroup", async () => {
      await TabSyncService.removeTabFromGroup(123);

      expect(TabService.removeTabFromGroup).toHaveBeenCalledWith(123);
    });
  });

  describe("closeTab", () => {
    it("should delegate to TabService.closeTabs with single tab", async () => {
      await TabSyncService.closeTab(123);

      expect(TabService.closeTabs).toHaveBeenCalledWith([123]);
    });
  });

  describe("moveTabGroup", () => {
    it("should delegate to TabService.moveTabGroup", async () => {
      await TabSyncService.moveTabGroup([1, 2, 3], 10);

      expect(TabService.moveTabGroup).toHaveBeenCalledWith([1, 2, 3], 10);
    });
  });

  describe("setTabGroupCollapsed", () => {
    it("should delegate to TabService.setTabGroupCollapsed", async () => {
      await TabSyncService.setTabGroupCollapsed(123, true);

      expect(TabService.setTabGroupCollapsed).toHaveBeenCalledWith(123, true);
    });
  });

  describe("activateTab", () => {
    it("should delegate to TabService.activateTab", async () => {
      await TabSyncService.activateTab(123);

      expect(TabService.activateTab).toHaveBeenCalledWith(123);
    });
  });

  describe("setPinned", () => {
    it("should delegate to TabService.setPinned", async () => {
      await TabSyncService.setPinned([1, 2], true);

      expect(TabService.setPinned).toHaveBeenCalledWith([1, 2], true);
    });
  });

  describe("duplicateTab", () => {
    it("should delegate to TabService.duplicateTab", async () => {
      await TabSyncService.duplicateTab(123);

      expect(TabService.duplicateTab).toHaveBeenCalledWith(123);
    });
  });
});
