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
  getApiUrl,
  RUNTIME_CONFIG_ELEMENT_ID,
  __resetRuntimeConfigCacheForTests,
} from "./runtime-config";

function renderConfigScript(json: string) {
  const el = document.createElement("script");
  el.id = RUNTIME_CONFIG_ELEMENT_ID;
  el.type = "application/json";
  el.textContent = json;
  document.body.appendChild(el);
}

describe("getApiUrl", () => {
  const originalApiUrl = process.env.API_URL;

  beforeEach(() => {
    __resetRuntimeConfigCacheForTests();
    document.body.innerHTML = "";
    delete process.env.API_URL;
  });

  afterAll(() => {
    if (originalApiUrl === undefined) delete process.env.API_URL;
    else process.env.API_URL = originalApiUrl;
  });

  it("reads the value injected by the server into the runtime-config script tag", () => {
    renderConfigScript(
      JSON.stringify({
        apiUrl: "https://tabula-api.vitruviansoftware.dev/api/v1",
      }),
    );
    expect(getApiUrl()).toBe("https://tabula-api.vitruviansoftware.dev/api/v1");
  });

  it("falls back to the local default when no script tag is present", () => {
    expect(getApiUrl()).toBe("http://localhost:8080/api/v1");
  });

  it("falls back to the local default when the script tag has no apiUrl", () => {
    renderConfigScript(JSON.stringify({ apiUrl: null }));
    expect(getApiUrl()).toBe("http://localhost:8080/api/v1");
  });

  it("falls back to the local default on malformed JSON rather than throwing", () => {
    renderConfigScript("{not json");
    expect(() => getApiUrl()).not.toThrow();
    expect(getApiUrl()).toBe("http://localhost:8080/api/v1");
  });

  it("caches the resolved value across calls, ignoring later DOM changes", () => {
    renderConfigScript(
      JSON.stringify({ apiUrl: "https://first.example/api/v1" }),
    );
    expect(getApiUrl()).toBe("https://first.example/api/v1");

    document.body.innerHTML = "";
    renderConfigScript(
      JSON.stringify({ apiUrl: "https://second.example/api/v1" }),
    );
    expect(getApiUrl()).toBe("https://first.example/api/v1");
  });

  // The server (no-`window`) branch is covered in runtime-config.server.test.ts
  // under the Node jest environment: jsdom's `window` isn't a deletable/
  // reassignable global here, so it can't be simulated in THIS file.
});
