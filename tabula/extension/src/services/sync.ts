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
 * SyncService - Robust sync with retry queue and state management
 *
 * Features:
 * - Persistent operation queue shared safely across extension contexts
 *   (multiple dashboard windows, popup, background worker)
 * - Exponential backoff retry (1s, 2s, 4s, 8s, max 30s)
 * - Max 5 retries per operation; exhausted ops parked until manual retry
 * - Optimistic-concurrency handling (409 conflict / 410 gone / 404 delete)
 * - Online/offline detection
 * - Sync state management
 *
 * Concurrency model:
 * - 'tabula_sync_queue_lock' guards every read-modify-write of the persisted
 *   queue. It is held only for storage I/O, never across network requests.
 * - 'tabula_sync_process_lock' is a cross-context single-flight guard so only
 *   one context drains the queue at a time (acquired with ifAvailable).
 * - Every queue mutation reloads the queue from storage first; in-memory
 *   copies are caches, never sources of truth.
 */

import { ApiService } from "./api";
import { ApiError, ConflictRetryError } from "./errors";
import { AuthService } from "./auth";
import { StorageService } from "./storage";
import { getDeviceId } from "./deviceId";
import type { Workspace, SpaceGroup } from "../types";

// ============================================
// TYPES
// ============================================

export type SyncOperationType = "workspace" | "spaceGroup";
export type SyncOperationAction = "save" | "delete";

export interface SyncOperationMeta {
  /** 'tabSync' saves renew the server-side active-device lease */
  source?: "tabSync" | "user";
  /** Explicitly claim the active-device lease (user switched to this workspace) */
  claimActiveDevice?: boolean;
}

export interface SyncOperation {
  id: string;
  type: SyncOperationType;
  action: SyncOperationAction;
  entityId: string;
  data?: Workspace | SpaceGroup;
  timestamp: number;
  retries: number;
  lastError?: string;
  nextRetryAt?: number;
  meta?: SyncOperationMeta;
}

export type SyncStatus = "idle" | "syncing" | "error" | "offline";

export interface SyncState {
  status: SyncStatus;
  pendingCount: number;
  lastSyncAt: number | null;
  lastError: string | null;
  isOnline: boolean;
}

// ============================================
// CONSTANTS
// ============================================

const QUEUE_STORAGE_KEY = "tabula_sync_queue";
const QUEUE_LOCK_NAME = "tabula_sync_queue_lock";
const PROCESS_LOCK_NAME = "tabula_sync_process_lock";
// Must match the lock used by WorkspaceService for local entity storage
const WORKSPACE_LOCK_NAME = "tabula_workspace_lock";
const MAX_RETRIES = 5;
const BASE_RETRY_DELAY_MS = 1000; // 1 second
const MAX_RETRY_DELAY_MS = 30000; // 30 seconds
const PERIODIC_SYNC_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes
const SSE_RECONNECT_DELAY_MS = 5000; // 5 seconds

// Configurable via environment variables injected by Webpack
const { API_URL } = process.env;

// ============================================
// STATE LISTENERS
// ============================================

type StateListener = (state: SyncState) => void;
const stateListeners: Set<StateListener> = new Set();

// ============================================
// SYNC SERVICE
// ============================================

export class SyncService {
  /** In-memory cache of the persisted queue. Never authoritative. */
  private static queue: SyncOperation[] = [];

  private static state: SyncState = {
    status: "idle",
    pendingCount: 0,
    lastSyncAt: null,
    lastError: null,
    isOnline: typeof navigator !== "undefined" ? navigator.onLine : true,
  };

  private static isProcessing = false;

  private static periodicSyncTimer: ReturnType<typeof setInterval> | null =
    null;

  private static retryTimer: ReturnType<typeof setTimeout> | null = null;

  private static initialized = false;

  // SSE connection for real-time notifications
  private static sseEventSource: EventSource | null = null;

  private static sseReconnectTimer: ReturnType<typeof setTimeout> | null = null;

  // SSE event listeners - for notifying UI of remote changes
  private static sseListeners: Set<
    (event: { type: string; data: unknown }) => void
  > = new Set();

  // ============================================
  // INITIALIZATION
  // ============================================

  /**
   * Initialize the sync service - call once on app startup
   */
  static async initialize(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;

    // Load persisted queue
    await this.loadQueue();

    // Set up online/offline listeners
    if (typeof window !== "undefined") {
      window.addEventListener("online", () =>
        this.handleOnlineStatusChange(true),
      );
      window.addEventListener("offline", () =>
        this.handleOnlineStatusChange(false),
      );
    }

    // Keep the in-memory cache (and UI counts) fresh when another context
    // mutates the persisted queue. Read-only: never re-save from here.
    if (typeof chrome !== "undefined" && chrome.storage?.onChanged) {
      chrome.storage.onChanged.addListener((changes) => {
        const change = changes[QUEUE_STORAGE_KEY];
        if (change) {
          this.queue = (change.newValue as SyncOperation[]) || [];
          this.updateState({ pendingCount: this.queue.length });
        }
      });
    }

    // Start periodic sync
    this.startPeriodicSync();

    // Initial sync if online and logged in
    if (this.state.isOnline && (await AuthService.getToken())) {
      this.processQueue();
    }

    // eslint-disable-next-line no-console
    console.log(
      "[SyncService] Initialized with",
      this.queue.length,
      "pending operations",
    );
  }

  // ============================================
  // LOCKING PRIMITIVES
  // ============================================

  /**
   * Guard queue state read-modify-write. Held only for storage I/O.
   */
  private static async withQueueLock<T>(
    callback: () => Promise<T>,
  ): Promise<T> {
    if (typeof navigator !== "undefined" && "locks" in navigator) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return (navigator as any).locks.request(QUEUE_LOCK_NAME, callback);
    }
    return callback();
  }

  /**
   * Cross-context single-flight guard for queue draining. Returns false when
   * another context already holds the lock (its drain will pick up our ops).
   */
  private static async withProcessLock(
    callback: () => Promise<void>,
  ): Promise<void> {
    if (typeof navigator !== "undefined" && "locks" in navigator) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return (navigator as any).locks.request(
        PROCESS_LOCK_NAME,
        { ifAvailable: true },
        async (lock: unknown) => {
          if (!lock) return; // someone else is draining
          await callback();
        },
      );
    }
    return callback();
  }

  /**
   * Guard local entity storage writes (same lock as WorkspaceService).
   */
  private static async withWorkspaceLock<T>(
    callback: () => Promise<T>,
  ): Promise<T> {
    if (typeof navigator !== "undefined" && "locks" in navigator) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return (navigator as any).locks.request(WORKSPACE_LOCK_NAME, callback);
    }
    return callback();
  }

  // ============================================
  // QUEUE MANAGEMENT
  // ============================================

  /**
   * Add an operation to the sync queue.
   *
   * The op is durably persisted before this resolves. Callers should await.
   */
  static async enqueue(operation: {
    type: SyncOperationType;
    action: SyncOperationAction;
    entityId: string;
    data?: Workspace | SpaceGroup;
    meta?: SyncOperationMeta;
  }): Promise<void> {
    await this.withQueueLock(async () => {
      // Re-read so we never clobber ops enqueued by other contexts
      await this.loadQueue();

      const op: SyncOperation = {
        id: `sync_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        type: operation.type,
        action: operation.action,
        entityId: operation.entityId,
        data: operation.data,
        timestamp: Date.now(),
        retries: 0,
        meta: operation.meta,
      };

      const existingIndex = this.queue.findIndex(
        (q) => q.entityId === op.entityId && q.type === op.type,
      );

      if (existingIndex === -1) {
        this.queue.push(op);
      } else {
        const existing = this.queue[existingIndex];
        if (existing.action === op.action) {
          // Same action: latest state wins, but keep the claim flag if any
          // pending op had it (a claim must not be lost to a later tab sync)
          if (existing.meta?.claimActiveDevice) {
            op.meta = { ...op.meta, claimActiveDevice: true };
          }
          this.queue[existingIndex] = op;
        } else if (existing.action === "save" && op.action === "delete") {
          // Delete supersedes a pending save (delete is idempotent remotely)
          this.queue[existingIndex] = op;
        } else {
          // delete -> save: keep both in order so the delete still executes
          this.queue.push(op);
        }
      }

      await this.saveQueue();
      this.updateState({ pendingCount: this.queue.length });
    });

    // Try to process immediately if online (outside the queue lock)
    if (this.state.isOnline && (await AuthService.getToken())) {
      this.processQueue();
    }
  }

  /**
   * Entity ids that currently have a pending `save` queued for the given type.
   *
   * The pull-merge uses this to protect un-acked local edits: a workspace with
   * a queued save must NOT be overwritten by a remote copy that only looks
   * "newer" because the server auto-stamps updated_at on write (Prisma
   * `@updatedAt`). Its queued PUT is the source of truth and will converge the
   * server. Reads the authoritative persisted queue under the queue lock —
   * callers may hold the workspace lock (workspace -> queue ordering is
   * allowed; never the reverse).
   */
  static async getPendingSaveIds(
    type: SyncOperationType,
  ): Promise<Set<string>> {
    return this.withQueueLock(async () => {
      await this.loadQueue();
      return new Set(
        this.queue
          .filter((op) => op.type === type && op.action === "save")
          .map((op) => op.entityId),
      );
    });
  }

  /**
   * Drain the sync queue, one operation at a time.
   *
   * The queue lock is held only around queue reads/writes — never across
   * network I/O — so other contexts can keep enqueueing while we drain.
   */
  static async processQueue(): Promise<void> {
    if (!this.state.isOnline) {
      this.updateState({ status: "offline" });
      return;
    }

    const token = await AuthService.getToken();
    if (!token) {
      // Not logged in, can't sync
      return;
    }

    return this.withProcessLock(async () => {
      if (this.isProcessing) return;
      this.isProcessing = true;
      this.updateState({ status: "syncing" });

      try {
        // Drain loop: pick next eligible op, execute, persist outcome.
        // eslint-disable-next-line no-constant-condition
        while (true) {
          // eslint-disable-next-line no-await-in-loop
          const operation = await this.withQueueLock(async () => {
            await this.loadQueue();
            const now = Date.now();
            return this.queue.find(
              (op) =>
                op.retries < MAX_RETRIES &&
                (!op.nextRetryAt || op.nextRetryAt <= now),
            );
          });

          if (!operation) break;

          let outcome: "ok" | "drop" | "conflict-retry" | "error";
          let errorMessage = "";
          try {
            // eslint-disable-next-line no-await-in-loop
            outcome = await this.executeOperation(operation);
          } catch (error) {
            if (error instanceof ConflictRetryError) {
              outcome = "conflict-retry";
            } else {
              outcome = "error";
            }
            errorMessage =
              error instanceof Error ? error.message : "Unknown error";
          }

          // eslint-disable-next-line no-await-in-loop
          await this.withQueueLock(async () => {
            await this.loadQueue();
            const queueIndex = this.queue.findIndex(
              (q) => q.id === operation.id,
            );
            // Op may have been replaced by a newer enqueue — leave it alone
            if (queueIndex === -1) return;

            if (outcome === "ok" || outcome === "drop") {
              this.queue.splice(queueIndex, 1);
            } else {
              const newRetries = this.queue[queueIndex].retries + 1;
              const delay =
                newRetries < MAX_RETRIES
                  ? Math.min(
                      BASE_RETRY_DELAY_MS * 2 ** (newRetries - 1),
                      MAX_RETRY_DELAY_MS,
                    )
                  : undefined;

              let refreshedData = this.queue[queueIndex].data;
              if (outcome === "conflict-retry") {
                // Local won the conflict: refresh the payload (now carrying
                // the new server version) from storage before the retry
                refreshedData = await this.refreshOperationData(
                  this.queue[queueIndex],
                );
              }

              this.queue[queueIndex] = {
                ...this.queue[queueIndex],
                data: refreshedData,
                lastError: errorMessage,
                retries: newRetries,
                nextRetryAt:
                  delay !== undefined ? Date.now() + delay : undefined,
              };

              if (newRetries >= MAX_RETRIES) {
                console.error(
                  `[SyncService] Operation ${operation.id} failed after ${MAX_RETRIES} retries:`,
                  errorMessage,
                );
              } else {
                // eslint-disable-next-line no-console
                console.log(
                  `[SyncService] Operation ${operation.id} failed, retry ${newRetries}/${MAX_RETRIES} in ${delay}ms`,
                );
              }
            }
            await this.saveQueue();
            this.updateState({ pendingCount: this.queue.length });
          });
        }
      } finally {
        this.isProcessing = false;
      }

      // Compute final state from the authoritative queue
      await this.withQueueLock(() => this.loadQueue());
      const failedOps = this.queue.filter((op) => op.retries >= MAX_RETRIES);
      const hasPending = this.queue.length > 0;

      if (failedOps.length > 0) {
        this.updateState({
          status: "error",
          pendingCount: this.queue.length,
          lastSyncAt: Date.now(),
          lastError: failedOps[0].lastError || "Sync failed",
        });
      } else if (hasPending) {
        this.updateState({
          status: "idle",
          pendingCount: this.queue.length,
        });
      } else {
        this.updateState({
          status: "idle",
          pendingCount: 0,
          lastSyncAt: Date.now(),
          lastError: null,
        });
      }

      // Schedule the next attempt for ops backing off (works in both the
      // pending and error cases — healthy ops must not be starved by an
      // exhausted one)
      this.scheduleRetry();
    });
  }

  /**
   * Execute a single sync operation.
   *
   * Returns 'ok' on success, 'drop' when the op is obsolete (entity gone,
   * remote already newer, delete of a missing entity). Throws
   * ConflictRetryError when the local copy won a version conflict and the op
   * should be retried with refreshed data.
   */
  private static async executeOperation(
    operation: SyncOperation,
  ): Promise<"ok" | "drop"> {
    if (operation.type === "workspace") {
      if (operation.action === "save" && operation.data) {
        return this.executeWorkspaceSave(operation);
      }
      if (operation.action === "delete") {
        try {
          await ApiService.deleteWorkspace(operation.entityId);
        } catch (error) {
          // Deleting something that's already gone is success
          if (error instanceof ApiError && error.status === 404) return "drop";
          throw error;
        }
        return "ok";
      }
    } else if (operation.type === "spaceGroup") {
      if (operation.action === "save" && operation.data) {
        return this.executeSpaceGroupSave(operation);
      }
      if (operation.action === "delete") {
        try {
          await ApiService.deleteSpaceGroup(operation.entityId);
        } catch (error) {
          if (error instanceof ApiError && error.status === 404) return "drop";
          throw error;
        }
        return "ok";
      }
    }
    return "ok";
  }

  private static async executeWorkspaceSave(
    operation: SyncOperation,
  ): Promise<"ok" | "drop"> {
    // Clone before sanitizing — never mutate the queued payload
    const workspace = { ...(operation.data as Workspace) };
    // Sanitize data: Ensure tab IDs are numbers (sync issue fix)
    // Some UI operations might have left them as strings.
    // Also drop tabs without a URL (mid-navigation snapshots) — one invalid
    // tab must not fail the whole workspace PUT.
    if (workspace.tabs) {
      workspace.tabs = workspace.tabs
        .filter((tab) => !!tab.url)
        .map((tab) => ({
          ...tab,
          id: typeof tab.id === "string" ? parseInt(tab.id, 10) : tab.id,
        }));
    }

    try {
      const saved = await ApiService.saveWorkspace(workspace, {
        tabSync: operation.meta?.source === "tabSync",
        claimActiveDevice: operation.meta?.claimActiveDevice,
      });
      // Record the new server version locally (content untouched)
      await this.applyServerWorkspaceMeta(operation.entityId, saved);
      return "ok";
    } catch (error) {
      if (error instanceof ApiError && error.status === 410) {
        // Entity was deleted on another device — remove our local copy
        await this.removeLocalWorkspace(operation.entityId);
        return "drop";
      }
      if (error instanceof ApiError && error.status === 409) {
        const serverWs = error.data as Workspace | undefined;
        if (!serverWs) throw error;
        const local = await StorageService.getWorkspaceById(operation.entityId);
        const localTime = new Date(
          local?.updatedAt || workspace.updatedAt || 0,
        ).getTime();
        const serverTime = new Date(serverWs.updatedAt || 0).getTime();
        if (local && localTime >= serverTime) {
          // Local wins: adopt the server version number, retry with it
          await this.applyServerWorkspaceMeta(operation.entityId, serverWs);
          throw new ConflictRetryError(
            `Version conflict on ${operation.entityId}; local copy is newer, retrying`,
          );
        }
        // Server wins: adopt the remote state locally, drop the stale op
        await this.adoptServerWorkspace(serverWs);
        return "drop";
      }
      throw error;
    }
  }

  private static async executeSpaceGroupSave(
    operation: SyncOperation,
  ): Promise<"ok" | "drop"> {
    const group = operation.data as SpaceGroup;
    try {
      const saved = await ApiService.saveSpaceGroup(group);
      await this.applyServerSpaceGroupMeta(operation.entityId, saved);
      return "ok";
    } catch (error) {
      if (error instanceof ApiError && error.status === 410) {
        await this.removeLocalSpaceGroup(operation.entityId);
        return "drop";
      }
      if (error instanceof ApiError && error.status === 409) {
        const serverGroup = error.data as SpaceGroup | undefined;
        if (!serverGroup) throw error;
        const groups = await StorageService.getSpaceGroups();
        const local = groups.find((g) => g.id === operation.entityId);
        const localTime = new Date(
          local?.updatedAt || group.updatedAt || 0,
        ).getTime();
        const serverTime = new Date(serverGroup.updatedAt || 0).getTime();
        if (local && localTime >= serverTime) {
          await this.applyServerSpaceGroupMeta(operation.entityId, serverGroup);
          throw new ConflictRetryError(
            `Version conflict on ${operation.entityId}; local copy is newer, retrying`,
          );
        }
        await this.adoptServerSpaceGroup(serverGroup);
        return "drop";
      }
      throw error;
    }
  }

  // ============================================
  // LOCAL STORAGE RECONCILIATION
  // ============================================

  /** Update only sync metadata (version/lease) on the local copy */
  private static async applyServerWorkspaceMeta(
    workspaceId: string,
    server: Workspace,
  ): Promise<void> {
    await this.withWorkspaceLock(async () => {
      const workspaces = await StorageService.getWorkspaces();
      const index = workspaces.findIndex((w) => w.id === workspaceId);
      if (index === -1) return;
      workspaces[index] = {
        ...workspaces[index],
        version: server.version,
        activeDeviceId: server.activeDeviceId,
        activeDeviceSeenAt: server.activeDeviceSeenAt,
      };
      await StorageService.saveWorkspaces(workspaces);
    });
  }

  /** Replace the local copy with the server's (server won the conflict) */
  private static async adoptServerWorkspace(server: Workspace): Promise<void> {
    await this.withWorkspaceLock(async () => {
      const workspaces = await StorageService.getWorkspaces();
      const index = workspaces.findIndex((w) => w.id === server.id);
      if (index === -1) {
        workspaces.push(server);
      } else {
        workspaces[index] = server;
      }
      await StorageService.saveWorkspaces(workspaces);
    });
  }

  private static async removeLocalWorkspace(
    workspaceId: string,
  ): Promise<void> {
    await this.withWorkspaceLock(async () => {
      const workspaces = await StorageService.getWorkspaces();
      const filtered = workspaces.filter((w) => w.id !== workspaceId);
      if (filtered.length !== workspaces.length) {
        await StorageService.saveWorkspaces(filtered);
      }
      const activeId = await StorageService.getActiveWorkspaceId();
      if (activeId === workspaceId) {
        await StorageService.setActiveWorkspaceId(null);
      }
    });
  }

  private static async applyServerSpaceGroupMeta(
    groupId: string,
    server: SpaceGroup,
  ): Promise<void> {
    await this.withWorkspaceLock(async () => {
      const groups = await StorageService.getSpaceGroups();
      const index = groups.findIndex((g) => g.id === groupId);
      if (index === -1) return;
      groups[index] = { ...groups[index], version: server.version };
      await StorageService.saveSpaceGroups(groups);
    });
  }

  private static async adoptServerSpaceGroup(
    server: SpaceGroup,
  ): Promise<void> {
    await this.withWorkspaceLock(async () => {
      const groups = await StorageService.getSpaceGroups();
      const index = groups.findIndex((g) => g.id === server.id);
      if (index === -1) {
        groups.push(server);
      } else {
        groups[index] = server;
      }
      await StorageService.saveSpaceGroups(groups);
    });
  }

  private static async removeLocalSpaceGroup(groupId: string): Promise<void> {
    await this.withWorkspaceLock(async () => {
      const groups = await StorageService.getSpaceGroups();
      const filtered = groups.filter((g) => g.id !== groupId);
      if (filtered.length !== groups.length) {
        await StorageService.saveSpaceGroups(filtered);
      }
    });
  }

  /** Re-read the freshest local copy of an op's entity (post-conflict) */
  private static async refreshOperationData(
    operation: SyncOperation,
  ): Promise<Workspace | SpaceGroup | undefined> {
    if (operation.type === "workspace") {
      const ws = await StorageService.getWorkspaceById(operation.entityId);
      return ws || operation.data;
    }
    const groups = await StorageService.getSpaceGroups();
    return groups.find((g) => g.id === operation.entityId) || operation.data;
  }

  // ============================================
  // RETRY SCHEDULING
  // ============================================

  /**
   * Schedule the next processQueue run for ops that are backing off.
   */
  private static scheduleRetry(): void {
    const nextRetry = this.queue
      .filter((op) => op.nextRetryAt && op.retries < MAX_RETRIES)
      .map((op) => op.nextRetryAt!)
      .sort((a, b) => a - b)[0];

    if (nextRetry) {
      const delay = Math.max(0, nextRetry - Date.now());
      if (this.retryTimer) clearTimeout(this.retryTimer);
      this.retryTimer = setTimeout(() => {
        this.retryTimer = null;
        this.processQueue();
      }, delay);
    }
  }

  /**
   * Manually retry all failed operations
   */
  static async retryAll(): Promise<void> {
    await this.withQueueLock(async () => {
      await this.loadQueue();
      this.queue = this.queue.map((op) => {
        if (op.retries >= MAX_RETRIES) {
          return {
            ...op,
            retries: 0,
            nextRetryAt: undefined,
            lastError: undefined,
          };
        }
        return op;
      });
      await this.saveQueue();
    });
    this.updateState({ status: "idle", lastError: null });
    this.processQueue();
  }

  /**
   * Drop operations that exhausted their retries (user escape hatch for
   * poison ops — e.g. a payload the server permanently rejects).
   */
  static async dropFailedOperations(): Promise<void> {
    await this.withQueueLock(async () => {
      await this.loadQueue();
      this.queue = this.queue.filter((op) => op.retries < MAX_RETRIES);
      await this.saveQueue();
      this.updateState({
        pendingCount: this.queue.length,
        status: "idle",
        lastError: null,
      });
    });
  }

  // ============================================
  // PERSISTENCE
  // ============================================

  private static async loadQueue(): Promise<void> {
    try {
      const result = await chrome.storage.local.get(QUEUE_STORAGE_KEY);
      this.queue = result[QUEUE_STORAGE_KEY] || [];
      this.updateState({ pendingCount: this.queue.length });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[SyncService] Failed to load queue:", error);
      this.queue = [];
    }
  }

  private static async saveQueue(): Promise<void> {
    try {
      await chrome.storage.local.set({ [QUEUE_STORAGE_KEY]: this.queue });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[SyncService] Failed to save queue:", error);
    }
  }

  // ============================================
  // STATE MANAGEMENT
  // ============================================

  private static updateState(updates: Partial<SyncState>): void {
    this.state = { ...this.state, ...updates };
    this.notifyListeners();
  }

  private static notifyListeners(): void {
    stateListeners.forEach((listener) => listener(this.state));
  }

  /**
   * Subscribe to state changes
   */
  static subscribe(listener: StateListener): () => void {
    stateListeners.add(listener);
    // Immediately call with current state
    listener(this.state);
    // Return unsubscribe function
    return () => stateListeners.delete(listener);
  }

  /**
   * Get current sync state
   */
  static getState(): SyncState {
    return { ...this.state };
  }

  // ============================================
  // ONLINE/OFFLINE HANDLING
  // ============================================

  private static handleOnlineStatusChange(isOnline: boolean): void {
    // eslint-disable-next-line no-console
    console.log("[SyncService] Online status changed:", isOnline);
    this.updateState({
      isOnline,
      status: isOnline ? "idle" : "offline",
    });

    if (isOnline) {
      // Back online: stale backoff timestamps shouldn't delay the flush
      this.withQueueLock(async () => {
        await this.loadQueue();
        this.queue = this.queue.map((op) =>
          op.retries < MAX_RETRIES ? { ...op, nextRetryAt: undefined } : op,
        );
        await this.saveQueue();
      }).then(() => this.processQueue());
    }
  }

  // ============================================
  // PERIODIC SYNC
  // ============================================

  private static startPeriodicSync(): void {
    if (this.periodicSyncTimer) return;

    this.periodicSyncTimer = setInterval(async () => {
      if (this.state.isOnline && (await AuthService.getToken())) {
        // eslint-disable-next-line no-console
        console.log("[SyncService] Periodic sync triggered");
        this.processQueue();
      }
    }, PERIODIC_SYNC_INTERVAL_MS);
  }

  static stopPeriodicSync(): void {
    if (this.periodicSyncTimer) {
      clearInterval(this.periodicSyncTimer);
      this.periodicSyncTimer = null;
    }
  }

  // ============================================
  // SSE REAL-TIME SYNC
  // ============================================

  /**
   * Connect to SSE stream for real-time sync notifications.
   *
   * EventSource cannot send an Authorization header, so the token rides in
   * the query string (the server accepts ?token= for this route only).
   */
  static async connectToSSE(): Promise<void> {
    const token = await AuthService.getToken();
    if (!token || !this.state.isOnline) {
      return;
    }
    if (typeof EventSource === "undefined") {
      // MV3 service workers have no EventSource; SSE is page-context only
      return;
    }

    // Close existing connection
    this.disconnectSSE();

    try {
      const deviceId = await getDeviceId();
      const url = `${API_URL}/sync/stream?deviceId=${encodeURIComponent(
        deviceId,
      )}&token=${encodeURIComponent(token)}`;
      this.sseEventSource = new EventSource(url);

      this.sseEventSource.onopen = () => {
        // eslint-disable-next-line no-console
        console.log("[SyncService] SSE connected");
      };

      // Handle connected event
      this.sseEventSource.addEventListener("connected", (event) => {
        // eslint-disable-next-line no-console
        console.log(
          "[SyncService] SSE received connected event:",
          (event as MessageEvent).data,
        );
      });

      // Remote change notifications (workspace/spaceGroup save/delete)
      this.sseEventSource.addEventListener("change", (event) => {
        try {
          const data = JSON.parse((event as MessageEvent).data);
          // Server heartbeats arrive on the same event name — not a change
          if (data?.type === "heartbeat") return;
          // Suppress echo of this device's own writes
          if (data?.fromDevice && data.fromDevice === deviceId) return;
          this.notifySSEListeners({ type: "change", data });
        } catch (err) {
          console.error("[SyncService] Failed to parse change event:", err);
        }
      });

      // Handle errors
      this.sseEventSource.onerror = (error) => {
        console.error("[SyncService] SSE error:", error);
        this.disconnectSSE();
        this.scheduleSSEReconnect();
      };
    } catch (error) {
      console.error("[SyncService] Failed to connect to SSE:", error);
      this.scheduleSSEReconnect();
    }
  }

  /**
   * Disconnect from SSE stream
   */
  static disconnectSSE(): void {
    if (this.sseEventSource) {
      this.sseEventSource.close();
      this.sseEventSource = null;
    }
    if (this.sseReconnectTimer) {
      clearTimeout(this.sseReconnectTimer);
      this.sseReconnectTimer = null;
    }
  }

  /**
   * Schedule SSE reconnection
   */
  private static scheduleSSEReconnect(): void {
    if (this.sseReconnectTimer) return;
    // Only reconnect while someone is listening
    if (this.sseListeners.size === 0) return;
    this.sseReconnectTimer = setTimeout(() => {
      this.sseReconnectTimer = null;
      this.connectToSSE();
    }, SSE_RECONNECT_DELAY_MS);
  }

  /**
   * Subscribe to SSE events (for UI components)
   */
  static subscribeToSSE(
    listener: (event: { type: string; data: unknown }) => void,
  ): () => void {
    this.sseListeners.add(listener);
    // Start SSE connection if first listener
    if (this.sseListeners.size === 1) {
      this.connectToSSE();
    }
    // Return unsubscribe function
    return () => {
      this.sseListeners.delete(listener);
      // Disconnect if no more listeners
      if (this.sseListeners.size === 0) {
        this.disconnectSSE();
      }
    };
  }

  /**
   * Notify all SSE listeners of an event
   */
  private static notifySSEListeners(event: {
    type: string;
    data: unknown;
  }): void {
    this.sseListeners.forEach((listener) => listener(event));
  }

  // ============================================
  // UTILITIES
  // ============================================

  /**
   * Get pending operations count
   */
  static getPendingCount(): number {
    return this.queue.length;
  }

  /**
   * Check if there are failed operations
   */
  static hasFailedOperations(): boolean {
    return this.queue.some((op) => op.retries >= MAX_RETRIES);
  }

  /**
   * Remove any pending operations for the given entities (used by backup
   * restore so stale pre-restore saves can't clobber restored state).
   */
  static async dropOperationsFor(entityIds: string[]): Promise<void> {
    const ids = new Set(entityIds);
    await this.withQueueLock(async () => {
      await this.loadQueue();
      this.queue = this.queue.filter((op) => !ids.has(op.entityId));
      await this.saveQueue();
      this.updateState({ pendingCount: this.queue.length });
    });
  }

  /**
   * Clear all pending operations (use with caution)
   */
  static async clearQueue(): Promise<void> {
    return this.withQueueLock(async () => {
      this.queue = [];
      await this.saveQueue();
      this.updateState({ pendingCount: 0, status: "idle", lastError: null });
    });
  }
}
