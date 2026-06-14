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
 * Tests for workspace Zod schemas — especially the tab wire-format mapping.
 *
 * The extension sends tabs in Chrome's field names ({ favIconUrl, pinned,
 * index }); the API persists { faviconUrl, isPinned, position }. Zod strips
 * unknown keys, so without explicit mapping the data would silently vanish.
 */
import { TabSchema, WorkspaceUpdateSchema } from "../../src/schemas/workspace";

describe("TabSchema wire-format mapping", () => {
  it("maps favIconUrl/pinned/index from the extension wire format", () => {
    const parsed = TabSchema.parse({
      id: 42,
      url: "https://example.com",
      title: "Example",
      favIconUrl: "https://example.com/favicon.ico",
      pinned: true,
      index: 3,
    });

    expect(parsed.faviconUrl).toBe("https://example.com/favicon.ico");
    expect(parsed.isPinned).toBe(true);
    expect(parsed.position).toBe(3);
  });

  it("prefers canonical fields when both spellings are present", () => {
    const parsed = TabSchema.parse({
      url: "https://example.com",
      faviconUrl: "https://canonical.example/icon.png",
      favIconUrl: "https://wire.example/icon.png",
      isPinned: false,
      pinned: true,
      position: 1,
      index: 9,
    });

    expect(parsed.faviconUrl).toBe("https://canonical.example/icon.png");
    expect(parsed.isPinned).toBe(false);
    expect(parsed.position).toBe(1);
  });

  it("leaves position undefined when neither position nor index is sent (service defaults to array index)", () => {
    const parsed = TabSchema.parse({ url: "https://example.com" });
    expect(parsed.position).toBeUndefined();
    expect(parsed.isPinned).toBe(false);
  });

  it("accepts non-http URLs that Chrome emits (about:, chrome:)", () => {
    expect(() => TabSchema.parse({ url: "about:blank" })).not.toThrow();
    expect(() => TabSchema.parse({ url: "chrome://newtab/" })).not.toThrow();
  });

  it("rejects tabs with an empty url", () => {
    expect(() => TabSchema.parse({ url: "" })).toThrow();
  });

  // Regression: the client's parseInt sanitizer turned server-generated string
  // tab ids ("tab_...") into NaN, which JSON.stringify sends as null. The schema
  // must tolerate that (and any absent id) instead of 400-ing the whole PUT —
  // the service regenerates tab ids regardless (buildTabRows).
  it("accepts a null tab id (id is non-identifying; the service regenerates it)", () => {
    expect(() =>
      TabSchema.parse({ id: null, url: "https://example.com" }),
    ).not.toThrow();
  });

  it("accepts a round-tripped server string id and an absent id", () => {
    expect(() =>
      TabSchema.parse({ id: "tab_lq3x_abc123", url: "https://example.com" }),
    ).not.toThrow();
    expect(() => TabSchema.parse({ url: "https://example.com" })).not.toThrow();
  });

  it("accepts a workspace PUT whose tabs carry null ids", () => {
    expect(() =>
      WorkspaceUpdateSchema.parse({
        name: "WS",
        tabs: [
          { id: null, url: "https://a.example", index: 0 },
          { id: "tab_zzz", url: "https://b.example", index: 1 },
        ],
      }),
    ).not.toThrow();
  });

  it("maps tab fields inside a full workspace update payload", () => {
    const parsed = WorkspaceUpdateSchema.parse({
      name: "WS",
      tabs: [
        {
          url: "https://a.example",
          favIconUrl: "https://a.example/i.png",
          pinned: true,
          index: 0,
        },
        { url: "https://b.example", index: 1 },
      ],
    });

    expect(parsed.tabs![0].faviconUrl).toBe("https://a.example/i.png");
    expect(parsed.tabs![0].isPinned).toBe(true);
    expect(parsed.tabs![1].position).toBe(1);
  });
});
