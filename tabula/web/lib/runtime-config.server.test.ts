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

// Runs under the Node jest environment (see the docblock above), where
// `window` is genuinely absent rather than an undeletable jsdom global — this
// exercises getApiUrl()'s actual server code path (RSC/route handlers/
// middleware all run in this same Node process) without needing to mutate a
// jsdom global that jsdom itself won't let go of.
import { getApiUrl } from "./runtime-config";

describe("getApiUrl (server / no window)", () => {
  const originalApiUrl = process.env.API_URL;

  afterEach(() => {
    if (originalApiUrl === undefined) delete process.env.API_URL;
    else process.env.API_URL = originalApiUrl;
  });

  it("reads directly from process.env.API_URL, re-evaluated per call — not cached like the client branch", () => {
    process.env.API_URL = "https://tabula-api.staging.vitruviansoftware.dev/api/v1";
    expect(getApiUrl()).toBe("https://tabula-api.staging.vitruviansoftware.dev/api/v1");
  });

  it("falls back to the local default when API_URL is unset", () => {
    delete process.env.API_URL;
    expect(getApiUrl()).toBe("http://localhost:8080/api/v1");
  });
});
