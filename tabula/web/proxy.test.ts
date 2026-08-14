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

import { NextRequest } from "next/server";
import { proxy } from "./proxy";

describe("proxy", () => {
  const originalApiUrl = process.env.API_URL;

  afterEach(() => {
    if (originalApiUrl === undefined) delete process.env.API_URL;
    else process.env.API_URL = originalApiUrl;
  });

  it("sets a CSP scoped to this environment's own API_URL", () => {
    process.env.API_URL = "https://tabula-api.vitruviansoftware.dev/api/v1";

    const request = new NextRequest(new URL("https://tabula.vitruviansoftware.dev/"));
    const response = proxy(request);

    const csp = response.headers.get("Content-Security-Policy");
    expect(csp).toContain("connect-src 'self' https://tabula-api.vitruviansoftware.dev");
    expect(response.headers.get("X-Frame-Options")).toBe("DENY");
    expect(response.headers.get("Referrer-Policy")).toBe("no-referrer");
  });

  it("falls back to the local default API host when API_URL is unset", () => {
    delete process.env.API_URL;

    const request = new NextRequest(new URL("http://localhost:3000/"));
    const response = proxy(request);

    expect(response.headers.get("Content-Security-Policy")).toContain(
      "connect-src 'self' http://localhost:8080",
    );
  });
});
