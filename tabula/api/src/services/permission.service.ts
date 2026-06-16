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
 * PermissionService — the single chokepoint for "may this user touch this
 * space, and at what role?".
 *
 * Every space read/write authorization in the API resolves through here instead
 * of the old scattered `WHERE userId = X` owner filter, so sharing is enforced
 * uniformly. OWNER is implicit (Workspace.userId == caller) and is never a
 * collaborator row; EDIT and VIEW come from an active SpaceCollaborator (or an
 * accepted ShareLink, which materializes a collaborator row).
 */
import { prisma } from "../lib/prisma";
import { ForbiddenError, NotFoundError } from "../lib/errors";

/** Effective access roles, total-ordered OWNER > EDIT > VIEW. */
export type SpaceRole = "owner" | "edit" | "view";

/** The role values a collaborator/share-link may carry (never "owner"). */
export type GrantRole = "edit" | "view";

const RANK: Record<SpaceRole, number> = { view: 1, edit: 2, owner: 3 };

export class PermissionService {
  /**
   * Resolve the caller's effective role on a space, or null if they have no
   * access at all (used by routes to 404-mask non-visible spaces).
   */
  static async resolveAccess(
    userId: string,
    workspaceId: string,
  ): Promise<SpaceRole | null> {
    const workspace = await prisma.workspace.findUnique({
      where: { id: workspaceId },
      select: { userId: true },
    });
    if (!workspace) return null;
    // Owner short-circuit: cheapest path, never touches the collaborator table.
    if (workspace.userId === userId) return "owner";

    const collaborator = await prisma.spaceCollaborator.findFirst({
      where: { workspaceId, userId, status: "active" },
      select: { role: true },
    });
    if (!collaborator) return null;
    return collaborator.role === "edit" ? "edit" : "view";
  }

  /**
   * Assert the caller holds at least `min` on the space, returning their actual
   * effective role. Throws NotFoundError (→404, existence-masked) when they have
   * NO access, and ForbiddenError (→403) when they can see it but the role is
   * below `min` (e.g. a VIEW collaborator attempting a write).
   */
  static async requireRole(
    userId: string,
    workspaceId: string,
    min: SpaceRole,
  ): Promise<SpaceRole> {
    const role = await this.resolveAccess(userId, workspaceId);
    if (role === null) throw new NotFoundError();
    if (RANK[role] < RANK[min]) {
      throw new ForbiddenError(`This action requires ${min} access`);
    }
    return role;
  }

  /**
   * All user ids that can currently access a space: the owner plus every active
   * collaborator with a registered (non-null) user id. Used to fan out sync
   * notifications and tombstones to everyone who holds the space. Returns [] if
   * the space does not exist. The owner is always first; ids are de-duplicated.
   */
  static async listAccessUserIds(workspaceId: string): Promise<string[]> {
    const workspace = await prisma.workspace.findUnique({
      where: { id: workspaceId },
      select: { userId: true },
    });
    if (!workspace) return [];

    const collaborators = await prisma.spaceCollaborator.findMany({
      where: { workspaceId, status: "active", userId: { not: null } },
      select: { userId: true },
    });
    const ids = [
      workspace.userId,
      ...collaborators
        .map((c) => c.userId)
        .filter((id): id is string => id !== null),
    ];
    return [...new Set(ids)];
  }

  /**
   * Spaces shared WITH a user (active collaborator grants they do not own),
   * each annotated with the caller's effective role. Powers
   * GET /workspaces/shared-with-me without changing the meaning of the existing
   * owner-only workspace list.
   */
  static async listSpacesSharedWith(
    userId: string,
  ): Promise<Array<{ workspaceId: string; role: GrantRole; name: string }>> {
    const grants = await prisma.spaceCollaborator.findMany({
      where: { userId, status: "active" },
      select: {
        workspaceId: true,
        role: true,
        workspace: { select: { name: true } },
      },
    });
    return grants.map((g) => ({
      workspaceId: g.workspaceId,
      role: g.role === "edit" ? "edit" : "view",
      name: g.workspace.name,
    }));
  }
}
