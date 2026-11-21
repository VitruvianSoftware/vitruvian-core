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

import { io, Socket } from "socket.io-client";
import { ROOMS_URL } from "../features";

// A random seat key for this browser tab. The rooms server holds a dropped
// player's seat for a short while, and this key is how the same tab claims it
// back after reconnecting. It lives in sessionStorage so a page reload keeps
// the seat too, and falls back to memory where storage is blocked.
const KEY_STORAGE = "mini-party-player-key";

function newKey(): string {
  const bytes = new Uint8Array(18);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function playerKey(storage: Storage | undefined = safeSession()) {
  try {
    const saved = storage?.getItem(KEY_STORAGE);
    if (saved) return saved;
    const key = newKey();
    storage?.setItem(KEY_STORAGE, key);
    return key;
  } catch {
    return newKey();
  }
}

function safeSession(): Storage | undefined {
  try {
    return typeof sessionStorage === "undefined" ? undefined : sessionStorage;
  } catch {
    return undefined;
  }
}

interface Join {
  roomId: string;
  playerName: string;
  playerColor: string;
  playerKey: string;
}

export class SocketService {
  private socket: Socket | null = null;
  private roomId: string | null = null;
  private join: Join | null = null;
  private readonly key: string;

  constructor(
    private readonly url: string | undefined = ROOMS_URL,
    key: string = playerKey(),
  ) {
    this.key = key;
  }

  connect() {
    if (!this.socket) {
      const socket = this.url ? io(this.url) : io();
      // socket.io reconnects on its own after a drop, but as a new socket
      // the server has not seated. Ask for the seat again on every
      // connection; the server ignores a repeat from a socket already seated.
      socket.on("connect", () => {
        if (this.join) socket.emit("join-room", this.join);
      });
      this.socket = socket;
    }
    return this.socket;
  }

  joinRoom(roomId: string, playerName: string, playerColor: string) {
    this.roomId = roomId;
    this.join = { roomId, playerName, playerColor, playerKey: this.key };
    // Sent now if connected; otherwise the "connect" handler sends it.
    if (this.socket?.connected) this.socket.emit("join-room", this.join);
  }

  // Calls back with true when connected and false when the connection drops,
  // so the page can say it is reconnecting. Returns a function that stops.
  onConnectionChange(callback: (connected: boolean) => void) {
    const up = () => callback(true);
    const down = () => callback(false);
    this.socket?.on("connect", up);
    this.socket?.on("disconnect", down);
    return () => {
      this.socket?.off("connect", up);
      this.socket?.off("disconnect", down);
    };
  }
  startGame(gameIndex: number) {
    if (this.roomId) {
      this.socket?.emit("start-game", { roomId: this.roomId, gameIndex });
    }
  }

  sendEvent(event: string, data: any) {
    if (this.roomId) {
      this.socket?.emit("game-event", { roomId: this.roomId, event, data });
    }
  }

  onRoomUpdate(callback: (data: any) => void) {
    this.socket?.on("room-update", callback);
  }

  onGameStarted(callback: (data: any) => void) {
    this.socket?.on("game-started", callback);
  }

  // Returns a function that stops listening, so a game can clean up when it
  // ends instead of leaving its handler attached for every later round.
  onRemoteEvent(callback: (data: any) => void) {
    this.socket?.on("remote-event", callback);
    return () => {
      this.socket?.off("remote-event", callback);
    };
  }

  disconnect() {
    this.socket?.disconnect();
    this.socket = null;
    this.roomId = null;
    this.join = null;
  }

  getSocketId() {
    return this.socket?.id;
  }
}

export const socketService = new SocketService();
