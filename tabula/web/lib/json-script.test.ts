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

import { escapeJsonForScript } from "./json-script";

describe("escapeJsonForScript", () => {
  it("round-trips a plain value unchanged in meaning", () => {
    const out = escapeJsonForScript({ apiUrl: "https://tabula-api.vitruviansoftware.dev/api/v1" });
    expect(JSON.parse(out)).toEqual({
      apiUrl: "https://tabula-api.vitruviansoftware.dev/api/v1",
    });
  });

  it("neutralizes a </script> breakout attempt", () => {
    const out = escapeJsonForScript({ apiUrl: "</script><script>alert(1)</script>" });
    expect(out).not.toContain("</script>");
    expect(out).not.toContain("<script>");
    expect(JSON.parse(out)).toEqual({
      apiUrl: "</script><script>alert(1)</script>",
    });
  });

  it("escapes raw U+2028/U+2029 so they can't act as illegal line terminators", () => {
    const lineSep = String.fromCharCode(0x2028);
    const paraSep = String.fromCharCode(0x2029);
    const out = escapeJsonForScript({ apiUrl: `before${lineSep}mid${paraSep}after` });
    expect(out).not.toContain(lineSep);
    expect(out).not.toContain(paraSep);
    expect(JSON.parse(out)).toEqual({ apiUrl: `before${lineSep}mid${paraSep}after` });
  });

  it("passes through null cleanly", () => {
    expect(escapeJsonForScript({ apiUrl: null })).toBe('{"apiUrl":null}');
  });
});
