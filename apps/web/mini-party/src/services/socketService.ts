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

class SocketService {
  private socket: Socket | null = null;
  private roomId: string | null = null;

  connect() {
    if (!this.socket) {
      this.socket = ROOMS_URL ? io(ROOMS_URL) : io();
    }
    return this.socket;
  }

  joinRoom(roomId: string, playerName: string, playerColor: string) {
    this.roomId = roomId;
    this.socket?.emit("join-room", { roomId, playerName, playerColor });
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
  }

  getSocketId() {
    return this.socket?.id;
  }
}

export const socketService = new SocketService();
