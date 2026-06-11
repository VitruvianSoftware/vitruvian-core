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
import { DataService } from "./data";

// Mock localStorage
const localStorageMock = (function createLocalStorageMock() {
  let store: Record<string, string> = {};
  return {
    getItem: jest.fn((key: string) => store[key] || null),
    setItem: jest.fn((key: string, value: string) => {
      store[key] = value.toString();
    }),
    removeItem: jest.fn((key: string) => {
      delete store[key];
    }),
    clear: jest.fn(() => {
      store = {};
    }),
  };
})();

Object.defineProperty(window, "localStorage", {
  value: localStorageMock,
});

// Mock fetch
global.fetch = jest.fn();

// Mock chrome
const chromeMock = {
  storage: {
    local: {
      get: jest.fn(),
    },
  },
};

describe("DataService", () => {
  beforeEach(() => {
    localStorageMock.clear();
    jest.clearAllMocks();
    // Reset global chrome if set
    // @ts-expect-error - chrome is not defined on global in test environment
    delete global.chrome;
  });

  describe("getDataSourceInfo", () => {
    it("should detect chrome extension environment", () => {
      // @ts-expect-error - mock chrome implementation
      global.chrome = chromeMock;
      const info = DataService.getDataSourceInfo();
      expect(info.type).toBe("chrome-storage");
      expect(info.available).toBe(true);
    });

    it("should detect api environment when token exists", () => {
      localStorageMock.setItem("tabula_token", "fake-token");
      const info = DataService.getDataSourceInfo();
      expect(info.type).toBe("api");
      expect(info.available).toBe(true);
    });

    it("should detect local storage (demo mode) when data exists", () => {
      localStorageMock.setItem("tabula_workspaces", "[]");
      const info = DataService.getDataSourceInfo();
      expect(info.type).toBe("local-storage");
      expect(info.message).toContain("Using local browser storage");
    });

    it("should show no data message for local storage when empty", () => {
      // localStorage is available but empty
      const info = DataService.getDataSourceInfo();
      expect(info.type).toBe("local-storage");
      expect(info.message).toContain("No workspace data found");
    });
  });

  describe("getWorkspaces", () => {
    const mockWorkspaces = [{ id: "1", name: "Test", tabs: [] }];

    it("should fetch from chrome storage", async () => {
      global.chrome = {
        storage: {
          local: {
            get: jest
              .fn()
              .mockResolvedValue({ tabula_workspaces: mockWorkspaces }),
          },
        },
      } as any;
      const result = await DataService.getWorkspaces();
      expect(result).toEqual(mockWorkspaces);
      expect(global.chrome.storage.local.get).toHaveBeenCalledWith(
        "tabula_workspaces",
      );
    });

    it("should fetch from API when token exists", async () => {
      localStorageMock.setItem("tabula_token", "fake-token");
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: mockWorkspaces }),
      });

      const result = await DataService.getWorkspaces();
      expect(result).toEqual(mockWorkspaces);
      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/workspaces"),
        expect.anything(),
      );
    });

    it("should fetch from local storage", async () => {
      localStorageMock.setItem(
        "tabula_workspaces",
        JSON.stringify(mockWorkspaces),
      );

      const result = await DataService.getWorkspaces();
      expect(result).toEqual(mockWorkspaces);
    });

    it("should return empty array if no data", async () => {
      const result = await DataService.getWorkspaces();
      expect(result).toEqual([]);
    });

    it("should handle API errors gracefully", async () => {
      localStorageMock.setItem("tabula_token", "fake-token");
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        statusText: "Internal Server Error",
      });

      // Console error mock
      const consoleSpy = jest.spyOn(console, "error").mockImplementation();

      const result = await DataService.getWorkspaces();
      expect(result).toEqual([]); // Falls back to localStorage which is empty

      expect(consoleSpy).toHaveBeenCalled();
      consoleSpy.mockRestore();
    });
  });

  describe("getStats", () => {
    it("should calculate stats correctly", async () => {
      const workspaces = [
        {
          id: "1",
          name: "Test",
          tabs: [{ id: 1 }],
          resources: [{ id: "r1" }],
          notes: [{ id: "n1" }],
          tasks: [
            { id: "t1", completed: true },
            { id: "t2", completed: false },
          ],
          sections: [{ resources: [{ id: "sr1" }] }],
        },
      ];

      localStorageMock.setItem("tabula_workspaces", JSON.stringify(workspaces));

      const stats = await DataService.getStats();
      expect(stats.totalWorkspaces).toBe(1);
      expect(stats.totalTabs).toBe(1);
      expect(stats.totalResources).toBe(2); // 1 direct + 1 in section
      expect(stats.totalNotes).toBe(1);
      expect(stats.totalTasks).toBe(2);
      expect(stats.completedTasks).toBe(1);
    });
  });

  describe("exportWorkspaces", () => {
    const mockWorkspaces = [
      {
        id: "1",
        name: 'Test "Quote"',
        description: "Desc",
        tabs: [],
        tasks: [],
      },
    ];

    it("should export as JSON", async () => {
      localStorageMock.setItem(
        "tabula_workspaces",
        JSON.stringify(mockWorkspaces),
      );
      const result = await DataService.exportWorkspaces("json");
      expect(JSON.parse(result)).toEqual(mockWorkspaces);
    });

    it("should export as CSV with complex data", async () => {
      const complexWorkspaces = [
        {
          id: "1",
          name: 'Test "Quote"',
          description: 'Desc "Quote"',
          tabs: [{ id: 1 }],
          resources: [{ id: "r1" }],
          sections: [{ resources: [{ id: "sr1" }] }],
          tasks: [{ id: "t1", completed: true }],
        },
      ];
      localStorageMock.setItem(
        "tabula_workspaces",
        JSON.stringify(complexWorkspaces),
      );
      const result = await DataService.exportWorkspaces("csv");

      expect(result).toContain('"Test ""Quote""","Desc ""Quote""",1,2,0,1,1');
    });
  });

  describe("downloadFile", () => {
    beforeEach(() => {
      // Mock URL
      global.URL.createObjectURL = jest.fn().mockReturnValue("blob:url");
      global.URL.revokeObjectURL = jest.fn();
      // Mock Blob
      global.Blob = jest.fn().mockImplementation((content, options) => ({
        content,
        options,
      })) as any;
    });

    it("should create a link and click it", () => {
      const appendSpy = jest
        .spyOn(document.body, "appendChild")
        .mockImplementation((node) => node);
      const removeSpy = jest
        .spyOn(document.body, "removeChild")
        .mockImplementation((node) => node);

      const link = document.createElement("a");
      const clickSpy = jest.spyOn(link, "click").mockImplementation();
      jest.spyOn(document, "createElement").mockReturnValue(link);

      DataService.downloadFile("content", "test.txt", "text/plain");

      expect(link.href).toBe("blob:url");
      expect(link.download).toBe("test.txt");
      expect(appendSpy).toHaveBeenCalled();
      expect(clickSpy).toHaveBeenCalled();
      expect(removeSpy).toHaveBeenCalled();
      expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:url");
    });

    it("should warn in non-window context", () => {
      const originalWindow = global.window;
      // @ts-expect-error Mocking window
      delete global.window;
      const consoleSpy = jest.spyOn(console, "warn").mockImplementation();

      DataService.downloadFile("c", "f", "m");

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining("Cannot download file in server context"),
      );

      global.window = originalWindow;
      consoleSpy.mockRestore();
    });
  });

  describe("seedDemoData", () => {
    it("should seed data and dispatch event", () => {
      const dispatchSpy = jest.spyOn(window, "dispatchEvent");

      DataService.seedDemoData();

      expect(localStorageMock.setItem).toHaveBeenCalledWith(
        "tabula_workspaces",
        expect.any(String),
      );
      expect(dispatchSpy).toHaveBeenCalledWith(expect.any(Event));
      expect(dispatchSpy.mock.calls[0][0].type).toBe("storage");
    });

    it("should do nothing in non-window context", () => {
      const originalWindow = global.window;
      // @ts-expect-error Mocking window
      delete global.window;

      // Should not throw
      DataService.seedDemoData();

      global.window = originalWindow;
    });
  });

  describe("edge cases", () => {
    it("should handle chrome storage error", async () => {
      global.chrome = {
        storage: {
          local: {
            get: jest.fn().mockRejectedValue(new Error("Storage error")),
          },
        },
      } as any;
      const consoleSpy = jest.spyOn(console, "error").mockImplementation();

      const result = await DataService.getWorkspaces();
      expect(result).toEqual([]);
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining("Failed to load from chrome.storage"),
        expect.any(Error),
      );

      consoleSpy.mockRestore();
    });

    it("should handle API fetch catch block", async () => {
      localStorageMock.setItem("tabula_token", "fake-token");
      (global.fetch as jest.Mock).mockRejectedValue(new Error("Network error"));
      const consoleSpy = jest.spyOn(console, "error").mockImplementation();

      const result = await DataService.getWorkspaces();
      expect(result).toEqual([]);
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining("Failed to load from API"),
        expect.any(Error),
      );

      consoleSpy.mockRestore();
    });

    it("should handle localStorage parse error", async () => {
      localStorageMock.setItem("tabula_workspaces", "invalid json");
      const consoleSpy = jest.spyOn(console, "error").mockImplementation();

      const result = await DataService.getWorkspaces();
      expect(result).toEqual([]);
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining("Failed to parse localStorage data"),
        expect.any(Error),
      );

      consoleSpy.mockRestore();
    });

    it("should handle getWorkspace not found", async () => {
      localStorageMock.setItem("tabula_workspaces", JSON.stringify([]));
      const result = await DataService.getWorkspace("non-existent");
      expect(result).toBeNull();
    });

    it("should handle getWorkspace found", async () => {
      const mockWorkspaces = [{ id: "1", name: "Test" }];
      localStorageMock.setItem(
        "tabula_workspaces",
        JSON.stringify(mockWorkspaces),
      );
      const result = await DataService.getWorkspace("1");
      expect(result).toEqual(mockWorkspaces[0]);
    });

    it("should handle missing properties in getStats", async () => {
      const workspaces = [{ id: "1", name: "Test" }]; // No tabs, resources, etc.
      localStorageMock.setItem("tabula_workspaces", JSON.stringify(workspaces));

      const stats = await DataService.getStats();
      expect(stats.totalTabs).toBe(0);
      expect(stats.totalResources).toBe(0);
    });

    it("should handle missing sections in getStats", async () => {
      const workspaces = [{ id: "1", name: "Test", sections: undefined }];
      localStorageMock.setItem("tabula_workspaces", JSON.stringify(workspaces));

      const stats = await DataService.getStats();
      expect(stats.totalResources).toBe(0);
    });

    it("should handle missing description in exportWorkspaces (CSV)", async () => {
      const workspaces = [{ id: "1", name: "Test", description: undefined }];
      localStorageMock.setItem("tabula_workspaces", JSON.stringify(workspaces));

      const result = await DataService.exportWorkspaces("csv");
      expect(result).toContain('"Test","",0,0,0,0,0');
    });

    it("should handle getDataSourceInfo in non-window context", () => {
      const originalWindow = global.window;
      // @ts-expect-error Mocking window
      delete global.window;

      const info = DataService.getDataSourceInfo();
      expect(info.type).toBe("none");
      expect(info.available).toBe(false);

      global.window = originalWindow;
    });

    it("should handle localStorage access error in getDataSourceInfo", () => {
      // Mock localStorage.getItem to throw for the data check but not for the token check
      const originalGetItem = localStorageMock.getItem;
      localStorageMock.getItem = jest.fn().mockImplementation((key) => {
        if (key === "tabula_token") return null;
        throw new Error("Access denied");
      });
      const consoleSpy = jest.spyOn(console, "warn").mockImplementation();

      const info = DataService.getDataSourceInfo();
      // It should fall through to 'none' because localStorage check failed
      expect(info.type).toBe("none");
      expect(consoleSpy).toHaveBeenCalledWith(
        "localStorage not available:",
        expect.any(Error),
      );

      localStorageMock.getItem = originalGetItem;
      consoleSpy.mockRestore();
    });
  });
});
