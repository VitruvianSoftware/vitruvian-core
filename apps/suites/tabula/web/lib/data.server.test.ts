/**
 * @jest-environment node
 */

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

/* eslint-disable no-console */

/**
 * Server-context (non-window) tests for DataService.
 *
 * These used to live in data.test.ts and simulated SSR with
 * `delete global.window`. jest-environment-jsdom 30 bundles jsdom 26, which
 * is spec-compliant about [Unforgeable] Window properties: `window` is now a
 * non-configurable own property of the environment's global, so deleting or
 * redefining it is a silent no-op and the code under test still sees a
 * browser context. Running these cases under the node test environment (see
 * the @jest-environment docblock above) is the accurate simulation:
 * `typeof window === "undefined"` for real.
 */
import { DataService } from "./data";

describe("DataService (server context)", () => {
  describe("downloadFile", () => {
    it("should warn in non-window context", () => {
      const consoleSpy = jest.spyOn(console, "warn").mockImplementation();

      DataService.downloadFile("c", "f", "m");

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining("Cannot download file in server context"),
      );

      consoleSpy.mockRestore();
    });
  });

  describe("seedDemoData", () => {
    it("should do nothing in non-window context", () => {
      // Should not throw (there is no DOM or localStorage to touch here, so
      // reaching past the guard would throw a ReferenceError).
      expect(() => DataService.seedDemoData()).not.toThrow();
    });
  });

  describe("getDataSourceInfo", () => {
    it("should report no storage in non-window context", () => {
      const info = DataService.getDataSourceInfo();
      expect(info.type).toBe("none");
      expect(info.available).toBe(false);
    });
  });
});
