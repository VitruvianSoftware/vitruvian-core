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
 * SpaceGroup service
 */
import { prisma } from "../lib/prisma";
import { ConflictError } from "../lib/errors";
import type {
  SpaceGroupCreateInput,
  SpaceGroupUpdateInput,
} from "../schemas/spacegroup";

export class SpaceGroupService {
  /**
   * Generate a unique ID with a given prefix
   */
  static generateId(prefix: string): string {
    return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).substring(2, 11)}`;
  }

  /**
   * Get all space groups for a user
   */
  static async getAllSpaceGroups(userId: string) {
    return prisma.spaceGroup.findMany({
      where: { userId },
      orderBy: { position: "asc" },
    });
  }

  /**
   * Get a single space group
   */
  static async getSpaceGroupById(userId: string, groupId: string) {
    const group = await prisma.spaceGroup.findFirst({
      where: {
        id: groupId,
        userId,
      },
    });

    if (!group) {
      throw new Error("Space group not found");
    }

    return group;
  }

  /**
   * Create a new space group
   */
  static async createSpaceGroup(
    userId: string,
    input: SpaceGroupCreateInput,
    id?: string,
  ) {
    return prisma.spaceGroup.create({
      data: {
        id: id || this.generateId("sg"),
        userId,
        title: input.title,
        collapsed: input.collapsed,
        position: input.position,
        color: input.color,
      },
    });
  }

  /**
   * Update a space group.
   *
   * Optimistic concurrency: the row is locked FOR UPDATE inside a transaction;
   * when the client supplies `baseVersion` older than the stored `version`, a
   * ConflictError is thrown (routes map it to 409 with the current server
   * copy). Legacy clients that omit baseVersion are accepted unconditionally.
   * Every successful update increments `version` by exactly 1.
   */
  static async updateSpaceGroup(
    userId: string,
    groupId: string,
    input: SpaceGroupUpdateInput,
  ) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return prisma.$transaction(async (tx: any) => {
      // Lock the row (scoped to the owner) and read the current version.
      // This also serves as the ownership/existence check.
      const rows: Array<{ version: number | null }> =
        await tx.$queryRaw`SELECT version FROM space_groups WHERE id = ${groupId} AND user_id = ${userId}::uuid FOR UPDATE`;

      if (!rows || rows.length === 0) {
        throw new Error("Space group not found");
      }

      const currentVersion = rows[0].version ?? 0;

      if (
        input.baseVersion !== undefined &&
        input.baseVersion < currentVersion
      ) {
        throw new ConflictError(
          "Space group was modified by another device",
          currentVersion,
        );
      }

      // Only write the fields actually provided (undefined -> leave untouched;
      // color: null is a meaningful clear).
      const data: Record<string, unknown> = { version: currentVersion + 1 };
      if (input.title !== undefined) data.title = input.title;
      if (input.collapsed !== undefined) data.collapsed = input.collapsed;
      if (input.position !== undefined) data.position = input.position;
      if (input.color !== undefined) data.color = input.color;

      return tx.spaceGroup.update({
        where: { id: groupId },
        data,
      });
    });
  }

  /**
   * Delete a space group
   */
  static async deleteSpaceGroup(userId: string, groupId: string) {
    // Verify ownership
    await this.getSpaceGroupById(userId, groupId);

    // Delete group (workspaces will set groupId to null due to SetNull constraint)
    // Wait, prisma schema says onDelete: SetNull?
    // Let's check schema: spaceGroup SpaceGroup? @relation(fields: [groupId], references: [id], onDelete: SetNull)
    // Yes, SetNull is correct.

    await prisma.spaceGroup.delete({
      where: { id: groupId },
    });
  }
}
