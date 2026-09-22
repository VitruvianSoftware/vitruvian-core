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

// Slack permalinks are the way humans hand a message to an agent, and the
// channel ID inside one is what the allow-list has to see. Parsing here, in a
// pure function, keeps "which channel does this URL name" testable on its own
// — the alternative was to pass the URL through and let Slack answer, which
// would move the allow-list decision to after the call it exists to prevent.

import {
  InvalidPermalinkError,
  parseFileReference,
  parsePermalink,
} from "../src/permalink.js";

describe("parsePermalink", () => {
  it("reads channel and timestamp from a top-level message permalink", () => {
    expect(
      parsePermalink(
        "https://acme.slack.com/archives/C0123ABCD/p1700000000123456",
      ),
    ).toEqual({ channelId: "C0123ABCD", ts: "1700000000.123456" });
  });

  it("reads the parent thread from a reply permalink", () => {
    expect(
      parsePermalink(
        "https://acme.slack.com/archives/C0123ABCD/p1700000001000000" +
          "?thread_ts=1700000000.123456&cid=C0123ABCD",
      ),
    ).toEqual({
      channelId: "C0123ABCD",
      ts: "1700000001.000000",
      threadTs: "1700000000.123456",
    });
  });

  it("treats a thread_ts equal to the message ts as a top-level message", () => {
    // Slack emits this shape for a parent opened from the thread view; it is
    // not a reply and fetching it through conversations.replies would be
    // wrong for a caller that only wants the one message.
    expect(
      parsePermalink(
        "https://acme.slack.com/archives/C0123ABCD/p1700000000123456" +
          "?thread_ts=1700000000.123456",
      ),
    ).toEqual({ channelId: "C0123ABCD", ts: "1700000000.123456" });
  });

  it("accepts group and DM conversation IDs", () => {
    expect(
      parsePermalink(
        "https://acme.slack.com/archives/G0PRIVATE1/p1700000000123456",
      ).channelId,
    ).toBe("G0PRIVATE1");
    expect(
      parsePermalink(
        "https://acme.slack.com/archives/D0DM000001/p1700000000123456",
      ).channelId,
    ).toBe("D0DM000001");
  });

  it("accepts enterprise-grid hosts", () => {
    expect(
      parsePermalink(
        "https://acme.enterprise.slack.com/archives/C0123ABCD/p1700000000123456",
      ).channelId,
    ).toBe("C0123ABCD");
  });

  it.each([
    [
      "a non-Slack host",
      "https://evil.example.com/archives/C0123ABCD/p1700000000123456",
    ],
    [
      "a look-alike host",
      "https://slack.com.evil.example/archives/C0123ABCD/p1700000000123456",
    ],
    ["a non-archives path", "https://acme.slack.com/files/U1/F1/x.txt"],
    [
      "a malformed timestamp",
      "https://acme.slack.com/archives/C0123ABCD/p17000",
    ],
    [
      "a lower-case channel id",
      "https://acme.slack.com/archives/c0123abcd/p1700000000123456",
    ],
    ["plain text", "not a url"],
    ["a bare channel id", "C0123ABCD"],
  ])("rejects %s", (_label, input) => {
    expect(() => parsePermalink(input)).toThrow(InvalidPermalinkError);
  });

  it("rejects a thread_ts that is not a Slack timestamp", () => {
    expect(() =>
      parsePermalink(
        "https://acme.slack.com/archives/C0123ABCD/p1700000000123456?thread_ts=abc",
      ),
    ).toThrow(InvalidPermalinkError);
  });
});

describe("parseFileReference", () => {
  it("passes a bare file ID through", () => {
    expect(parseFileReference("F0123ABCD")).toBe("F0123ABCD");
  });

  it("reads the file ID out of a Slack file URL", () => {
    expect(
      parseFileReference(
        "https://acme.slack.com/files/U0USER/F0123ABCD/report.pdf",
      ),
    ).toBe("F0123ABCD");
  });

  it.each([
    [
      "a non-Slack host",
      "https://evil.example.com/files/U0USER/F0123ABCD/x.pdf",
    ],
    [
      "a message permalink",
      "https://acme.slack.com/archives/C0123ABCD/p1700000000123456",
    ],
    ["an empty string", ""],
    ["a channel id", "C0123ABCD"],
  ])("rejects %s", (_label, input) => {
    expect(() => parseFileReference(input)).toThrow(InvalidPermalinkError);
  });
});
