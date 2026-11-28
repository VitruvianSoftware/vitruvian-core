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

/**
 * Server-context (non-window) tests for AuthService.
 *
 * Moved out of auth.test.ts because jest-environment-jsdom 30 bundles jsdom
 * 26, where `window` is a spec-compliant non-configurable [Unforgeable] own
 * property of the global object; under Node 26 `delete global.window` throws
 * `TypeError: Cannot delete property 'window' of #<Window>`. Running under
 * `@jest-environment node` provides a genuine `typeof window === "undefined"`
 * environment (matching data.server.test.ts and runtime-config.server.test.ts).
 */
import { AuthService } from "./auth";

describe("AuthService (server context)", () => {
  it("should return null if window is undefined (getToken)", () => {
    expect(typeof window).toBe("undefined");
    expect(AuthService.getToken()).toBeNull();
  });

  it("should return null if window is undefined (getUser)", () => {
    expect(typeof window).toBe("undefined");
    expect(AuthService.getUser()).toBeNull();
  });
});
