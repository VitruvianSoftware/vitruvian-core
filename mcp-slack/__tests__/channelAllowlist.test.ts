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
  ChannelNotAllowedError,
  MissingAllowlistError,
  createChannelGuard,
  parseChannelIds,
} from "../src/channelAllowlist.js";

describe("parseChannelIds", () => {
  it("returns an empty list for undefined or blank input", () => {
    expect(parseChannelIds(undefined)).toEqual([]);
    expect(parseChannelIds("")).toEqual([]);
    expect(parseChannelIds("   ")).toEqual([]);
  });

  it("trims whitespace and drops empty entries from trailing commas", () => {
    expect(parseChannelIds(" C123 , C456,, ")).toEqual(["C123", "C456"]);
  });

  it("de-duplicates while preserving configuration order", () => {
    expect(parseChannelIds("C1,C2,C1,C3")).toEqual(["C1", "C2", "C3"]);
  });
});

describe("createChannelGuard on the HTTP transport", () => {
  const guard = createChannelGuard("C_ALLOWED,C_ALSO_ALLOWED", {
    required: true,
  });

  it("refuses to start without an allow-list", () => {
    expect(() => createChannelGuard(undefined, { required: true })).toThrow(
      MissingAllowlistError
    );
    // A value that parses to nothing is the same hazard as an unset one.
    expect(() => createChannelGuard(" , ", { required: true })).toThrow(
      MissingAllowlistError
    );
  });

  it("permits channels named in the allow-list", () => {
    expect(guard.isAllowed("C_ALLOWED")).toBe(true);
    expect(() => guard.assertAllowed("C_ALSO_ALLOWED")).not.toThrow();
  });

  // The regression this whole module exists for: knowing an ID used to be
  // enough, because SLACK_CHANNEL_IDS only ever filtered channel *listing*.
  it("rejects a channel the caller names but that is not allow-listed", () => {
    expect(guard.isAllowed("D_SOME_DM")).toBe(false);
    expect(() => guard.assertAllowed("D_SOME_DM")).toThrow(
      ChannelNotAllowedError
    );
  });

  it("names the rejected channel in the error, without leaking the list", () => {
    try {
      guard.assertAllowed("G_PRIVATE");
      throw new Error("expected assertAllowed to throw");
    } catch (error) {
      expect(error).toBeInstanceOf(ChannelNotAllowedError);
      const err = error as ChannelNotAllowedError;
      expect(err.channelId).toBe("G_PRIVATE");
      expect(err.message).toContain("G_PRIVATE");
      expect(err.message).not.toContain("C_ALLOWED");
    }
  });

  it("is exact — no prefix or substring matching", () => {
    expect(guard.isAllowed("C_ALLOWED_EXTRA")).toBe(false);
    expect(guard.isAllowed("C_ALLOWE")).toBe(false);
    expect(guard.isAllowed("c_allowed")).toBe(false);
  });
});

describe("createChannelGuard on stdio", () => {
  // stdio's caller is a local process the user started themselves, and the
  // existing published behaviour is unrestricted. Tightening it here would
  // break every current local user, so absence of config stays permissive.
  it("allows everything when no allow-list is configured", () => {
    const guard = createChannelGuard(undefined, { required: false });
    expect(guard.allowed).toEqual([]);
    expect(guard.isAllowed("anything")).toBe(true);
    expect(() => guard.assertAllowed("anything")).not.toThrow();
  });

  it("still enforces an allow-list when the user configures one", () => {
    const guard = createChannelGuard("C_ONLY", { required: false });
    expect(guard.isAllowed("C_ONLY")).toBe(true);
    expect(() => guard.assertAllowed("C_OTHER")).toThrow(ChannelNotAllowedError);
  });
});
