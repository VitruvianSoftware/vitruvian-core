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
 * Unit tests for CollaboratorService (share-by-email).
 */
import { CollaboratorService } from "../../src/services/collaborator.service";
import { NotFoundError } from "../../src/lib/errors";
import { prisma } from "../../src/lib/prisma";

jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    user: { findUnique: jest.fn() },
    spaceCollaborator: {
      upsert: jest.fn(),
      findMany: jest.fn(),
      findUnique: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
  },
}));

const mockUser = prisma.user as unknown as Record<string, jest.Mock>;
const mockCollab = prisma.spaceCollaborator as unknown as Record<
  string,
  jest.Mock
>;

const WS = "ws_1";
const INVITER = "00000000-0000-0000-0000-00000inviter";

describe("CollaboratorService", () => {
  beforeEach(() => jest.clearAllMocks());

  describe("shareByEmail", () => {
    it("lowercases the email and marks the grant active + linked when the user exists", async () => {
      mockUser.findUnique.mockResolvedValue({ id: "user-9" });
      mockCollab.upsert.mockResolvedValue({ id: "sc_1" });

      await CollaboratorService.shareByEmail(
        WS,
        INVITER,
        "Person@X.COM",
        "edit",
      );

      const args = mockCollab.upsert.mock.calls[0][0];
      expect(args.where.workspaceId_inviteeEmail.inviteeEmail).toBe(
        "person@x.com",
      );
      expect(args.create.status).toBe("active");
      expect(args.create.userId).toBe("user-9");
      expect(args.create.role).toBe("edit");
      expect(args.update.role).toBe("edit");
    });

    it("marks the grant pending with a null userId when the email is unregistered", async () => {
      mockUser.findUnique.mockResolvedValue(null);
      mockCollab.upsert.mockResolvedValue({ id: "sc_2" });

      await CollaboratorService.shareByEmail(
        WS,
        INVITER,
        "ghost@x.com",
        "view",
      );

      const args = mockCollab.upsert.mock.calls[0][0];
      expect(args.create.status).toBe("pending");
      expect(args.create.userId).toBeNull();
    });
  });

  describe("listCollaborators", () => {
    it("queries grants for the space without exposing the userId column", async () => {
      mockCollab.findMany.mockResolvedValue([]);
      await CollaboratorService.listCollaborators(WS);
      const args = mockCollab.findMany.mock.calls[0][0];
      expect(args.where).toEqual({ workspaceId: WS });
      expect(args.select.userId).toBeUndefined();
    });
  });

  describe("setRole", () => {
    it("throws NotFoundError when the collaborator is not in this space", async () => {
      mockCollab.updateMany.mockResolvedValue({ count: 0 });
      await expect(
        CollaboratorService.setRole(WS, "sc_x", "edit"),
      ).rejects.toBeInstanceOf(NotFoundError);
    });

    it("updates the role scoped to (id, workspaceId)", async () => {
      mockCollab.updateMany.mockResolvedValue({ count: 1 });
      mockCollab.findUnique.mockResolvedValue({ id: "sc_1", role: "edit" });
      await CollaboratorService.setRole(WS, "sc_1", "edit");
      expect(mockCollab.updateMany.mock.calls[0][0].where).toEqual({
        id: "sc_1",
        workspaceId: WS,
      });
    });
  });

  describe("revoke", () => {
    it("throws NotFoundError when nothing was deleted", async () => {
      mockCollab.deleteMany.mockResolvedValue({ count: 0 });
      await expect(
        CollaboratorService.revoke(WS, "sc_x"),
      ).rejects.toBeInstanceOf(NotFoundError);
    });

    it("deletes the grant scoped to (id, workspaceId)", async () => {
      mockCollab.deleteMany.mockResolvedValue({ count: 1 });
      await CollaboratorService.revoke(WS, "sc_1");
      expect(mockCollab.deleteMany.mock.calls[0][0].where).toEqual({
        id: "sc_1",
        workspaceId: WS,
      });
    });
  });
});
