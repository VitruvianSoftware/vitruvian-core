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
import { useWorkspaceStore } from "./store";
import { AuthService } from "./auth";

// We need to type the mocked functions for usage in tests
import * as DataModule from "./data";

// Mock dependencies
jest.mock("./data", () => ({
  getWorkspaces: jest.fn(),
  getStats: jest.fn(),
  getDataSourceInfo: jest.fn(),
  seedDemoData: jest.fn(),
  DataService: {
    getWorkspaces: jest.fn(),
    getStats: jest.fn(),
    getDataSourceInfo: jest.fn(),
    seedDemoData: jest.fn(),
  },
}));
const mockedData = DataModule as jest.Mocked<typeof DataModule>;

jest.mock("./auth", () => ({
  AuthService: {
    getUser: jest.fn(),
    getToken: jest.fn(),
    login: jest.fn(),
    logout: jest.fn(),
  },
}));

describe("useWorkspaceStore", () => {
  const initialState = useWorkspaceStore.getState();

  beforeEach(() => {
    useWorkspaceStore.setState(initialState, true); // Reset store
    jest.clearAllMocks();
  });

  describe("fetchWorkspaces", () => {
    it("should fetch workspaces successfully", async () => {
      const mockWorkspaces = [{ id: "1", name: "Test" }];
      const mockDataSource = { type: "api", available: true };

      (mockedData.getWorkspaces as jest.Mock).mockResolvedValue(mockWorkspaces);
      (mockedData.getDataSourceInfo as jest.Mock).mockReturnValue(
        mockDataSource,
      );

      await useWorkspaceStore.getState().fetchWorkspaces();

      const state = useWorkspaceStore.getState();
      expect(state.workspaces).toEqual(mockWorkspaces);
      expect(state.dataSource).toEqual(mockDataSource);
      expect(state.loading).toBe(false);
      expect(state.error).toBeNull();
    });

    it("should handle fetch errors", async () => {
      (mockedData.getWorkspaces as jest.Mock).mockRejectedValue(
        new Error("Fetch failed"),
      );

      await useWorkspaceStore.getState().fetchWorkspaces();

      const state = useWorkspaceStore.getState();
      expect(state.loading).toBe(false);
      expect(state.error).toBe("Fetch failed");
    });
  });

  describe("fetchStats", () => {
    it("should fetch stats successfully", async () => {
      const mockStats = { totalWorkspaces: 5 };
      (mockedData.getStats as jest.Mock).mockResolvedValue(mockStats);

      await useWorkspaceStore.getState().fetchStats();

      const state = useWorkspaceStore.getState();
      expect(state.stats).toEqual(mockStats);
      expect(state.loading).toBe(false);
    });
  });

  describe("refresh", () => {
    it("should refresh both workspaces and stats", async () => {
      const mockWorkspaces = [{ id: "1" }];
      const mockStats = { totalWorkspaces: 1 };

      (mockedData.getWorkspaces as jest.Mock).mockResolvedValue(mockWorkspaces);
      (mockedData.getStats as jest.Mock).mockResolvedValue(mockStats);

      await useWorkspaceStore.getState().refresh();

      const state = useWorkspaceStore.getState();
      expect(state.workspaces).toEqual(mockWorkspaces);
      expect(state.stats).toEqual(mockStats);
    });
  });

  describe("auth actions", () => {
    it("should login successfully", async () => {
      const mockUser = { id: "1", name: "User" };
      (AuthService.login as jest.Mock).mockResolvedValue({
        user: mockUser,
        token: "token",
      });

      // Mock refresh since login calls it
      (mockedData.getWorkspaces as jest.Mock).mockResolvedValue([]);
      (mockedData.getStats as jest.Mock).mockResolvedValue({});

      await useWorkspaceStore.getState().login();

      const state = useWorkspaceStore.getState();
      expect(state.user).toEqual(mockUser);
      expect(state.isAuthenticated).toBe(true);
      expect(state.loading).toBe(false);
    });

    it("should handle login failure", async () => {
      (AuthService.login as jest.Mock).mockRejectedValue(
        new Error("Login failed"),
      );

      await useWorkspaceStore.getState().login();

      const state = useWorkspaceStore.getState();
      expect(state.isAuthenticated).toBeFalsy(); // Depends on initial state but assume false
      expect(state.error).toBe("Login failed");
    });

    it("should logout successfully", () => {
      useWorkspaceStore.setState({
        user: { id: "1" } as any,
        isAuthenticated: true,
      });

      useWorkspaceStore.getState().logout();

      const state = useWorkspaceStore.getState();
      expect(state.user).toBeNull();
      expect(state.isAuthenticated).toBe(false);
      expect(AuthService.logout).toHaveBeenCalled();
    });
  });

  describe("edge cases", () => {
    it("should handle non-Error objects in catch blocks (fetchWorkspaces)", async () => {
      (mockedData.getWorkspaces as jest.Mock).mockRejectedValue("String Error");

      await useWorkspaceStore.getState().fetchWorkspaces();

      const state = useWorkspaceStore.getState();
      expect(state.error).toBe("Failed to load workspaces");
    });

    it("should handle non-Error objects in catch blocks (fetchStats)", async () => {
      (mockedData.getStats as jest.Mock).mockRejectedValue("String Error");

      await useWorkspaceStore.getState().fetchStats();

      const state = useWorkspaceStore.getState();
      expect(state.error).toBe("Failed to load stats");
    });

    it("should handle non-Error objects in catch blocks (login)", async () => {
      (AuthService.login as jest.Mock).mockRejectedValue("String Error");

      await useWorkspaceStore.getState().login();

      const state = useWorkspaceStore.getState();
      expect(state.error).toBe("Login failed");
    });

    it("should seed demo data and refresh", async () => {
      await useWorkspaceStore.getState().seedDemoData();

      expect(mockedData.seedDemoData).toHaveBeenCalled();
      // Ensure refresh (fetchWorkspaces + fetchStats) was called
      expect(mockedData.getWorkspaces).toHaveBeenCalled();
      expect(mockedData.getStats).toHaveBeenCalled();
    });
  });
});
