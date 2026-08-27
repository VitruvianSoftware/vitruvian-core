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
  /** The `sub` values this endpoint serves. Never empty on HTTP. */
  allowedSubjects: string[];
  /** OIDC client this server pins itself to (#1491). Never empty on HTTP. */
  allowedClientId: string;
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

/**
 * Splits `OIDC_ALLOWED_SUBJECTS`, refusing an empty result.
 *
 * Mandatory on HTTP, and the refusal is the point rather than an inconvenience.
 * Every other identity control here is decided when Zitadel *issues* a token —
 * the audience scope, and `projectRoleCheck` if it is ever turned on — so all
 * of them leave an already-issued token working until it expires. This list is
 * read per request, which makes it the only one whose revocation takes effect
 * immediately, and the only one that separates two users of the same client.
 *
 * Deliberately not sharing parseChannelIds: the shapes coincide today, and
 * coupling a subject list to a channel-list parser means a later change made
 * for channels silently changes who can authenticate.
 */
function parseSubjects(raw: string | undefined): string[] {
  const seen = new Set<string>();
  const subjects: string[] = [];
  for (const part of (raw ?? "").split(",")) {
    const value = part.trim();
    if (value.length === 0 || seen.has(value)) continue;
    seen.add(value);
    subjects.push(value);
  }
  if (subjects.length === 0) {
    throw new ConfigError(
      "OIDC_ALLOWED_SUBJECTS must list at least one Zitadel subject (sub) " +
        "when MCP_TRANSPORT=http. Without it any account this Zitadel " +
        "instance will issue a token to reaches this endpoint, which is a " +
        "much larger set than the people it is meant to serve. The value is " +
        "the numeric user ID; a rejected caller's sub is named in the 403."
    );
  }
  return subjects;
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
 * Parses `SLACK_WRITE_MODE`, which controls whether write operations on the
 * HTTP transport use the user token (impersonation) or the bot token.
 *
 * - `"user"` — writes post as the authenticated human. Requires
 *   `SLACK_USER_TOKEN` to be present; validated by the caller.
 * - `"bot"` — writes post as the app bot.
 * - Absent / empty — defaults to `"user"` if `SLACK_USER_TOKEN` is present,
 *   `"bot"` otherwise. This means impersonation is the default when the
 *   credential is available, matching the stdio transport's behaviour, and
 *   operators who deploy without a user token get the previous bot-only
 *   behaviour with no config change.
 *
 * Only meaningful on the HTTP transport; stdio always writes as the user.
 */
export function parseWriteMode(
  raw: string | undefined,
  hasUserToken: boolean
): WriteTokenPreference {
  const value = raw?.trim().toLowerCase();
  if (!value) return hasUserToken ? "user" : "bot";
  if (value === "user" || value === "bot")
    return value as WriteTokenPreference;
  throw new ConfigError(
    `SLACK_WRITE_MODE must be "user" or "bot" (got "${raw}"). ` +
      `Omit it to default based on whether SLACK_USER_TOKEN is present.`
  );
}

/**
 * Resolves and validates startup configuration, or throws {@link ConfigError}.
 *
 * Pure in `env` so the failure modes are testable without spawning a process —
 * these branches decide whether a public endpoint is safe to expose, which is
 * not something to leave to a manual smoke test.
 *
 * Called exactly once, at startup. There is deliberately no watch, no SIGHUP
 * handler and no reload path anywhere in this package, and that absence is
 * load-bearing rather than incidental: the guard is captured once and cannot
 * change under an in-flight request. Config hot-reload is the kind of
 * convenience that arrives looking like an improvement and would put a race
 * inside the only control standing in front of private channels.
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
      channelGuard: createChannelGuard(
        env.SLACK_CHANNEL_IDS,
        // Not enforced here: stdio users who set SLACK_CHANNEL_IDS were never
        // asked to declare visibility, so every channel would read as public
        // and any private one among them would begin failing on an upgrade.
        { required: false, enforceVisibility: false },
        env.SLACK_PRIVATE_CHANNEL_IDS
      ),
      writeToken: "user",
    };
  }

  // ── HTTP transport: user-token impersonation is opt-in ──────────────
  //
  // The previous invariant was "refused, not ignored": any user token in
  // the environment of a network-reachable listener was a hard startup
  // error. That has been relaxed to an *explicit opt-in*: when
  // SLACK_USER_TOKEN is present, SLACK_WRITE_MODE controls whether writes
  // impersonate the human (default when the token is present) or stay as
  // the bot. The Zitadel `sub` allowlist and channel allowlist remain the
  // security boundary — the token's blast radius is bounded by those
  // controls rather than by the transport boundary alone.
  //
  // When the user token is absent, behaviour is identical to the previous
  // bot-only mode: no config change required for existing deployments.
  const userToken = env.SLACK_USER_TOKEN?.trim() || undefined;
  const writeMode = parseWriteMode(env.SLACK_WRITE_MODE, !!userToken);

  // Fail fast: asking for impersonation without the credential is a
  // configuration error, not a silent fallback.
  if (writeMode === "user" && !userToken) {
    throw new ConfigError(
      "SLACK_WRITE_MODE=user requires SLACK_USER_TOKEN to be set. The " +
        "user token is the credential that posts as the authenticated " +
        "human. Either set it, or use SLACK_WRITE_MODE=bot."
    );
  }

  return {
    transport,
    slack: { botToken, ...(userToken ? { userToken } : {}), teamId },
    channelGuard: createChannelGuard(
      env.SLACK_CHANNEL_IDS,
      { required: true, enforceVisibility: true },
      env.SLACK_PRIVATE_CHANNEL_IDS
    ),
    writeToken: writeMode,
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
      allowedSubjects: parseSubjects(env.OIDC_ALLOWED_SUBJECTS),
      // Distinct from OIDC_PROJECT_ID: that one is the audience check, which
      // is not an identity check (`aud` is caller-authored). This pins the
      // caller to this server's own OIDC client — see auth.ts's
      // ClientNotAllowedError for why that closes a gap allowedSubjects
      // cannot.
      allowedClientId: required(
        env,
        "OIDC_ALLOWED_CLIENT_ID",
        "to pin the caller to this server's own OIDC client (#1491); it is " +
          "a stack output of zitadel-apps-mcp-slack, distinct from " +
          "OIDC_PROJECT_ID"
      ),
    },
  };
}
