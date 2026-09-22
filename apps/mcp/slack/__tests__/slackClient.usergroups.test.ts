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

// User groups are workspace-scoped: nothing in a usergroups.* call names a
// channel, so the allow-list has nothing to bind — the same shape as
// users.list, and handled the same way. Reads that enumerate people, and every
// write, are withheld from bot-only HTTP; the handle list alone is not. The
// one channel-shaped input (a group's default channels) is checked explicitly
// because Slack spells it `channels`, which the parameter guard does not read.

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

const HTTP_IMPERSONATE_ENV = { ...HTTP_ENV, SLACK_USER_TOKEN: "xoxp-test" };

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

describe("user group reads", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch();
  });
  afterEach(() => capture.restore());

  it("lists groups with the bot token, excluding disabled ones by default", async () => {
    await clientFor(STDIO_ENV).listUserGroups();
    const url = capture.calls[0]!.url;
    expect(url).toContain("usergroups.list");
    expect(url).toContain("include_disabled=false");
    expect(url).toContain("team_id=T123");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
  });

  it("includes disabled groups when asked", async () => {
    await clientFor(STDIO_ENV).listUserGroups(true);
    expect(capture.calls[0]!.url).toContain("include_disabled=true");
  });

  it("lists a group's members with the bot token", async () => {
    await clientFor(STDIO_ENV).listUserGroupMembers("S0GROUP001");
    const url = capture.calls[0]!.url;
    expect(url).toContain("usergroups.users.list");
    expect(url).toContain("usergroup=S0GROUP001");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
  });
});

describe("user group writes", () => {
  let capture: ReturnType<typeof captureFetch>;
  beforeEach(() => {
    capture = captureFetch();
  });
  afterEach(() => capture.restore());

  it("creates a group as the user with its default channels joined", async () => {
    await clientFor(STDIO_ENV).createUserGroup({
      name: "Platform",
      handle: "platform",
      description: "Platform engineers",
      channelIds: ["C0ALLOWED1", "C0SECOND01"],
    });
    expect(capture.calls[0]!.url).toContain("usergroups.create");
    expect(capture.calls[0]!.method).toBe("POST");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxp-test");
    expect(JSON.parse(capture.calls[0]!.body!)).toEqual({
      name: "Platform",
      handle: "platform",
      description: "Platform engineers",
      channels: "C0ALLOWED1,C0SECOND01",
      team_id: "T123",
    });
  });

  it("refuses a default channel outside the allow-list before calling Slack", async () => {
    await expect(
      clientFor(HTTP_IMPERSONATE_ENV).createUserGroup({
        name: "x",
        handle: "x",
        channelIds: ["C0ALLOWED1", "G0PRIVATE1"],
      }),
    ).rejects.toBeInstanceOf(ChannelNotAllowedError);
    expect(capture.calls).toHaveLength(0);
  });

  it("updates only the fields given", async () => {
    await clientFor(STDIO_ENV).updateUserGroup("S0GROUP001", {
      handle: "platform-eng",
    });
    expect(capture.calls[0]!.url).toContain("usergroups.update");
    expect(JSON.parse(capture.calls[0]!.body!)).toEqual({
      usergroup: "S0GROUP001",
      handle: "platform-eng",
      team_id: "T123",
    });
  });

  it("replaces the member list as the user", async () => {
    await clientFor(STDIO_ENV).setUserGroupMembers("S0GROUP001", ["U1", "U2"]);
    expect(capture.calls[0]!.url).toContain("usergroups.users.update");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxp-test");
    expect(JSON.parse(capture.calls[0]!.body!)).toEqual({
      usergroup: "S0GROUP001",
      users: "U1,U2",
      team_id: "T123",
    });
  });

  it("enables and disables through the two distinct endpoints", async () => {
    const client = clientFor(STDIO_ENV);
    await client.setUserGroupEnabled("S0GROUP001", false);
    await client.setUserGroupEnabled("S0GROUP001", true);
    expect(capture.calls[0]!.url).toContain("usergroups.disable");
    expect(capture.calls[1]!.url).toContain("usergroups.enable");
    expect(JSON.parse(capture.calls[0]!.body!)).toEqual({
      usergroup: "S0GROUP001",
      team_id: "T123",
    });
  });

  it("refuses every write on a transport without a user token", async () => {
    const client = clientFor(HTTP_ENV);
    await expect(
      client.createUserGroup({ name: "x", handle: "x" }),
    ).rejects.toBeInstanceOf(UserTokenUnavailableError);
    await expect(
      client.setUserGroupMembers("S0GROUP001", ["U1"]),
    ).rejects.toBeInstanceOf(UserTokenUnavailableError);
    await expect(
      client.setUserGroupEnabled("S0GROUP001", false),
    ).rejects.toBeInstanceOf(UserTokenUnavailableError);
    expect(capture.calls).toHaveLength(0);
  });
});

describe("user group tools per transport", () => {
  const WRITES = [
    "slack_create_user_group",
    "slack_update_user_group",
    "slack_set_user_group_members",
    "slack_set_user_group_enabled",
  ];

  it("advertises the handle list on bot-only HTTP", () => {
    const advertised = toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name);
    expect(advertised).toContain("slack_list_user_groups");
  });

  it("withholds member enumeration and every write on bot-only HTTP", () => {
    const advertised = toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name);
    expect(advertised).not.toContain("slack_list_user_group_members");
    for (const name of WRITES) expect(advertised).not.toContain(name);
  });

  it("offers all of them with a user token, on either transport", () => {
    for (const env of [STDIO_ENV, HTTP_IMPERSONATE_ENV]) {
      const advertised = toolsFor(resolveConfig(env)).map((t) => t.name);
      expect(advertised).toContain("slack_list_user_group_members");
      for (const name of WRITES) expect(advertised).toContain(name);
    }
  });
});
