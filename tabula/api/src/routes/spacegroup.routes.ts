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
 * SpaceGroup routes
 */
import { FastifyInstance } from "fastify";
import { SpaceGroupService } from "../services/spacegroup.service";
import { authenticateUser } from "../middleware/auth";
import { ConflictError } from "../lib/errors";
import { getDeviceId } from "../lib/device";
import { publishSyncEvent } from "../lib/syncEvents";
import { isTombstoned, markEntityDeleted } from "../lib/tombstones";
import {
  SpaceGroupCreateSchema,
  SpaceGroupUpdateSchema,
} from "../schemas/spacegroup";

interface SpaceGroupParams {
  id: string;
}

export async function spaceGroupRoutes(fastify: FastifyInstance) {
  // Add authentication hook to all routes
  fastify.addHook("preHandler", authenticateUser);

  /**
   * GET /api/v1/space-groups
   * Get all space groups
   */
  fastify.get("/", async (request) => {
    const groups = await SpaceGroupService.getAllSpaceGroups(request.user!.id);
    return { data: groups };
  });

  /**
   * GET /api/v1/space-groups/:id
   * Get a specific space group
   */
  fastify.get<{ Params: SpaceGroupParams }>("/:id", async (request, reply) => {
    try {
      const group = await SpaceGroupService.getSpaceGroupById(
        request.user!.id,
        request.params.id,
      );
      return { data: group };
    } catch (error) {
      return reply.code(404).send({
        error: "Not Found",
        message:
          error instanceof Error ? error.message : "Space group not found",
      });
    }
  });

  /**
   * POST /api/v1/space-groups
   * Create a new space group
   */
  fastify.post<{ Body: unknown }>("/", async (request, reply) => {
    try {
      const input = SpaceGroupCreateSchema.parse(request.body);
      const group = await SpaceGroupService.createSpaceGroup(
        request.user!.id,
        input,
      );
      return reply.code(201).send({ data: group });
    } catch (error) {
      return reply.code(400).send({
        error: "Bad Request",
        message: error instanceof Error ? error.message : "Invalid input",
      });
    }
  });

  /**
   * PUT /api/v1/space-groups/:id
   * Update a space group (upsert: creates when the id has never been seen).
   *
   * Concurrency contract mirrors PUT /workspaces/:id: optional baseVersion ->
   * 409 with current copy on staleness, 410 for tombstoned ids, and a 'save'
   * event published on success.
   */
  fastify.put<{ Params: SpaceGroupParams; Body: unknown }>(
    "/:id",
    async (request, reply) => {
      const userId = request.user!.id;
      const groupId = request.params.id;
      const deviceId = getDeviceId(request);

      try {
        const input = SpaceGroupUpdateSchema.parse(request.body);
        const group = await SpaceGroupService.updateSpaceGroup(
          userId,
          groupId,
          input,
        );
        publishSyncEvent(
          userId,
          {
            type: "spaceGroup",
            action: "save",
            entityId: groupId,
            version: group?.version,
            updatedAt: group?.updatedAt
              ? new Date(group.updatedAt).toISOString()
              : new Date().toISOString(),
            fromDevice: deviceId || "unknown",
          },
          request.log,
        );
        return { data: group };
      } catch (error) {
        if (error instanceof ConflictError) {
          const current = await SpaceGroupService.getSpaceGroupById(
            userId,
            groupId,
          );
          return reply.code(409).send({
            error: "Conflict",
            data: current,
          });
        }
        if (
          error instanceof Error &&
          error.message === "Space group not found"
        ) {
          // Resurrection guard: a recently deleted id must not be re-created by
          // a stale offline snapshot. Never-seen ids are allowed through.
          if (await isTombstoned(userId, "spaceGroup", groupId)) {
            return reply
              .code(410)
              .send({ error: "Gone", message: "Entity was deleted" });
          }
          try {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const createInput = request.body as any;
            await SpaceGroupService.createSpaceGroup(
              userId,
              createInput,
              groupId,
            );
            const group = await SpaceGroupService.updateSpaceGroup(
              userId,
              groupId,
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              request.body as any,
            );
            publishSyncEvent(
              userId,
              {
                type: "spaceGroup",
                action: "save",
                entityId: groupId,
                version: group?.version,
                updatedAt: group?.updatedAt
                  ? new Date(group.updatedAt).toISOString()
                  : new Date().toISOString(),
                fromDevice: deviceId || "unknown",
              },
              request.log,
            );
            return { data: group };
          } catch (createError) {
            return reply.code(400).send({
              error: "Bad Request",
              message:
                createError instanceof Error
                  ? createError.message
                  : "Invalid input for upsert",
            });
          }
        }
        return reply.code(400).send({
          error: "Bad Request",
          message: error instanceof Error ? error.message : "Invalid input",
        });
      }
    },
  );

  /**
   * DELETE /api/v1/space-groups/:id
   * Delete a space group
   */
  fastify.delete<{ Params: SpaceGroupParams }>(
    "/:id",
    async (request, reply) => {
      const userId = request.user!.id;
      const groupId = request.params.id;

      try {
        await SpaceGroupService.deleteSpaceGroup(userId, groupId);
      } catch (error) {
        return reply.code(404).send({
          error: "Not Found",
          message:
            error instanceof Error ? error.message : "Space group not found",
        });
      }

      // Tombstone the id and drop its sync version/state keys so stale offline
      // snapshots cannot resurrect it. Best-effort: the row is already gone, so
      // a Redis failure must not fail the request.
      try {
        await markEntityDeleted(userId, "spaceGroup", groupId);
      } catch (error) {
        request.log.error(
          { err: error, groupId },
          "Failed to tombstone deleted space group",
        );
      }

      publishSyncEvent(
        userId,
        {
          type: "spaceGroup",
          action: "delete",
          entityId: groupId,
          updatedAt: new Date().toISOString(),
          fromDevice: getDeviceId(request) || "unknown",
        },
        request.log,
      );

      return reply.code(204).send();
    },
  );
}
