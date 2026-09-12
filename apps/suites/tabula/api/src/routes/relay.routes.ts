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
 * Relay routes (#140): the public-facing side of a share LINK, addressed by its
 * opaque relay id (the `tabula.com/s/<relayId>` URL handle).
 *
 * Registered as its OWN plugin — deliberately WITHOUT the blanket
 * `authenticateUser` hook that `sharingRoutes` applies — so the preview is
 * reachable by a logged-OUT stranger (the relay landing's "you've been invited
 * to <Space>" state for someone who has neither the extension nor an account).
 * The relay id is 256 bits and resolved by SHA-256 hash; the global rate limiter
 * guards against enumeration. Accepting still requires a logged-in user.
 */
import { FastifyInstance } from "fastify";
import { authenticateUser } from "../middleware/auth";
import { ShareService } from "../services/share.service";

interface RelayParams {
  relayId: string;
}

export async function relayRoutes(fastify: FastifyInstance) {
  // GET /share-links/relay/:relayId/info — PUBLIC preview (no auth).
  fastify.get<{ Params: RelayParams }>(
    "/share-links/relay/:relayId/info",
    async (request) => {
      const info = await ShareService.getRelayInfo(request.params.relayId);
      return { data: info };
    },
  );

  // POST /share-links/relay/:relayId/accept — redeem the link (login required).
  fastify.post<{ Params: RelayParams }>(
    "/share-links/relay/:relayId/accept",
    { preHandler: authenticateUser },
    async (request) => {
      const result = await ShareService.acceptByRelayId(
        request.params.relayId,
        request.user!.id,
        request.user!.email,
      );
      return { data: result };
    },
  );
}
