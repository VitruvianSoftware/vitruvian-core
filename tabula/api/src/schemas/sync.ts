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
 * Sync validation schemas using Zod
 */
import { z } from "zod";

/**
 * Device info for sync
 */
export const DeviceInfoSchema = z.object({
  deviceId: z.string().min(1),
  deviceName: z.string().optional(),
  platform: z.string().optional(),
  userAgent: z.string().optional(),
});

export type DeviceInfo = z.infer<typeof DeviceInfoSchema>;

/**
 * Sync state for a single entity
 */
export const SyncEntityStateSchema = z.object({
  id: z.string(),
  version: z.number().int().min(0),
  updatedAt: z.coerce.date(),
  data: z.record(z.unknown()),
});

export type SyncEntityState = z.infer<typeof SyncEntityStateSchema>;

/**
 * Push sync request
 */
export const SyncPushSchema = z.object({
  deviceId: z.string().min(1),
  clientTimestamp: z.coerce.date(),
  changes: z.array(
    z.object({
      type: z.enum(["workspace", "spaceGroup"]),
      action: z.enum(["create", "update", "delete"]),
      entityId: z.string(),
      data: z.record(z.unknown()).optional(),
      version: z.number().int().min(0).default(0),
    }),
  ),
});

export type SyncPushInput = z.infer<typeof SyncPushSchema>;

/**
 * Pull sync request
 */
export const SyncPullSchema = z.object({
  deviceId: z.string().min(1),
  lastSyncAt: z.coerce.date().optional(),
  entityTypes: z
    .array(z.enum(["workspace", "spaceGroup"]))
    .optional()
    .default(["workspace", "spaceGroup"]),
});

export type SyncPullInput = z.infer<typeof SyncPullSchema>;

/**
 * Sync status response
 */
export interface SyncStatus {
  lastSyncAt: Date | null;
  pendingChanges: number;
  conflictsCount: number;
  connectedDevices: number;
}

/**
 * Sync conflict response
 */
export interface SyncConflict {
  entityId: string;
  entityType: "workspace" | "spaceGroup";
  localVersion: number;
  remoteVersion: number;
  localUpdatedAt: Date;
  remoteUpdatedAt: Date;
}

/**
 * Sync push response
 */
export interface SyncPushResponse {
  accepted: string[];
  rejected: Array<{
    entityId: string;
    reason: string;
  }>;
  conflicts: SyncConflict[];
  serverTimestamp: Date;
}

/**
 * Sync pull response
 */
export interface SyncPullResponse {
  changes: Array<{
    type: "workspace" | "spaceGroup";
    action: "create" | "update" | "delete";
    entityId: string;
    data?: Record<string, unknown>;
    version: number;
    updatedAt: Date;
  }>;
  serverTimestamp: Date;
  hasMore: boolean;
}
