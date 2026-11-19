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

import type { Server as HttpServer } from "http";
import { Server } from "socket.io";

export const MAX_PLAYERS = 4;

export interface RoomPlayer {
  id: number;
  socketId: string;
  name: string;
  color: string;
}

interface Room {
  players: RoomPlayer[];
}

// The lowest seat number nobody in the room holds. Seats are reused after a
// player leaves, so two players can never share an id.
export function nextFreeSeat(players: RoomPlayer[]): number {
  const taken = new Set(players.map((p) => p.id));
  let seat = 0;
  while (taken.has(seat)) seat++;
  return seat;
}

// Attaches the multiplayer relay to an HTTP server. Rooms live in memory: they
// exist only while at least one player is connected to them.
export function attachGameServer(httpServer: HttpServer) {
  const io = new Server(httpServer);
  const rooms = new Map<string, Room>();

  io.on("connection", (socket) => {
    socket.on("join-room", ({ roomId, playerName, playerColor }) => {
      if (typeof roomId !== "string" || roomId.length === 0) return;
      const room = rooms.get(roomId) ?? { players: [] };

      if (room.players.length >= MAX_PLAYERS) {
        socket.emit("error", "Room is full");
        return;
      }

      rooms.set(roomId, room);
      socket.join(roomId);
      room.players.push({
        id: nextFreeSeat(room.players),
        socketId: socket.id,
        name: String(playerName ?? ""),
        color: String(playerColor ?? ""),
      });
      room.players.sort((a, b) => a.id - b.id);

      io.to(roomId).emit("room-update", {
        players: room.players,
        maxPlayers: MAX_PLAYERS,
      });
    });

    socket.on("start-game", ({ roomId, gameIndex }) => {
      io.to(roomId).emit("game-started", { gameIndex });
    });

    socket.on("game-event", ({ roomId, event, data }) => {
      socket
        .to(roomId)
        .emit("remote-event", { event, data, senderId: socket.id });
    });

    socket.on("disconnect", () => {
      for (const [roomId, room] of rooms.entries()) {
        const index = room.players.findIndex((p) => p.socketId === socket.id);
        if (index === -1) continue;
        room.players.splice(index, 1);
        if (room.players.length === 0) {
          rooms.delete(roomId);
        } else {
          io.to(roomId).emit("room-update", {
            players: room.players,
            maxPlayers: MAX_PLAYERS,
          });
        }
      }
    });
  });

  return { io, rooms };
}
