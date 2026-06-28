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

import { withDefaultUserAgent, SAFE_FETCH_USER_AGENT } from "../safeFetch.js";

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
