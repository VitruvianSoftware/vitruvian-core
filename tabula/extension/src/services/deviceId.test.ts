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
 * Tests for the stable per-profile device id.
 */
import { getDeviceId, resetDeviceIdCacheForTests } from "./deviceId";

const store = new Map<string, unknown>();
const mockChrome = {
  storage: {
    local: {
      get: jest.fn((key: string) => Promise.resolve({ [key]: store.get(key) })),
      set: jest.fn((items: Record<string, unknown>) => {
        Object.entries(items).forEach(([k, v]) => store.set(k, v));
        return Promise.resolve();
      }),
    },
  },
};
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

describe("getDeviceId", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    store.clear();
    resetDeviceIdCacheForTests();
    // No Web Locks in this suite — exercises the fallback path
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (globalThis as any).navigator = {};
  });

  it("generates and persists a device id on first use", async () => {
    const id = await getDeviceId();
    expect(id).toMatch(/^device_/);
    expect(store.get("tabula_device_id")).toBe(id);
  });

  it("returns the same id across calls (cached)", async () => {
    const first = await getDeviceId();
    const second = await getDeviceId();
    expect(second).toBe(first);
    // Only one storage write despite two calls
    expect(mockChrome.storage.local.set).toHaveBeenCalledTimes(1);
  });

  it("reuses an existing persisted id", async () => {
    store.set("tabula_device_id", "device_existing");
    resetDeviceIdCacheForTests();
    const id = await getDeviceId();
    expect(id).toBe("device_existing");
    expect(mockChrome.storage.local.set).not.toHaveBeenCalled();
  });

  it("serializes id generation through Web Locks when available", async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (globalThis as any).navigator = {
      locks: { request: (_name: string, cb: () => Promise<string>) => cb() },
    };
    resetDeviceIdCacheForTests();
    const id = await getDeviceId();
    expect(id).toMatch(/^device_/);
  });
});
