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
 * Unit tests for PermissionService (the sharing authorization chokepoint).
 */
import { PermissionService } from "../../src/services/permission.service";
import { ForbiddenError, NotFoundError } from "../../src/lib/errors";
import { prisma } from "../../src/lib/prisma";

jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    workspace: {
      findUnique: jest.fn(),
    },
    spaceCollaborator: {
      findFirst: jest.fn(),
      findMany: jest.fn(),
    },
  },
}));

const mockWorkspace = prisma.workspace.findUnique as jest.Mock;
const mockCollabFirst = prisma.spaceCollaborator.findFirst as jest.Mock;
const mockCollabMany = prisma.spaceCollaborator.findMany as jest.Mock;

const OWNER = "00000000-0000-0000-0000-0000000owner";
const COLLAB = "00000000-0000-0000-0000-000000collab";
const STRANGER = "00000000-0000-0000-0000-00000strange";
const WS = "ws_abc";

describe("PermissionService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("resolveAccess", () => {
    it("returns owner when the workspace belongs to the caller (without touching collaborators)", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      const role = await PermissionService.resolveAccess(OWNER, WS);
      expect(role).toBe("owner");
      expect(mockCollabFirst).not.toHaveBeenCalled();
    });

    it("returns the collaborator's role when an active edit grant matches", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      mockCollabFirst.mockResolvedValue({ role: "edit" });
      expect(await PermissionService.resolveAccess(COLLAB, WS)).toBe("edit");
      expect(mockCollabFirst).toHaveBeenCalledWith({
        where: { workspaceId: WS, userId: COLLAB, status: "active" },
        select: { role: true },
      });
    });

    it("returns view for an active view grant", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      mockCollabFirst.mockResolvedValue({ role: "view" });
      expect(await PermissionService.resolveAccess(COLLAB, WS)).toBe("view");
    });

    it("returns null when the workspace does not exist", async () => {
      mockWorkspace.mockResolvedValue(null);
      expect(await PermissionService.resolveAccess(OWNER, WS)).toBeNull();
      expect(mockCollabFirst).not.toHaveBeenCalled();
    });

    it("returns null when the caller has no grant", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      mockCollabFirst.mockResolvedValue(null);
      expect(await PermissionService.resolveAccess(STRANGER, WS)).toBeNull();
    });
  });

  describe("requireRole", () => {
    it("throws NotFoundError (existence-masked) when the caller has no access", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      mockCollabFirst.mockResolvedValue(null);
      await expect(
        PermissionService.requireRole(STRANGER, WS, "view"),
      ).rejects.toBeInstanceOf(NotFoundError);
    });

    it("throws ForbiddenError when the caller can see it but the role is too low", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      mockCollabFirst.mockResolvedValue({ role: "view" });
      await expect(
        PermissionService.requireRole(COLLAB, WS, "edit"),
      ).rejects.toBeInstanceOf(ForbiddenError);
    });

    it("resolves with the effective role when it meets the minimum", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      mockCollabFirst.mockResolvedValue({ role: "edit" });
      expect(await PermissionService.requireRole(COLLAB, WS, "view")).toBe(
        "edit",
      );
    });

    it("lets the owner pass any minimum (OWNER > EDIT > VIEW)", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      expect(await PermissionService.requireRole(OWNER, WS, "edit")).toBe(
        "owner",
      );
      expect(await PermissionService.requireRole(OWNER, WS, "owner")).toBe(
        "owner",
      );
    });

    it("rejects an EDIT collaborator from an OWNER-only action", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      mockCollabFirst.mockResolvedValue({ role: "edit" });
      await expect(
        PermissionService.requireRole(COLLAB, WS, "owner"),
      ).rejects.toBeInstanceOf(ForbiddenError);
    });
  });

  describe("listAccessUserIds", () => {
    it("returns the owner first plus active registered collaborators, de-duplicated", async () => {
      mockWorkspace.mockResolvedValue({ userId: OWNER });
      mockCollabMany.mockResolvedValue([
        { userId: COLLAB },
        { userId: COLLAB }, // duplicate is collapsed
      ]);
      expect(await PermissionService.listAccessUserIds(WS)).toEqual([
        OWNER,
        COLLAB,
      ]);
      expect(mockCollabMany).toHaveBeenCalledWith({
        where: { workspaceId: WS, status: "active", userId: { not: null } },
        select: { userId: true },
      });
    });

    it("returns an empty list when the workspace does not exist", async () => {
      mockWorkspace.mockResolvedValue(null);
      expect(await PermissionService.listAccessUserIds(WS)).toEqual([]);
      expect(mockCollabMany).not.toHaveBeenCalled();
    });
  });

  describe("listSpacesSharedWith", () => {
    it("maps active grants to workspaceId + role + name", async () => {
      mockCollabMany.mockResolvedValue([
        { workspaceId: "ws_1", role: "view", workspace: { name: "Alpha" } },
        { workspaceId: "ws_2", role: "edit", workspace: { name: "Beta" } },
      ]);
      expect(await PermissionService.listSpacesSharedWith(COLLAB)).toEqual([
        { workspaceId: "ws_1", role: "view", name: "Alpha" },
        { workspaceId: "ws_2", role: "edit", name: "Beta" },
      ]);
    });
  });
});
