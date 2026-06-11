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

import { WindowOwnershipRecord } from "./windowOwnership";

/**
 * Message types for cross-window communication
 */
export type SyncMessage =
  | {
      type: "CLAIM_WORKSPACE";
      workspaceId: string;
      windowId: number;
      tabId: number;
      timestamp: number;
    }
  | {
      type: "RELEASE_WORKSPACE";
      workspaceId: string;
      windowId: number;
      timestamp: number;
    }
  | { type: "PING"; windowId: number }
  | { type: "PONG"; windowId: number; ownerships: WindowOwnershipRecord[] };

type MessageCallback = (message: SyncMessage) => void;

/**
 * Service for instant (<10ms) communication between extension windows using BroadcastChannel.
 * This bypasses the slow polling required by chrome.storage.
 */
class CrossWindowSyncService {
  private channel: BroadcastChannel | null = null;

  private listeners: Set<MessageCallback> = new Set();

  private readonly CHANNEL_NAME = "tabula_sync_channel";

  constructor() {
    this.initChannel();
  }

  private initChannel() {
    if (typeof BroadcastChannel !== "undefined") {
      try {
        this.channel = new BroadcastChannel(this.CHANNEL_NAME);
        this.channel.onmessage = this.handleMessage.bind(this);
        // eslint-disable-next-line no-console
        console.log("[CrossWindowSync] Channel initialized");
      } catch (e) {
        console.error("[CrossWindowSync] Failed to init BroadcastChannel:", e);
      }
    } else {
      console.warn("[CrossWindowSync] BroadcastChannel not supported");
    }
  }

  private handleMessage(event: MessageEvent<SyncMessage>) {
    // console.log('[CrossWindowSync] Received:', event.data);
    this.listeners.forEach((listener) => listener(event.data));
  }

  public subscribe(callback: MessageCallback): () => void {
    this.listeners.add(callback);
    return () => {
      this.listeners.delete(callback);
    };
  }

  public broadcastClaim(workspaceId: string, windowId: number, tabId: number) {
    this.postMessage({
      type: "CLAIM_WORKSPACE",
      workspaceId,
      windowId,
      tabId,
      timestamp: Date.now(),
    });
  }

  public broadcastRelease(workspaceId: string, windowId: number) {
    this.postMessage({
      type: "RELEASE_WORKSPACE",
      workspaceId,
      windowId,
      timestamp: Date.now(),
    });
  }

  public broadcastPing(windowId: number) {
    this.postMessage({
      type: "PING",
      windowId,
    });
  }

  public broadcastPong(windowId: number, ownerships: WindowOwnershipRecord[]) {
    this.postMessage({
      type: "PONG",
      windowId,
      ownerships,
    });
  }

  private postMessage(message: SyncMessage) {
    if (this.channel) {
      try {
        this.channel.postMessage(message);
      } catch (e) {
        console.error("[CrossWindowSync] Send failed:", e);
      }
    }
  }
}

export const crossWindowSync = new CrossWindowSyncService();
