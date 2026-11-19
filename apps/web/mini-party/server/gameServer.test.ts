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

import { createServer, type Server as HttpServer } from "http";
import type { AddressInfo } from "net";
import { io as connect, type Socket } from "socket.io-client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  attachGameServer,
  nextFreeSeat,
  parseOrigins,
  type GameServerOptions,
  type RoomPlayer,
} from "./gameServer";

let httpServer: HttpServer;
let url: string;
let clients: Socket[] = [];

// Starts a fresh server; the default one is replaced by tests that need
// other options.
async function start(options: GameServerOptions = {}) {
  if (httpServer?.listening) {
    clients.forEach((c) => c.disconnect());
    clients = [];
    await new Promise((resolve) => httpServer.close(resolve));
  }
  httpServer = createServer();
  attachGameServer(httpServer, options);
  await new Promise<void>((resolve) =>
    httpServer.listen(0, "127.0.0.1", resolve),
  );
  url = `http://127.0.0.1:${(httpServer.address() as AddressInfo).port}`;
}

beforeEach(() => start());

afterEach(async () => {
  clients.forEach((c) => c.disconnect());
  clients = [];
  await new Promise((resolve) => httpServer.close(resolve));
});

function client(origin?: string): Socket {
  const c = connect(url, {
    transports: ["websocket"],
    forceNew: true,
    extraHeaders: origin ? { origin } : undefined,
  });
  clients.push(c);
  return c;
}

// Resolves "connected" or "refused", whichever happens first.
function outcome(socket: Socket): Promise<"connected" | "refused"> {
  return new Promise((resolve) => {
    socket.once("connect", () => resolve("connected"));
    socket.once("connect_error", () => resolve("refused"));
  });
}

// Waits briefly and reports whether `event` arrived on `socket`.
function arrives(socket: Socket, event: string, ms = 200): Promise<boolean> {
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve(false), ms);
    socket.once(event, () => {
      clearTimeout(t);
      resolve(true);
    });
  });
}

function next<T>(socket: Socket, event: string): Promise<T> {
  return new Promise((resolve) => socket.once(event, resolve));
}

// Joins and waits for the room-update that this join caused.
async function join(socket: Socket, name: string, roomId = "ROOM") {
  const update = next<{ players: RoomPlayer[] }>(socket, "room-update");
  socket.emit("join-room", { roomId, playerName: name, playerColor: "#fff" });
  return (await update).players;
}

describe("nextFreeSeat", () => {
  const p = (id: number) => ({ id, socketId: `s${id}`, name: "", color: "" });
  it("fills the lowest gap", () => {
    expect(nextFreeSeat([])).toBe(0);
    expect(nextFreeSeat([p(0), p(1)])).toBe(2);
    expect(nextFreeSeat([p(1), p(2)])).toBe(0);
  });
});

describe("game server", () => {
  it("seats players in join order and tells everyone", async () => {
    const a = client();
    const b = client();
    expect((await join(a, "Ann")).map((p) => p.id)).toEqual([0]);
    const seenByA = next<{ players: RoomPlayer[] }>(a, "room-update");
    expect((await join(b, "Bo")).map((p) => p.name)).toEqual(["Ann", "Bo"]);
    expect((await seenByA).players).toHaveLength(2);
  });

  it("turns away a fifth player", async () => {
    for (const name of ["A", "B", "C", "D"]) await join(client(), name);
    const late = client();
    const error = next<string>(late, "error");
    late.emit("join-room", {
      roomId: "ROOM",
      playerName: "E",
      playerColor: "#fff",
    });
    expect(await error).toBe("Room is full");
  });

  it("reuses a seat after a player leaves instead of duplicating an id", async () => {
    const a = client();
    const b = client();
    await join(a, "A");
    await join(b, "B");
    const afterLeave = next<{ players: RoomPlayer[] }>(b, "room-update");
    a.disconnect();
    expect((await afterLeave).players.map((p) => p.id)).toEqual([1]);
    const ids = (await join(client(), "C")).map((p) => p.id);
    expect(ids).toEqual([0, 1]);
  });

  it("relays game events to the other players only", async () => {
    const a = client();
    const b = client();
    await join(a, "A");
    await join(b, "B");
    let echoedToSender = false;
    a.on("remote-event", () => (echoedToSender = true));
    const got = next<{ event: string; data: unknown }>(b, "remote-event");
    a.emit("game-event", {
      roomId: "ROOM",
      event: "press",
      data: { playerId: 0 },
    });
    expect(await got).toMatchObject({ event: "press", data: { playerId: 0 } });
    expect(echoedToSender).toBe(false);
  });
});

describe("parseOrigins", () => {
  it("splits and trims a comma list, ignoring blanks", () => {
    expect(parseOrigins(" https://a.dev, https://b.dev ,,")).toEqual([
      "https://a.dev",
      "https://b.dev",
    ]);
    expect(parseOrigins(undefined)).toEqual([]);
  });
});

describe("a server open to the internet", () => {
  it("refuses pages from other sites and admits the allowed one", async () => {
    await start({
      allowedOrigins: ["https://mini-games.vitruviansoftware.dev"],
    });
    expect(await outcome(client("https://evil.example"))).toBe("refused");
    expect(
      await outcome(client("https://mini-games.vitruviansoftware.dev")),
    ).toBe("connected");
    // Native clients send no Origin header and are let in.
    expect(await outcome(client())).toBe("connected");
  });

  it("refuses other sites when no origin is allowed", async () => {
    expect(await outcome(client("https://evil.example"))).toBe("refused");
  });

  it("caps how many rooms exist at once", async () => {
    await start({ limits: { maxRooms: 1 } });
    await join(client(), "A", "ONE");
    const late = client();
    const error = next<string>(late, "error");
    late.emit("join-room", { roomId: "TWO", playerName: "B" });
    expect(await error).toMatch(/Too many rooms/);
  });

  it("ignores room ids that are not short and alphanumeric", async () => {
    const c = client();
    c.emit("join-room", { roomId: "../../etc", playerName: "A" });
    c.emit("join-room", { roomId: "X".repeat(17), playerName: "A" });
    c.emit("join-room", { roomId: { $ne: 1 }, playerName: "A" });
    expect(await arrives(c, "room-update")).toBe(false);
  });

  it("trims long names", async () => {
    const players = await join(client(), "N".repeat(500));
    expect(players[0].name).toHaveLength(24);
  });

  it("relays only within the room the sender sits in", async () => {
    const a = client();
    const b = client();
    const outsider = client();
    await join(a, "A", "ROOM");
    await join(b, "B", "ROOM");
    await join(outsider, "O", "OTHER");
    // The outsider names ROOM, but sits in OTHER: nothing reaches ROOM.
    const leaked = arrives(a, "remote-event");
    outsider.emit("game-event", { roomId: "ROOM", event: "press", data: {} });
    outsider.emit("start-game", { roomId: "ROOM", gameIndex: 3 });
    expect(await leaked).toBe(false);
  });

  it("does not let a socket hold seats in two rooms", async () => {
    const a = client();
    const watcher = client();
    await join(watcher, "W", "ROOM");
    await join(a, "A", "ROOM");
    const update = next<{ players: RoomPlayer[] }>(watcher, "room-update");
    await join(a, "A", "OTHER");
    expect((await update).players.map((p) => p.name)).toEqual(["W"]);
  });

  it("drops a flood of events past the per-second budget", async () => {
    await start({ limits: { maxEventsPerSecond: 5 } });
    const a = client();
    const b = client();
    await join(a, "A");
    await join(b, "B");
    let received = 0;
    b.on("remote-event", () => received++);
    // The join above already spent one of a's five.
    for (let i = 0; i < 50; i++) {
      a.emit("game-event", { event: "press", data: { i } });
    }
    await new Promise((r) => setTimeout(r, 300));
    expect(received).toBeGreaterThan(0);
    expect(received).toBeLessThanOrEqual(5);
  });
});
