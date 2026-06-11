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
 * Workspace routes
 */
import { FastifyInstance } from "fastify";
import { WorkspaceService } from "../services/workspace.service";
import { authenticateUser } from "../middleware/auth";
import { ConflictError } from "../lib/errors";
import { getDeviceId } from "../lib/device";
import { publishSyncEvent } from "../lib/syncEvents";
import { isTombstoned, markEntityDeleted } from "../lib/tombstones";
import {
  WorkspaceCreateSchema,
  WorkspaceUpdateSchema,
  WorkspaceSaveTabsSchema,
  TabMoveSchema,
  TabReorderSchema,
  TabBulkOperationSchema,
} from "../schemas/workspace";

interface WorkspaceParams {
  id: string;
}

/**
 * Transform workspace for API response:
 * - Extract tabGroups from settings to top-level
 * - Extract groupId from tab metadata to top-level tab property
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function transformWorkspaceResponse(workspace: any): any {
  if (!workspace) return workspace;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const settings = workspace.settings as Record<string, any>;
  const tabGroups = Array.isArray(settings?.tabGroups)
    ? settings.tabGroups
    : [];

  // Transform tabs to include groupId at top level
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const tabs = (workspace.tabs || []).map((tab: any) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const metadata = tab.metadata as Record<string, any>;
    return {
      ...tab,
      groupId: metadata?.groupId || null,
      // Extension wire-format aliases (Chrome's field names) so favicons,
      // pin state, and order survive the round-trip back to the client
      favIconUrl: tab.faviconUrl ?? null,
      pinned: tab.isPinned ?? false,
      index: tab.position,
    };
  });

  return {
    ...workspace,
    tabs,
    tabGroups,
  };
}

export async function workspaceRoutes(fastify: FastifyInstance) {
  // Add authentication hook to all routes
  fastify.addHook("preHandler", authenticateUser);

  /**
   * GET /api/v1/workspaces
   * Get all workspaces for the authenticated user
   */
  fastify.get("/", async (request) => {
    const workspaces = await WorkspaceService.getAllWorkspaces(
      request.user!.id,
    );
    return { data: workspaces.map(transformWorkspaceResponse) };
  });

  /**
   * GET /api/v1/workspaces/:id
   * Get a specific workspace
   */
  fastify.get<{ Params: WorkspaceParams }>("/:id", async (request, reply) => {
    try {
      const workspace = await WorkspaceService.getWorkspaceById(
        request.user!.id,
        request.params.id,
      );
      return { data: transformWorkspaceResponse(workspace) };
    } catch (error) {
      // getWorkspaceById only throws 'Workspace not found' by design; any other
      // failure is genuinely a missing/inaccessible workspace from the client's
      // perspective. Use a fixed message so internal error text never leaks.
      request.log.error(error);
      return reply.code(404).send({
        error: "Not Found",
        message: "Workspace not found",
      });
    }
  });

  /**
   * POST /api/v1/workspaces
   * Create a new workspace
   */
  fastify.post<{ Body: unknown }>("/", async (request, reply) => {
    try {
      const input = WorkspaceCreateSchema.parse(request.body);
      const workspace = await WorkspaceService.createWorkspace(
        request.user!.id,
        request.user!.tier,
        input,
      );
      return reply
        .code(201)
        .send({ data: transformWorkspaceResponse(workspace) });
    } catch (error) {
      if (error instanceof Error && error.message.includes("Maximum number")) {
        return reply.code(403).send({
          error: "Forbidden",
          message: error.message,
        });
      }
      if (error instanceof Error && error.name === "ZodError") {
        return reply
          .code(400)
          .send({ error: "Bad Request", message: "Invalid input" });
      }
      // Unexpected errors: log server-side, return a generic message (never the
      // raw Prisma/Redis error text).
      request.log.error(error);
      return reply.code(400).send({
        error: "Bad Request",
        message: "Invalid input",
      });
    }
  });

  /**
   * PUT /api/v1/workspaces/:id
   * Update a workspace (upsert: creates when the id has never been seen).
   *
   * Concurrency contract:
   * - Body may include baseVersion; when it is older than the stored version
   *   the request fails with 409 { error: 'Conflict', data: <current copy> }.
   * - Recently deleted ids respond 410 Gone instead of resurrecting.
   * - Successful writes publish a 'save' event on sync:updates:<userId>.
   */
  fastify.put<{ Params: WorkspaceParams; Body: unknown }>(
    "/:id",
    async (request, reply) => {
      const userId = request.user!.id;
      const workspaceId = request.params.id;
      const deviceId = getDeviceId(request);

      try {
        const input = WorkspaceUpdateSchema.parse(request.body);
        const workspace = await WorkspaceService.updateWorkspace(
          userId,
          workspaceId,
          input,
          {
            deviceId,
          },
        );
        publishSyncEvent(
          userId,
          {
            type: "workspace",
            action: "save",
            entityId: workspaceId,
            version: workspace?.version,
            updatedAt: workspace?.updatedAt
              ? new Date(workspace.updatedAt).toISOString()
              : new Date().toISOString(),
            fromDevice: deviceId || "unknown",
          },
          request.log,
        );
        return { data: transformWorkspaceResponse(workspace) };
      } catch (error) {
        if (error instanceof ConflictError) {
          const current = await WorkspaceService.getWorkspaceById(
            userId,
            workspaceId,
          );
          return reply.code(409).send({
            error: "Conflict",
            data: transformWorkspaceResponse(current),
          });
        }
        if (error instanceof Error && error.message === "Workspace not found") {
          // Resurrection guard: a recently deleted id must not be re-created by
          // a stale offline snapshot. Never-seen ids are allowed through.
          if (await isTombstoned(userId, "workspace", workspaceId)) {
            return reply
              .code(410)
              .send({ error: "Gone", message: "Entity was deleted" });
          }
          try {
            // Upsert: Create if not found using the input and ID
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const createInput = request.body as any;
            await WorkspaceService.createWorkspace(
              userId,
              request.user!.tier,
              createInput,
              workspaceId,
            );
            // Apply full update to handle nested data
            const workspace = await WorkspaceService.updateWorkspace(
              userId,
              workspaceId,
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              request.body as any,
              { deviceId },
            );
            publishSyncEvent(
              userId,
              {
                type: "workspace",
                action: "save",
                entityId: workspaceId,
                version: workspace?.version,
                updatedAt: workspace?.updatedAt
                  ? new Date(workspace.updatedAt).toISOString()
                  : new Date().toISOString(),
                fromDevice: deviceId || "unknown",
              },
              request.log,
            );
            return { data: transformWorkspaceResponse(workspace) };
          } catch (createError) {
            // Surface user-facing tier-limit/validation sentinels; otherwise a
            // generic message so internal error text never leaks.
            const isSentinel =
              createError instanceof Error &&
              (createError.message.includes("Maximum number") ||
                createError.name === "ZodError");
            if (!isSentinel) request.log.error(createError);
            return reply.code(400).send({
              error: "Bad Request",
              message: isSentinel
                ? (createError as Error).message
                : "Invalid input for upsert",
            });
          }
        }
        // Surface known user-facing sentinels; otherwise generic.
        const isSentinel =
          error instanceof Error &&
          (error.name === "ZodError" ||
            error.message.includes("Maximum number"));
        if (!isSentinel) request.log.error(error);
        return reply.code(400).send({
          error: "Bad Request",
          message: isSentinel ? (error as Error).message : "Invalid input",
        });
      }
    },
  );

  /**
   * DELETE /api/v1/workspaces/:id
   * Delete a workspace
   */
  fastify.delete<{ Params: WorkspaceParams }>(
    "/:id",
    async (request, reply) => {
      const userId = request.user!.id;
      const workspaceId = request.params.id;

      try {
        await WorkspaceService.deleteWorkspace(userId, workspaceId);
      } catch (error) {
        return reply.code(404).send({
          error: "Not Found",
          message:
            error instanceof Error ? error.message : "Workspace not found",
        });
      }

      // Tombstone the id and drop its sync version/state keys so stale offline
      // snapshots cannot resurrect it. Best-effort: the row is already gone, so
      // a Redis failure must not fail the request.
      try {
        await markEntityDeleted(userId, "workspace", workspaceId);
      } catch (error) {
        request.log.error(
          { err: error, workspaceId },
          "Failed to tombstone deleted workspace",
        );
      }

      publishSyncEvent(
        userId,
        {
          type: "workspace",
          action: "delete",
          entityId: workspaceId,
          updatedAt: new Date().toISOString(),
          fromDevice: getDeviceId(request) || "unknown",
        },
        request.log,
      );

      return reply.code(204).send();
    },
  );

  /**
   * POST /api/v1/workspaces/:id/tabs
   * Save tabs to a workspace
   */
  fastify.post<{ Params: WorkspaceParams; Body: unknown }>(
    "/:id/tabs",
    async (request, reply) => {
      try {
        const input = WorkspaceSaveTabsSchema.parse(request.body);
        const workspace = await WorkspaceService.saveTabsToWorkspace(
          request.user!.id,
          request.params.id,
          input.tabs,
        );
        return { data: workspace };
      } catch (error) {
        if (error instanceof Error && error.message === "Workspace not found") {
          return reply.code(404).send({
            error: "Not Found",
            message: error.message,
          });
        }
        if (!(error instanceof Error) || error.name !== "ZodError")
          request.log.error(error);
        return reply.code(400).send({
          error: "Bad Request",
          message: "Invalid input",
        });
      }
    },
  );

  /**
   * POST /api/v1/workspaces/tabs/move
   * Move a tab to another workspace
   */
  fastify.post<{ Body: unknown }>("/tabs/move", async (request, reply) => {
    try {
      const input = TabMoveSchema.parse(request.body);
      const tab = await WorkspaceService.moveTab(
        request.user!.id,
        input.tabId,
        input.targetWorkspaceId,
        input.position,
      );
      return { data: tab };
    } catch (error) {
      if (error instanceof Error && error.message.includes("not found")) {
        return reply.code(404).send({
          error: "Not Found",
          message: error.message,
        });
      }
      if (!(error instanceof Error) || error.name !== "ZodError")
        request.log.error(error);
      return reply.code(400).send({
        error: "Bad Request",
        message: "Invalid input",
      });
    }
  });

  /**
   * POST /api/v1/workspaces/tabs/reorder
   * Reorder a tab within a workspace
   */
  fastify.post<{ Body: unknown }>("/tabs/reorder", async (request, reply) => {
    try {
      const input = TabReorderSchema.parse(request.body);
      const tab = await WorkspaceService.reorderTab(
        request.user!.id,
        input.tabId,
        input.newPosition,
      );
      return { data: tab };
    } catch (error) {
      if (error instanceof Error && error.message.includes("not found")) {
        return reply.code(404).send({
          error: "Not Found",
          message: error.message,
        });
      }
      if (!(error instanceof Error) || error.name !== "ZodError")
        request.log.error(error);
      return reply.code(400).send({
        error: "Bad Request",
        message: "Invalid input",
      });
    }
  });

  /**
   * POST /api/v1/workspaces/tabs/bulk
   * Bulk operations on tabs (close, suspend, pin, unpin)
   */
  fastify.post<{ Body: unknown }>("/tabs/bulk", async (request, reply) => {
    try {
      const input = TabBulkOperationSchema.parse(request.body);

      let result;
      if (input.operation === "close") {
        result = await WorkspaceService.bulkDeleteTabs(
          request.user!.id,
          input.tabIds,
        );
      } else if (input.operation === "pin" || input.operation === "unpin") {
        result = await WorkspaceService.bulkUpdateTabs(
          request.user!.id,
          input.tabIds,
          input.operation,
        );
      } else {
        // suspend operation is handled on client side
        return reply.code(400).send({
          error: "Bad Request",
          message: "Suspend operation should be handled on client side",
        });
      }

      return { data: result };
    } catch (error) {
      if (error instanceof Error && error.message.includes("not belong")) {
        return reply.code(403).send({
          error: "Forbidden",
          message: error.message,
        });
      }
      if (!(error instanceof Error) || error.name !== "ZodError")
        request.log.error(error);
      return reply.code(400).send({
        error: "Bad Request",
        message: "Invalid input",
      });
    }
  });
}
