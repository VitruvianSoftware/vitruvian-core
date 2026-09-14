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
 * CollaboratorService — share a space with people by email (#139).
 *
 * Authorization (owner-only) is enforced in the route via
 * PermissionService.requireRole; this service is pure data access. A grant is
 * keyed on the lowercased invitee email so re-inviting updates the role rather
 * than duplicating, and so an invite to an as-yet-unregistered email persists
 * as "pending" (userId null) until that user exists.
 */
import { prisma } from "../lib/prisma";
import { generateId } from "../lib/ids";
import { NotFoundError } from "../lib/errors";
import type { GrantRole } from "./permission.service";

export class CollaboratorService {
  /**
   * Grant (or re-grant) a space to an email at a role. If a User already has
   * that email the grant is "active" and linked to their id; otherwise it is
   * "pending" by email until they register. Idempotent on (workspaceId, email).
   */
  static async shareByEmail(
    workspaceId: string,
    invitedByUserId: string,
    email: string,
    role: GrantRole,
  ) {
    const inviteeEmail = email.toLowerCase();
    const user = await prisma.user.findUnique({
      where: { email: inviteeEmail },
      select: { id: true },
    });
    const userId = user?.id ?? null;
    const status = user ? "active" : "pending";

    return prisma.spaceCollaborator.upsert({
      where: { workspaceId_inviteeEmail: { workspaceId, inviteeEmail } },
      update: { role, userId, status },
      create: {
        id: generateId("sc"),
        workspaceId,
        inviteeEmail,
        role,
        invitedByUserId,
        userId,
        status,
      },
    });
  }

  /**
   * The collaborator roster for a space (route restricts this to the OWNER, so
   * invitee emails are not exposed to view-only grantees).
   */
  static async listCollaborators(workspaceId: string) {
    return prisma.spaceCollaborator.findMany({
      where: { workspaceId },
      select: {
        id: true,
        inviteeEmail: true,
        role: true,
        status: true,
        createdAt: true,
      },
      orderBy: { createdAt: "asc" },
    });
  }

  /** Change a collaborator's role, scoped to the space (cross-space-safe). */
  static async setRole(
    workspaceId: string,
    collaboratorId: string,
    role: GrantRole,
  ) {
    const result = await prisma.spaceCollaborator.updateMany({
      where: { id: collaboratorId, workspaceId },
      data: { role },
    });
    if (result.count === 0) {
      throw new NotFoundError("Collaborator not found");
    }
    return prisma.spaceCollaborator.findUnique({
      where: { id: collaboratorId },
      select: {
        id: true,
        inviteeEmail: true,
        role: true,
        status: true,
        createdAt: true,
      },
    });
  }

  /** Revoke (un-share) a grant, scoped to the space. */
  static async revoke(workspaceId: string, collaboratorId: string) {
    const result = await prisma.spaceCollaborator.deleteMany({
      where: { id: collaboratorId, workspaceId },
    });
    if (result.count === 0) {
      throw new NotFoundError("Collaborator not found");
    }
  }
}
