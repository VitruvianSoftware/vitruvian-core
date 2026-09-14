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
 * Sync Store - Zustand store for sync state
 * Provides reactive sync status to UI components
 */

import { create } from "zustand";
import { SyncService, SyncState } from "../services/sync";

interface SyncStore extends SyncState {
  // Actions
  initialize: () => Promise<void>;
  retrySync: () => Promise<void>;
  /** Drop operations that exhausted their retries (poison-op escape hatch) */
  discardFailed: () => Promise<void>;
}

export const useSyncStore = create<SyncStore>((set) => ({
  // Initial state
  status: "idle",
  pendingCount: 0,
  lastSyncAt: null,
  lastError: null,
  isOnline:
    typeof navigator !== "undefined"
      ? navigator.onLine
      : /* istanbul ignore next */ true,

  // Initialize and subscribe to SyncService
  initialize: async () => {
    await SyncService.initialize();

    // Subscribe to state changes
    SyncService.subscribe((state: SyncState) => {
      set({
        status: state.status,
        pendingCount: state.pendingCount,
        lastSyncAt: state.lastSyncAt,
        lastError: state.lastError,
        isOnline: state.isOnline,
      });
    });
  },

  // Manual retry action
  retrySync: async () => {
    await SyncService.retryAll();
  },

  discardFailed: async () => {
    await SyncService.dropFailedOperations();
  },
}));
