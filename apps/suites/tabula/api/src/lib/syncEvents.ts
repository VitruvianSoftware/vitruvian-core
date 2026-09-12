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
 * Sync event publishing for REST writes.
 *
 * Every successful REST PUT (create or update) and DELETE of a workspace or
 * space group publishes an event on `sync:updates:${userId}` so SSE clients
 * (GET /api/v1/sync/stream) receive real-time change notifications. Publishing
 * is fire-and-forget: it happens after the transaction commits and must never
 * fail the request.
 */
import { redis } from "./redis";

export type SyncEventEntityType = "workspace" | "spaceGroup";
export type SyncEventAction = "save" | "delete";

export interface SyncEvent {
  type: SyncEventEntityType;
  action: SyncEventAction;
  entityId: string;
  version?: number;
  updatedAt: string;
  fromDevice: string;
}

interface SyncEventLogger {
  error: (obj: unknown, msg?: string) => void;
}

/**
 * Publish a sync event to all of the user's connected devices.
 * Fire-and-forget: errors are logged, never thrown.
 */
export function publishSyncEvent(
  userId: string,
  event: SyncEvent,
  logger?: SyncEventLogger,
): void {
  const channel = `sync:updates:${userId}`;
  redis.publish(channel, JSON.stringify(event)).catch((error: unknown) => {
    logger?.error(
      { err: error, channel, event },
      "Failed to publish sync event",
    );
  });
}
