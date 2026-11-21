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
import { Server, type Socket } from "socket.io";
import {
  claimedProtocol,
  MIN_CLIENT_PROTOCOL,
  PROTOCOL,
  VERSION_REFUSED,
  type ServerInfo,
} from "../src/protocol";

export const MAX_PLAYERS = 4;

// Limits for a server open to the internet. Defaults suit a party-game relay
// on one small pod; each can be overridden when attaching.
export interface Limits {
  // Rooms that can exist at once. A join that would create another is refused.
  maxRooms: number;
  // Sockets connected at once. Past this, new connections are dropped.
  maxConnections: number;
  // Largest message a client may send, in bytes.
  maxMessageBytes: number;
  // Events one socket may send per second before the rest are dropped.
  maxEventsPerSecond: number;
  // How long a dropped player's seat is held, in milliseconds. A phone that
  // locks its screen or loses Wi-Fi for a moment reconnects with a new socket;
  // within this window it gets its old seat back instead of being dropped.
  rejoinGraceMs: number;
}

export const DEFAULT_LIMITS: Limits = {
  maxRooms: 500,
  maxConnections: 2000,
  maxMessageBytes: 16 * 1024,
  maxEventsPerSecond: 60,
  rejoinGraceMs: 30_000,
};

export interface GameServerOptions {
  // Web origins allowed to connect from another site, e.g. the GitHub Pages
  // game at https://mini-games.vitruviansoftware.dev. Empty: same origin only.
  allowedOrigins?: string[];
  limits?: Partial<Limits>;
  // The oldest page version to seat; tests raise it to see a refusal.
  minClientProtocol?: number;
}

export interface RoomPlayer {
  id: number;
  socketId: string;
  name: string;
  color: string;
  // False while the player's connection is down and their seat is held.
  connected: boolean;
}

// A seat as the server keeps it. `key` is the secret the player's device
// sends to reclaim the seat after a reconnect; it is never sent to others.
interface Seat extends RoomPlayer {
  key: string | null;
  dropTimer?: ReturnType<typeof setTimeout>;
}

interface Room {
  players: Seat[];
}

// A device's seat key: long enough to be unguessable, short and plain enough
// to store safely.
const PLAYER_KEY = /^[A-Za-z0-9_-]{16,64}$/;

const ROOM_ID = /^[A-Za-z0-9]{1,16}$/;
const MAX_NAME = 24;
const MAX_COLOR = 16;

// The lowest seat number nobody in the room holds. Seats are reused after a
// player leaves, so two players can never share an id.
export function nextFreeSeat(players: Pick<RoomPlayer, "id">[]): number {
  const taken = new Set(players.map((p) => p.id));
  let seat = 0;
  while (taken.has(seat)) seat++;
  return seat;
}

function isSameOrigin(origin: string, host: string | undefined): boolean {
  try {
    return host !== undefined && new URL(origin).host === host;
  } catch {
    return false;
  }
}

// Parses a comma-separated origin list such as ALLOWED_ORIGINS.
export function parseOrigins(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean);
}

// Attaches the multiplayer relay to an HTTP server. Rooms live in memory: they
// exist while at least one player holds a seat in them (a dropped player's
// seat is held for rejoinGraceMs), and a restart ends every game in progress.
export function attachGameServer(
  httpServer: HttpServer,
  options: GameServerOptions = {},
) {
  const limits = { ...DEFAULT_LIMITS, ...options.limits };
  const allowedOrigins = options.allowedOrigins ?? [];
  const io = new Server(httpServer, {
    maxHttpBufferSize: limits.maxMessageBytes,
    cors:
      allowedOrigins.length > 0
        ? { origin: allowedOrigins, methods: ["GET", "POST"] }
        : undefined,
    // socket.io checks the Origin header on every request, websocket
    // upgrades included, so a page on another site cannot connect.
    allowRequest: (req, callback) => {
      const origin = req.headers.origin;
      callback(
        null,
        !origin ||
          isSameOrigin(origin, req.headers.host) ||
          allowedOrigins.includes(origin),
      );
    },
  });
  const info: ServerInfo = {
    protocol: PROTOCOL,
    minClientProtocol: options.minClientProtocol ?? MIN_CLIENT_PROTOCOL,
  };
  // A page too old for this server is refused before it connects. socket.io
  // gives the page this error and does not retry, so it can ask for a reload.
  io.use((socket, next) => {
    if (
      claimedProtocol(socket.handshake.auth?.protocol) >= info.minClientProtocol
    ) {
      next();
      return;
    }
    next(Object.assign(new Error(VERSION_REFUSED), { data: info }));
  });
  const rooms = new Map<string, Room>();
  // The room each socket sits in; a socket is in at most one.
  const roomOf = new Map<string, string>();

  // True while this socket is within its events-per-second budget.
  function rateLimiter() {
    let windowStart = Date.now();
    let count = 0;
    return () => {
      const now = Date.now();
      if (now - windowStart >= 1000) {
        windowStart = now;
        count = 0;
      }
      count++;
      return count <= limits.maxEventsPerSecond;
    };
  }

  function broadcastRoom(roomId: string, room: Room) {
    io.to(roomId).emit("room-update", {
      players: room.players.map(
        ({ id, socketId, name, color, connected }): RoomPlayer => ({
          id,
          socketId,
          name,
          color,
          connected,
        }),
      ),
      maxPlayers: MAX_PLAYERS,
    });
  }

  // Frees a seat for good and closes the room if it was the last one.
  function removeSeat(roomId: string, room: Room, seat: Seat) {
    clearTimeout(seat.dropTimer);
    room.players = room.players.filter((p) => p !== seat);
    if (room.players.length === 0) {
      rooms.delete(roomId);
    } else {
      broadcastRoom(roomId, room);
    }
  }

  // Takes a socket out of its room. A player who chose to leave (`hold`
  // false) loses the seat now; a dropped connection keeps it for the grace
  // window so the same device can come back to it.
  function leave(socket: Socket, hold: boolean) {
    const roomId = roomOf.get(socket.id);
    if (roomId === undefined) return;
    roomOf.delete(socket.id);
    socket.leave(roomId);
    const room = rooms.get(roomId);
    const seat = room?.players.find((p) => p.socketId === socket.id);
    if (!room || !seat) return;
    if (!hold || seat.key === null || limits.rejoinGraceMs <= 0) {
      removeSeat(roomId, room, seat);
      return;
    }
    seat.connected = false;
    seat.dropTimer = setTimeout(
      () => removeSeat(roomId, room, seat),
      limits.rejoinGraceMs,
    );
    seat.dropTimer.unref?.();
    broadcastRoom(roomId, room);
  }

  io.on("connection", (socket) => {
    if (io.engine.clientsCount > limits.maxConnections) {
      socket.emit("error", "Server is full");
      socket.disconnect(true);
      return;
    }
    // Tell the page which version it is talking to, so a page newer than
    // this server can tell the server is behind.
    socket.emit("server-info", info);
    const allowed = rateLimiter();
    socket.use((_packet, next) => {
      if (allowed()) next();
    });

    socket.on("join-room", (payload) => {
      const { roomId, playerName, playerColor, playerKey } = payload ?? {};
      if (typeof roomId !== "string" || !ROOM_ID.test(roomId)) return;
      if (roomOf.get(socket.id) === roomId) return;
      leave(socket, false);
      const key =
        typeof playerKey === "string" && PLAYER_KEY.test(playerKey)
          ? playerKey
          : null;

      // The same device coming back: give it its old seat, id and all.
      const held =
        key === null
          ? undefined
          : rooms.get(roomId)?.players.find((p) => p.key === key);
      if (held) {
        const room = rooms.get(roomId)!;
        // A second tab or a socket the server has not yet noticed is gone:
        // the newest connection wins the seat.
        if (held.connected) {
          roomOf.delete(held.socketId);
          io.sockets.sockets.get(held.socketId)?.leave(roomId);
        }
        clearTimeout(held.dropTimer);
        held.dropTimer = undefined;
        held.socketId = socket.id;
        held.connected = true;
        roomOf.set(socket.id, roomId);
        socket.join(roomId);
        broadcastRoom(roomId, room);
        return;
      }

      let room = rooms.get(roomId);
      if (!room) {
        if (rooms.size >= limits.maxRooms) {
          socket.emit("error", "Too many rooms right now; try again soon");
          return;
        }
        room = { players: [] };
      }
      if (room.players.length >= MAX_PLAYERS) {
        socket.emit("error", "Room is full");
        return;
      }

      rooms.set(roomId, room);
      roomOf.set(socket.id, roomId);
      socket.join(roomId);
      room.players.push({
        id: nextFreeSeat(room.players),
        socketId: socket.id,
        name: String(playerName ?? "").slice(0, MAX_NAME),
        color: String(playerColor ?? "").slice(0, MAX_COLOR),
        connected: true,
        key,
      });
      room.players.sort((a, b) => a.id - b.id);
      broadcastRoom(roomId, room);
    });

    // Only a player in the room can start its games or send it events; the
    // room comes from where the socket sits, not from what it claims.
    socket.on("start-game", (payload) => {
      const roomId = roomOf.get(socket.id);
      const gameIndex = payload?.gameIndex;
      if (roomId === undefined || !Number.isInteger(gameIndex)) return;
      io.to(roomId).emit("game-started", { gameIndex });
    });

    socket.on("game-event", (payload) => {
      const roomId = roomOf.get(socket.id);
      if (roomId === undefined || typeof payload?.event !== "string") return;
      socket.to(roomId).emit("remote-event", {
        event: payload.event,
        data: payload.data,
        senderId: socket.id,
      });
    });

    socket.on("disconnect", () => leave(socket, true));
  });

  return { io, rooms, info };
}
