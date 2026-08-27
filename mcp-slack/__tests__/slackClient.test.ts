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

import { SlackClient, UserTokenUnavailableError } from "../src/slackClient.js";
import {
  ChannelNotAllowedError,
  ChannelVisibilityMismatchError,
  UnusableChannelParamError,
} from "../src/channelAllowlist.js";
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
  OIDC_ALLOWED_SUBJECTS: "379361013981513322",
  OIDC_ALLOWED_CLIENT_ID: "111222333",
};

/**
 * Captures outbound Slack calls instead of making them.
 *
 * `is_private` is in the default response because `conversations.info` always
 * returns it, and the visibility check refuses a response without it. The
 * first version of this mock returned a bare `channel: {}`, which made every
 * caller of `conversations.info` fail closed — correct behaviour against an
 * unfaithful mock. `channel` is the one place a stub that is *thinner* than
 * the real API produces a wrong test result rather than a passing one.
 */
function captureFetch(channel: Record<string, unknown> = { is_private: false }) {
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
      return new Response(JSON.stringify({ ok: true, channel }), {
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

// With user token available on HTTP (impersonation mode), channel-scoped
// user-token tools are unlocked but workspace-scoped ones stay withheld.
describe("impersonation-mode tool surface", () => {
  const HTTP_IMPERSONATE_ENV = {
    ...HTTP_ENV,
    SLACK_USER_TOKEN: "xoxp-test",
  };

  it("unlocks channel-scoped user-token tools when user token is present", () => {
    const advertised = toolsFor(resolveConfig(HTTP_IMPERSONATE_ENV)).map(
      (t) => t.name
    );
    expect(advertised).toContain("slack_set_channel_topic");
    expect(advertised).toContain("slack_add_reaction");
    expect(advertised).toContain("slack_pin_message");
    expect(advertised).toContain("slack_unpin_message");
    expect(advertised).toContain("slack_add_bookmark");
  });

  it("still withholds workspace-scoped tools even with user token", () => {
    const advertised = toolsFor(resolveConfig(HTTP_IMPERSONATE_ENV)).map(
      (t) => t.name
    );
    expect(advertised).not.toContain("slack_get_users");
    expect(advertised).not.toContain("slack_search_messages");
    expect(advertised).not.toContain("slack_search_files");
    expect(advertised).not.toContain("slack_create_canvas");
    expect(advertised).not.toContain("slack_edit_canvas");
    expect(advertised).not.toContain("slack_lookup_canvas_sections");
    expect(advertised).not.toContain("slack_delete_canvas");
  });

  it("withholds user-token tools when user token is absent (bot-only mode)", () => {
    const advertised = toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name);
    expect(advertised).not.toContain("slack_set_channel_topic");
    expect(advertised).not.toContain("slack_add_reaction");
    expect(advertised).not.toContain("slack_pin_message");
    expect(advertised).not.toContain("slack_unpin_message");
    expect(advertised).not.toContain("slack_add_bookmark");
  });
});

// Startup verification: the one check that runs before the listener binds.
//
// This is the layer that catches the mistake the allow-list structurally
// cannot — a private channel ID pasted into SLACK_CHANNEL_IDS is on the list,
// so the guard admits it. Only Slack can say the declaration was wrong.
describe("verifyAllowlistVisibility", () => {
  let capture: ReturnType<typeof captureFetch> | undefined;
  afterEach(() => capture?.restore());

  const PRIVATE_ENV = {
    ...HTTP_ENV,
    SLACK_CHANNEL_IDS: "C_PUBLIC",
    SLACK_PRIVATE_CHANNEL_IDS: "G_PRIVATE",
  };

  it("passes when every channel is what configuration claims", async () => {
    // conversations.info is called per channel, and the declaration decides
    // what a passing answer looks like for each.
    const spy = jest
      .spyOn(globalThis, "fetch")
      .mockImplementation(async (input: RequestInfo | URL) => {
        const isPrivate = String(input).includes("G_PRIVATE");
        return new Response(
          JSON.stringify({ ok: true, channel: { is_private: isPrivate } }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        );
      });
    await expect(
      clientFor(PRIVATE_ENV).verifyAllowlistVisibility()
    ).resolves.toBeUndefined();
    spy.mockRestore();
  });

  it("refuses to start when a private channel was declared public", async () => {
    // The whole reason the two lists exist. Every channel answers is_private:
    // true, so C_PUBLIC — declared public — is a contradiction.
    capture = captureFetch({ is_private: true });
    await expect(
      clientFor(PRIVATE_ENV).verifyAllowlistVisibility()
    ).rejects.toThrow(ChannelVisibilityMismatchError);
  });

  it("refuses to start when the bot cannot see an allow-listed channel", async () => {
    // An entry that silently does nothing is worth failing on: the reasons
    // (bot not invited, wrong ID, wrong workspace) are all deploy-time facts.
    const spy = jest.spyOn(globalThis, "fetch").mockImplementation(
      async () =>
        new Response(JSON.stringify({ ok: false, error: "channel_not_found" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        })
    );
    await expect(
      clientFor(PRIVATE_ENV).verifyAllowlistVisibility()
    ).rejects.toThrow(/channel_not_found/);
    // The remedy is in the message because this is read at deploy time. The
    // intuitive order — add the ID, deploy, then invite the bot — produces
    // exactly this error, and without the remedy it reads as a broken deploy.
    await expect(
      clientFor(PRIVATE_ENV).verifyAllowlistVisibility()
    ).rejects.toThrow(/Invite the bot to the channel first/);
    spy.mockRestore();
  });

  it("distinguishes Slack being unreachable from Slack disagreeing", async () => {
    // Both exit non-zero, so the exit code cannot tell them apart — the
    // message has to. One is fixed by editing SLACK_PRIVATE_CHANNEL_IDS; the
    // other is fixed by waiting. Same split the auth path draws between an IdP
    // outage and a bad token.
    const spy = jest.spyOn(globalThis, "fetch").mockImplementation(async () => {
      throw new TypeError("fetch failed");
    });
    await expect(
      clientFor(PRIVATE_ENV).verifyAllowlistVisibility()
    ).rejects.toThrow(/did not return a usable answer.*fetch failed/s);
    // And not as a disagreement: Slack never answered, so there was nothing to
    // disagree with. That is the discrimination, not the wording.
    await expect(
      clientFor(PRIVATE_ENV).verifyAllowlistVisibility()
    ).rejects.not.toBeInstanceOf(ChannelVisibilityMismatchError);
    spy.mockRestore();
  });

  it("checks nothing on stdio, which declares no visibility", async () => {
    // The unrestricted guard has an empty allowed list, so the loop does not
    // run at all — no Slack calls, no failure, no behaviour change for the
    // path every existing user is on.
    capture = captureFetch({ is_private: true });
    await expect(
      clientFor(STDIO_ENV).verifyAllowlistVisibility()
    ).resolves.toBeUndefined();
    expect(capture.calls).toHaveLength(0);
  });
});

describe("request-time visibility checks are free ones only", () => {
  let capture: ReturnType<typeof captureFetch>;
  afterEach(() => capture.restore());

  it("catches a mismatch on getChannelInfo without a second call", async () => {
    capture = captureFetch({ is_private: true });
    await expect(
      clientFor(HTTP_ENV).getChannelInfo("C_ALLOWED")
    ).rejects.toThrow(ChannelVisibilityMismatchError);
    expect(capture.calls).toHaveLength(1);
  });

  it("does not add a round trip to history or replies", async () => {
    // Deliberate: conversations.history does not return is_private, so
    // checking there would mean an extra conversations.info on the hot path to
    // re-answer what startup already settled. One call in, one call out.
    capture = captureFetch({ is_private: true });
    const client = clientFor(HTTP_ENV);
    await client.getChannelHistory("C_ALLOWED");
    await client.getThreadReplies("C_ALLOWED", "1234.5678");
    expect(capture.calls).toHaveLength(2);
    expect(capture.calls.every((c) => !c.url.includes("conversations.info"))).toBe(
      true
    );
  });
});

describe("the user-token backstop is typed, not a bare Error", () => {
  it("throws UserTokenUnavailableError so callers can tell it from an outage", async () => {
    // verifyAllowlistVisibility wraps everything out of api() in a message
    // asserting Slack was unreachable. That claim is false for this one, which
    // is a configuration fault — the same assume-the-cause mistake auth.ts
    // stopped making. Unreachable from that call site today; the type is what
    // keeps it unreachable-and-correct rather than unreachable-and-lucky.
    const capture = captureFetch();
    try {
      await expect(
        clientFor(HTTP_ENV).setChannelTopic("C_ALLOWED", "x")
      ).rejects.toBeInstanceOf(UserTokenUnavailableError);
      expect(capture.calls).toHaveLength(0);
    } finally {
      capture.restore();
    }
  });
});
