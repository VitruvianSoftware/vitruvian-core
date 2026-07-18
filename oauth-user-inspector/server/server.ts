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

import express, { Request, Response, NextFunction } from "express";
import path from "path";
import { URLSearchParams } from "url";
import fs from "fs";
import { v4 as uuidv4 } from "uuid";
import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import logger, { createRequestLogger, logTiming, logError } from "./logger.js";
import { enhanceOAuthError } from "./oauth-error-guide.js";
import { safeFetch, resolveAndPin, UpstreamError } from "./safeFetch.js";
import {
  resolveExploreTarget,
  UnknownExploreEndpointError,
} from "./apiEndpoints.server.js";
import { securityHeaders } from "./securityHeaders.js";
import { RateLimitTier, rateLimitMiddleware } from "./rateLimit.js";

const app = express();
const port = parseInt(process.env.PORT || "8080", 10);

// Behind Cloudflare Tunnel -> Cloud Run there is exactly one trusted proxy hop,
// so `req.ip` reflects the immediate proxy and CF-Connecting-IP carries the real
// client (see rateLimit.clientIp). trust proxy = 1 keeps Express from blindly
// trusting an arbitrarily long X-Forwarded-For chain.
app.set("trust proxy", 1);

// Express advertises itself via X-Powered-By by default; strip it (don't leak
// the stack, and it's free attack-surface signalling).
app.disable("x-powered-by");

// Initialize Google Secret Manager client
const secretManagerClient = new SecretManagerServiceClient();

process.on("exit", (code) => {
  console.log(`About to exit with code: ${code}`);
});

// In-process TTL cache for Secret Manager reads. A single page load fans out to
// many getSecret() calls (hosted creds + availability checks), each previously a
// separate Secret Manager round-trip; caching collapses those to one read per
// secret per TTL window. The app always reads the "latest" version, so a ROTATED
// secret now takes up to SECRET_CACHE_TTL_MS to propagate to this instance —
// acceptable for this tool (creds rotate rarely; a stale window of <=60s is
// fine, and worst case a 401 on the next call self-heals once the TTL expires).
const SECRET_CACHE_TTL_MS = 60_000;
const secretCache = new Map<string, { value: string; expires: number }>();

// Helper function to retrieve secrets from Google Secret Manager (TTL-cached).
// SECRET_PREFIX (default "") is prepended to the secret id so co-tenant apps
// sharing one project can namespace their secrets (e.g.
// OAUTH_USER_INSPECTOR_GITHUB_APP_OAUTH_CLIENT_ID); an empty prefix preserves
// the historical bare-name behaviour. The cache is keyed on the prefixed id so
// two apps in the same instance can't collide on a cache entry.
export async function getSecret(secretName: string): Promise<string> {
  const prefix = process.env.SECRET_PREFIX ?? "";
  const fullName = `${prefix}${secretName}`;

  const cached = secretCache.get(fullName);
  if (cached && Date.now() < cached.expires) {
    return cached.value;
  }

  try {
    const projectId =
      process.env.GOOGLE_CLOUD_PROJECT || process.env.GCP_PROJECT;
    if (!projectId) {
      throw new Error(
        "GOOGLE_CLOUD_PROJECT or GCP_PROJECT environment variable not set",
      );
    }

    const name = `projects/${projectId}/secrets/${fullName}/versions/latest`;
    const [version] = await secretManagerClient.accessSecretVersion({ name });

    if (!version.payload?.data) {
      throw new Error(`No payload data found for secret: ${secretName}`);
    }

    const value = version.payload.data.toString();
    secretCache.set(fullName, {
      value,
      expires: Date.now() + SECRET_CACHE_TTL_MS,
    });
    return value;
  } catch (error: any) {
    logger.error("Failed to retrieve secret from Secret Manager", {
      secretName,
      error: error.message,
      stack: error.stack,
    });
    throw new Error(
      `Failed to retrieve secret ${secretName}: ${error.message}`,
    );
  }
}

// Default Zitadel (self-hosted IdP) domain. Used when no domain is provided in
// the request body and the ZITADEL_APP_OAUTH_DOMAIN secret is absent, so the
// provider works out of the box. Mirrors how Auth0 sources its domain, but with
// a sensible default for our self-hosted instance.
const DEFAULT_ZITADEL_DOMAIN = "auth.ipv1337.dev";

// Resolve the Zitadel domain from (in order): the request body, the
// ZITADEL_APP_OAUTH_DOMAIN secret, or the built-in default.
async function resolveZitadelDomain(domainFromBody?: string): Promise<string> {
  if (domainFromBody) {
    return domainFromBody;
  }
  try {
    const secretDomain = await getSecret("ZITADEL_APP_OAUTH_DOMAIN");
    if (secretDomain) {
      return secretDomain;
    }
  } catch (e) {
    // Secret absent; fall through to the default.
  }
  return DEFAULT_ZITADEL_DOMAIN;
}

// Helper function to get hosted OAuth credentials
async function getHostedCredentials(
  provider: "github" | "google" | "gitlab" | "auth0" | "zitadel" | "linkedin",
): Promise<{ clientId: string; clientSecret: string }> {
  if (provider === "github") {
    const [clientId, clientSecret] = await Promise.all([
      getSecret("GITHUB_APP_OAUTH_CLIENT_ID"),
      getSecret("GITHUB_APP_OAUTH_CLIENT_SECRET"),
    ]);
    return { clientId, clientSecret };
  } else if (provider === "google") {
    const [clientId, clientSecret] = await Promise.all([
      getSecret("GOOGLE_APP_OAUTH_CLIENT_ID"),
      getSecret("GOOGLE_APP_OAUTH_CLIENT_SECRET"),
    ]);
    return { clientId, clientSecret };
  } else if (provider === "gitlab") {
    const [clientId, clientSecret] = await Promise.all([
      getSecret("GITLAB_APP_OAUTH_CLIENT_ID"),
      getSecret("GITLAB_APP_OAUTH_CLIENT_SECRET"),
    ]);
    return { clientId, clientSecret };
  } else if (provider === "auth0") {
    const [clientId, clientSecret] = await Promise.all([
      getSecret("AUTH0_APP_OAUTH_CLIENT_ID"),
      getSecret("AUTH0_APP_OAUTH_CLIENT_SECRET"),
    ]);
    return { clientId, clientSecret };
  } else if (provider === "zitadel") {
    const [clientId, clientSecret] = await Promise.all([
      getSecret("ZITADEL_APP_OAUTH_CLIENT_ID"),
      getSecret("ZITADEL_APP_OAUTH_CLIENT_SECRET"),
    ]);
    return { clientId, clientSecret };
  } else if (provider === "linkedin") {
    const [clientId, clientSecret] = await Promise.all([
      getSecret("LINKEDIN_APP_OAUTH_CLIENT_ID"),
      getSecret("LINKEDIN_APP_OAUTH_CLIENT_SECRET"),
    ]);
    return { clientId, clientSecret };
  } else {
    throw new Error(`Unsupported provider: ${provider}`);
  }
}

// Validate a client-supplied issuer domain (Auth0 tenant / Zitadel host) before
// it is interpolated into any outbound URL. resolveAndPin throws UpstreamError
// if the domain resolves to anything other than a public unicast address, which
// is exactly the SSRF guard we want on a BYO host (CGNAT/metadata/private/etc.).
// We feed it a throwaway https URL so only the host is exercised here; safeFetch
// re-pins the *real* target URL at call time.
async function validateIssuerDomain(domain: string): Promise<void> {
  // `new URL` would mangle a domain that already contains a scheme or path; the
  // explore/token flows only ever pass a bare hostname[:port], so build a
  // minimal https URL around it and let resolveAndPin reject anything unsafe.
  await resolveAndPin(`https://${domain}/`);
}

// Collapse ANY user-influenced outbound failure (DNS reject / refused / TLS /
// timeout / redirect / size / unknown endpoint) into a single generic client
// response, logging the real reason server-side only. Reflecting distinct
// failure reasons for a user-supplied host is an SSRF recon oracle, so the
// client always sees the same opaque message + a requestId for correlation.
function collapseUpstreamError(
  reqLogger: typeof logger,
  res: Response,
  requestId: string | undefined,
  context: Record<string, unknown>,
  err: unknown,
): void {
  const reason =
    err instanceof UpstreamError
      ? err.reason
      : err instanceof Error
        ? err.message
        : String(err);
  reqLogger.warn("Upstream request failed (collapsed)", {
    ...context,
    reason,
    requestId,
  });
  res.status(502).json({ error: "Upstream request failed", requestId });
}

// --- Middleware ---
// Security headers FIRST, before the request logger, so every response (incl.
// early returns, 4xx/5xx, and static SPA assets) carries CSP/HSTS/etc. The CSP
// is the load-bearing one: it contains an XSS so injected JS can't exfiltrate
// the OAuth tokens this app keeps in the browser's localStorage.
app.use(securityHeaders());

// Request ID and logging middleware
app.use((req: Request, res: Response, next: NextFunction) => {
  req.id = (req.headers["x-request-id"] as string) || uuidv4();
  res.setHeader("X-Request-ID", req.id);

  const reqLogger = createRequestLogger(req);
  req.logger = reqLogger;

  reqLogger.info("Incoming request", {
    method: req.method,
    url: req.url,
    query: req.query,
    headers: {
      "content-type": req.headers["content-type"],
      "user-agent": req.headers["user-agent"],
      referer: req.headers.referer,
    },
  });

  // Log response when finished
  const originalSend = res.send.bind(res);
  res.send = function (data: any): Response {
    reqLogger.info("Response sent", {
      statusCode: res.statusCode,
      statusMessage: res.statusMessage,
      contentLength: data
        ? typeof data === "string"
          ? data.length
          : JSON.stringify(data).length
        : 0,
    });
    return originalSend(data);
  } as any;

  next();
});

// Bound the request body. These endpoints only ever receive small JSON
// (tokens, a code, a provider, an endpoint id), so 64kb is generous; the limit
// keeps a hostile client from spending our memory/CPU on a giant body.
app.use(express.json({ limit: "64kb" }));

// Tokens must not be cached by any intermediary. Mark every /api/* response
// no-store so a proxy/CDN never retains an access/refresh token in a response.
app.use("/api", (req: Request, res: Response, next: NextFunction) => {
  res.setHeader("Cache-Control", "no-store");
  next();
});

// --- Rate limiting (hand-written, in-memory, per client IP) ---
// Tiers are per-IP fixed windows. Keyed on the REAL client IP via
// CF-Connecting-IP (Cloudflare) falling back to req.ip. NOTE: this is fully
// effective only once Cloud Run ingress is locked to the tunnel (separate infra
// change) — until then CF-Connecting-IP is advisory/spoofable, so treat the
// limiter as best-effort defense-in-depth.
// Under Jest the app singleton is hammered by the broader handler suite far past
// these production tiers; raise the ceiling there so the limiter never trips the
// unrelated tests. The 429 + Retry-After behavior is proven directly against a
// low-limit limiter instance in hardening.test.ts. (Same JEST_WORKER_ID gate the
// app already uses to skip listen().)
const RL = process.env.JEST_WORKER_ID ? 1_000_000 : undefined;
const RATE_LIMIT_TIERS: Record<string, RateLimitTier> = {
  // Global /api/* floor: a coarse ceiling across all endpoints.
  apiFloor: { bucket: "api-floor", limit: RL ?? 120, windowMs: 5 * 60_000 },
  // The outbound-proxy endpoint (most abusable; drives upstream calls).
  explore: { bucket: "explore", limit: RL ?? 30, windowMs: 60_000 },
  // Token-bearing OAuth endpoints (exchange/refresh/revoke).
  oauthToken: { bucket: "oauth-token", limit: RL ?? 20, windowMs: 60_000 },
  // Hosted-OAuth helpers (init/availability) — higher, they're cheap & polled.
  oauthHosted: { bucket: "oauth-hosted", limit: RL ?? 60, windowMs: 60_000 },
};

// Order matters: the global floor runs first on every /api/* request, then the
// tighter per-route tiers stack on top of it.
app.use("/api", rateLimitMiddleware(RATE_LIMIT_TIERS.apiFloor));
app.use("/api/explore", rateLimitMiddleware(RATE_LIMIT_TIERS.explore));
app.use(
  ["/api/oauth/token", "/api/oauth/refresh", "/api/oauth/revoke"],
  rateLimitMiddleware(RATE_LIMIT_TIERS.oauthToken),
);
app.use("/api/oauth-hosted", rateLimitMiddleware(RATE_LIMIT_TIERS.oauthHosted));

// --- API Routes ---
// API routes are defined before static file serving.
app.post("/api/oauth/token", async (req: Request, res: Response) => {
  const reqLogger = req.logger || logger;
  const endTimer = logTiming(reqLogger, "oauth-token-exchange");

  try {
    const { code, provider, redirectUri, isHosted } = req.body;
    let { clientId, clientSecret, auth0Domain, zitadelDomain } = req.body;

    reqLogger.info("OAuth token exchange initiated", {
      provider,
      isHosted,
      hasCode: !!code,
      hasRedirectUri: !!redirectUri,
    });

    if (!code || !provider || !redirectUri) {
      reqLogger.warn("OAuth token exchange failed - missing base parameters");
      return res.status(400).json({
        error: "Missing required parameters: code, provider, redirectUri.",
      });
    }

    if (
      provider !== "github" &&
      provider !== "google" &&
      provider !== "gitlab" &&
      provider !== "auth0" &&
      provider !== "zitadel" &&
      provider !== "linkedin"
    ) {
      reqLogger.warn("OAuth token exchange failed - unsupported provider", {
        provider,
      });
      return res.status(400).json({ error: "Unsupported provider." });
    }

    // Auth0 requires a domain
    if (provider === "auth0" && !auth0Domain && !isHosted) {
      reqLogger.warn("OAuth token exchange failed - missing Auth0 domain");
      return res
        .status(400)
        .json({ error: "Auth0 domain is required for non-hosted auth." });
    }

    // If hosted, retrieve credentials from secret manager. Otherwise, require them in the body.
    if (isHosted) {
      const hostedCreds = await getHostedCredentials(provider);
      clientId = hostedCreds.clientId;
      clientSecret = hostedCreds.clientSecret;
      // Hosted Auth0 also requires the domain
      if (provider === "auth0") {
        try {
          auth0Domain = await getSecret("AUTH0_APP_OAUTH_DOMAIN");
        } catch (e) {
          // leave undefined; the provider-specific check below will handle error response
        }
      }
      // Hosted Zitadel resolves its domain from the secret (or built-in default).
      if (provider === "zitadel") {
        zitadelDomain = await resolveZitadelDomain(zitadelDomain);
      }
    } else if (!clientId || !clientSecret) {
      reqLogger.warn(
        "OAuth token exchange failed - missing client credentials for non-hosted flow",
      );
      return res.status(400).json({
        error:
          "Missing required parameters for non-hosted auth: clientId, clientSecret.",
      });
    }

    let tokenUrl: string;
    const fetchOptions: {
      method: string;
      headers: Record<string, string>;
      body: string;
    } = { method: "POST", headers: {}, body: "" };

    if (provider === "github") {
      tokenUrl = "https://github.com/login/oauth/access_token";
      const params = new URLSearchParams();
      params.append("client_id", clientId);
      params.append("client_secret", clientSecret);
      params.append("code", code);
      params.append("redirect_uri", redirectUri);

      fetchOptions.headers = {
        Accept: "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
      };
      fetchOptions.body = params.toString();
    } else if (provider === "google") {
      tokenUrl = "https://oauth2.googleapis.com/token";
      fetchOptions.headers = {
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      fetchOptions.body = JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        code,
        grant_type: "authorization_code",
        redirect_uri: redirectUri,
      });
    } else if (provider === "gitlab") {
      tokenUrl = "https://gitlab.com/oauth/token";
      fetchOptions.headers = {
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      fetchOptions.body = JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        code,
        grant_type: "authorization_code",
        redirect_uri: redirectUri,
      });
    } else if (provider === "auth0") {
      if (!auth0Domain) {
        return res.status(400).json({ error: "Auth0 domain is required." });
      }
      // Validate the BYO/hosted Auth0 domain BEFORE interpolating it into the
      // token URL — this POSTs the owner's client_secret, so the host must be
      // a public unicast issuer, never an internal/CGNAT/metadata target.
      try {
        await validateIssuerDomain(auth0Domain);
      } catch (err) {
        collapseUpstreamError(
          reqLogger,
          res,
          req.id,
          {
            endpoint: "/api/oauth/token",
            provider,
            phase: "domain-validation",
          },
          err,
        );
        endTimer();
        return;
      }
      tokenUrl = `https://${auth0Domain}/oauth/token`;
      fetchOptions.headers = {
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      fetchOptions.body = JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        code,
        grant_type: "authorization_code",
        redirect_uri: redirectUri,
      });
    } else if (provider === "zitadel") {
      // Zitadel is standard OIDC (like Auth0) with a configurable domain that
      // defaults to our self-hosted instance. Its token endpoint expects the
      // form-encoded code grant.
      zitadelDomain = zitadelDomain || (await resolveZitadelDomain());
      try {
        await validateIssuerDomain(zitadelDomain);
      } catch (err) {
        collapseUpstreamError(
          reqLogger,
          res,
          req.id,
          {
            endpoint: "/api/oauth/token",
            provider,
            phase: "domain-validation",
          },
          err,
        );
        endTimer();
        return;
      }
      tokenUrl = `https://${zitadelDomain}/oauth/v2/token`;
      fetchOptions.headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      };
      const params = new URLSearchParams();
      params.append("grant_type", "authorization_code");
      params.append("code", code);
      params.append("redirect_uri", redirectUri);
      params.append("client_id", clientId);
      params.append("client_secret", clientSecret);
      fetchOptions.body = params.toString();
    } else if (provider === "linkedin") {
      tokenUrl = "https://www.linkedin.com/oauth/v2/accessToken";
      fetchOptions.headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      };
      const params = new URLSearchParams();
      params.append("grant_type", "authorization_code");
      params.append("code", code);
      params.append("redirect_uri", redirectUri);
      params.append("client_id", clientId);
      params.append("client_secret", clientSecret);
      fetchOptions.body = params.toString();
    } else {
      // This case is already handled above, but kept for safety.
      return res.status(400).json({ error: "Unsupported provider." });
    }

    reqLogger.info("Making OAuth provider token request", {
      provider,
      tokenUrl,
      method: fetchOptions.method,
    });

    // All token-exchange egress goes through safeFetch: it re-resolves+pins the
    // host to a public unicast IP, validates TLS against the real hostname, and
    // never follows redirects (so a malicious 3xx can't bounce the client_secret
    // POST to an internal target).
    let tokenResponse: { status: number; body: string };
    try {
      tokenResponse = await safeFetch(tokenUrl, fetchOptions);
    } catch (err) {
      collapseUpstreamError(
        reqLogger,
        res,
        req.id,
        { endpoint: "/api/oauth/token", provider, phase: "outbound" },
        err,
      );
      endTimer();
      return;
    }
    const responseText = tokenResponse.body;
    const responseOk =
      tokenResponse.status >= 200 && tokenResponse.status < 300;

    reqLogger.info("OAuth provider response received", {
      provider,
      statusCode: tokenResponse.status,
    });

    if (!responseOk) {
      reqLogger.error("OAuth provider error response", {
        provider,
        statusCode: tokenResponse.status,
        responseText: responseText.substring(0, 500),
      });

      if (provider === "auth0" && !auth0Domain) {
        reqLogger.warn("Auth0 token exchange failed due to missing domain", {
          hint: "Ensure AUTH0_APP_OAUTH_DOMAIN secret exists or pass auth0Domain from client.",
        });
      }

      // Use enhanced error detection to provide better troubleshooting guidance
      const enhancedError = enhanceOAuthError(
        responseText,
        tokenResponse.status,
        provider,
      );

      reqLogger.info("Enhanced OAuth error detected", {
        provider,
        errorCode: enhancedError.errorCode,
        hasGuide: !!enhancedError.guide,
      });

      return res.status(tokenResponse.status).json(enhancedError);
    }

    const tokenData = JSON.parse(responseText);

    // Attach provider-specific metadata helpful to the client
    if (provider === "auth0" && auth0Domain) {
      (tokenData as any).auth0_domain = auth0Domain;
    }
    if (provider === "zitadel" && zitadelDomain) {
      (tokenData as any).zitadel_domain = zitadelDomain;
    }

    reqLogger.info("OAuth token exchange successful", {
      provider,
      hasAccessToken: !!tokenData.access_token,
    });

    endTimer();
    res.json(tokenData);
  } catch (error: any) {
    logError(reqLogger, error, {
      endpoint: "/api/oauth/token",
      provider: req.body?.provider,
    });
    endTimer();
    res
      .status(500)
      .json({ error: "Internal server error.", message: error.message });
  }
});

// OAuth Token Refresh endpoint
app.post("/api/oauth/refresh", async (req: Request, res: Response) => {
  const reqLogger = req.logger || logger;
  const endTimer = logTiming(reqLogger, "oauth-token-refresh");

  try {
    const { provider, refreshToken, isHosted } = req.body;
    let { clientId, clientSecret, auth0Domain, zitadelDomain } = req.body;

    reqLogger.info("OAuth token refresh initiated", {
      provider,
      isHosted,
      hasRefreshToken: !!refreshToken,
    });

    if (!refreshToken || !provider) {
      reqLogger.warn(
        "OAuth token refresh failed - missing required parameters",
      );
      return res.status(400).json({
        error: "Missing required parameters: refreshToken, provider.",
      });
    }

    if (
      provider !== "github" &&
      provider !== "google" &&
      provider !== "gitlab" &&
      provider !== "auth0" &&
      provider !== "zitadel" &&
      provider !== "linkedin"
    ) {
      reqLogger.warn("OAuth token refresh failed - unsupported provider", {
        provider,
      });
      return res.status(400).json({ error: "Unsupported provider." });
    }

    // If hosted, retrieve credentials from secret manager
    if (isHosted) {
      const hostedCreds = await getHostedCredentials(provider);
      clientId = hostedCreds.clientId;
      clientSecret = hostedCreds.clientSecret;
      if (provider === "auth0") {
        try {
          auth0Domain = await getSecret("AUTH0_APP_OAUTH_DOMAIN");
        } catch (e) {
          // leave undefined; the provider-specific check below will handle error response
        }
      }
      if (provider === "zitadel") {
        zitadelDomain = await resolveZitadelDomain(zitadelDomain);
      }
    } else if (!clientId || !clientSecret) {
      reqLogger.warn(
        "OAuth token refresh failed - missing client credentials for non-hosted flow",
      );
      return res.status(400).json({
        error:
          "Missing required parameters for non-hosted auth: clientId, clientSecret.",
      });
    }

    let refreshUrl: string;
    const fetchOptions: {
      method: string;
      headers: Record<string, string>;
      body: string;
    } = { method: "POST", headers: {}, body: "" };

    if (provider === "github") {
      // Note: GitHub doesn't typically provide refresh tokens for OAuth apps
      // Only GitHub Apps can use refresh tokens
      reqLogger.warn("GitHub OAuth Apps do not support refresh tokens");
      return res.status(400).json({
        error:
          "GitHub OAuth Apps do not support refresh tokens. Only GitHub Apps support refresh tokens.",
      });
    } else if (provider === "google") {
      refreshUrl = "https://oauth2.googleapis.com/token";
      fetchOptions.headers = {
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      fetchOptions.body = JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      });
    } else if (provider === "gitlab") {
      refreshUrl = "https://gitlab.com/oauth/token";
      fetchOptions.headers = {
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      fetchOptions.body = JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      });
    } else if (provider === "auth0") {
      if (!auth0Domain) {
        return res.status(400).json({ error: "Auth0 domain is required." });
      }
      try {
        await validateIssuerDomain(auth0Domain);
      } catch (err) {
        collapseUpstreamError(
          reqLogger,
          res,
          req.id,
          {
            endpoint: "/api/oauth/refresh",
            provider,
            phase: "domain-validation",
          },
          err,
        );
        endTimer();
        return;
      }
      refreshUrl = `https://${auth0Domain}/oauth/token`;
      fetchOptions.headers = {
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      fetchOptions.body = JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      });
    } else if (provider === "zitadel") {
      zitadelDomain = zitadelDomain || (await resolveZitadelDomain());
      try {
        await validateIssuerDomain(zitadelDomain);
      } catch (err) {
        collapseUpstreamError(
          reqLogger,
          res,
          req.id,
          {
            endpoint: "/api/oauth/refresh",
            provider,
            phase: "domain-validation",
          },
          err,
        );
        endTimer();
        return;
      }
      refreshUrl = `https://${zitadelDomain}/oauth/v2/token`;
      fetchOptions.headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      };
      const params = new URLSearchParams();
      params.append("grant_type", "refresh_token");
      params.append("refresh_token", refreshToken);
      params.append("client_id", clientId);
      params.append("client_secret", clientSecret);
      fetchOptions.body = params.toString();
    } else if (provider === "linkedin") {
      refreshUrl = "https://www.linkedin.com/oauth/v2/accessToken";
      fetchOptions.headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      };
      const params = new URLSearchParams();
      params.append("grant_type", "refresh_token");
      params.append("refresh_token", refreshToken);
      params.append("client_id", clientId);
      params.append("client_secret", clientSecret);
      fetchOptions.body = params.toString();
    } else {
      return res.status(400).json({ error: "Unsupported provider." });
    }

    reqLogger.info("Making OAuth provider refresh request", {
      provider,
      refreshUrl,
      method: fetchOptions.method,
    });

    let refreshResponse: { status: number; body: string };
    try {
      refreshResponse = await safeFetch(refreshUrl, fetchOptions);
    } catch (err) {
      collapseUpstreamError(
        reqLogger,
        res,
        req.id,
        { endpoint: "/api/oauth/refresh", provider, phase: "outbound" },
        err,
      );
      endTimer();
      return;
    }
    const responseText = refreshResponse.body;
    const refreshOk =
      refreshResponse.status >= 200 && refreshResponse.status < 300;

    reqLogger.info("OAuth provider refresh response received", {
      provider,
      statusCode: refreshResponse.status,
    });

    if (!refreshOk) {
      reqLogger.error("OAuth provider refresh error response", {
        provider,
        statusCode: refreshResponse.status,
        responseText: responseText.substring(0, 500),
      });

      // Use enhanced error detection to provide better troubleshooting guidance
      const enhancedError = enhanceOAuthError(
        responseText,
        refreshResponse.status,
        provider,
      );

      reqLogger.info("Enhanced OAuth refresh error detected", {
        provider,
        errorCode: enhancedError.errorCode,
        hasGuide: !!enhancedError.guide,
      });

      return res.status(refreshResponse.status).json(enhancedError);
    }

    const tokenData = JSON.parse(responseText);

    reqLogger.info("OAuth token refresh successful", {
      provider,
      hasAccessToken: !!tokenData.access_token,
      hasRefreshToken: !!tokenData.refresh_token,
    });

    endTimer();
    res.json(tokenData);
  } catch (error: any) {
    logError(reqLogger, error, {
      endpoint: "/api/oauth/refresh",
      provider: req.body?.provider,
    });
    endTimer();
    res
      .status(500)
      .json({ error: "Internal server error.", message: error.message });
  }
});

// OAuth Token Revocation endpoint
app.post("/api/oauth/revoke", async (req: Request, res: Response) => {
  const reqLogger = req.logger || logger;
  const endTimer = logTiming(reqLogger, "oauth-token-revocation");

  try {
    const { provider, token, tokenTypeHint, isHosted } = req.body;
    let { clientId, clientSecret, auth0Domain, zitadelDomain } = req.body;

    reqLogger.info("OAuth token revocation initiated", {
      provider,
      isHosted,
      hasToken: !!token,
      tokenTypeHint,
    });

    if (!token || !provider) {
      reqLogger.warn(
        "OAuth token revocation failed - missing required parameters",
      );
      return res.status(400).json({
        error: "Missing required parameters: token, provider.",
      });
    }

    if (
      provider !== "github" &&
      provider !== "google" &&
      provider !== "gitlab" &&
      provider !== "auth0" &&
      provider !== "zitadel" &&
      provider !== "linkedin"
    ) {
      reqLogger.warn("OAuth token revocation failed - unsupported provider", {
        provider,
      });
      return res.status(400).json({ error: "Unsupported provider." });
    }

    // If hosted, retrieve credentials from secret manager
    if (isHosted) {
      const hostedCreds = await getHostedCredentials(provider);
      clientId = hostedCreds.clientId;
      clientSecret = hostedCreds.clientSecret;
      if (provider === "auth0") {
        try {
          auth0Domain = await getSecret("AUTH0_APP_OAUTH_DOMAIN");
        } catch (e) {
          // leave undefined; the provider-specific check below will handle error response
        }
      }
      if (provider === "zitadel") {
        zitadelDomain = await resolveZitadelDomain(zitadelDomain);
      }
    } else if (!clientId || !clientSecret) {
      reqLogger.warn(
        "OAuth token revocation failed - missing client credentials for non-hosted flow",
      );
      return res.status(400).json({
        error:
          "Missing required parameters for non-hosted auth: clientId, clientSecret.",
      });
    }

    let revokeUrl: string;
    const fetchOptions: {
      method: string;
      headers: Record<string, string>;
      body: string;
    } = { method: "POST", headers: {}, body: "" };

    if (provider === "github") {
      // GitHub uses Basic Auth for revocation
      revokeUrl = `https://api.github.com/applications/${clientId}/token`;
      fetchOptions.method = "DELETE";
      fetchOptions.headers = {
        Accept: "application/vnd.github.v3+json",
        Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
        "Content-Type": "application/json",
      };
      fetchOptions.body = JSON.stringify({
        access_token: token,
      });
    } else if (provider === "google") {
      revokeUrl = "https://oauth2.googleapis.com/revoke";
      fetchOptions.headers = {
        "Content-Type": "application/x-www-form-urlencoded",
      };
      const params = new URLSearchParams();
      params.append("token", token);
      if (tokenTypeHint) {
        params.append("token_type_hint", tokenTypeHint);
      }
      fetchOptions.body = params.toString();
    } else if (provider === "gitlab") {
      revokeUrl = "https://gitlab.com/oauth/revoke";
      fetchOptions.headers = {
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      fetchOptions.body = JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        token: token,
      });
    } else if (provider === "auth0") {
      if (!auth0Domain) {
        return res.status(400).json({ error: "Auth0 domain is required." });
      }
      try {
        await validateIssuerDomain(auth0Domain);
      } catch (err) {
        collapseUpstreamError(
          reqLogger,
          res,
          req.id,
          {
            endpoint: "/api/oauth/revoke",
            provider,
            phase: "domain-validation",
          },
          err,
        );
        endTimer();
        return;
      }
      revokeUrl = `https://${auth0Domain}/oauth/revoke`;
      fetchOptions.headers = {
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      fetchOptions.body = JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        token: token,
        token_type_hint: tokenTypeHint || "access_token",
      });
    } else if (provider === "zitadel") {
      zitadelDomain = zitadelDomain || (await resolveZitadelDomain());
      try {
        await validateIssuerDomain(zitadelDomain);
      } catch (err) {
        collapseUpstreamError(
          reqLogger,
          res,
          req.id,
          {
            endpoint: "/api/oauth/revoke",
            provider,
            phase: "domain-validation",
          },
          err,
        );
        endTimer();
        return;
      }
      revokeUrl = `https://${zitadelDomain}/oauth/v2/revoke`;
      fetchOptions.headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      };
      const params = new URLSearchParams();
      params.append("token", token);
      params.append("client_id", clientId);
      params.append("client_secret", clientSecret);
      params.append("token_type_hint", tokenTypeHint || "access_token");
      fetchOptions.body = params.toString();
    } else if (provider === "linkedin") {
      // LinkedIn doesn't have a standard revoke endpoint, but we can simulate it
      // by making an API call with the token to verify it's still valid
      reqLogger.info("LinkedIn doesn't provide a token revocation endpoint");
      return res.json({
        success: true,
        message:
          "LinkedIn doesn't provide a token revocation endpoint. The token will expire naturally according to LinkedIn's token lifetime policy.",
      });
    } else {
      return res.status(400).json({ error: "Unsupported provider." });
    }

    reqLogger.info("Making OAuth provider revocation request", {
      provider,
      revokeUrl,
      method: fetchOptions.method,
    });

    let revokeResponse: {
      status: number;
      headers: Record<string, string | string[] | undefined>;
      body: string;
    };
    try {
      revokeResponse = await safeFetch(revokeUrl, fetchOptions);
    } catch (err) {
      collapseUpstreamError(
        reqLogger,
        res,
        req.id,
        { endpoint: "/api/oauth/revoke", provider, phase: "outbound" },
        err,
      );
      endTimer();
      return;
    }

    // Different providers handle revocation responses differently
    let success = false;
    let responseData: any = {};

    if (provider === "github") {
      // GitHub returns 204 No Content on successful revocation
      success = revokeResponse.status === 204;
    } else if (provider === "google") {
      // Google returns 200 on successful revocation
      success = revokeResponse.status === 200;
    } else {
      // For other providers, check if status is 2xx
      success = revokeResponse.status >= 200 && revokeResponse.status < 300;
    }

    // safeFetch returns headers as a plain object (node https res.headers).
    const contentType = revokeResponse.headers["content-type"];
    const contentTypeStr = Array.isArray(contentType)
      ? contentType.join(",")
      : (contentType ?? "");
    if (contentTypeStr.includes("application/json")) {
      try {
        const responseText = revokeResponse.body;
        if (responseText.trim()) {
          responseData = JSON.parse(responseText);
        }
      } catch (e) {
        // Ignore JSON parsing errors for revocation responses
      }
    }

    reqLogger.info("OAuth provider revocation response received", {
      provider,
      statusCode: revokeResponse.status,
      success,
    });

    if (!success) {
      reqLogger.error("OAuth provider revocation error response", {
        provider,
        statusCode: revokeResponse.status,
      });

      return res.status(revokeResponse.status).json({
        success: false,
        error:
          responseData.error ||
          responseData.error_description ||
          "Failed to revoke token.",
      });
    }

    reqLogger.info("OAuth token revocation successful", {
      provider,
    });

    endTimer();
    res.json({
      success: true,
      message: "Token revoked successfully.",
    });
  } catch (error: any) {
    logError(reqLogger, error, {
      endpoint: "/api/oauth/revoke",
      provider: req.body?.provider,
    });
    endTimer();
    res.status(500).json({
      success: false,
      error: "Internal server error.",
      message: error.message,
    });
  }
});

// Hosted OAuth - Get authorization URL using stored credentials
app.post("/api/oauth-hosted/init", async (req: Request, res: Response) => {
  const reqLogger = req.logger || logger;
  const endTimer = logTiming(reqLogger, "oauth-hosted-init");

  try {
    const { provider, redirectUri, scopes } = req.body;

    reqLogger.info("Hosted OAuth initialization requested", {
      provider,
      hasRedirectUri: !!redirectUri,
      redirectUri: redirectUri, // Safe to log redirect URI
    });

    if (!provider || !redirectUri) {
      reqLogger.warn(
        "Hosted OAuth initialization failed - missing parameters",
        {
          missingFields: {
            provider: !provider,
            redirectUri: !redirectUri,
          },
        },
      );
      return res.status(400).json({
        error: "Missing required parameters: provider and redirectUri.",
      });
    }

    if (
      !["github", "google", "gitlab", "auth0", "zitadel", "linkedin"].includes(
        provider,
      )
    ) {
      reqLogger.warn(
        "Hosted OAuth initialization failed - unsupported provider",
        { provider },
      );
      return res.status(400).json({
        error:
          "Unsupported provider. Supported providers are: github, google, gitlab, auth0, zitadel, linkedin.",
      });
    }

    // Retrieve hosted credentials
    const { clientId } = await getHostedCredentials(provider);

    // OAuth providers require the redirect_uri in the authorize request to be an
    // EXACT match for one registered on the application — so it must be sent
    // percent-encoded. Encoding also keeps a custom redirect URI that contains
    // query params (`?`/`&`) from corrupting the rest of the authorize URL.
    const encodedRedirectUri = encodeURIComponent(redirectUri);

    let authUrl = "";

    if (provider === "github") {
      const scope = "read:user,user:email";
      authUrl = `https://github.com/login/oauth/authorize?client_id=${clientId}&redirect_uri=${encodedRedirectUri}&scope=${scope}&state=github-hosted`;
    } else if (provider === "google") {
      const scope =
        "https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email";
      authUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${clientId}&redirect_uri=${encodedRedirectUri}&response_type=code&scope=${scope}&state=google-hosted`;
    } else if (provider === "gitlab") {
      const scope = "read_user";
      authUrl = `https://gitlab.com/oauth/authorize?client_id=${clientId}&redirect_uri=${encodedRedirectUri}&response_type=code&scope=${scope}&state=gitlab-hosted`;
    } else if (provider === "auth0") {
      // For hosted Auth0, we'll need to get the domain from configuration
      // For now, we'll use a placeholder that should be configured
      const auth0Domain = await getSecret("AUTH0_APP_OAUTH_DOMAIN").catch(
        () => "your-tenant.us.auth0.com",
      );
      const scope = "openid profile email";
      authUrl = `https://${auth0Domain}/authorize?client_id=${clientId}&redirect_uri=${encodedRedirectUri}&response_type=code&scope=${scope}&state=auth0-hosted`;
    } else if (provider === "zitadel") {
      // Self-hosted Zitadel: domain comes from the secret, defaulting to our
      // instance so hosted login works out of the box. offline_access yields a
      // refresh token (so refresh + revoke work, like Auth0).
      const zitadelDomain = await resolveZitadelDomain();
      // Honor user-selected scopes from the hosted Zitadel card (ScopeSelector),
      // falling back to the sensible default (offline_access keeps refresh working).
      const scope =
        typeof scopes === "string" && scopes.trim()
          ? scopes
          : "openid profile email offline_access";
      authUrl = `https://${zitadelDomain}/oauth/v2/authorize?client_id=${clientId}&redirect_uri=${encodedRedirectUri}&response_type=code&scope=${encodeURIComponent(
        scope,
      )}&state=zitadel-hosted`;
    } else if (provider === "linkedin") {
      // "Sign In with LinkedIn using OpenID Connect" — the legacy
      // r_liteprofile/r_emailaddress scopes were retired in 2023 and are no
      // longer grantable to newly-created LinkedIn apps. honor user-selected
      // scopes from the hosted LinkedIn card (ScopeSelector), falling back to
      // the OIDC default.
      const scope =
        typeof scopes === "string" && scopes.trim()
          ? scopes
          : "openid profile email";
      authUrl = `https://www.linkedin.com/oauth/v2/authorization?client_id=${clientId}&redirect_uri=${encodedRedirectUri}&response_type=code&scope=${encodeURIComponent(
        scope,
      )}&state=linkedin-hosted`;
    }

    reqLogger.info("Hosted OAuth authorization URL generated", {
      provider,
      hasAuthUrl: !!authUrl,
    });

    endTimer();
    res.json({ authUrl });
  } catch (error: any) {
    logError(reqLogger, error, {
      endpoint: "/api/oauth-hosted/init",
      provider: req.body?.provider,
    });
    endTimer();
    res.status(500).json({
      error: "Failed to initialize hosted OAuth.",
      message: error.message,
    });
  }
});

// Hosted OAuth - Report availability based on presence of Secret Manager keys
app.get(
  "/api/oauth-hosted/availability",
  async (req: Request, res: Response) => {
    const reqLogger = req.logger || logger;
    const endTimer = logTiming(reqLogger, "oauth-hosted-availability");

    const secretExists = async (name: string): Promise<boolean> => {
      try {
        await getSecret(name);
        return true;
      } catch {
        return false;
      }
    };

    try {
      const [
        github,
        google,
        gitlab,
        auth0Id,
        auth0Secret,
        auth0Domain,
        zitadel,
        linkedin,
      ] = await Promise.all([
        Promise.all([
          secretExists("GITHUB_APP_OAUTH_CLIENT_ID"),
          secretExists("GITHUB_APP_OAUTH_CLIENT_SECRET"),
        ]).then(([id, secret]) => id && secret),
        Promise.all([
          secretExists("GOOGLE_APP_OAUTH_CLIENT_ID"),
          secretExists("GOOGLE_APP_OAUTH_CLIENT_SECRET"),
        ]).then(([id, secret]) => id && secret),
        Promise.all([
          secretExists("GITLAB_APP_OAUTH_CLIENT_ID"),
          secretExists("GITLAB_APP_OAUTH_CLIENT_SECRET"),
        ]).then(([id, secret]) => id && secret),
        secretExists("AUTH0_APP_OAUTH_CLIENT_ID"),
        secretExists("AUTH0_APP_OAUTH_CLIENT_SECRET"),
        secretExists("AUTH0_APP_OAUTH_DOMAIN"),
        // Zitadel's domain has a built-in default, so hosted availability only
        // depends on the client id + secret being present.
        Promise.all([
          secretExists("ZITADEL_APP_OAUTH_CLIENT_ID"),
          secretExists("ZITADEL_APP_OAUTH_CLIENT_SECRET"),
        ]).then(([id, secret]) => id && secret),
        Promise.all([
          secretExists("LINKEDIN_APP_OAUTH_CLIENT_ID"),
          secretExists("LINKEDIN_APP_OAUTH_CLIENT_SECRET"),
        ]).then(([id, secret]) => id && secret),
      ]);

      const availability = {
        github,
        google,
        gitlab,
        auth0: auth0Id && auth0Secret && auth0Domain,
        zitadel,
        linkedin,
      };

      reqLogger.info("Hosted availability computed", { availability });
      endTimer();
      res.json({ availability });
    } catch (error: any) {
      logError(reqLogger, error, {
        endpoint: "/api/oauth-hosted/availability",
      });
      endTimer();
      res.status(500).json({ error: "Failed to check availability." });
    }
  },
);

// This endpoint is now consolidated into /api/oauth/token
// app.post('/api/oauth-hosted/token', ...);

// Lightweight health / readiness endpoint
app.get("/api/health", (req: Request, res: Response) => {
  res.json({
    status: "ok",
    uptime: process.uptime(),
    timestamp: Date.now(),
    node: process.version,
  });
});

// API Explorer endpoint - proxy API calls to avoid CORS issues
app.post("/api/explore", async (req: Request, res: Response) => {
  const reqLogger = req.logger || logger;
  const endTimer = logTiming(reqLogger, "API Explore");

  try {
    const { provider, accessToken, endpoint } = req.body;

    if (!provider || !accessToken || !endpoint) {
      res.status(400).json({
        error: "Missing required fields: provider, accessToken, endpoint",
      });
      return;
    }

    // FAIL CLOSED: the server NEVER trusts the client-supplied endpoint.url.
    // We resolve the target from a server-owned table keyed by
    // (provider, endpoint.id). An unknown pair is a hard 400 with NO outbound
    // call — there is no fallback to the client URL, which is what made the old
    // `fetch(endpoint.url)` an open SSRF relay.
    const endpointId = endpoint.id;
    if (!endpointId || !endpoint.method) {
      res.status(400).json({
        error: "Invalid endpoint: missing id or method",
      });
      return;
    }

    reqLogger.info("API explore request", {
      provider,
      endpointId,
      method: endpoint.method,
    });

    // For issuer providers (auth0/zitadel) the host is the user's IdP domain;
    // resolve it and validate it via resolveAndPin BEFORE building the target,
    // so a BYO domain pointing at an internal/CGNAT/metadata host is rejected.
    let issuerDomain: string | undefined;
    if (provider === "auth0") {
      issuerDomain = req.body.auth0Domain;
      if (!issuerDomain) {
        res.status(400).json({
          error: "Auth0 domain required for Auth0 API calls",
        });
        return;
      }
    } else if (provider === "zitadel") {
      issuerDomain = await resolveZitadelDomain(req.body.zitadelDomain);
    }

    // Resolve the absolute target from the server-owned table. Unknown
    // provider/endpoint id → 400, never an outbound call.
    let targetUrl: string;
    try {
      targetUrl = resolveExploreTarget(provider, endpointId, issuerDomain);
    } catch (err) {
      if (err instanceof UnknownExploreEndpointError) {
        reqLogger.warn("API explore rejected - unknown endpoint", {
          provider,
          endpointId,
          reason: err.message,
        });
        res.status(400).json({ error: "unknown endpoint" });
        endTimer();
        return;
      }
      throw err;
    }

    // Validate the issuer domain host now that we know we will call it. (For
    // fixed providers the host is a hardcoded constant, so no validation is
    // needed; safeFetch still pins + vets it on the way out.)
    if (issuerDomain) {
      try {
        await validateIssuerDomain(issuerDomain);
      } catch (err) {
        collapseUpstreamError(
          reqLogger,
          res,
          req.id,
          { endpoint: "/api/explore", provider, phase: "domain-validation" },
          err,
        );
        endTimer();
        return;
      }
    }

    // Prepare headers. The Authorization bearer is attached ONLY to the
    // server-resolved target host — never to a client-supplied URL.
    const headers: Record<string, string> = {
      Authorization: `Bearer ${accessToken}`,
      "User-Agent": "OAuth-User-Inspector/1.0",
    };

    // Add provider-specific headers
    if (provider === "github") {
      headers["X-GitHub-Api-Version"] = "2022-11-28";
      headers["Accept"] = "application/vnd.github+json";
    }

    // Outbound via safeFetch: resolve+pin to a public unicast IP, TLS-validate
    // against the real host, no redirect follow, size/time bounded.
    let apiResponse: {
      status: number;
      headers: Record<string, string | string[] | undefined>;
      body: string;
    };
    try {
      apiResponse = await safeFetch(targetUrl, {
        method: endpoint.method,
        headers,
      });
    } catch (err) {
      collapseUpstreamError(
        reqLogger,
        res,
        req.id,
        { endpoint: "/api/explore", provider, endpointId, phase: "outbound" },
        err,
      );
      endTimer();
      return;
    }

    const apiOk = apiResponse.status >= 200 && apiResponse.status < 300;
    let responseData: any;
    try {
      responseData = apiResponse.body ? JSON.parse(apiResponse.body) : {};
    } catch {
      // Upstream returned non-JSON; surface the raw text so callers still see it.
      responseData = { raw: apiResponse.body };
    }

    reqLogger.info("API explore response", {
      provider,
      endpointId,
      status: apiResponse.status,
      success: apiOk,
    });

    // Return response data and metadata
    res.json({
      success: apiOk,
      status: apiResponse.status,
      data: responseData,
      error: apiOk
        ? undefined
        : responseData?.message || responseData?.error || "API call failed",
      headers: apiResponse.headers,
    });

    endTimer();
  } catch (error: any) {
    endTimer();
    logError(reqLogger, error, {
      endpoint: "/api/explore",
      provider: req.body?.provider,
      endpointId: req.body?.endpoint?.id,
    });
    res.status(500).json({
      success: false,
      error: error.message || "Failed to make API call",
    });
  }
});

// --- Static file serving & SPA Fallback ---
// Use process.cwd() so tests and production builds resolve consistently
const baseDir = process.cwd();
const distDir = path.join(baseDir, "dist");
const rootDir = baseDir;

// Log the directories for debugging
logger.info("Static file serving configuration", {
  baseDir,
  distDir,
  rootDir,
  paths: {
    distIndex: path.join(distDir, "index.html"),
    rootIndex: path.join(rootDir, "index.html"),
    distAssets: path.join(distDir, "assets"),
  },
});

// Check if files exist and their contents
const distIndexExists = fs.existsSync(path.join(distDir, "index.html"));
const rootIndexExists = fs.existsSync(path.join(rootDir, "index.html"));
const distAssetsExists = fs.existsSync(path.join(distDir, "assets"));

logger.info("File system check", {
  files: {
    "dist/index.html": distIndexExists,
    "root/index.html": rootIndexExists,
    "dist/assets": distAssetsExists,
  },
});

// Log directory contents
try {
  const distContents = fs.readdirSync(distDir);
  logger.info("Directory contents", {
    directory: "dist",
    contents: distContents,
  });

  if (distAssetsExists) {
    const assetsContents = fs.readdirSync(path.join(distDir, "assets"));
    logger.info("Directory contents", {
      directory: "dist/assets",
      contents: assetsContents,
    });
  }
} catch (error) {
  logger.error("directory-listing", { error });
}

// IMPORTANT: Only serve from dist directory to avoid serving wrong index.html
// First, try to serve built assets from dist/assets
app.use("/assets", express.static(path.join(distDir, "assets")));
// Then serve other static files from dist (but exclude index.html to prevent conflicts)
app.use(express.static(distDir, { index: false }));

// DO NOT serve static files from root to avoid source index.html override

// The SPA fallback route sends 'index.html' for any GET request that doesn't match a static file.
// NOTE: Express 5 (path-to-regexp v8) rejects the bare "*" string path and throws at startup
// ("Missing parameter name at index 1: *"). A regex catch-all is the behavior-identical
// replacement — it matches every path including "/", and this handler uses req.path/query, not
// req.params, so no named wildcard is needed.
app.get(/.*/, (req, res) => {
  const reqLogger = req.logger || logger;

  reqLogger.info("SPA fallback route triggered", {
    path: req.path,
    query: req.query,
    referer: req.headers.referer,
  });

  // Try dist/index.html first, then fallback to root index.html
  const distIndex = path.resolve(distDir, "index.html");
  const rootIndex = path.resolve(rootDir, "index.html");

  // Check if dist/index.html exists, if not use root index.html
  if (fs.existsSync(distIndex)) {
    reqLogger.info("Serving SPA index.html", {
      source: "dist",
      file: distIndex,
    });
    res.sendFile(distIndex);
  } else {
    reqLogger.info("Serving SPA index.html", {
      source: "root",
      file: rootIndex,
      reason: "dist/index.html not found",
    });
    res.sendFile(rootIndex);
  }
});

// --- Error Handling ---
// Generic error handler middleware
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  const reqLogger = req.logger || logger;
  logError(reqLogger, err, {
    endpoint: req.originalUrl,
    method: req.method,
  });

  if (res.headersSent) {
    return next(err);
  }

  // Honor a status carried by the error (e.g. body-parser's 413 PayloadTooLarge
  // from the express.json 64kb limit, or its 400 on malformed JSON). Only an
  // error with no/invalid status falls through to a generic 500 — we never
  // mask a 4xx client error as a 500.
  const status =
    (err as { status?: number; statusCode?: number }).status ??
    (err as { statusCode?: number }).statusCode;
  if (typeof status === "number" && status >= 400 && status < 600) {
    res.status(status).json({
      error:
        status === 413
          ? "Request body too large."
          : "Request could not be processed.",
      requestId: req.id,
    });
    return;
  }

  res.status(500).json({
    error: "An unexpected error occurred.",
    message: err.message,
    requestId: req.id,
  });
});

// Unhandled promise rejection handler
process.on("unhandledRejection", (reason: any, promise: Promise<any>) => {
  logger.error("Unhandled Rejection", {
    reason: (reason as any)?.message || reason,
    stack: (reason as any)?.stack,
    promise,
  });
});

// Uncaught exception handler
process.on("uncaughtException", (error: Error) => {
  logger.error("Uncaught Exception", {
    message: error.message,
    stack: error.stack,
  });
  // It's generally recommended to exit the process after an uncaught exception
  process.exit(1);
});

// Avoid listening when running in Jest tests to prevent open handle issues
if (!process.env.JEST_WORKER_ID) {
  app.listen(port, "0.0.0.0", () => {
    logger.info("Server started successfully", {
      port,
      host: "0.0.0.0",
      environment: process.env.NODE_ENV || "development",
      nodeVersion: process.version,
      platform: process.platform,
      memory: {
        rss: Math.round(process.memoryUsage().rss / 1024 / 1024) + "MB",
        heapUsed:
          Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + "MB",
        heapTotal:
          Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + "MB",
      },
      uptime: process.uptime() + "s",
      pid: process.pid,
    });
  });
}

export default app;
