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
 * Unit tests for SpaceGroup service
 */
import { SpaceGroupService } from "../../src/services/spacegroup.service";
import { ConflictError } from "../../src/lib/errors";
import { prisma } from "../../src/lib/prisma";

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    spaceGroup: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    $transaction: jest.fn(),
  },
}));

describe("SpaceGroupService", () => {
  const userId = "user-123";
  const groupId = "sg-456";

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("generateId", () => {
    it("should generate a unique ID with the given prefix", () => {
      const id = SpaceGroupService.generateId("sg");
      expect(id).toMatch(/^sg_[a-z0-9]+_[a-z0-9]+$/);
    });

    it("should generate different IDs on each call", () => {
      const id1 = SpaceGroupService.generateId("sg");
      const id2 = SpaceGroupService.generateId("sg");
      expect(id1).not.toBe(id2);
    });
  });

  describe("getAllSpaceGroups", () => {
    it("should return all space groups for a user", async () => {
      const mockGroups = [
        { id: "sg1", title: "Work", userId, position: 0, collapsed: false },
        { id: "sg2", title: "Personal", userId, position: 1, collapsed: true },
      ];
      (prisma.spaceGroup.findMany as jest.Mock).mockResolvedValue(mockGroups);

      const result = await SpaceGroupService.getAllSpaceGroups(userId);

      expect(result).toEqual(mockGroups);
      expect(prisma.spaceGroup.findMany).toHaveBeenCalledWith({
        where: { userId },
        orderBy: { position: "asc" },
      });
    });

    it("should return empty array when user has no groups", async () => {
      (prisma.spaceGroup.findMany as jest.Mock).mockResolvedValue([]);

      const result = await SpaceGroupService.getAllSpaceGroups(userId);

      expect(result).toEqual([]);
    });
  });

  describe("getSpaceGroupById", () => {
    it("should return a space group by ID", async () => {
      const mockGroup = {
        id: groupId,
        title: "Work",
        userId,
        position: 0,
        collapsed: false,
      };
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(mockGroup);

      const result = await SpaceGroupService.getSpaceGroupById(userId, groupId);

      expect(result).toEqual(mockGroup);
      expect(prisma.spaceGroup.findFirst).toHaveBeenCalledWith({
        where: { id: groupId, userId },
      });
    });

    it("should throw error if space group not found", async () => {
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(null);

      await expect(
        SpaceGroupService.getSpaceGroupById(userId, groupId),
      ).rejects.toThrow("Space group not found");
    });
  });

  describe("createSpaceGroup", () => {
    it("should create a new space group", async () => {
      const input = {
        title: "New Group",
        collapsed: false,
        position: 0,
        color: "#4F46E5",
      };
      const mockGroup = { id: "sg-new", ...input, userId };

      (prisma.spaceGroup.create as jest.Mock).mockResolvedValue(mockGroup);

      const result = await SpaceGroupService.createSpaceGroup(userId, input);

      expect(result).toEqual(mockGroup);
      expect(prisma.spaceGroup.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          id: expect.stringMatching(/^sg_/),
          userId,
          title: input.title,
          collapsed: input.collapsed,
          position: input.position,
          color: input.color,
        }),
      });
    });
  });

  describe("updateSpaceGroup", () => {
    /**
     * Mock transaction client matching what updateSpaceGroup uses: $queryRaw
     * for the FOR UPDATE row lock + version read, then the update delegate.
     */
    const makeTx = () => ({
      $queryRaw: jest.fn().mockResolvedValue([{ version: 0 }]),
      spaceGroup: {
        update: jest.fn().mockResolvedValue({}),
      },
    });

    const useTx = (tx: ReturnType<typeof makeTx>) => {
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );
    };

    it("should update an existing space group", async () => {
      const updatedGroup = {
        id: groupId,
        title: "New Title",
        userId,
        version: 1,
      };
      const tx = makeTx();
      tx.spaceGroup.update.mockResolvedValue(updatedGroup);
      useTx(tx);

      const result = await SpaceGroupService.updateSpaceGroup(userId, groupId, {
        title: "New Title",
      });

      expect(result).toEqual(updatedGroup);
      // Row lock + version read happens before the write
      expect(tx.$queryRaw).toHaveBeenCalled();
      expect(tx.spaceGroup.update).toHaveBeenCalledWith({
        where: { id: groupId },
        data: { title: "New Title", version: 1 },
      });
    });

    it("should throw error if space group not found", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([]);
      useTx(tx);

      await expect(
        SpaceGroupService.updateSpaceGroup(userId, groupId, { title: "Test" }),
      ).rejects.toThrow("Space group not found");
    });

    it("should throw ConflictError when baseVersion is stale", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([{ version: 4 }]);
      useTx(tx);

      await expect(
        SpaceGroupService.updateSpaceGroup(userId, groupId, {
          title: "Test",
          baseVersion: 2,
        }),
      ).rejects.toBeInstanceOf(ConflictError);
      expect(tx.spaceGroup.update).not.toHaveBeenCalled();
    });

    it("should accept updates without baseVersion and increment version (legacy clients)", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([{ version: 4 }]);
      useTx(tx);

      await SpaceGroupService.updateSpaceGroup(userId, groupId, {
        title: "Legacy",
      });

      expect(tx.spaceGroup.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ version: 5 }),
        }),
      );
    });

    it("should only persist provided fields and never the baseVersion flag", async () => {
      const tx = makeTx();
      useTx(tx);

      await SpaceGroupService.updateSpaceGroup(userId, groupId, {
        collapsed: true,
        baseVersion: 0,
      });

      const { data } = tx.spaceGroup.update.mock.calls[0][0];
      expect(Object.keys(data).sort()).toEqual(["collapsed", "version"]);
    });
  });

  describe("deleteSpaceGroup", () => {
    it("should delete a space group", async () => {
      const mockGroup = { id: groupId, title: "Test", userId };
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(mockGroup);
      (prisma.spaceGroup.delete as jest.Mock).mockResolvedValue(mockGroup);

      await SpaceGroupService.deleteSpaceGroup(userId, groupId);

      expect(prisma.spaceGroup.delete).toHaveBeenCalledWith({
        where: { id: groupId },
      });
    });

    it("should throw error if space group not found", async () => {
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(null);

      await expect(
        SpaceGroupService.deleteSpaceGroup(userId, groupId),
      ).rejects.toThrow("Space group not found");
    });
  });
});
