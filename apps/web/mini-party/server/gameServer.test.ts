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
import { attachGameServer, nextFreeSeat, type RoomPlayer } from "./gameServer";

let httpServer: HttpServer;
let url: string;
let clients: Socket[] = [];

beforeEach(async () => {
  httpServer = createServer();
  attachGameServer(httpServer);
  await new Promise<void>((resolve) =>
    httpServer.listen(0, "127.0.0.1", resolve),
  );
  url = `http://127.0.0.1:${(httpServer.address() as AddressInfo).port}`;
});

afterEach(async () => {
  clients.forEach((c) => c.disconnect());
  clients = [];
  await new Promise((resolve) => httpServer.close(resolve));
});

function client(): Socket {
  const c = connect(url, { transports: ["websocket"], forceNew: true });
  clients.push(c);
  return c;
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
