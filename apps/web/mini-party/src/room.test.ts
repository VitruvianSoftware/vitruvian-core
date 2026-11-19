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

import { describe, expect, it } from "vitest";
import { roomFromSearch } from "./room";

describe("roomFromSearch", () => {
  it("reads the room from a share link", () => {
    expect(roomFromSearch("?room=81D0I7", true)).toBe("81D0I7");
  });

  it("is null without a room, or when online play is off", () => {
    expect(roomFromSearch("", true)).toBeNull();
    expect(roomFromSearch("?other=1", true)).toBeNull();
    expect(roomFromSearch("?room=81D0I7", false)).toBeNull();
  });

  it("ignores room codes the server would refuse", () => {
    expect(roomFromSearch("?room=../../x", true)).toBeNull();
    expect(roomFromSearch(`?room=${"A".repeat(17)}`, true)).toBeNull();
    expect(roomFromSearch("?room=", true)).toBeNull();
  });
});
