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

// The wiring layer, which had no tests until now.
//
// Two of the six defects found while building this lived here — not in the
// primitives, which were correct and tested, but in the callers that were
// meant to use them. `SlackClient` is where the allow-list is actually
// enforced and where the transport's credential choice actually takes effect,
// and neither was reachable from a test before.
//
// It also covers the claim this whole change rests on: that stdio behaves as
// it did. That claim was made repeatedly, was never tested, and turned out to
// be false in one respect.

import { SlackClient } from "../src/slackClient.js";
import { ChannelNotAllowedError, UnusableChannelParamError } from "../src/channelAllowlist.js";
import { resolveConfig } from "../src/config.js";
import { toolsFor } from "../src/tools.js";

const STDIO_ENV = {
  SLACK_BOT_TOKEN: "xoxb-test",
  SLACK_USER_TOKEN: "xoxp-test",
  SLACK_TEAM_ID: "T123",
};

const HTTP_ENV = {
  MCP_TRANSPORT: "http",
  SLACK_BOT_TOKEN: "xoxb-test",
  SLACK_TEAM_ID: "T123",
  SLACK_CHANNEL_IDS: "C_ALLOWED, C_SECOND,",
  OIDC_ISSUER: "https://auth.example.test",
  OIDC_PROJECT_ID: "999",
};

/** Captures outbound Slack calls instead of making them. */
function captureFetch() {
  const calls: { url: string; auth: string | undefined; body?: string }[] = [];
  const spy = jest
    .spyOn(globalThis, "fetch")
    .mockImplementation(async (input: RequestInfo | URL, init?: RequestInit) => {
      const headers = (init?.headers ?? {}) as Record<string, string>;
      calls.push({
        url: String(input),
        auth: headers.Authorization,
        body: typeof init?.body === "string" ? init.body : undefined,
      });
      return new Response(JSON.stringify({ ok: true, channel: {} }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    });
  return { calls, restore: () => spy.mockRestore() };
}

function clientFor(env: Record<string, string | undefined>) {
  const config = resolveConfig(env);
  return new SlackClient(config.slack, {
    channelGuard: config.channelGuard,
    writeToken: config.writeToken,
  });
}

describe("stdio regression — the path every existing user runs", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch();
  });
  afterEach(() => capture.restore());

  it("constructs from the stdio config and reads with the bot token", async () => {
    await clientFor(STDIO_ENV).getChannelHistory("C_ANYTHING", 5);
    expect(capture.calls).toHaveLength(1);
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
  });

  // The published contract: stdio writes post as the authenticated human.
  // A method-level rather than transport-scoped token flip would have silently
  // changed every existing user's messages to come from the app.
  it("still writes with the USER token", async () => {
    await clientFor(STDIO_ENV).postMessage("C_ANYTHING", "hello");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxp-test");
    expect(capture.calls[0]!.url).toContain("chat.postMessage");
  });

  it("imposes no channel restriction when none is configured", async () => {
    const client = clientFor(STDIO_ENV);
    await expect(
      client.getChannelHistory("D_A_DM_NOBODY_ALLOW_LISTED")
    ).resolves.toBeDefined();
  });

  it("honours an allow-list on stdio when the user sets one", async () => {
    const client = clientFor({ ...STDIO_ENV, SLACK_CHANNEL_IDS: "C_ONLY" });
    await expect(client.getChannelHistory("C_ONLY")).resolves.toBeDefined();
    await expect(client.getChannelHistory("C_OTHER")).rejects.toBeInstanceOf(
      ChannelNotAllowedError
    );
  });
});

describe("the allow-list is enforced through api(), not only in isolation", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch();
  });
  afterEach(() => capture.restore());

  // These assert the wiring. `assertParamsAllowed` was already tested; what was
  // not tested is that every outbound call actually goes through it.
  it.each([
    ["getChannelHistory", (c: SlackClient) => c.getChannelHistory("G_PRIVATE")],
    ["getChannelInfo", (c: SlackClient) => c.getChannelInfo("G_PRIVATE")],
    ["getThreadReplies", (c: SlackClient) => c.getThreadReplies("G_PRIVATE", "1.0")],
    ["listPins", (c: SlackClient) => c.listPins("G_PRIVATE")],
    ["listBookmarks", (c: SlackClient) => c.listBookmarks("G_PRIVATE")],
    ["postMessage", (c: SlackClient) => c.postMessage("G_PRIVATE", "x")],
    ["replyToThread", (c: SlackClient) => c.replyToThread("G_PRIVATE", "1.0", "x")],
    ["updateMessage", (c: SlackClient) => c.updateMessage("G_PRIVATE", "1.0", "x")],
  ])("%s refuses a channel outside the allow-list", async (_name, call) => {
    await expect(call(clientFor(HTTP_ENV))).rejects.toBeInstanceOf(
      ChannelNotAllowedError
    );
    expect(capture.calls).toHaveLength(0); // refused before reaching Slack
  });

  // The bypass found in review: String(["G_PRIVATE"]) is "G_PRIVATE", and the
  // GET branch coerces every parameter that way.
  it("refuses an array-wrapped channel before it can be coerced", async () => {
    const client = clientFor(HTTP_ENV);
    await expect(
      client.getChannelHistory(["G_PRIVATE"] as unknown as string)
    ).rejects.toBeInstanceOf(UnusableChannelParamError);
    expect(capture.calls).toHaveLength(0);
  });

  it("allows an allow-listed channel through", async () => {
    await clientFor(HTTP_ENV).getChannelHistory("C_ALLOWED");
    expect(capture.calls).toHaveLength(1);
    expect(capture.calls[0]!.url).toContain("channel=C_ALLOWED");
  });

  it("writes with the BOT token on the HTTP transport", async () => {
    await clientFor(HTTP_ENV).postMessage("C_ALLOWED", "hello");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
  });

  // A user-token tool invoked directly on HTTP: the tool list is one control,
  // this is the other. Both were assumed to be the same thing by three
  // separate reviewers.
  it("refuses a user-token-only call when no user token exists", async () => {
    await expect(
      clientFor(HTTP_ENV).searchMessages("anything")
    ).rejects.toThrow(/requires the user token/);
    expect(capture.calls).toHaveLength(0);
  });
});

describe("listChannels enumerates the same list the guard enforces", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch();
  });
  afterEach(() => capture.restore());

  // Found in review: this re-parsed SLACK_CHANNEL_IDS from the environment with
  // weaker rules than parseChannelIds. The trailing comma in HTTP_ENV is
  // deliberate — it produced an empty id, which the guard then (correctly)
  // refused, taking the whole listing down with it.
  it("skips blank entries a trailing comma produces", async () => {
    const result = (await clientFor(HTTP_ENV).listChannels()) as {
      ok: boolean;
    };
    expect(result.ok).toBe(true);
    expect(capture.calls).toHaveLength(2); // C_ALLOWED and C_SECOND, not three
    expect(capture.calls.map((c) => c.url).join(" ")).not.toContain("channel=&");
  });

  it("falls back to conversations.list when no allow-list is configured", async () => {
    await clientFor(STDIO_ENV).listChannels();
    expect(capture.calls[0]!.url).toContain("conversations.list");
  });
});

// Workspace-scoped calls are the class every control built for this endpoint
// misses: SLACK_CHANNEL_IDS bounds calls that name a channel, and `users.list`
// names none. The guard correctly finds nothing to check, so the call goes
// through — returning the full member directory regardless of the allow-list,
// the bot's channel membership, or which subject holds the token.
describe("workspace-scoped tools the allow-list cannot bound", () => {
  it("withholds bulk user enumeration from the HTTP transport", () => {
    const advertised = toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name);
    expect(advertised).not.toContain("slack_get_users");
    // Kept: resolving one U… id at a time is what a caller needs to turn an
    // author id from allow-listed history into a name.
    expect(advertised).toContain("slack_get_user_profile");
  });

  it("still offers bulk enumeration on stdio, which is not exposed", () => {
    const advertised = toolsFor(resolveConfig(STDIO_ENV)).map((t) => t.name);
    expect(advertised).toContain("slack_get_users");
  });

  // Demonstrates why the tool list has to carry this rather than the guard:
  // the guard is behaving correctly, there is simply no channel to check.
  it("confirms the guard has nothing to bind to on a workspace-scoped call", async () => {
    const capture = captureFetch();
    try {
      await clientFor(HTTP_ENV).getUsers();
      expect(capture.calls).toHaveLength(1);
      expect(capture.calls[0]!.url).toContain("users.list");
    } finally {
      capture.restore();
    }
  });
});
