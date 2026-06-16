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
 * ShareService — share a space by opaque link (#139).
 *
 * A space may have MANY links, each at its own role and individually revocable.
 * The raw token is 256 bits of entropy and is returned to the creator exactly
 * ONCE; only its SHA-256 hash is stored, so a database read never yields a
 * usable token. resolveToken returns null identically for not-found, revoked,
 * and expired links so callers cannot distinguish those states (no oracle).
 */
import { prisma } from "../lib/prisma";
import { generateId, generateOpaqueToken, hashToken } from "../lib/ids";
import { NotFoundError } from "../lib/errors";
import type { GrantRole } from "./permission.service";

export class ShareService {
  /**
   * Mint a new share link. Returns the raw token ONCE — it is never persisted
   * (only its hash) and cannot be recovered afterward.
   */
  static async createLink(
    workspaceId: string,
    createdByUserId: string,
    role: GrantRole,
    label?: string,
    expiresAt?: string,
  ) {
    const token = generateOpaqueToken();
    const link = await prisma.shareLink.create({
      data: {
        id: generateId("sl"),
        workspaceId,
        tokenHash: hashToken(token),
        role,
        createdByUserId,
        label: label ?? null,
        expiresAt: expiresAt ? new Date(expiresAt) : null,
      },
      select: { id: true, role: true, label: true, expiresAt: true },
    });
    return { ...link, token };
  }

  /** Active (non-revoked) links for a space. Never returns token material. */
  static async listLinks(workspaceId: string) {
    return prisma.shareLink.findMany({
      where: { workspaceId, revokedAt: null },
      select: {
        id: true,
        role: true,
        label: true,
        expiresAt: true,
        createdAt: true,
      },
      orderBy: { createdAt: "asc" },
    });
  }

  /** Soft-revoke a link (future accepts fail; existing collaborators unaffected). */
  static async revokeLink(workspaceId: string, linkId: string) {
    const result = await prisma.shareLink.updateMany({
      where: { id: linkId, workspaceId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (result.count === 0) {
      throw new NotFoundError("Share link not found");
    }
  }

  /**
   * Resolve a raw token to a usable link, or null if it does not exist, is
   * revoked, or is expired (all indistinguishable to the caller).
   */
  private static async resolveToken(token: string) {
    const link = await prisma.shareLink.findUnique({
      where: { tokenHash: hashToken(token) },
      include: { workspace: { select: { name: true, userId: true } } },
    });
    if (!link || link.revokedAt) return null;
    if (link.expiresAt && link.expiresAt.getTime() < Date.now()) return null;
    return link;
  }

  /** Preview a link before accepting (no grant is created). */
  static async getLinkInfo(token: string) {
    const link = await this.resolveToken(token);
    if (!link) {
      throw new NotFoundError("Share link not found");
    }
    return {
      workspaceId: link.workspaceId,
      workspaceName: link.workspace.name,
      role: link.role as GrantRole,
    };
  }

  /**
   * Redeem a link: materialize a collaborator grant for the caller. Idempotent
   * and never downgrades an existing higher grant; the owner accepting their own
   * link is a no-op. Throws NotFoundError for an invalid/revoked/expired token.
   */
  static async acceptLink(token: string, userId: string, userEmail: string) {
    const link = await this.resolveToken(token);
    if (!link) {
      throw new NotFoundError("Share link not found");
    }

    // The owner is already the owner — accepting their own link does nothing.
    if (link.workspace.userId === userId) {
      return {
        workspaceId: link.workspaceId,
        workspaceName: link.workspace.name,
        role: "owner" as const,
      };
    }

    const inviteeEmail = userEmail.toLowerCase();
    const existing = await prisma.spaceCollaborator.findUnique({
      where: {
        workspaceId_inviteeEmail: {
          workspaceId: link.workspaceId,
          inviteeEmail,
        },
      },
      select: { role: true },
    });
    // Never downgrade: an EDIT collaborator accepting a VIEW link stays EDIT.
    const role: GrantRole =
      existing?.role === "edit" ? "edit" : (link.role as GrantRole);

    const collaborator = await prisma.spaceCollaborator.upsert({
      where: {
        workspaceId_inviteeEmail: {
          workspaceId: link.workspaceId,
          inviteeEmail,
        },
      },
      update: { role, userId, status: "active" },
      create: {
        id: generateId("sc"),
        workspaceId: link.workspaceId,
        inviteeEmail,
        role,
        invitedByUserId: link.createdByUserId,
        userId,
        status: "active",
      },
      select: { role: true },
    });

    return {
      workspaceId: link.workspaceId,
      workspaceName: link.workspace.name,
      role: collaborator.role as GrantRole,
    };
  }
}
