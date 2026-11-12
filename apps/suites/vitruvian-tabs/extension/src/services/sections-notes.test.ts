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
 * Unit tests for Sections and Notes functionality in WorkspaceService
 */

import { WorkspaceService } from "./workspace";
import { StorageService } from "./storage";
import type { Workspace } from "../types";

jest.mock("../services/storage");
jest.mock("../services/tabs");
jest.mock("./auth", () => ({
  AuthService: {
    getToken: jest.fn().mockResolvedValue(null),
  },
}));
jest.mock("./api", () => ({
  ApiService: {
    saveWorkspace: jest.fn(),
    deleteWorkspace: jest.fn(),
    saveSpaceGroup: jest.fn(),
    deleteSpaceGroup: jest.fn(),
  },
}));

describe("WorkspaceService - Sections & Notes", () => {
  const mockWorkspace: Workspace = {
    id: "ws1",
    name: "Test",
    tabs: [],
    resources: [],
    sections: [],
    notes: [],
    tasks: [],
    position: 0,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("Sections", () => {
    it("should add a section", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        { ...mockWorkspace },
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.addSection("ws1", "Docs");

      expect(result.sections).toHaveLength(1);
      expect(result.sections[0].title).toBe("Docs");
      expect(result.sections[0].resources).toEqual([]);
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });

    it("should delete a section", async () => {
      const workspaceWithSection = {
        ...mockWorkspace,
        sections: [{ id: "sec1", title: "Docs", resources: [] }],
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspaceWithSection,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.deleteSection("ws1", "sec1");

      expect(result.sections).toHaveLength(0);
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });

    it("should add resource to section", async () => {
      const workspaceWithSection = {
        ...mockWorkspace,
        sections: [{ id: "sec1", title: "Docs", resources: [] }],
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspaceWithSection,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.addResourceToSection(
        "ws1",
        "sec1",
        {
          title: "Google",
          url: "https://google.com",
        },
      );

      expect(result.sections[0].resources).toHaveLength(1);
      expect(result.sections[0].resources[0].title).toBe("Google");
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });
  });

  describe("Notes", () => {
    it("should add a note", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        { ...mockWorkspace },
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.addNote("ws1", {
        title: "Meeting",
        content: "Notes content",
      });

      expect(result.notes).toHaveLength(1);
      expect(result.notes[0].title).toBe("Meeting");
      expect(result.notes[0].content).toBe("Notes content");
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });

    it("should update a note", async () => {
      const workspaceWithNote = {
        ...mockWorkspace,
        notes: [
          {
            id: "note1",
            title: "Meeting",
            content: "Notes content",
            updatedAt: Date.now(),
          },
        ],
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspaceWithNote,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.updateNote("ws1", "note1", {
        content: "Updated content",
      });

      expect(result.notes[0].content).toBe("Updated content");
      expect(result.notes[0].title).toBe("Meeting"); // Unchanged
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });

    it("should delete a note", async () => {
      const workspaceWithNote = {
        ...mockWorkspace,
        notes: [
          {
            id: "note1",
            title: "Meeting",
            content: "Notes content",
            updatedAt: Date.now(),
          },
        ],
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspaceWithNote,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.deleteNote("ws1", "note1");

      expect(result.notes).toHaveLength(0);
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });
  });
});
