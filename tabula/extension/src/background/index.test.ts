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
declare let require: any;

// Mock dependencies
jest.mock("../services/storage");
jest.mock("../services/tabs");
jest.mock("../services/sync", () => ({
  SyncService: {
    processQueue: jest.fn().mockResolvedValue(undefined),
  },
}));
jest.mock("../services/windowOwnership", () => ({
  clearWindowOwnership: jest.fn().mockResolvedValue(undefined),
  clearAllWindowOwnership: jest.fn().mockResolvedValue(undefined),
}));

// Mock chrome API
const mockChrome = {
  runtime: {
    onInstalled: { addListener: jest.fn() },
    onStartup: { addListener: jest.fn() },
    onMessage: { addListener: jest.fn() },
    onMessageExternal: { addListener: jest.fn() },
    getURL: jest.fn((path: string) => `chrome-extension://test-id/${path}`),
    getManifest: jest.fn(() => ({ version: "0.1.0" })),
  },
  tabs: {
    onUpdated: { addListener: jest.fn() },
    onCreated: { addListener: jest.fn() },
    onRemoved: { addListener: jest.fn() },
    create: jest.fn(),
    get: jest.fn(),
    query: jest.fn().mockResolvedValue([]),
  },
  windows: {
    onRemoved: { addListener: jest.fn() },
  },
  alarms: {
    create: jest.fn(),
    onAlarm: { addListener: jest.fn() },
  },
  action: {
    onClicked: { addListener: jest.fn() },
  },
  storage: {
    local: {
      remove: jest.fn().mockResolvedValue(undefined),
    },
  },
};
(globalThis as any).chrome = mockChrome;

describe("Background Script", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.resetModules();
    jest.spyOn(console, "log").mockImplementation(() => {});
    jest.spyOn(console, "error").mockImplementation(() => {});
  });

  it("should initialize extension on install", async () => {
    // Setup manual trigger for onInstalled
    let installCallback: any;
    mockChrome.runtime.onInstalled.addListener.mockImplementation((cb: any) => {
      installCallback = cb;
    });

    require("./index");

    // Trigger install
    const { StorageService } = require("../services/storage");
    (StorageService.getSettings as jest.Mock).mockResolvedValue(null);
    (StorageService.saveSettings as jest.Mock).mockResolvedValue(undefined);

    await installCallback({ reason: "install" });

    expect(console.log).toHaveBeenCalledWith("Tabula extension installed"); // Assuming console.log is mocked or we check side effects
    expect(StorageService.getSettings).toHaveBeenCalled();
    expect(StorageService.saveSettings).toHaveBeenCalled();
    expect(chrome.tabs.create).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "dashboard.html",
        pinned: true,
        active: true,
      }),
    );
  });

  it("should handle extension update", async () => {
    let installCallback: any;
    mockChrome.runtime.onInstalled.addListener.mockImplementation((cb: any) => {
      installCallback = cb;
    });

    // Re-require to register listeners
    jest.isolateModules(() => {
      require("./index");
    });

    await installCallback({ reason: "update" });

    expect(console.log).toHaveBeenCalledWith("Tabula extension updated");
  });

  it("runs an auto-suspend scan on the autoSuspendCheck alarm", async () => {
    let alarmCallback: any;
    mockChrome.alarms.onAlarm.addListener.mockImplementation((cb: any) => {
      alarmCallback = cb;
    });

    let StorageServiceMock: any;
    let TabServiceMock: any;
    jest.isolateModules(() => {
      require("./index");
      StorageServiceMock = require("../services/storage").StorageService;
      TabServiceMock = require("../services/tabs").TabService;
    });

    (StorageServiceMock.getSettings as jest.Mock).mockResolvedValue({
      autoSuspend: true,
      suspendAfterMinutes: 30,
    });
    (chrome.tabs.query as jest.Mock).mockResolvedValue([
      {
        id: 1,
        active: false,
        pinned: false,
        discarded: false,
        lastAccessed: 0,
      },
    ]);
    (TabServiceMock.suspendTab as jest.Mock).mockResolvedValue(undefined);

    await alarmCallback({ name: "autoSuspendCheck" });
    await new Promise((r) => {
      setTimeout(r, 0);
    });

    expect(TabServiceMock.suspendTab).toHaveBeenCalledWith(1);
  });

  it("does NOT suspend when auto-suspend is disabled", async () => {
    let alarmCallback: any;
    mockChrome.alarms.onAlarm.addListener.mockImplementation((cb: any) => {
      alarmCallback = cb;
    });

    let StorageServiceMock: any;
    let TabServiceMock: any;
    jest.isolateModules(() => {
      require("./index");
      StorageServiceMock = require("../services/storage").StorageService;
      TabServiceMock = require("../services/tabs").TabService;
    });

    (StorageServiceMock.getSettings as jest.Mock).mockResolvedValue({
      autoSuspend: false,
    });

    await alarmCallback({ name: "autoSuspendCheck" });
    await new Promise((r) => {
      setTimeout(r, 0);
    });

    expect(TabServiceMock.suspendTab).not.toHaveBeenCalled();
  });

  it("does NOT suspend a recently-accessed tab", async () => {
    let alarmCallback: any;
    mockChrome.alarms.onAlarm.addListener.mockImplementation((cb: any) => {
      alarmCallback = cb;
    });

    let StorageServiceMock: any;
    let TabServiceMock: any;
    jest.isolateModules(() => {
      require("./index");
      StorageServiceMock = require("../services/storage").StorageService;
      TabServiceMock = require("../services/tabs").TabService;
    });

    (StorageServiceMock.getSettings as jest.Mock).mockResolvedValue({
      autoSuspend: true,
      suspendAfterMinutes: 30,
    });
    (chrome.tabs.query as jest.Mock).mockResolvedValue([
      {
        id: 1,
        active: false,
        pinned: false,
        discarded: false,
        lastAccessed: Date.now(),
      },
    ]);

    await alarmCallback({ name: "autoSuspendCheck" });
    await new Promise((r) => {
      setTimeout(r, 0);
    });

    expect(TabServiceMock.suspendTab).not.toHaveBeenCalled();
  });

  it("registers the syncQueueFlush and autoSuspendCheck alarms", () => {
    jest.isolateModules(() => {
      require("./index");
    });
    expect(mockChrome.alarms.create).toHaveBeenCalledWith("syncQueueFlush", {
      periodInMinutes: 5,
    });
    expect(mockChrome.alarms.create).toHaveBeenCalledWith("autoSuspendCheck", {
      periodInMinutes: 1,
    });
  });

  it("migrates a legacy on-disk token away on install", async () => {
    let installCallback: any;
    mockChrome.runtime.onInstalled.addListener.mockImplementation((cb: any) => {
      installCallback = cb;
    });

    let StorageServiceMock: any;
    jest.isolateModules(() => {
      require("./index");
      StorageServiceMock = require("../services/storage").StorageService;
    });
    (StorageServiceMock.getSettings as jest.Mock).mockResolvedValue({});

    await installCallback({ reason: "update" });

    expect(mockChrome.storage.local.remove).toHaveBeenCalledWith(
      "tabula_access_token",
    );
  });

  it("clears window ownership when a window closes", async () => {
    let removedCallback: any;
    mockChrome.windows.onRemoved.addListener.mockImplementation((cb: any) => {
      removedCallback = cb;
    });

    let ownershipMock: any;
    jest.isolateModules(() => {
      require("./index");
      ownershipMock = require("../services/windowOwnership");
    });

    await removedCallback(42);

    expect(ownershipMock.clearWindowOwnership).toHaveBeenCalledWith(42);
  });

  it("wipes ownership records and flushes the queue on browser startup", async () => {
    let startupCallback: any;
    mockChrome.runtime.onStartup.addListener.mockImplementation((cb: any) => {
      startupCallback = cb;
    });

    let ownershipMock: any;
    let syncMock: any;
    jest.isolateModules(() => {
      require("./index");
      ownershipMock = require("../services/windowOwnership");
      syncMock = require("../services/sync").SyncService;
    });

    await startupCallback();

    expect(ownershipMock.clearAllWindowOwnership).toHaveBeenCalled();
    expect(syncMock.processQueue).toHaveBeenCalled();
  });

  it("flushes the sync queue on the syncQueueFlush alarm", async () => {
    let alarmCallback: any;
    mockChrome.alarms.onAlarm.addListener.mockImplementation((cb: any) => {
      alarmCallback = cb;
    });

    let syncMock: any;
    jest.isolateModules(() => {
      require("./index");
      syncMock = require("../services/sync").SyncService;
    });

    await alarmCallback({ name: "syncQueueFlush" });

    expect(syncMock.processQueue).toHaveBeenCalled();
    expect(mockChrome.alarms.create).toHaveBeenCalledWith("syncQueueFlush", {
      periodInMinutes: 5,
    });
  });

  it("should handle onMessage events", async () => {
    let messageCallback: any;
    mockChrome.runtime.onMessage.addListener.mockImplementation((cb: any) => {
      messageCallback = cb;
    });

    let TabServiceMock: any;

    jest.isolateModules(() => {
      require("./index");
      TabServiceMock = require("../services/tabs").TabService;
    });

    (TabServiceMock.getMemoryStats as jest.Mock).mockResolvedValue({
      total: 200,
    });
    (TabServiceMock.suspendInactiveTabs as jest.Mock).mockResolvedValue(
      undefined,
    );

    // Test GET_STATS
    const sendResponseStats = jest.fn();
    const resultStats = messageCallback(
      { type: "GET_STATS" },
      {},
      sendResponseStats,
    );
    expect(resultStats).toBe(true); // Should return true for async

    expect(TabServiceMock.getMemoryStats).toHaveBeenCalled();

    // Test SUSPEND_INACTIVE
    const sendResponseSuspend = jest.fn();
    const resultSuspend = messageCallback(
      { type: "SUSPEND_INACTIVE" },
      {},
      sendResponseSuspend,
    );
    expect(resultSuspend).toBe(true);
    expect(TabServiceMock.suspendInactiveTabs).toHaveBeenCalled();

    // Test unknown message
    const resultUnknown = messageCallback({ type: "UNKNOWN" }, {}, jest.fn());
    expect(resultUnknown).toBe(false);
  });
});
