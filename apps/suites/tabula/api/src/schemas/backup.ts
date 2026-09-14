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
 * Backup validation schemas using Zod
 */
import { z } from "zod";

/**
 * Backup types
 */
export const BackupTypeSchema = z.enum(["auto", "manual", "scheduled"]);
export type BackupType = z.infer<typeof BackupTypeSchema>;

/**
 * Create backup input
 */
export const BackupCreateSchema = z.object({
  workspaceId: z.string().optional(),
  name: z.string().max(255).optional(),
  type: BackupTypeSchema.default("manual"),
});

export type BackupCreateInput = z.infer<typeof BackupCreateSchema>;

/**
 * Restore backup input
 */
export const BackupRestoreSchema = z.object({
  targetWorkspaceId: z.string().optional(), // If not provided, restore to original
  createNew: z.boolean().default(false), // Create new workspace from backup
});

export type BackupRestoreInput = z.infer<typeof BackupRestoreSchema>;

/**
 * List backups query params
 */
export const BackupListQuerySchema = z.object({
  workspaceId: z.string().optional(),
  type: BackupTypeSchema.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
  sortBy: z.enum(["createdAt", "name", "sizeBytes"]).default("createdAt"),
  sortOrder: z.enum(["asc", "desc"]).default("desc"),
});

export type BackupListQuery = z.infer<typeof BackupListQuerySchema>;

/**
 * Backup stats response type (not a schema, just a TypeScript type)
 */
export interface BackupStats {
  totalBackups: number;
  totalSizeBytes: number;
  autoBackups: number;
  manualBackups: number;
  oldestBackup: Date | null;
  newestBackup: Date | null;
  backupsByWorkspace: Record<string, number>;
}
