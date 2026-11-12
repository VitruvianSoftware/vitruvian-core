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

import { parseMarkdown } from "./markdown";

describe("parseMarkdown", () => {
  it("should parse headers", () => {
    expect(parseMarkdown("# Header 1")).toBe("<h1>Header 1</h1>");
    expect(parseMarkdown("## Header 2")).toBe("<h2>Header 2</h2>");
    expect(parseMarkdown("### Header 3")).toBe("<h3>Header 3</h3>");
  });

  it("should parse bold text", () => {
    expect(parseMarkdown("**bold**")).toBe("<strong>bold</strong>");
    expect(parseMarkdown("start **bold** end")).toBe(
      "start <strong>bold</strong> end",
    );
  });

  it("should parse italic text", () => {
    expect(parseMarkdown("*italic*")).toBe("<em>italic</em>");
    expect(parseMarkdown("start *italic* end")).toBe(
      "start <em>italic</em> end",
    );
  });

  it("should parse links", () => {
    expect(parseMarkdown("[text](url)")).toBe(
      '<a href="url" target="_blank" rel="noopener noreferrer">text</a>',
    );
  });

  it("should parse unordered lists", () => {
    // - text -> <ul><li>text</li></ul>
    expect(parseMarkdown("- Item 1")).toBe("<ul><li>Item 1</li></ul>");
  });

  it("should parse inline code", () => {
    expect(parseMarkdown("`code`")).toBe("<code>code</code>");
  });

  it("should parse code blocks", () => {
    const mark = "```";
    const input = `${mark}\nconst a = 1;\n${mark}`;
    expect(parseMarkdown(input)).toContain("<pre><code>");
  });

  it("should handle newlines", () => {
    expect(parseMarkdown("Line 1\nLine 2")).toBe("Line 1<br />Line 2");
  });

  it("should escape HTML", () => {
    expect(parseMarkdown("<script>")).toBe("&lt;script&gt;");
  });

  it("should handle mixed content", () => {
    expect(parseMarkdown("# Header\n**Bold** and *Italic*")).toBe(
      "<h1>Header</h1><br /><strong>Bold</strong> and <em>Italic</em>",
    );
  });
});
