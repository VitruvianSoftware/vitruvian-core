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

import { ConfigError, parseTransportMode, resolveConfig } from "../src/config.js";

const STDIO_ENV = {
  SLACK_BOT_TOKEN: "xoxb-test",
  SLACK_USER_TOKEN: "xoxp-test",
  SLACK_TEAM_ID: "T123",
};

const HTTP_ENV = {
  MCP_TRANSPORT: "http",
  SLACK_BOT_TOKEN: "xoxb-test",
  SLACK_TEAM_ID: "T123",
  SLACK_CHANNEL_IDS: "C1,C2",
  OIDC_ISSUER: "https://auth.example.test",
  OIDC_PROJECT_ID: "999",
  OIDC_ALLOWED_SUBJECTS: "379361013981513322",
};

describe("parseTransportMode", () => {
  it("defaults to stdio so existing installs are unaffected", () => {
    expect(parseTransportMode(undefined)).toBe("stdio");
    expect(parseTransportMode("")).toBe("stdio");
  });

  it("accepts either mode, case-insensitively", () => {
    expect(parseTransportMode("http")).toBe("http");
    expect(parseTransportMode("HTTP")).toBe("http");
    expect(parseTransportMode(" stdio ")).toBe("stdio");
  });

  // A typo must not silently fall back to stdio: an operator who meant to
  // expose HTTP would get a server that starts and does nothing remote.
  it("rejects anything else rather than falling back", () => {
    expect(() => parseTransportMode("htp")).toThrow(ConfigError);
    expect(() => parseTransportMode("sse")).toThrow(ConfigError);
  });
});

describe("stdio configuration", () => {
  it("preserves the published contract: user token required, writes as user", () => {
    const config = resolveConfig(STDIO_ENV);
    expect(config.transport).toBe("stdio");
    expect(config.slack.userToken).toBe("xoxp-test");
    expect(config.writeToken).toBe("user");
    expect(config.http).toBeUndefined();
  });

  it("still requires the user token, as it always has", () => {
    const { SLACK_USER_TOKEN: _omitted, ...withoutUserToken } = STDIO_ENV;
    expect(() => resolveConfig(withoutUserToken)).toThrow(ConfigError);
  });

  it("does not require an allow-list, and stays permissive without one", () => {
    const config = resolveConfig(STDIO_ENV);
    expect(config.channelGuard.isAllowed("any-channel")).toBe(true);
  });

  it("honours an allow-list when the user sets one", () => {
    const config = resolveConfig({ ...STDIO_ENV, SLACK_CHANNEL_IDS: "C1" });
    expect(config.channelGuard.isAllowed("C1")).toBe(true);
    expect(config.channelGuard.isAllowed("C2")).toBe(false);
  });
});

describe("http configuration", () => {
  it("resolves a complete configuration", () => {
    const config = resolveConfig(HTTP_ENV);
    expect(config.transport).toBe("http");
    expect(config.writeToken).toBe("bot");
    expect(config.slack.userToken).toBeUndefined();
    expect(config.http).toEqual({
      port: 3000,
      issuer: "https://auth.example.test",
      projectId: "999",
      allowedSubjects: ["379361013981513322"],
    });
    expect(config.channelGuard.allowed).toEqual(["C1", "C2"]);
  });

  // The decision this whole build turns on: no user token in a remote
  // deployment. Refusing to start is stronger than leaving it unused, because
  // "unused" is a property of today's code paths only.
  it("refuses to start if a user token is present", () => {
    expect(() =>
      resolveConfig({ ...HTTP_ENV, SLACK_USER_TOKEN: "xoxp-test" })
    ).toThrow(ConfigError);

    try {
      resolveConfig({ ...HTTP_ENV, SLACK_USER_TOKEN: "xoxp-test" });
    } catch (error) {
      // The message has to explain *why*, or someone will just delete the check.
      expect((error as Error).message).toContain("bot-token-only");
      expect((error as Error).message).toContain("DMs");
    }
  });

  it("requires an explicit channel allow-list", () => {
    const { SLACK_CHANNEL_IDS: _omitted, ...withoutAllowlist } = HTTP_ENV;
    expect(() => resolveConfig(withoutAllowlist)).toThrow(
      /SLACK_CHANNEL_IDS must list at least one channel/
    );
  });

  it("requires the token-validation settings", () => {
    const { OIDC_ISSUER: _i, ...noIssuer } = HTTP_ENV;
    expect(() => resolveConfig(noIssuer)).toThrow(/OIDC_ISSUER is required/);

    const { OIDC_PROJECT_ID: _p, ...noProject } = HTTP_ENV;
    expect(() => resolveConfig(noProject)).toThrow(
      /OIDC_PROJECT_ID is required/
    );
  });

  // The only identity control here that is evaluated per request. The audience
  // check and projectRoleCheck are both decided when Zitadel issues a token, so
  // revoking a grant leaves issued tokens working until they expire.
  it("requires at least one allowed subject", () => {
    const { OIDC_ALLOWED_SUBJECTS: _s, ...noSubjects } = HTTP_ENV;
    expect(() => resolveConfig(noSubjects)).toThrow(
      /OIDC_ALLOWED_SUBJECTS must list at least one/
    );
    // Present-but-empty is the same intent as absent, and the more likely
    // shape: a manifest that declares the variable with no value.
    expect(() =>
      resolveConfig({ ...HTTP_ENV, OIDC_ALLOWED_SUBJECTS: "  , ,, " })
    ).toThrow(ConfigError);
  });

  it("parses several subjects and drops duplicates", () => {
    const config = resolveConfig({
      ...HTTP_ENV,
      OIDC_ALLOWED_SUBJECTS: " 111, 222 ,111,",
    });
    expect(config.http?.allowedSubjects).toEqual(["111", "222"]);
  });

  it("does not require subjects on stdio", () => {
    // stdio has no bearer tokens at all; requiring this there would break
    // every existing local user for a check that has nothing to check.
    expect(() => resolveConfig(STDIO_ENV)).not.toThrow();
  });

  it("defaults the port and validates an explicit one", () => {
    expect(resolveConfig(HTTP_ENV).http?.port).toBe(3000);
    expect(resolveConfig({ ...HTTP_ENV, PORT: "8080" }).http?.port).toBe(8080);
    expect(() => resolveConfig({ ...HTTP_ENV, PORT: "0" })).toThrow(ConfigError);
    expect(() => resolveConfig({ ...HTTP_ENV, PORT: "70000" })).toThrow(
      ConfigError
    );
    expect(() => resolveConfig({ ...HTTP_ENV, PORT: "http" })).toThrow(
      ConfigError
    );
  });

  it("still requires the bot token and team ID", () => {
    const { SLACK_BOT_TOKEN: _b, ...noBot } = HTTP_ENV;
    expect(() => resolveConfig(noBot)).toThrow(/SLACK_BOT_TOKEN is required/);

    const { SLACK_TEAM_ID: _t, ...noTeam } = HTTP_ENV;
    expect(() => resolveConfig(noTeam)).toThrow(/SLACK_TEAM_ID is required/);
  });
});
