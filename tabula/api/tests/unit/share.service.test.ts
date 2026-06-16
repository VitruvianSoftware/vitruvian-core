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
 * Unit tests for ShareService (share-by-link).
 */
import { ShareService } from "../../src/services/share.service";
import { NotFoundError } from "../../src/lib/errors";
import { hashToken } from "../../src/lib/ids";
import { prisma } from "../../src/lib/prisma";

jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    shareLink: {
      create: jest.fn(),
      findMany: jest.fn(),
      updateMany: jest.fn(),
      findUnique: jest.fn(),
    },
    spaceCollaborator: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
    },
  },
}));

const mockLink = prisma.shareLink as unknown as Record<string, jest.Mock>;
const mockCollab = prisma.spaceCollaborator as unknown as Record<
  string,
  jest.Mock
>;

const WS = "ws_1";
const OWNER = "00000000-0000-0000-0000-0000000owner";
const USER = "00000000-0000-0000-0000-00000000user";

describe("ShareService", () => {
  beforeEach(() => jest.clearAllMocks());

  describe("createLink", () => {
    it("returns the raw token exactly once and stores ONLY its hash", async () => {
      mockLink.create.mockImplementation(async ({ data }) => ({
        id: data.id,
        role: data.role,
        label: data.label,
        expiresAt: data.expiresAt,
      }));

      const result = await ShareService.createLink(WS, OWNER, "edit", "team");

      // A 256-bit token, 64 hex chars.
      expect(result.token).toMatch(/^[a-f0-9]{64}$/);
      const persisted = mockLink.create.mock.calls[0][0].data;
      // The stored hash is the SHA-256 of the token, and is NOT the token.
      expect(persisted.tokenHash).toBe(hashToken(result.token));
      expect(persisted.tokenHash).not.toBe(result.token);
      expect(persisted.role).toBe("edit");
      expect(result.role).toBe("edit");
      // A distinct 256-bit relay id is also returned once; only its hash is stored.
      expect(result.relayId).toMatch(/^[a-f0-9]{64}$/);
      expect(result.relayId).not.toBe(result.token);
      expect(persisted.relayIdHash).toBe(hashToken(result.relayId));
      expect(persisted.relayIdHash).not.toBe(result.relayId);
    });

    it("stores expiresAt as a Date when provided", async () => {
      mockLink.create.mockResolvedValue({ id: "sl_1", role: "view" });
      await ShareService.createLink(
        WS,
        OWNER,
        "view",
        undefined,
        "2027-01-01T00:00:00.000Z",
      );
      const persisted = mockLink.create.mock.calls[0][0].data;
      expect(persisted.expiresAt).toBeInstanceOf(Date);
    });
  });

  describe("listLinks", () => {
    it("requests only non-revoked links", async () => {
      mockLink.findMany.mockResolvedValue([]);
      await ShareService.listLinks(WS);
      expect(mockLink.findMany.mock.calls[0][0].where).toEqual({
        workspaceId: WS,
        revokedAt: null,
      });
    });
  });

  describe("revokeLink", () => {
    it("throws NotFoundError when nothing was revoked", async () => {
      mockLink.updateMany.mockResolvedValue({ count: 0 });
      await expect(ShareService.revokeLink(WS, "sl_x")).rejects.toBeInstanceOf(
        NotFoundError,
      );
    });

    it("soft-revokes by setting revokedAt", async () => {
      mockLink.updateMany.mockResolvedValue({ count: 1 });
      await ShareService.revokeLink(WS, "sl_1");
      expect(
        mockLink.updateMany.mock.calls[0][0].data.revokedAt,
      ).toBeInstanceOf(Date);
    });
  });

  describe("getLinkInfo", () => {
    it("resolves a valid token to its space, role, and owner name", async () => {
      mockLink.findUnique.mockResolvedValue({
        workspaceId: WS,
        role: "view",
        revokedAt: null,
        expiresAt: null,
        workspace: { name: "Alpha", userId: OWNER, user: { name: "Jane" } },
      });
      expect(await ShareService.getLinkInfo("tok")).toEqual({
        workspaceId: WS,
        workspaceName: "Alpha",
        ownerName: "Jane",
        role: "view",
      });
    });

    it("throws for an unknown, revoked, or expired token (indistinguishable)", async () => {
      mockLink.findUnique.mockResolvedValueOnce(null);
      await expect(ShareService.getLinkInfo("nope")).rejects.toBeInstanceOf(
        NotFoundError,
      );

      mockLink.findUnique.mockResolvedValueOnce({
        workspaceId: WS,
        role: "view",
        revokedAt: new Date(),
        expiresAt: null,
        workspace: { name: "Alpha", userId: OWNER },
      });
      await expect(ShareService.getLinkInfo("revoked")).rejects.toBeInstanceOf(
        NotFoundError,
      );

      mockLink.findUnique.mockResolvedValueOnce({
        workspaceId: WS,
        role: "view",
        revokedAt: null,
        expiresAt: new Date("2000-01-01T00:00:00.000Z"),
        workspace: { name: "Alpha", userId: OWNER },
      });
      await expect(ShareService.getLinkInfo("expired")).rejects.toBeInstanceOf(
        NotFoundError,
      );
    });
  });

  describe("acceptLink", () => {
    const validLink = {
      workspaceId: WS,
      role: "view",
      revokedAt: null,
      expiresAt: null,
      createdByUserId: OWNER,
      workspace: { name: "Alpha", userId: OWNER },
    };

    it("is a no-op for the owner accepting their own link", async () => {
      mockLink.findUnique.mockResolvedValue(validLink);
      const result = await ShareService.acceptLink("tok", OWNER, "o@x.com");
      expect(result.role).toBe("owner");
      expect(mockCollab.upsert).not.toHaveBeenCalled();
    });

    it("materializes a collaborator at the link's role for a new user", async () => {
      mockLink.findUnique.mockResolvedValue(validLink);
      mockCollab.findUnique.mockResolvedValue(null);
      mockCollab.upsert.mockResolvedValue({ role: "view" });
      const result = await ShareService.acceptLink("tok", USER, "U@X.com");
      expect(result.role).toBe("view");
      // Email is lowercased into the grant key.
      expect(mockCollab.upsert.mock.calls[0][0].create.inviteeEmail).toBe(
        "u@x.com",
      );
      expect(mockCollab.upsert.mock.calls[0][0].create.role).toBe("view");
    });

    it("never downgrades an existing higher (edit) grant when accepting a view link", async () => {
      mockLink.findUnique.mockResolvedValue(validLink); // view link
      mockCollab.findUnique.mockResolvedValue({ role: "edit" });
      mockCollab.upsert.mockResolvedValue({ role: "edit" });
      await ShareService.acceptLink("tok", USER, "u@x.com");
      expect(mockCollab.upsert.mock.calls[0][0].update.role).toBe("edit");
    });

    it("throws for an invalid token", async () => {
      mockLink.findUnique.mockResolvedValue(null);
      await expect(
        ShareService.acceptLink("nope", USER, "u@x.com"),
      ).rejects.toBeInstanceOf(NotFoundError);
    });
  });

  describe("relay (by relay id)", () => {
    const link = {
      workspaceId: WS,
      role: "edit",
      revokedAt: null,
      expiresAt: null,
      createdByUserId: OWNER,
      workspace: { name: "Alpha", userId: OWNER, user: { name: "Jane" } },
    };

    it("getRelayInfo resolves a relay id (by hash) to space, role, and owner", async () => {
      mockLink.findUnique.mockResolvedValue(link);
      expect(await ShareService.getRelayInfo("relay-id")).toEqual({
        workspaceId: WS,
        workspaceName: "Alpha",
        ownerName: "Jane",
        role: "edit",
      });
      // Resolved by the HASH of the relay id, never the raw value.
      expect(mockLink.findUnique.mock.calls[0][0].where).toEqual({
        relayIdHash: hashToken("relay-id"),
      });
    });

    it("getRelayInfo throws for an unknown / revoked / expired relay id", async () => {
      mockLink.findUnique.mockResolvedValue(null);
      await expect(ShareService.getRelayInfo("nope")).rejects.toBeInstanceOf(
        NotFoundError,
      );
    });

    it("acceptByRelayId materializes a grant for the caller", async () => {
      mockLink.findUnique.mockResolvedValue(link);
      mockCollab.findUnique.mockResolvedValue(null);
      mockCollab.upsert.mockResolvedValue({ role: "edit" });
      const result = await ShareService.acceptByRelayId(
        "relay-id",
        USER,
        "u@x.com",
      );
      expect(result.role).toBe("edit");
      expect(mockCollab.upsert.mock.calls[0][0].create.role).toBe("edit");
    });
  });
});
