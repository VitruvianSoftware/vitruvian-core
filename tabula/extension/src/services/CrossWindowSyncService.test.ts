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

/* eslint-disable @typescript-eslint/no-explicit-any, global-require, @typescript-eslint/no-var-requires, no-use-before-define, @typescript-eslint/no-use-before-define */
/**
 * Tests for the BroadcastChannel-based cross-window sync service.
 */
export {}; // make this a module so the `require` declaration is module-scoped

declare let require: any;

class MockBroadcastChannel {
  static instances: MockBroadcastChannel[] = [];

  onmessage: ((event: MessageEvent) => void) | null = null;

  posted: unknown[] = [];

  constructor(public name: string) {
    MockBroadcastChannel.instances.push(this);
  }

  postMessage(msg: unknown) {
    this.posted.push(msg);
  }
}

describe("CrossWindowSyncService", () => {
  let crossWindowSync: typeof import("./CrossWindowSyncService").crossWindowSync;

  beforeEach(() => {
    jest.resetModules();
    MockBroadcastChannel.instances = [];
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (globalThis as any).BroadcastChannel = MockBroadcastChannel;
    // eslint-disable-next-line global-require, @typescript-eslint/no-var-requires
    crossWindowSync = require("./CrossWindowSyncService").crossWindowSync;
  });

  afterEach(() => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    delete (globalThis as any).BroadcastChannel;
  });

  it("initializes a BroadcastChannel on the shared channel name", () => {
    expect(MockBroadcastChannel.instances).toHaveLength(1);
    expect(MockBroadcastChannel.instances[0].name).toBe("tabula_sync_channel");
  });

  it("broadcasts claim/release messages with the expected shape", () => {
    crossWindowSync.broadcastClaim("ws1", 7, 42);
    crossWindowSync.broadcastRelease("ws1", 7);

    const posted = MockBroadcastChannel.instances[0].posted as Array<
      Record<string, unknown>
    >;
    expect(posted[0]).toMatchObject({
      type: "CLAIM_WORKSPACE",
      workspaceId: "ws1",
      windowId: 7,
      tabId: 42,
    });
    expect(posted[1]).toMatchObject({
      type: "RELEASE_WORKSPACE",
      workspaceId: "ws1",
      windowId: 7,
    });
  });

  it("delivers incoming messages to subscribers and supports unsubscribe", () => {
    const received: unknown[] = [];
    const unsubscribe = crossWindowSync.subscribe((m) => received.push(m));

    const channel = MockBroadcastChannel.instances[0];
    const event = {
      data: {
        type: "CLAIM_WORKSPACE",
        workspaceId: "ws1",
        windowId: 9,
        tabId: 1,
      },
    };
    channel.onmessage!(event as MessageEvent);
    expect(received).toHaveLength(1);

    unsubscribe();
    channel.onmessage!(event as MessageEvent);
    expect(received).toHaveLength(1); // no further deliveries after unsubscribe
  });

  it("broadcasts ping/pong messages", () => {
    crossWindowSync.broadcastPing(3);
    crossWindowSync.broadcastPong(3, []);
    const posted = MockBroadcastChannel.instances[0].posted as Array<
      Record<string, unknown>
    >;
    expect(posted.map((m) => m.type)).toEqual(["PING", "PONG"]);
  });

  it("degrades gracefully when BroadcastChannel is unavailable", () => {
    jest.resetModules();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    delete (globalThis as any).BroadcastChannel;
    // eslint-disable-next-line global-require, @typescript-eslint/no-var-requires
    const svc = require("./CrossWindowSyncService").crossWindowSync;
    // No channel — broadcasting must not throw
    expect(() => svc.broadcastClaim("ws1", 1, 1)).not.toThrow();
  });
});
