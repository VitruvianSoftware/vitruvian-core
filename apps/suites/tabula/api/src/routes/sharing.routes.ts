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
 * Sharing & permissions routes (#139): collaborators (share by email),
 * share links (share by opaque token), and the "shared with me" listing.
 *
 * These handlers deliberately do NOT try/catch — domain errors flow to the app's
 * central errorHandler, which maps ForbiddenError (statusCode 403) → 403,
 * NotFoundError (404) → 404, and ZodError → 400. requireRole(..., 'owner')
 * is the management gate; a non-owner who can see the space gets 403, a stranger
 * gets 404 (existence-masked).
 */
import { FastifyInstance } from "fastify";
import { authenticateUser } from "../middleware/auth";
import { PermissionService } from "../services/permission.service";
import { CollaboratorService } from "../services/collaborator.service";
import { ShareService } from "../services/share.service";
import {
  CollaboratorCreateSchema,
  CollaboratorUpdateSchema,
  ShareLinkCreateSchema,
  ShareTokenSchema,
} from "../schemas/sharing";

interface SpaceParams {
  id: string;
}
interface CollaboratorParams {
  id: string;
  collaboratorId: string;
}
interface LinkParams {
  id: string;
  linkId: string;
}

export async function sharingRoutes(fastify: FastifyInstance) {
  fastify.addHook("preHandler", authenticateUser);

  // --- Spaces shared WITH the caller ---------------------------------------

  fastify.get("/workspaces/shared-with-me", async (request) => {
    const spaces = await PermissionService.listSpacesSharedWith(
      request.user!.id,
    );
    return { data: spaces };
  });

  // --- Collaborators (share by email) — OWNER-only management ---------------

  fastify.get<{ Params: SpaceParams }>(
    "/workspaces/:id/collaborators",
    async (request) => {
      await PermissionService.requireRole(
        request.user!.id,
        request.params.id,
        "owner",
      );
      const collaborators = await CollaboratorService.listCollaborators(
        request.params.id,
      );
      return { data: collaborators };
    },
  );

  fastify.post<{ Params: SpaceParams; Body: unknown }>(
    "/workspaces/:id/collaborators",
    async (request, reply) => {
      await PermissionService.requireRole(
        request.user!.id,
        request.params.id,
        "owner",
      );
      const input = CollaboratorCreateSchema.parse(request.body);
      const collaborator = await CollaboratorService.shareByEmail(
        request.params.id,
        request.user!.id,
        input.email,
        input.role,
      );
      // Do NOT reflect active/pending back to the inviter — that would reveal
      // whether the email belongs to a registered user (an enumeration oracle).
      reply.code(201);
      return {
        data: {
          id: collaborator.id,
          email: collaborator.inviteeEmail,
          role: collaborator.role,
        },
      };
    },
  );

  fastify.patch<{ Params: CollaboratorParams; Body: unknown }>(
    "/workspaces/:id/collaborators/:collaboratorId",
    async (request) => {
      await PermissionService.requireRole(
        request.user!.id,
        request.params.id,
        "owner",
      );
      const input = CollaboratorUpdateSchema.parse(request.body);
      const collaborator = await CollaboratorService.setRole(
        request.params.id,
        request.params.collaboratorId,
        input.role,
      );
      return { data: collaborator };
    },
  );

  fastify.delete<{ Params: CollaboratorParams }>(
    "/workspaces/:id/collaborators/:collaboratorId",
    async (request, reply) => {
      await PermissionService.requireRole(
        request.user!.id,
        request.params.id,
        "owner",
      );
      await CollaboratorService.revoke(
        request.params.id,
        request.params.collaboratorId,
      );
      return reply.code(204).send();
    },
  );

  // --- Share links (share by opaque token) — OWNER-only management ----------

  fastify.get<{ Params: SpaceParams }>(
    "/workspaces/:id/share-links",
    async (request) => {
      await PermissionService.requireRole(
        request.user!.id,
        request.params.id,
        "owner",
      );
      const links = await ShareService.listLinks(request.params.id);
      return { data: links };
    },
  );

  fastify.post<{ Params: SpaceParams; Body: unknown }>(
    "/workspaces/:id/share-links",
    async (request, reply) => {
      await PermissionService.requireRole(
        request.user!.id,
        request.params.id,
        "owner",
      );
      const input = ShareLinkCreateSchema.parse(request.body);
      const link = await ShareService.createLink(
        request.params.id,
        request.user!.id,
        input.role,
        input.label,
        input.expiresAt,
      );
      // `token` is present here exactly once and never again.
      reply.code(201);
      return { data: link };
    },
  );

  fastify.delete<{ Params: LinkParams }>(
    "/workspaces/:id/share-links/:linkId",
    async (request, reply) => {
      await PermissionService.requireRole(
        request.user!.id,
        request.params.id,
        "owner",
      );
      await ShareService.revokeLink(request.params.id, request.params.linkId);
      return reply.code(204).send();
    },
  );

  // --- Redeeming a share link (token in BODY, never the URL) ----------------

  fastify.post<{ Body: unknown }>("/share-links/info", async (request) => {
    const { token } = ShareTokenSchema.parse(request.body);
    const info = await ShareService.getLinkInfo(token);
    return { data: info };
  });

  fastify.post<{ Body: unknown }>("/share-links/accept", async (request) => {
    const { token } = ShareTokenSchema.parse(request.body);
    const result = await ShareService.acceptLink(
      token,
      request.user!.id,
      request.user!.email,
    );
    return { data: result };
  });
}
