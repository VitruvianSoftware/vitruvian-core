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

import { safeHref } from "@/lib/safeHref";

describe("safeHref", () => {
  it("allows absolute http and https URLs", () => {
    expect(safeHref("https://example.com/x?y=1")).toBe(
      "https://example.com/x?y=1",
    );
    expect(safeHref("http://example.com")).toBe("http://example.com");
  });

  it("rejects javascript:, data:, vbscript: and other dangerous schemes", () => {
    expect(safeHref("javascript:alert(1)")).toBeNull();
    expect(safeHref("JavaScript:alert(1)")).toBeNull();
    expect(safeHref("data:text/html,<script>alert(1)</script>")).toBeNull();
    expect(safeHref("vbscript:msgbox(1)")).toBeNull();
    expect(safeHref("about:blank")).toBeNull();
    expect(safeHref("chrome://settings")).toBeNull();
    expect(safeHref("file:///etc/passwd")).toBeNull();
  });

  it("rejects relative and scheme-relative URLs (no base to resolve against)", () => {
    expect(safeHref("//evil.com")).toBeNull();
    expect(safeHref("/path/only")).toBeNull();
    expect(safeHref("relative")).toBeNull();
  });

  it("rejects empty / nullish input", () => {
    expect(safeHref("")).toBeNull();
    expect(safeHref(null)).toBeNull();
    expect(safeHref(undefined)).toBeNull();
  });
});
