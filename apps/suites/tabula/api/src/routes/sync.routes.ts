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
 * Sync API Routes
 *
 * Endpoints:
 * - GET    /state    - Get sync status
 * - POST   /push     - Push local changes
 * - GET    /pull     - Pull remote changes
 * - GET    /stream   - SSE stream for real-time updates
 */
import { FastifyInstance } from "fastify";
import { SyncService } from "../services/sync.service";
import {
  authenticateUser,
  authenticateUserAllowQueryToken,
} from "../middleware/auth";
import { SyncPushSchema, SyncPullSchema } from "../schemas/sync";

export async function syncRoutes(fastify: FastifyInstance) {
  // Authentication is attached per-route: every route requires the
  // Authorization header except /stream, which additionally accepts
  // ?token=<jwt> because EventSource cannot send headers.

  /**
   * GET /api/v1/sync/state
   * Get current sync status
   */
  fastify.get("/state", { preHandler: authenticateUser }, async (request) => {
    const status = await SyncService.getSyncStatus(request.user!.id);
    return { data: status };
  });

  /**
   * POST /api/v1/sync/push
   * Push local changes to server
   */
  fastify.post(
    "/push",
    { preHandler: authenticateUser },
    async (request, reply) => {
      try {
        const input = SyncPushSchema.parse(request.body);
        const result = await SyncService.pushChanges(
          request.user!.id,
          request.user!.tier,
          input,
        );
        return { data: result };
      } catch (error) {
        if (error instanceof Error && error.name === "ZodError") {
          return reply
            .code(400)
            .send({ error: "Bad Request", message: "Invalid input" });
        }
        throw error;
      }
    },
  );

  /**
   * GET /api/v1/sync/pull
   * Pull remote changes from server
   */
  fastify.get(
    "/pull",
    { preHandler: authenticateUser },
    async (request, reply) => {
      try {
        const input = SyncPullSchema.parse(request.query);
        const result = await SyncService.pullChanges(request.user!.id, input);
        return { data: result };
      } catch (error) {
        if (error instanceof Error && error.name === "ZodError") {
          return reply.code(400).send({
            error: "Bad Request",
            message: "Invalid query parameters",
          });
        }
        throw error;
      }
    },
  );

  /**
   * GET /api/v1/sync/stream
   * SSE stream for real-time sync updates.
   * Accepts auth via Authorization header OR ?token=<jwt> (EventSource cannot
   * send headers).
   */
  fastify.get(
    "/stream",
    { preHandler: authenticateUserAllowQueryToken },
    async (request, reply) => {
      // Get device ID from query or generate one
      const query = request.query as { deviceId?: string };
      const deviceId = query.deviceId || `device_${Date.now()}`;

      // Set SSE headers
      reply.raw.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
        "Access-Control-Allow-Origin": "*",
      });

      // Send initial connection event
      reply.raw.write(
        `event: connected\ndata: ${JSON.stringify({ timestamp: new Date().toISOString() })}\n\n`,
      );

      // Handle client disconnect: abort wakes the subscription generator so it
      // exits (and cleans up its Redis subscriber) promptly instead of after the
      // next heartbeat/timeout cycle.
      let isConnected = true;
      const disconnect = new AbortController();
      request.raw.on("close", () => {
        isConnected = false;
        disconnect.abort();
      });

      try {
        // Subscribe to updates
        const updateStream = SyncService.subscribeToUpdates(
          request.user!.id,
          deviceId,
          {
            signal: disconnect.signal,
          },
        );

        // SSE stream consumption - for-await is appropriate for async iterators
        // eslint-disable-next-line no-restricted-syntax
        for await (const update of updateStream) {
          if (!isConnected) break;

          const eventType = update.type;
          const eventData = JSON.stringify(update.data);
          reply.raw.write(`event: ${eventType}\ndata: ${eventData}\n\n`);
        }
      } catch {
        if (isConnected) {
          reply.raw.write(
            `event: error\ndata: ${JSON.stringify({ message: "Connection error" })}\n\n`,
          );
        }
      } finally {
        reply.raw.end();
      }
    },
  );
}
