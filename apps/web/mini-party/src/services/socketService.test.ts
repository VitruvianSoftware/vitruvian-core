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

// The real client service against the real rooms server: when the
// connection drops and socket.io reconnects, the player is back in their seat
// without the page doing anything.
import { createServer, type Server as HttpServer } from "http";
import type { AddressInfo } from "net";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { attachGameServer, type RoomPlayer } from "../../server/gameServer";
import { playerKey, SocketService } from "./socketService";

let httpServer: HttpServer;
let url: string;
const services: SocketService[] = [];

beforeEach(async () => {
  httpServer = createServer();
  attachGameServer(httpServer);
  await new Promise<void>((r) => httpServer.listen(0, "127.0.0.1", r));
  url = `http://127.0.0.1:${(httpServer.address() as AddressInfo).port}`;
});

afterEach(async () => {
  services.splice(0).forEach((s) => s.disconnect());
  await new Promise((r) => httpServer.close(r));
});

function service(key: string) {
  const s = new SocketService(url, key);
  services.push(s);
  s.connect();
  return s;
}

// Resolves with the first room-update that satisfies `ok`.
function update(s: SocketService, ok: (players: RoomPlayer[]) => boolean) {
  return new Promise<RoomPlayer[]>((resolve) =>
    s.onRoomUpdate(({ players }) => {
      if (ok(players)) resolve(players);
    }),
  );
}

describe("SocketService", () => {
  it("rejoins its seat after the connection drops", async () => {
    const host = service("h".repeat(32));
    const guest = service("g".repeat(32));
    const bothIn = update(guest, (p) => p.length === 2);
    host.joinRoom("ROOM", "Host", "#f00");
    await update(host, (p) => p.length === 1);
    guest.joinRoom("ROOM", "Guest", "#0f0");
    await bothIn;

    const firstId = host.getSocketId();
    const seen: boolean[] = [];
    host.onConnectionChange((up) => seen.push(up));
    const dropped = update(guest, (p) => p[0]?.connected === false);
    const back = update(
      guest,
      (p) => p[0]?.connected === true && p[0].socketId !== firstId,
    );
    // Kill the transport the way a sleeping phone or lost Wi-Fi does;
    // socket.io then reconnects by itself.
    host.connect().io.engine.close();

    await dropped;
    const players = await back;
    expect(players.map((p) => p.id)).toEqual([0, 1]);
    expect(players[0].socketId).toBe(host.getSocketId());
    expect(seen).toEqual([false, true]);
  });

  it("keeps one key per tab in session storage", () => {
    const store = new Map<string, string>();
    const storage = {
      getItem: (k: string) => store.get(k) ?? null,
      setItem: (k: string, v: string) => void store.set(k, v),
    } as unknown as Storage;
    const key = playerKey(storage);
    expect(key).toMatch(/^[0-9a-f]{36}$/);
    expect(playerKey(storage)).toBe(key);
    expect(playerKey(undefined)).not.toBe(key);
  });
});
