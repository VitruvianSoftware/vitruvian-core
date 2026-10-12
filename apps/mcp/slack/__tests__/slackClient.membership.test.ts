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

// Channel membership and custom emoji — the slackcli parity gaps that need no
// new security control, only the existing ones applied. Membership calls all
// name a channel, so the allow-list binds them for free; the one thing worth
// asserting per method is *which* token each uses, because that is the
// difference between "the bot joins" and "the human is made to join".

import { SlackClient, UserTokenUnavailableError } from "../src/slackClient.js";
import { ChannelNotAllowedError } from "../src/channelAllowlist.js";
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
  const calls: {
    url: string;
    method: string;
    auth: string | undefined;
    body?: string;
  }[] = [];
  const spy = jest
    .spyOn(globalThis, "fetch")
    .mockImplementation(
      async (input: RequestInfo | URL, init?: RequestInit) => {
        const headers = (init?.headers ?? {}) as Record<string, string>;
        calls.push({
          url: String(input),
          method: init?.method ?? "GET",
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

describe("channel membership", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch();
  });
  afterEach(() => capture.restore());

  it("joins as the bot by default, so the bot can self-join public channels", async () => {
    await clientFor(STDIO_ENV).joinChannel("C0ALLOWED1");
    expect(capture.calls[0]!.url).toContain("conversations.join");
    expect(capture.calls[0]!.method).toBe("POST");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
    expect(JSON.parse(capture.calls[0]!.body!)).toEqual({
      channel: "C0ALLOWED1",
    });
  });

  it("joins as the user when asked to", async () => {
    await clientFor(STDIO_ENV).joinChannel("C0ALLOWED1", "user");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxp-test");
  });

  it("leaves as the bot by default", async () => {
    await clientFor(STDIO_ENV).leaveChannel("C0ALLOWED1");
    expect(capture.calls[0]!.url).toContain("conversations.leave");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
  });

  it("lists members with the bot token and a bounded page size", async () => {
    await clientFor(STDIO_ENV).listChannelMembers("C0ALLOWED1", 500, "next");
    const url = capture.calls[0]!.url;
    expect(url).toContain("conversations.members");
    expect(url).toContain("channel=C0ALLOWED1");
    expect(url).toContain("limit=200");
    expect(url).toContain("cursor=next");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
  });

  it("invites as the user, joining the IDs the way Slack wants them", async () => {
    await clientFor(STDIO_ENV).inviteToChannel("C0ALLOWED1", ["U1", "U2"]);
    expect(capture.calls[0]!.url).toContain("conversations.invite");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxp-test");
    expect(JSON.parse(capture.calls[0]!.body!)).toEqual({
      channel: "C0ALLOWED1",
      users: "U1,U2",
    });
  });

  it("marks read as the user, because the bot token would move the bot's cursor", async () => {
    await clientFor(STDIO_ENV).markRead("C0ALLOWED1", "1712345678.123456");
    expect(capture.calls).toHaveLength(1);
    expect(capture.calls[0]!.url).toContain("conversations.mark");
    expect(capture.calls[0]!.method).toBe("POST");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxp-test");
    expect(JSON.parse(capture.calls[0]!.body!)).toEqual({
      channel: "C0ALLOWED1",
      ts: "1712345678.123456",
    });
  });

  it("refuses to mark read on a transport without a user token", async () => {
    await expect(
      clientFor(HTTP_ENV).markRead("C0ALLOWED1", "1712345678.123456"),
    ).rejects.toBeInstanceOf(UserTokenUnavailableError);
    expect(capture.calls).toHaveLength(0);
    expect(toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name)).not.toContain(
      "slack_mark_read",
    );
  });

  it.each([
    ["markRead", (c: SlackClient) => c.markRead("G0PRIVATE1", "1.2")],
    ["joinChannel", (c: SlackClient) => c.joinChannel("G0PRIVATE1")],
    ["leaveChannel", (c: SlackClient) => c.leaveChannel("G0PRIVATE1")],
    [
      "listChannelMembers",
      (c: SlackClient) => c.listChannelMembers("G0PRIVATE1"),
    ],
    [
      "inviteToChannel",
      (c: SlackClient) => c.inviteToChannel("G0PRIVATE1", ["U1"]),
    ],
  ])("%s refuses a channel outside the allow-list", async (_name, call) => {
    await expect(call(clientFor(HTTP_ENV))).rejects.toBeInstanceOf(
      ChannelNotAllowedError,
    );
    expect(capture.calls).toHaveLength(0);
  });

  it("refuses a user-token join on a transport without a user token", async () => {
    await expect(
      clientFor(HTTP_ENV).joinChannel("C0ALLOWED1", "user"),
    ).rejects.toBeInstanceOf(UserTokenUnavailableError);
    expect(capture.calls).toHaveLength(0);
  });
});

describe("custom emoji", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch({
      ok: true,
      emoji: {
        partyparrot: "https://emoji.slack-edge.com/T1/partyparrot/a.gif",
        parrot: "alias:partyparrot",
        shipit: "https://emoji.slack-edge.com/T1/shipit/b.png",
      },
    });
  });
  afterEach(() => capture.restore());

  it("lists custom emoji with the bot token", async () => {
    const result = (await clientFor(STDIO_ENV).listEmoji()) as {
      ok: boolean;
      emoji: Record<string, string>;
    };
    expect(capture.calls[0]!.url).toContain("emoji.list");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
    expect(Object.keys(result.emoji).sort()).toEqual([
      "parrot",
      "partyparrot",
      "shipit",
    ]);
  });

  it("filters by a case-insensitive substring of the name", async () => {
    const result = (await clientFor(STDIO_ENV).listEmoji("PARROT")) as {
      emoji: Record<string, string>;
    };
    expect(Object.keys(result.emoji).sort()).toEqual(["parrot", "partyparrot"]);
  });

  it("drops aliases when asked", async () => {
    const result = (await clientFor(STDIO_ENV).listEmoji(undefined, false)) as {
      emoji: Record<string, string>;
    };
    expect(Object.keys(result.emoji).sort()).toEqual(["partyparrot", "shipit"]);
  });
});

describe("transport visibility for the membership and emoji tools", () => {
  it("advertises bot-token membership tools and emoji on bot-only HTTP", () => {
    const advertised = toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name);
    expect(advertised).toEqual(
      expect.arrayContaining([
        "slack_join_channel",
        "slack_leave_channel",
        "slack_list_channel_members",
        "slack_list_emoji",
      ]),
    );
  });

  it("withholds invitations, which need the user token, on bot-only HTTP", () => {
    const advertised = toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name);
    expect(advertised).not.toContain("slack_invite_to_channel");
  });

  it("offers invitations on stdio", () => {
    const advertised = toolsFor(resolveConfig(STDIO_ENV)).map((t) => t.name);
    expect(advertised).toContain("slack_invite_to_channel");
  });
});

describe("unread listing", () => {
  type Reply = Record<string, unknown>;
  function routeFetch(route: (method: string, q: URLSearchParams) => Reply) {
    const calls: { method: string; auth: string | undefined }[] = [];
    const spy = jest
      .spyOn(globalThis, "fetch")
      .mockImplementation(
        async (input: RequestInfo | URL, init?: RequestInit) => {
          const url = new URL(String(input));
          const method = url.pathname.replace("/api/", "");
          const headers = (init?.headers ?? {}) as Record<string, string>;
          calls.push({ method, auth: headers.Authorization });
          const reply = route(method, url.searchParams);
          const limited = reply.error === "ratelimited";
          return new Response(JSON.stringify(reply), {
            status: limited ? 429 : 200,
            headers: {
              "Content-Type": "application/json",
              // Zero, so the retry path is exercised without a real wait.
              ...(limited ? { "Retry-After": "0" } : {}),
            },
          });
        },
      );
    return { calls, restore: () => spy.mockRestore() };
  }

  const LAST_READ: Record<string, string> = {
    C_QUIET: "200.0",
    C_BUSY: "100.0",
    C_LIMITED: "100.0",
    C_JOINS: "100.0",
    D_NEVER_OPENED: "0000000000.000000",
  };
  let capture: ReturnType<typeof routeFetch>;
  afterEach(() => capture.restore());

  function workspace(method: string, q: URLSearchParams): Reply {
    if (method === "users.conversations") {
      const types = q.get("types");
      if (types === "im") return { ok: false, error: "missing_scope" };
      if (types === "mpim") {
        return { ok: true, channels: [{ id: "D_NEVER_OPENED" }] };
      }
      return {
        ok: true,
        channels: [
          { id: "C_QUIET" },
          { id: "C_BUSY" },
          { id: "C_LIMITED" },
          { id: "C_JOINS" },
        ],
      };
    }
    const id = q.get("channel")!;
    if (method === "conversations.info") {
      return {
        ok: true,
        channel: { name: id.toLowerCase(), last_read: LAST_READ[id] },
      };
    }
    // conversations.history: the unread check must start at the read cursor.
    if (id === "D_NEVER_OPENED") {
      // What Slack does with the all-zero cursor it hands out itself.
      if (q.get("oldest") !== "0")
        return { ok: false, error: "invalid_ts_oldest" };
      return { ok: true, messages: [{ ts: "500.0" }] };
    }
    expect(q.get("oldest")).toBe(LAST_READ[id]);
    if (id === "C_LIMITED") return { ok: false, error: "ratelimited" };
    if (id === "C_JOINS") {
      return { ok: true, messages: [{ ts: "400.0", subtype: "channel_join" }] };
    }
    if (id === "C_BUSY") {
      return {
        ok: true,
        has_more: true,
        messages: [{ ts: "300.0" }, { ts: "250.0" }],
      };
    }
    return { ok: true, messages: [] };
  }

  it("reports only conversations with messages after the read cursor", async () => {
    capture = routeFetch(workspace);
    const result = await clientFor(STDIO_ENV).listUnread();
    expect(result.conversations).toEqual([
      expect.objectContaining({ id: "D_NEVER_OPENED", unread_count: 1 }),
      {
        id: "C_BUSY",
        name: "c_busy",
        type: "public_channel",
        unread_count: 2,
        unread_count_is_minimum: true,
        last_read: "100.0",
        latest_ts: "300.0",
      },
    ]);
    expect(result.checked).toBe(5);
  });

  it("does not call a channel unread when only join notices are new", async () => {
    capture = routeFetch(workspace);
    const result = await clientFor(STDIO_ENV).listUnread();
    expect(result.conversations.map((c) => c.id)).not.toContain("C_JOINS");
  });

  it("names what it could not check instead of failing the listing", async () => {
    capture = routeFetch(workspace);
    const result = await clientFor(STDIO_ENV).listUnread();
    expect(result.ok).toBe(true);
    expect(result.skipped).toEqual([{ types: "im", error: "missing_scope" }]);
    expect(result.errors).toEqual([{ id: "C_LIMITED", error: "ratelimited" }]);
  });

  it("waits out a rate limit and asks again rather than dropping the conversation", async () => {
    let limitedOnce = false;
    capture = routeFetch((method, q) => {
      if (
        method === "conversations.history" &&
        q.get("channel") === "C_BUSY" &&
        !limitedOnce
      ) {
        limitedOnce = true;
        return { ok: false, error: "ratelimited" };
      }
      return workspace(method, q);
    });
    const result = await clientFor(STDIO_ENV).listUnread();
    expect(limitedOnce).toBe(true);
    expect(result.conversations.map((c) => c.id)).toContain("C_BUSY");
    expect(result.errors.map((e) => e.id)).not.toContain("C_BUSY");
  });

  it("reads cursors with the user token only, never the bot's", async () => {
    capture = routeFetch(workspace);
    await clientFor(STDIO_ENV).listUnread();
    expect(capture.calls.length).toBeGreaterThan(0);
    for (const call of capture.calls) {
      expect(call.auth).toBe("Bearer xoxp-test");
    }
  });

  it("checks only the allow-listed channels when an allow-list is set", async () => {
    capture = routeFetch(workspace);
    const result = await clientFor({
      ...STDIO_ENV,
      SLACK_CHANNEL_IDS: "C_BUSY",
    }).listUnread();
    expect(capture.calls.map((c) => c.method)).toEqual([
      "conversations.info",
      "conversations.history",
    ]);
    expect(result.conversations.map((c) => c.id)).toEqual(["C_BUSY"]);
  });

  it("is refused and hidden on a transport without a user token", async () => {
    capture = routeFetch(workspace);
    await expect(clientFor(HTTP_ENV).listUnread()).rejects.toBeInstanceOf(
      UserTokenUnavailableError,
    );
    expect(capture.calls).toHaveLength(0);
    expect(toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name)).not.toContain(
      "slack_list_unread",
    );
  });
});
