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
 * Backup API Routes
 *
 * Endpoints:
 * - GET    /             - List backups
 * - POST   /             - Create backup
 * - GET    /stats        - Get backup statistics
 * - GET    /:id          - Get specific backup
 * - POST   /:id/restore  - Restore from backup
 * - DELETE /:id          - Delete backup
 */
import { FastifyInstance } from "fastify";
import { BackupService } from "../services/backup.service";
import { authenticateUser } from "../middleware/auth";
import {
  BackupCreateSchema,
  BackupRestoreSchema,
  BackupListQuerySchema,
} from "../schemas/backup";

interface BackupParams {
  id: string;
}

export async function backupRoutes(fastify: FastifyInstance) {
  // Add authentication hook to all routes
  fastify.addHook("preHandler", authenticateUser);

  /**
   * GET /api/v1/backups
   * List backups with pagination and filtering
   */
  fastify.get("/", async (request, reply) => {
    try {
      const query = BackupListQuerySchema.parse(request.query);
      const result = await BackupService.listBackups(request.user!.id, query);
      return { data: result };
    } catch (error) {
      if (error instanceof Error && error.name === "ZodError") {
        return reply
          .code(400)
          .send({ error: "Bad Request", message: "Invalid query parameters" });
      }
      throw error;
    }
  });

  /**
   * GET /api/v1/backups/stats
   * Get backup statistics
   */
  fastify.get("/stats", async (request) => {
    const stats = await BackupService.getBackupStats(request.user!.id);
    return { data: stats };
  });

  /**
   * GET /api/v1/backups/:id
   * Get a specific backup
   */
  fastify.get<{ Params: BackupParams }>("/:id", async (request, reply) => {
    const backup = await BackupService.getBackup(
      request.user!.id,
      request.params.id,
    );
    if (!backup) {
      return reply
        .code(404)
        .send({ error: "Not Found", message: "Backup not found" });
    }
    return { data: backup };
  });

  /**
   * POST /api/v1/backups
   * Create a new backup
   */
  fastify.post("/", async (request, reply) => {
    try {
      const input = BackupCreateSchema.parse(request.body);
      const backup = await BackupService.createBackup(
        request.user!.id,
        request.user!.tier,
        input,
      );
      return reply.code(201).send({ data: backup });
    } catch (error) {
      if (error instanceof Error) {
        if (error.name === "ZodError") {
          return reply
            .code(400)
            .send({ error: "Bad Request", message: "Invalid input" });
        }
        if (error.message.includes("limit")) {
          return reply
            .code(403)
            .send({ error: "Forbidden", message: error.message });
        }
        if (error.message.includes("not found")) {
          return reply
            .code(404)
            .send({ error: "Not Found", message: error.message });
        }
      }
      throw error;
    }
  });

  /**
   * POST /api/v1/backups/:id/restore
   * Restore from backup
   */
  fastify.post<{ Params: BackupParams }>(
    "/:id/restore",
    async (request, reply) => {
      try {
        const input = BackupRestoreSchema.parse(request.body || {});
        const result = await BackupService.restoreBackup(
          request.user!.id,
          request.params.id,
          {
            targetWorkspaceId: input.targetWorkspaceId,
            createNew: input.createNew,
          },
        );
        return { data: result };
      } catch (error) {
        if (error instanceof Error) {
          if (error.name === "ZodError") {
            return reply
              .code(400)
              .send({ error: "Bad Request", message: "Invalid input" });
          }
          if (error.message.includes("not found")) {
            return reply
              .code(404)
              .send({ error: "Not Found", message: error.message });
          }
          // Multi-workspace restore onto a single target is rejected to prevent
          // silent data loss (see BackupService.restoreBackup).
          if (error.message.includes("not supported")) {
            return reply
              .code(400)
              .send({ error: "Bad Request", message: error.message });
          }
        }
        // Unexpected errors fall through to the central handler (generic 500).
        throw error;
      }
    },
  );

  /**
   * DELETE /api/v1/backups/:id
   * Delete a backup
   */
  fastify.delete<{ Params: BackupParams }>("/:id", async (request, reply) => {
    const deleted = await BackupService.deleteBackup(
      request.user!.id,
      request.params.id,
    );
    if (!deleted) {
      return reply
        .code(404)
        .send({ error: "Not Found", message: "Backup not found" });
    }
    return reply.code(204).send();
  });
}
