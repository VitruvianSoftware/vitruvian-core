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
  ChannelVisibilityMismatchError,
  ChannelVisibilityUnverifiableError,
  ConflictingChannelDeclarationError,
  MissingAllowlistError,
  UnusableChannelParamError,
  assertParamsAllowed,
  createChannelGuard,
  parseChannelIds,
  readChannelParam,
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

// Enforcement is anchored on request parameters rather than on wrapper-method
// signatures, so this is the single thing that has to know how Slack spells
// the channel. Two methods were originally missed because their signatures hid
// the parameter; nothing can be missed this way.
describe("readChannelParam", () => {
  it("reads Slack's `channel` spelling (conversations, chat, pins)", () => {
    expect(readChannelParam({ channel: "C1", limit: 10 })).toEqual({
      kind: "channel",
      channelId: "C1",
    });
  });

  it("reads Slack's `channel_id` spelling (bookmarks, canvases)", () => {
    expect(readChannelParam({ channel_id: "C2", title: "x" })).toEqual({
      kind: "channel",
      channelId: "C2",
    });
  });

  it("reports absent when the call is not channel-scoped", () => {
    expect(readChannelParam({ query: "hello" })).toEqual({ kind: "absent" });
    expect(readChannelParam({})).toEqual({ kind: "absent" });
  });

  it("treats an explicitly undefined or null channel as absent", () => {
    // createCanvas omits the key this way when no channel is given.
    expect(readChannelParam({ channel_id: undefined })).toEqual({
      kind: "absent",
    });
    expect(readChannelParam({ channel: null })).toEqual({ kind: "absent" });
  });

  // The distinction the first version of this collapsed: a value that is
  // present but not usable is NOT the same as no value.
  it("reports unusable for a present-but-non-string channel", () => {
    expect(readChannelParam({ channel: ["C1"] })).toEqual({
      kind: "unusable",
      value: ["C1"],
    });
    expect(readChannelParam({ channel: 123 })).toMatchObject({
      kind: "unusable",
    });
    expect(readChannelParam({ channel: "" })).toMatchObject({
      kind: "unusable",
    });
  });
});

// These are the tests that would have caught the fail-open defect. The earlier
// ones asserted only what the *extractor* returned, which was correct in
// isolation; the bug was in what the guard concluded from it.
describe("assertParamsAllowed", () => {
  const guard = createChannelGuard("C_ALLOWED", { required: true });

  it("permits an allow-listed channel", () => {
    expect(() =>
      assertParamsAllowed(guard, { channel: "C_ALLOWED", limit: 5 })
    ).not.toThrow();
  });

  it("permits a call that names no channel at all", () => {
    expect(() =>
      assertParamsAllowed(guard, { query: "hello" })
    ).not.toThrow();
    expect(() =>
      assertParamsAllowed(guard, { title: "a canvas", channel_id: undefined })
    ).not.toThrow();
  });

  it("rejects a channel outside the allow-list", () => {
    expect(() => assertParamsAllowed(guard, { channel: "G_PRIVATE" })).toThrow(
      ChannelNotAllowedError
    );
  });

  // The actual bypass: `String(["C0PRIVATE"])` is "C0PRIVATE", and the GET
  // branch coerces every parameter that way — so an array-wrapped ID reached
  // Slack intact while the guard saw "no channel" and waved it through.
  it("rejects an array-wrapped channel rather than skipping the check", () => {
    expect(() =>
      assertParamsAllowed(guard, { channel: ["G_PRIVATE"] })
    ).toThrow(UnusableChannelParamError);
    expect(() =>
      assertParamsAllowed(guard, { channel_id: ["G_PRIVATE"] })
    ).toThrow(UnusableChannelParamError);
  });

  it("rejects an object whose toString would coerce to a channel ID", () => {
    const sneaky = { toString: () => "G_PRIVATE" };
    expect(() => assertParamsAllowed(guard, { channel: sneaky })).toThrow(
      UnusableChannelParamError
    );
  });

  // Fail-closed applies even to a value that would coerce to an ALLOWED
  // channel: the point is that an unreadable parameter is never waved through.
  it("rejects an unusable value even when it would coerce to an allowed id", () => {
    expect(() =>
      assertParamsAllowed(guard, { channel: ["C_ALLOWED"] })
    ).toThrow(UnusableChannelParamError);
  });

  it("rejects other non-string shapes", () => {
    expect(() => assertParamsAllowed(guard, { channel: 123 })).toThrow(
      UnusableChannelParamError
    );
    expect(() => assertParamsAllowed(guard, { channel: "" })).toThrow(
      UnusableChannelParamError
    );
  });
});

// Visibility is declared per channel rather than inferred, because with a
// single list "is it allowed" and "is it listed as private" are the same
// question — so a check against Slack's own is_private could only ever agree
// with the guard. Two lists make disagreement expressible.
describe("declared visibility", () => {
  const guard = createChannelGuard("C_PUBLIC", { required: true }, "G_PRIVATE");

  it("admits channels from either list", () => {
    expect(guard.isAllowed("C_PUBLIC")).toBe(true);
    expect(guard.isAllowed("G_PRIVATE")).toBe(true);
    expect(guard.isAllowed("C_UNLISTED")).toBe(false);
  });

  it("reports how each channel was declared", () => {
    expect(guard.declaredVisibility("C_PUBLIC")).toBe("public");
    expect(guard.declaredVisibility("G_PRIVATE")).toBe("private");
    expect(guard.declaredVisibility("C_UNLISTED")).toBeUndefined();
  });

  it("keeps the two lists separately readable for the deploy diff", () => {
    // The point of the split is legibility in review: adding an id to the
    // private list reads as granting a public endpoint access to a private
    // conversation, which one undifferentiated list does not convey.
    expect(guard.publicChannels).toEqual(["C_PUBLIC"]);
    expect(guard.privateChannels).toEqual(["G_PRIVATE"]);
  });

  it("refuses a channel declared both public and private", () => {
    expect(() =>
      createChannelGuard("C_ONE,C_BOTH", { required: true }, "C_BOTH")
    ).toThrow(ConflictingChannelDeclarationError);
  });

  it("still requires at least one channel from either list on http", () => {
    expect(() => createChannelGuard(undefined, { required: true }, "")).toThrow(
      MissingAllowlistError
    );
    // A private-only allow-list is legitimate.
    expect(() =>
      createChannelGuard(undefined, { required: true }, "G_ONLY")
    ).not.toThrow();
  });
});

// The check the split exists to make possible: an operator who means to add a
// public channel and pastes a private one is undetectable with one list, and a
// contradiction with two.
describe("assertVisibilityMatches", () => {
  const http = createChannelGuard(
    "C_PUBLIC",
    { required: true, enforceVisibility: true },
    "G_PRIVATE"
  );

  it("passes when Slack agrees with the declaration", () => {
    expect(() => http.assertVisibilityMatches("C_PUBLIC", false)).not.toThrow();
    expect(() => http.assertVisibilityMatches("G_PRIVATE", true)).not.toThrow();
  });

  it("refuses a channel declared public that Slack reports private", () => {
    expect(() => http.assertVisibilityMatches("C_PUBLIC", true)).toThrow(
      ChannelVisibilityMismatchError
    );
    // Names the variable to edit, and the direction. This is read at deploy
    // time: with replicas: 1 the refusal presents as CrashLoopBackOff, so
    // "the deploy is broken" is the natural reading unless the message says
    // otherwise. Same reasoning as the invite-the-bot-first remedy.
    expect(() => http.assertVisibilityMatches("C_PUBLIC", true)).toThrow(
      /SLACK_CHANNEL_IDS to SLACK_PRIVATE_CHANNEL_IDS/
    );
  });

  it("refuses a channel declared private that Slack reports public", () => {
    // The less obvious direction, and still a contradiction: the operator
    // believed they were granting private-channel access deliberately, and one
    // of the two beliefs is wrong.
    expect(() => http.assertVisibilityMatches("G_PRIVATE", false)).toThrow(
      ChannelVisibilityMismatchError
    );
    expect(() => http.assertVisibilityMatches("G_PRIVATE", false)).toThrow(
      /SLACK_PRIVATE_CHANNEL_IDS to SLACK_CHANNEL_IDS/
    );
  });

  // Aegis's requirement, and the reason it is its own test: it would pass by
  // accident today because every caller runs after assertAllowed. That makes
  // the behaviour a property of the call order rather than of this function,
  // and call orders change.
  it("fails closed on an undeclared channel without relying on assertAllowed", () => {
    expect(() => http.assertVisibilityMatches("C_UNLISTED", false)).toThrow(
      ChannelNotAllowedError
    );
    // Same input, no allow-list check anywhere near it — the refusal has to
    // come from this function alone.
    expect(() => http.assertVisibilityMatches("C_UNLISTED", true)).toThrow(
      ChannelNotAllowedError
    );
  });

  it("refuses rather than assuming when is_private is not a boolean", () => {
    // A missing field reads exactly like a passing check if it is coerced.
    expect(() =>
      http.assertVisibilityMatches("C_PUBLIC", undefined)
    ).toThrow(ChannelVisibilityUnverifiableError);
    expect(() => http.assertVisibilityMatches("C_PUBLIC", "false")).toThrow(
      ChannelVisibilityUnverifiableError
    );
  });

  it("is a no-op on stdio, which never declared visibility", () => {
    // Two stdio shapes. Unrestricted is the common one; the second matters
    // more, because a stdio user who set SLACK_CHANNEL_IDS to filter listings
    // has a fully-populated guard and would otherwise start failing on any
    // private channel in it after an upgrade.
    const unrestricted = createChannelGuard(undefined, { required: false });
    expect(() =>
      unrestricted.assertVisibilityMatches("C_ANYTHING", true)
    ).not.toThrow();

    const filtered = createChannelGuard("C_PUBLIC", { required: false });
    expect(() =>
      filtered.assertVisibilityMatches("C_PUBLIC", true)
    ).not.toThrow();
    expect(() =>
      filtered.assertVisibilityMatches("C_UNLISTED", false)
    ).not.toThrow();
  });
});
