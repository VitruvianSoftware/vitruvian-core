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

// The dispatch table replaces a switch in index.ts that nothing could test
// without starting a server. Two things are asserted here. Structurally, the
// table and the advertised tool list must be the same set — a tool with no
// handler is a `default:` branch that fires in production, and a handler with
// no tool is dead code that reads as live. Behaviourally, each handler must
// pass its arguments to the client in the shape the client expects, which is
// exactly the wiring the old switch got wrong twice.

import { dispatch, handlers } from "../src/dispatch.js";
import { tools } from "../src/tools.js";
import { SlackClient } from "../src/slackClient.js";
import { resolveConfig } from "../src/config.js";
import { ChannelNotAllowedError } from "../src/channelAllowlist.js";
import { InvalidPermalinkError } from "../src/permalink.js";

const STDIO_ENV = {
  SLACK_BOT_TOKEN: "xoxb-test",
  SLACK_USER_TOKEN: "xoxp-test",
  SLACK_TEAM_ID: "T123",
};

const HTTP_ENV = {
  MCP_TRANSPORT: "http",
  SLACK_BOT_TOKEN: "xoxb-test",
  SLACK_TEAM_ID: "T123",
  SLACK_CHANNEL_IDS: "C0ALLOWED1",
  OIDC_ISSUER: "https://auth.example.test",
  OIDC_PROJECT_ID: "999",
  OIDC_ALLOWED_SUBJECTS: "379361013981513322",
  OIDC_ALLOWED_CLIENT_ID: "111222333",
};

function clientFor(env: Record<string, string | undefined>) {
  const config = resolveConfig(env);
  return new SlackClient(config.slack, {
    channelGuard: config.channelGuard,
    writeToken: config.writeToken,
  });
}

function captureFetch(body: Record<string, unknown> = { ok: true }) {
  const calls: { url: string; auth: string | undefined; body?: string }[] = [];
  const spy = jest
    .spyOn(globalThis, "fetch")
    .mockImplementation(
      async (input: RequestInfo | URL, init?: RequestInit) => {
        const headers = (init?.headers ?? {}) as Record<string, string>;
        calls.push({
          url: String(input),
          auth: headers.Authorization,
          body: typeof init?.body === "string" ? init.body : undefined,
        });
        return new Response(JSON.stringify(body), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      },
    );
  return { calls, restore: () => spy.mockRestore() };
}

describe("every advertised tool has a handler, and vice versa", () => {
  const toolNames: string[] = tools.map((t) => t.name).sort();
  const handlerNames = Object.keys(handlers).sort();

  it("has a handler for every tool in tools.ts", () => {
    const missing = toolNames.filter((n) => !handlerNames.includes(n));
    expect(missing).toEqual([]);
  });

  it("has no handler for a tool that is not advertised", () => {
    const orphaned = handlerNames.filter((n) => !toolNames.includes(n));
    expect(orphaned).toEqual([]);
  });

  it("refuses an unknown tool name", async () => {
    await expect(
      dispatch(clientFor(STDIO_ENV), "slack_no_such_tool", {}),
    ).rejects.toThrow(/Unknown tool/);
  });
});

describe("handlers pass arguments through in the client's shape", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch();
  });
  afterEach(() => capture.restore());

  it("routes slack_get_channel_history to conversations.history", async () => {
    await dispatch(clientFor(STDIO_ENV), "slack_get_channel_history", {
      channel_id: "C1",
      limit: 3,
    });
    expect(capture.calls[0]!.url).toContain("conversations.history");
    expect(capture.calls[0]!.url).toContain("channel=C1");
    expect(capture.calls[0]!.url).toContain("limit=3");
  });

  it("routes slack_reply_to_thread with the thread timestamp", async () => {
    await dispatch(clientFor(STDIO_ENV), "slack_reply_to_thread", {
      channel_id: "C1",
      thread_ts: "1.000001",
      text: "hi",
    });
    expect(capture.calls[0]!.url).toContain("chat.postMessage");
    expect(JSON.parse(capture.calls[0]!.body!)).toMatchObject({
      channel: "C1",
      thread_ts: "1.000001",
      text: "hi",
    });
  });

  it("rejects a missing required string before calling Slack", async () => {
    await expect(
      dispatch(clientFor(STDIO_ENV), "slack_get_channel_history", {}),
    ).rejects.toThrow(/channel_id/);
    expect(capture.calls).toHaveLength(0);
  });
});

// The reason permalink parsing happens in the handler rather than the client:
// the allow-list has to see the channel the URL names, before anything is
// sent. A URL naming a private channel must be refused as that channel, not
// forwarded as an opaque string the guard has nothing to say about.
describe("permalinks are resolved to a channel before the guard runs", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch({ ok: true, messages: [] });
  });
  afterEach(() => capture.restore());

  it("refuses a permalink into a channel outside the allow-list", async () => {
    await expect(
      dispatch(clientFor(HTTP_ENV), "slack_get_message", {
        permalink:
          "https://acme.slack.com/archives/G0PRIVATE1/p1700000000123456",
      }),
    ).rejects.toBeInstanceOf(ChannelNotAllowedError);
    expect(capture.calls).toHaveLength(0);
  });

  it("fetches a top-level message by its permalink", async () => {
    await dispatch(clientFor(HTTP_ENV), "slack_get_message", {
      permalink: "https://acme.slack.com/archives/C0ALLOWED1/p1700000000123456",
    });
    expect(capture.calls).toHaveLength(1);
    const url = capture.calls[0]!.url;
    expect(url).toContain("conversations.history");
    expect(url).toContain("channel=C0ALLOWED1");
    expect(url).toContain("latest=1700000000.123456");
    expect(url).toContain("oldest=1700000000.123456");
    expect(url).toContain("inclusive=true");
  });

  it("fetches a reply through its parent thread", async () => {
    await dispatch(clientFor(HTTP_ENV), "slack_get_message", {
      permalink:
        "https://acme.slack.com/archives/C0ALLOWED1/p1700000001000000" +
        "?thread_ts=1700000000.123456",
    });
    const url = capture.calls[0]!.url;
    expect(url).toContain("conversations.replies");
    expect(url).toContain("ts=1700000000.123456");
  });

  it("accepts channel_id and timestamp instead of a permalink", async () => {
    await dispatch(clientFor(HTTP_ENV), "slack_get_message", {
      channel_id: "C0ALLOWED1",
      timestamp: "1700000000.123456",
    });
    expect(capture.calls[0]!.url).toContain("conversations.history");
  });

  it("rejects a malformed permalink without calling Slack", async () => {
    await expect(
      dispatch(clientFor(HTTP_ENV), "slack_get_message", {
        permalink: "https://evil.example/archives/C0ALLOWED1/p1700000000123456",
      }),
    ).rejects.toBeInstanceOf(InvalidPermalinkError);
    expect(capture.calls).toHaveLength(0);
  });

  it("requires either a permalink or channel_id plus timestamp", async () => {
    await expect(
      dispatch(clientFor(HTTP_ENV), "slack_get_message", {}),
    ).rejects.toThrow(/permalink/);
    expect(capture.calls).toHaveLength(0);
  });
});
