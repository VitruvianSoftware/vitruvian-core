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

import { getFaviconSrc } from "./favicon";

describe("getFaviconSrc", () => {
  it("prefers the tab favIconUrl when present", () => {
    expect(
      getFaviconSrc({
        favIconUrl: "https://x.com/i.png",
        url: "https://x.com",
      }),
    ).toBe("https://x.com/i.png");
  });

  it("falls back to the Google s2 service (encoded) when favIconUrl is missing", () => {
    expect(getFaviconSrc({ url: "https://x.com" })).toBe(
      "https://www.google.com/s2/favicons?domain=https%3A%2F%2Fx.com&sz=32",
    );
  });

  it("handles a missing url with an empty domain", () => {
    expect(getFaviconSrc({})).toBe(
      "https://www.google.com/s2/favicons?domain=&sz=32",
    );
  });

  it("honors a custom size", () => {
    expect(getFaviconSrc({ url: "https://x.com" }, 16)).toContain("sz=16");
  });
});
