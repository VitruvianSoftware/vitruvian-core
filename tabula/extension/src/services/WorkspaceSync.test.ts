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
import { WorkspaceService } from "./workspace";
import { StorageService } from "./storage";
import { ApiService } from "./api";
import { AuthService } from "./auth";
import type { Workspace } from "../types";

jest.mock("./storage");
jest.mock("./api");
jest.mock("./auth");
jest.mock("./sync");

// Mock global chrome
(globalThis as any).chrome = {
  tabs: {
    query: jest.fn().mockResolvedValue([]),
  },
  storage: {
    local: {
      get: jest.fn().mockResolvedValue({}), // No force-remote flag by default
    },
  },
};

describe("WorkspaceSync Conflict Resolution", () => {
  const now = Date.now();
  const slightlyLater = now + 1000;
  const slightlyEarlier = now - 1000;

  beforeEach(() => {
    jest.clearAllMocks();
    (AuthService.getToken as jest.Mock).mockResolvedValue("fake-token");
  });

  it("should prefer local workspace if local is newer than remote", async () => {
    const localWs: Workspace = {
      id: "ws1",
      name: "Local Version",
      updatedAt: slightlyLater,
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: now,
    };

    const remoteWs: Workspace = {
      ...localWs,
      name: "Remote Version",
      updatedAt: slightlyEarlier,
    };

    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([localWs]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([remoteWs]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.getAllWorkspaces();
    const ws = result.find((w) => w.id === "ws1");

    expect(ws?.name).toBe("Local Version");
  });

  it("should prefer remote workspace if remote is newer than local", async () => {
    const localWs: Workspace = {
      id: "ws1",
      name: "Local Version",
      updatedAt: slightlyEarlier,
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: now,
    };

    const remoteWs: Workspace = {
      ...localWs,
      name: "Remote Version",
      updatedAt: slightlyLater,
    };

    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([localWs]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([remoteWs]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.getAllWorkspaces();
    const ws = result.find((w) => w.id === "ws1");

    expect(ws?.name).toBe("Remote Version");
  });

  it("should reproduction: stale remote state keeps groupId even if local removed it", async () => {
    // Scenario: User moves workspace out of group locally.
    // Local state has NO groupId and newer timestamp.
    // Remote state has groupId and OLDER timestamp.
    // BUT what if there is clock skew? Or what if timestamps are equal?

    // 1. Setup: Local has NO groupId, Remote HAS groupId.
    // Local updatedAt is +10ms ahead of Remote.
    // This SHOULD pick Local.

    const baseWs: Workspace = {
      id: "ws-bug",
      name: "Buggy Workspace",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: now,
      updatedAt: now,
    };

    const remoteWs: Workspace = {
      ...baseWs,
      groupId: "group-1", // Stale remote has the group
      updatedAt: now,
    };

    const localWs: Workspace = {
      ...baseWs,
      // No groupId (it was deleted)
      updatedAt: now + 50, // Local is newer
    };

    // explicit undefined for test clarity, though absence of key is the reality
    delete (localWs as any).groupId;

    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([localWs]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([remoteWs]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.getAllWorkspaces();
    const ws = result.find((w) => w.id === "ws-bug");

    // We expect local to win (no groupId)
    expect(ws?.groupId).toBeUndefined();

    // IF THIS FAILS, it means conflict resolution isn't working as expected.
  });

  it("should prefer local if timestamps are identical (ambiguity resolution)", async () => {
    // If timestamps are exactly equal, we should prefer local to avoid reverting immediate user actions
    // due to potential sync races or identical clock times.

    const remoteWs: Workspace = {
      id: "ws-tie",
      name: "Workspace",
      groupId: "group-1",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: now,
      updatedAt: now,
    };

    const localWs: Workspace = {
      ...remoteWs,
    };
    delete (localWs as any).groupId; // Local removed it
    localWs.updatedAt = now; // Same timestamp

    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([localWs]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([remoteWs]);

    const result = await WorkspaceService.getAllWorkspaces();
    const ws = result.find((w) => w.id === "ws-tie");

    // We change expectation: LOCAL should win.
    expect(ws?.groupId).toBeUndefined();
  });
});
