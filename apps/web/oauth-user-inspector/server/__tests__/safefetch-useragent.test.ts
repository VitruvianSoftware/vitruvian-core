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

import {
  withDefaultUserAgent,
  withContentLength,
  SAFE_FETCH_USER_AGENT,
} from "../safeFetch.js";

/**
 * Guards the User-Agent default that safeFetch applies to every outbound
 * request. GitHub's api.github.com returns HTTP 403 to requests with no
 * User-Agent, which broke the server-side token revoke + the GitHub API
 * Explorer. safeFetch is the single egress point, so it must always carry a UA.
 */
describe("withDefaultUserAgent", () => {
  it("adds a non-empty default User-Agent when the caller set none", () => {
    const out = withDefaultUserAgent({
      Accept: "application/vnd.github.v3+json",
    });
    expect(out["User-Agent"]).toBe(SAFE_FETCH_USER_AGENT);
    expect(SAFE_FETCH_USER_AGENT.length).toBeGreaterThan(0);
    // existing headers are preserved
    expect(out.Accept).toBe("application/vnd.github.v3+json");
  });

  it("preserves a caller-supplied User-Agent (any casing) and adds no duplicate", () => {
    const canonical = withDefaultUserAgent({ "User-Agent": "custom/1.0" });
    expect(canonical["User-Agent"]).toBe("custom/1.0");

    const lower = withDefaultUserAgent({ "user-agent": "custom/2.0" });
    expect(lower["user-agent"]).toBe("custom/2.0");
    // must not inject a second, canonical-cased key alongside the caller's
    expect(lower["User-Agent"]).toBeUndefined();
  });

  it("does not mutate the caller's headers object", () => {
    const input: Record<string, string> = { Accept: "x" };
    withDefaultUserAgent(input);
    expect(input).toEqual({ Accept: "x" });
  });
});

/**
 * Guards the Content-Length default. With no Content-Length, Node frames a
 * written body as `Transfer-Encoding: chunked`, which GitHub's api.github.com
 * token revoke rejects with HTTP 422 ("Invalid request ... nil is not an
 * object"). safeFetch must set an explicit, byte-accurate Content-Length.
 */
describe("withContentLength", () => {
  it("adds a byte-accurate Content-Length when a body is present and none is set", () => {
    // include a multi-byte char so the byte count differs from string length
    const body = JSON.stringify({ access_token: "gho_x", note: "é" });
    const out = withContentLength({ "Content-Type": "application/json" }, body);
    expect(out["Content-Length"]).toBe(String(Buffer.byteLength(body)));
    expect(Number(out["Content-Length"])).toBe(Buffer.byteLength(body));
    expect(Number(out["Content-Length"])).not.toBe(body.length);
    expect(out["Content-Type"]).toBe("application/json");
  });

  it("adds nothing when there is no body", () => {
    expect(withContentLength({ Accept: "x" }, undefined)).toEqual({
      Accept: "x",
    });
  });

  it("preserves a caller-supplied Content-Length (case-insensitive)", () => {
    const out = withContentLength({ "content-length": "5" }, "abcdefghij");
    expect(out["content-length"]).toBe("5");
    expect(out["Content-Length"]).toBeUndefined();
  });

  it("does not mutate the caller's headers object", () => {
    const input: Record<string, string> = { Accept: "x" };
    withContentLength(input, "body");
    expect(input).toEqual({ Accept: "x" });
  });
});
