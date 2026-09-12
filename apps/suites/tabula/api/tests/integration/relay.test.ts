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
 * Integration tests for the relay routes (#140): the public preview must work
 * WITHOUT auth, and accept must require a logged-in user.
 */
import Fastify, { FastifyInstance } from "fastify";
import fastifyJwt from "@fastify/jwt";
import { relayRoutes } from "../../src/routes/relay.routes";
import { errorHandler } from "../../src/lib/errorHandler";
import { ShareService } from "../../src/services/share.service";
import { NotFoundError } from "../../src/lib/errors";

jest.mock("../../src/services/share.service");
const mockShare = jest.mocked(ShareService);

describe("Relay routes", () => {
  let app: FastifyInstance;
  let authToken: string;

  beforeAll(async () => {
    app = Fastify();
    await app.register(fastifyJwt, { secret: "test-relay-secret" });
    app.setErrorHandler(errorHandler);
    await app.register(relayRoutes, { prefix: "/api/v1" });
    await app.ready();
    authToken = `Bearer ${app.jwt.sign({ id: "user-1", email: "u@x.com", tier: "free" })}`;
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => jest.clearAllMocks());

  describe("GET /share-links/relay/:relayId/info", () => {
    it("returns the preview (name, owner, role) WITHOUT authentication", async () => {
      mockShare.getRelayInfo.mockResolvedValue({
        workspaceId: "ws_1",
        workspaceName: "Alpha",
        ownerName: "Jane",
        role: "view",
      });
      const res = await app.inject({
        method: "GET",
        url: "/api/v1/share-links/relay/relay-abc/info",
      });
      expect(res.statusCode).toBe(200);
      const data = JSON.parse(res.payload).data;
      expect(data).toEqual({
        workspaceId: "ws_1",
        workspaceName: "Alpha",
        ownerName: "Jane",
        role: "view",
      });
      expect(mockShare.getRelayInfo).toHaveBeenCalledWith("relay-abc");
    });

    it("404 for an unknown / revoked / expired relay id", async () => {
      mockShare.getRelayInfo.mockRejectedValue(new NotFoundError());
      const res = await app.inject({
        method: "GET",
        url: "/api/v1/share-links/relay/nope/info",
      });
      expect(res.statusCode).toBe(404);
    });
  });

  describe("POST /share-links/relay/:relayId/accept", () => {
    it("401 without a token (login required to redeem)", async () => {
      const res = await app.inject({
        method: "POST",
        url: "/api/v1/share-links/relay/relay-abc/accept",
      });
      expect(res.statusCode).toBe(401);
      expect(mockShare.acceptByRelayId).not.toHaveBeenCalled();
    });

    it("materializes the grant for a logged-in user", async () => {
      mockShare.acceptByRelayId.mockResolvedValue({
        workspaceId: "ws_1",
        workspaceName: "Alpha",
        role: "edit",
      });
      const res = await app.inject({
        method: "POST",
        url: "/api/v1/share-links/relay/relay-abc/accept",
        headers: { authorization: authToken },
      });
      expect(res.statusCode).toBe(200);
      expect(JSON.parse(res.payload).data.role).toBe("edit");
      expect(mockShare.acceptByRelayId).toHaveBeenCalledWith(
        "relay-abc",
        "user-1",
        "u@x.com",
      );
    });
  });
});
