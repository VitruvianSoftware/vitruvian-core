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

import Fastify from "fastify";
import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import jwt from "@fastify/jwt";
import dotenv from "dotenv";
import { redis } from "./lib/redis";
import { resolveJwtSecret, ACCESS_TOKEN_TTL } from "./lib/auth";
import { errorHandler } from "./lib/errorHandler";
import { registerEmptyJsonBodyTolerance } from "./lib/emptyJsonBody";
import { assertDatabaseSchemaCurrent } from "./lib/migrationGuard";
import { workspaceRoutes } from "./routes/workspace.routes";
import { spaceGroupRoutes } from "./routes/spacegroup.routes";
import { authRoutes } from "./routes/auth.routes";
import { userRoutes } from "./routes/user.routes";
import { backupRoutes } from "./routes/backup.routes";
import { syncRoutes } from "./routes/sync.routes";
import { sharingRoutes } from "./routes/sharing.routes";
import { relayRoutes } from "./routes/relay.routes";
import { bootstrapSecrets } from "./lib/secrets";

// Load environment variables
dotenv.config();

// Largest request body the API accepts. chrome.storage.local allows ~10MB per
// extension, so a legitimately large workspace PUT can exceed Fastify's 1MB
// default — without this an entire workspace sync silently 413s. Overridable
// via BODY_LIMIT_BYTES for ops tuning.
const DEFAULT_BODY_LIMIT = 10 * 1024 * 1024; // 10 MB

// Export for testing
export const buildApp = (opts: Record<string, unknown> = {}) => {
  const app = Fastify({
    logger: {
      level: process.env.LOG_LEVEL || "info",
    },
    bodyLimit:
      parseInt(process.env.BODY_LIMIT_BYTES || "", 10) || DEFAULT_BODY_LIMIT,
    ...opts,
  });

  // Field clients (deployed extension builds) claim a JSON body on body-less
  // DELETEs; fastify 5 would 400 them at the parsing step. See
  // lib/emptyJsonBody.ts; regression guard in emptyJsonBody.test.ts.
  registerEmptyJsonBodyTolerance(app);

  // Register plugins
  app.register(cors, {
    origin: (process.env.CORS_ORIGIN || "http://localhost:3000").split(","),
    // @fastify/cors v11 narrowed the default to the CORS-safelisted methods
    // (GET, HEAD, POST) — without this list, browser preflight blocks every
    // cross-origin PUT/PATCH/DELETE. Invisible to CI: app.inject bypasses
    // CORS entirely.
    methods: ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"],
  });

  // Default generously: the extension's sync is chatty (a whole-workspace PUT
  // per debounced tab event, per window), and the per-IP key means users
  // behind a shared NAT (offices) pool into one bucket. 1000/min still stops
  // abusive clients; tighten per-route later if needed.
  //
  // skipOnError is NOT optional: without it, a Redis-store error (e.g. the
  // client unreachable, which lib/redis's enableOfflineQueue:false makes an
  // IMMEDIATE rejection rather than a hang) throws inside rate-limit's
  // onRequest hook. That throw happens before any route handler runs -- for
  // EVERY route registered through a prefixed plugin (auth, users, workspaces,
  // sync, backups, sharing, relay: the entire real API surface) -- bypassing
  // even a route's own try/catch and landing on the generic 500 from
  // errorHandler.ts. Only the two bare top-level routes (/health, /) are
  // exempt, so /health kept reporting "ok" while the rest of the API was
  // completely down. Verified by reproducing this exact failure (and its fix)
  // against the real fastify/@fastify/rate-limit/ioredis versions in
  // isolation, pointed at an unreachable Redis.
  app.register(rateLimit, {
    max: parseInt(process.env.RATE_LIMIT_MAX || "1000", 10),
    timeWindow: parseInt(process.env.RATE_LIMIT_WINDOW || "60000", 10),
    redis: redis || undefined, // Use Redis for rate limiting if available
    skipOnError: true, // A rate-limiter outage must never take down the API.
  });

  // Resolve the JWT secret. Throws (crash-loops the deploy) when JWT_SECRET is
  // missing in production rather than silently signing every token with a known
  // default — see lib/auth.resolveJwtSecret.
  app.register(jwt, {
    secret: resolveJwtSecret(),
    sign: { expiresIn: ACCESS_TOKEN_TTL },
  });

  // Log JWT secret status (NOT the secret itself)
  const hasJwtSecret = !!process.env.JWT_SECRET;
  app.log.info(
    `JWT_SECRET configured: ${hasJwtSecret ? "Yes (from env)" : "No (dev fallback)"}`,
  );

  // Central error handler (extracted to lib/errorHandler for unit testing).
  // Maps schema-drift (P2021/P2022) to a clean 503 and otherwise keeps 4xx
  // messages while masking raw 5xx detail in production.
  app.setErrorHandler(errorHandler);

  // Register routes
  app.register(authRoutes, { prefix: "/api/v1/auth" });
  app.register(userRoutes, { prefix: "/api/v1/users" });
  app.register(workspaceRoutes, { prefix: "/api/v1/workspaces" });
  app.register(spaceGroupRoutes, { prefix: "/api/v1/space-groups" });
  app.register(backupRoutes, { prefix: "/api/v1/backups" });
  app.register(syncRoutes, { prefix: "/api/v1/sync" });
  // Sharing routes use full /workspaces/... and /share-links/... paths.
  app.register(sharingRoutes, { prefix: "/api/v1" });
  // Relay routes are a SEPARATE plugin so the public preview is not behind
  // sharingRoutes' blanket auth hook.
  app.register(relayRoutes, { prefix: "/api/v1" });

  // Health check endpoint
  app.get("/health", async () => ({
    status: "ok",
    timestamp: new Date().toISOString(),
    redis: redis ? "connected" : "disabled",
  }));

  // Root endpoint: identifies exactly what is deployed. version tracks
  // package.json (release-please bumps it); GIT_SHA is injected by the
  // Pulumi deploy (the image tag); K_REVISION is set by Cloud Run.
  app.get("/", async () => ({
    name: "Tabula API",
    // eslint-disable-next-line @typescript-eslint/no-var-requires, global-require
    version: (require("../package.json") as { version: string }).version,
    commit: process.env.GIT_SHA || "unknown",
    revision: process.env.K_REVISION || null,
    environment: process.env.NODE_ENV || "development",
  }));

  return app;
};

// NOT built at module scope. buildApp() reads JWT_SECRET (lib/auth) eagerly, so
// constructing it here would run BEFORE bootstrapSecrets() resolves Secret
// Manager — which is exactly the cold-deploy failure this whole change exists to
// prevent. The container died with "JWT_SECRET environment variable is required
// in production" on the first bu2 deploy for this reason.
let app: ReturnType<typeof buildApp>;

// Start server
const start = async () => {
  try {
    // Resolve secrets FIRST, then construct the app against a populated env.
    const missingSecrets = await bootstrapSecrets();

    app = buildApp();

    if (missingSecrets.length > 0) {
      app.log.warn(
        { secrets: missingSecrets },
        "optional secrets unresolved; features depending on them are disabled",
      );
    }

    // Refuse to serve traffic against a database that is behind this code (a
    // migration-less rollout). Crash-looping here keeps Cloud Run on the
    // previous healthy revision instead of surfacing schema errors to users.
    await assertDatabaseSchemaCurrent(app.log);

    const port = parseInt(process.env.PORT || "8080", 10);
    const host = process.env.HOST || "0.0.0.0";

    await app.listen({ port, host });
    app.log.info(`Server listening on ${host}:${port}`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
};

// Handle shutdown gracefully
process.on("SIGTERM", async () => {
  app?.log.info("SIGTERM received, shutting down gracefully");
  await app?.close();
  process.exit(0);
});

process.on("SIGINT", async () => {
  app?.log.info("SIGINT received, shutting down gracefully");
  await app?.close();
  process.exit(0);
});

start();
