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

import { redis } from "../../src/lib/redis";
import {
  setTombstone,
  isTombstoned,
  clearSyncKeys,
  markEntityDeleted,
} from "../../src/lib/tombstones";

jest.mock("../../src/lib/redis", () => ({
  redis: {
    get: jest.fn(),
    set: jest.fn(),
    del: jest.fn(),
  },
}));

describe("tombstones fail-open and fail-safe handling", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("isTombstoned", () => {
    it("returns true when tombstone exists in Redis", async () => {
      (redis.get as jest.Mock).mockResolvedValue("2026-08-14T22:00:00.000Z");
      const result = await isTombstoned("u1", "workspace", "ws1");
      expect(result).toBe(true);
      expect(redis.get).toHaveBeenCalledWith("tombstone:u1:workspace:ws1");
    });

    it("returns false when tombstone is absent", async () => {
      (redis.get as jest.Mock).mockResolvedValue(null);
      const result = await isTombstoned("u1", "workspace", "ws1");
      expect(result).toBe(false);
    });

    it("fails open (returns false) when Redis throws 'Connection is closed'", async () => {
      (redis.get as jest.Mock).mockRejectedValue(
        new Error("Connection is closed."),
      );
      const result = await isTombstoned("u1", "workspace", "ws1");
      expect(result).toBe(false);
    });

    it("fails open (returns false) on unexpected network error", async () => {
      (redis.get as jest.Mock).mockRejectedValue(new Error("ECONNREFUSED"));
      const result = await isTombstoned("u1", "spaceGroup", "sg1");
      expect(result).toBe(false);
    });
  });

  describe("setTombstone", () => {
    it("sets tombstone key in Redis with 30-day TTL", async () => {
      (redis.set as jest.Mock).mockResolvedValue("OK");
      await setTombstone("u1", "workspace", "ws1");
      expect(redis.set).toHaveBeenCalledWith(
        "tombstone:u1:workspace:ws1",
        expect.any(String),
        "EX",
        2592000,
      );
    });

    it("does not throw when Redis throws an error", async () => {
      (redis.set as jest.Mock).mockRejectedValue(
        new Error("Connection is closed."),
      );
      await expect(
        setTombstone("u1", "workspace", "ws1"),
      ).resolves.toBeUndefined();
    });
  });

  describe("clearSyncKeys", () => {
    it("deletes version and state sync keys in Redis", async () => {
      (redis.del as jest.Mock).mockResolvedValue(2);
      await clearSyncKeys("u1", "workspace", "ws1");
      expect(redis.del).toHaveBeenCalledWith(
        "sync:version:u1:workspace:ws1",
        "sync:state:u1:workspace:ws1",
      );
    });

    it("does not throw when Redis throws an error", async () => {
      (redis.del as jest.Mock).mockRejectedValue(
        new Error("Connection is closed."),
      );
      await expect(
        clearSyncKeys("u1", "workspace", "ws1"),
      ).resolves.toBeUndefined();
    });
  });

  describe("markEntityDeleted", () => {
    it("calls setTombstone and clearSyncKeys", async () => {
      (redis.set as jest.Mock).mockResolvedValue("OK");
      (redis.del as jest.Mock).mockResolvedValue(2);
      await markEntityDeleted("u1", "workspace", "ws1");
      expect(redis.set).toHaveBeenCalled();
      expect(redis.del).toHaveBeenCalled();
    });
  });
});
