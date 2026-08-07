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

// ---------------------------------------------------------------------------
// Startup configuration
// ---------------------------------------------------------------------------
//
// The two transports have deliberately different requirements, and the
// asymmetry is the point:
//
//   stdio — unchanged from the published behaviour. The caller is a local
//   process the user started, so the user token is present, writes post as the
//   user, and no allow-list or authentication is required.
//
//   http  — a network-reachable listener. The user token is refused outright
//   rather than merely unused (it would let a remote caller post as the human
//   and search their DMs), an explicit channel allow-list is mandatory, and
//   every request must carry a bearer token this server can verify.
//
// Everything below fails closed: a misconfigured HTTP listener does not start.

import { createChannelGuard, type ChannelGuard } from "./channelAllowlist.js";

export type TransportMode = "stdio" | "http";

/** Which credential the write tools use. See {@link resolveConfig}. */
export type WriteTokenPreference = "bot" | "user";

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

export interface SlackCredentials {
  botToken: string;
  /** Absent on the HTTP transport by design. */
  userToken?: string;
  teamId: string;
}

export interface HttpConfig {
  port: number;
  /** OIDC issuer whose tokens this server accepts. */
  issuer: string;
  /** Zitadel project ID that must appear in each token's audience. */
  projectId: string;
}

export interface ServerConfig {
  transport: TransportMode;
  slack: SlackCredentials;
  channelGuard: ChannelGuard;
  writeToken: WriteTokenPreference;
  /** Present only when `transport === "http"`. */
  http?: HttpConfig;
}

export type Env = Record<string, string | undefined>;

function required(env: Env, name: string, why: string): string {
  const value = env[name]?.trim();
  if (!value) throw new ConfigError(`${name} is required ${why}.`);
  return value;
}

export function parseTransportMode(raw: string | undefined): TransportMode {
  // An empty value is treated as unset — a manifest that declares the variable
  // without a value is the same intent as omitting it.
  const value = raw?.trim().toLowerCase();
  if (!value) return "stdio";
  if (value === "stdio" || value === "http") return value;
  throw new ConfigError(
    `MCP_TRANSPORT must be "stdio" or "http" (got "${raw}"). ` +
      `Omit it for the default stdio behaviour.`
  );
}

function parsePort(raw: string | undefined): number {
  if (!raw?.trim()) return 3000;
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new ConfigError(`PORT must be an integer 1-65535 (got "${raw}").`);
  }
  return port;
}

/**
 * Resolves and validates startup configuration, or throws {@link ConfigError}.
 *
 * Pure in `env` so the failure modes are testable without spawning a process —
 * these branches decide whether a public endpoint is safe to expose, which is
 * not something to leave to a manual smoke test.
 */
export function resolveConfig(env: Env): ServerConfig {
  const transport = parseTransportMode(env.MCP_TRANSPORT);
  const teamId = required(env, "SLACK_TEAM_ID", "to scope Slack API calls");
  const botToken = required(env, "SLACK_BOT_TOKEN", "for all Slack reads");

  if (transport === "stdio") {
    // The published contract: stdio has always required the user token, and
    // its writes have always posted as the user. Preserved exactly.
    const userToken = required(
      env,
      "SLACK_USER_TOKEN",
      "on the stdio transport, which posts and searches as the authenticated user"
    );
    return {
      transport,
      slack: { botToken, userToken, teamId },
      channelGuard: createChannelGuard(env.SLACK_CHANNEL_IDS, {
        required: false,
      }),
      writeToken: "user",
    };
  }

  // Refused, not ignored. A user token present in the environment of a
  // network-reachable listener is a latent hazard: any later code path that
  // reaches for it would silently hand a remote caller the human's identity.
  // Failing at startup makes that impossible rather than merely unlikely.
  if (env.SLACK_USER_TOKEN?.trim()) {
    throw new ConfigError(
      "SLACK_USER_TOKEN must not be set when MCP_TRANSPORT=http. The HTTP " +
        "listener is bot-token-only by design: the user token posts as the " +
        "authenticated human and can search their DMs and private channels. " +
        "Remove it from this deployment's environment."
    );
  }

  return {
    transport,
    slack: { botToken, teamId },
    channelGuard: createChannelGuard(env.SLACK_CHANNEL_IDS, { required: true }),
    // Writes go out as the app. This is only reachable because the Slack app
    // manifest grants the bot chat:write; without it Slack rejects the call.
    writeToken: "bot",
    http: {
      port: parsePort(env.PORT),
      issuer: required(
        env,
        "OIDC_ISSUER",
        "to verify bearer tokens (e.g. https://auth.ipv1337.dev)"
      ),
      projectId: required(
        env,
        "OIDC_PROJECT_ID",
        "to check the token audience; it is a stack output of zitadel-apps-mcp-slack"
      ),
    },
  };
}
