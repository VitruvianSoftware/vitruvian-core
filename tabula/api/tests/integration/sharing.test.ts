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
 * Integration tests for the sharing routes: authorization gates (owner-only
 * management; 403 vs 404 masking), status codes, and response shapes. The
 * services are unit-tested separately, so they are mocked here.
 */
import Fastify, { FastifyInstance } from "fastify";
import fastifyJwt from "@fastify/jwt";
import { sharingRoutes } from "../../src/routes/sharing.routes";
import { errorHandler } from "../../src/lib/errorHandler";
import { PermissionService } from "../../src/services/permission.service";
import { CollaboratorService } from "../../src/services/collaborator.service";
import { ShareService } from "../../src/services/share.service";
import { ForbiddenError, NotFoundError } from "../../src/lib/errors";

jest.mock("../../src/services/permission.service");
jest.mock("../../src/services/collaborator.service");
jest.mock("../../src/services/share.service");

const mockPermission = jest.mocked(PermissionService);
const mockCollab = jest.mocked(CollaboratorService);
const mockShare = jest.mocked(ShareService);

describe("Sharing API Endpoints", () => {
  let app: FastifyInstance;
  let authToken: string;
  const WS = "ws_1";

  beforeAll(async () => {
    app = Fastify();
    await app.register(fastifyJwt, { secret: "test-jwt-secret-sharing" });
    app.setErrorHandler(errorHandler);
    await app.register(sharingRoutes, { prefix: "/api/v1" });
    await app.ready();
    authToken = `Bearer ${app.jwt.sign({ id: "owner-1", email: "owner@x.com", tier: "free" })}`;
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockPermission.requireRole.mockResolvedValue("owner");
  });

  const inject = (
    method: "GET" | "POST" | "PATCH" | "DELETE",
    url: string,
    payload?: unknown,
  ) =>
    app.inject({
      method,
      url,
      headers: { authorization: authToken, "content-type": "application/json" },
      payload: payload as object,
    });

  describe("GET /workspaces/shared-with-me", () => {
    it("returns the spaces shared with the caller", async () => {
      mockPermission.listSpacesSharedWith.mockResolvedValue([
        { workspaceId: WS, role: "view", name: "Alpha" },
      ]);
      const res = await inject("GET", "/api/v1/workspaces/shared-with-me");
      expect(res.statusCode).toBe(200);
      expect(JSON.parse(res.payload).data).toHaveLength(1);
    });
  });

  describe("collaborators", () => {
    it("lists the roster for the owner", async () => {
      mockCollab.listCollaborators.mockResolvedValue([]);
      const res = await inject("GET", `/api/v1/workspaces/${WS}/collaborators`);
      expect(res.statusCode).toBe(200);
      expect(mockPermission.requireRole).toHaveBeenCalledWith(
        "owner-1",
        WS,
        "owner",
      );
    });

    it("returns 403 for a non-owner collaborator", async () => {
      mockPermission.requireRole.mockRejectedValue(new ForbiddenError());
      const res = await inject("GET", `/api/v1/workspaces/${WS}/collaborators`);
      expect(res.statusCode).toBe(403);
    });

    it("returns 404 for a stranger (existence-masked)", async () => {
      mockPermission.requireRole.mockRejectedValue(new NotFoundError());
      const res = await inject("GET", `/api/v1/workspaces/${WS}/collaborators`);
      expect(res.statusCode).toBe(404);
    });

    it("shares by email (201) and never reflects active/pending status", async () => {
      mockCollab.shareByEmail.mockResolvedValue({
        id: "sc_1",
        inviteeEmail: "p@x.com",
        role: "edit",
        status: "pending",
        userId: null,
        workspaceId: WS,
        invitedByUserId: "owner-1",
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      const res = await inject(
        "POST",
        `/api/v1/workspaces/${WS}/collaborators`,
        { email: "p@x.com", role: "edit" },
      );
      expect(res.statusCode).toBe(201);
      const body = JSON.parse(res.payload).data;
      expect(body).toEqual({ id: "sc_1", email: "p@x.com", role: "edit" });
      expect(body.status).toBeUndefined();
    });

    it("rejects an invalid email with 400", async () => {
      const res = await inject(
        "POST",
        `/api/v1/workspaces/${WS}/collaborators`,
        { email: "not-an-email", role: "view" },
      );
      expect(res.statusCode).toBe(400);
      expect(mockCollab.shareByEmail).not.toHaveBeenCalled();
    });

    it("revokes a collaborator (204)", async () => {
      mockCollab.revoke.mockResolvedValue(undefined);
      const res = await inject(
        "DELETE",
        `/api/v1/workspaces/${WS}/collaborators/sc_1`,
      );
      expect(res.statusCode).toBe(204);
      expect(mockCollab.revoke).toHaveBeenCalledWith(WS, "sc_1");
    });
  });

  describe("share links", () => {
    it("mints a link (201) and returns the token once", async () => {
      mockShare.createLink.mockResolvedValue({
        id: "sl_1",
        role: "view",
        label: null,
        expiresAt: null,
        token: "a".repeat(64),
      });
      const res = await inject("POST", `/api/v1/workspaces/${WS}/share-links`, {
        role: "view",
      });
      expect(res.statusCode).toBe(201);
      expect(JSON.parse(res.payload).data.token).toBe("a".repeat(64));
    });

    it("revokes a link (204)", async () => {
      mockShare.revokeLink.mockResolvedValue(undefined);
      const res = await inject(
        "DELETE",
        `/api/v1/workspaces/${WS}/share-links/sl_1`,
      );
      expect(res.statusCode).toBe(204);
    });

    it("previews a link via token in the body (200)", async () => {
      mockShare.getLinkInfo.mockResolvedValue({
        workspaceId: WS,
        workspaceName: "Alpha",
        role: "view",
      });
      const res = await inject("POST", "/api/v1/share-links/info", {
        token: "tok",
      });
      expect(res.statusCode).toBe(200);
      expect(JSON.parse(res.payload).data.workspaceName).toBe("Alpha");
    });

    it("returns 404 for an invalid/revoked/expired token", async () => {
      mockShare.getLinkInfo.mockRejectedValue(new NotFoundError());
      const res = await inject("POST", "/api/v1/share-links/info", {
        token: "nope",
      });
      expect(res.statusCode).toBe(404);
    });

    it("accepts a link and returns the effective role (200)", async () => {
      mockShare.acceptLink.mockResolvedValue({
        workspaceId: WS,
        workspaceName: "Alpha",
        role: "edit",
      });
      const res = await inject("POST", "/api/v1/share-links/accept", {
        token: "tok",
      });
      expect(res.statusCode).toBe(200);
      expect(JSON.parse(res.payload).data.role).toBe("edit");
      expect(mockShare.acceptLink).toHaveBeenCalledWith(
        "tok",
        "owner-1",
        "owner@x.com",
      );
    });
  });
});
