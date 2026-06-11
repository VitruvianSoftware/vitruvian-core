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
import { ZodError } from "zod";
import { redis } from "./lib/redis";
import { resolveJwtSecret, ACCESS_TOKEN_TTL } from "./lib/auth";
import { workspaceRoutes } from "./routes/workspace.routes";
import { spaceGroupRoutes } from "./routes/spacegroup.routes";
import { authRoutes } from "./routes/auth.routes";
import { userRoutes } from "./routes/user.routes";
import { backupRoutes } from "./routes/backup.routes";
import { syncRoutes } from "./routes/sync.routes";

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

  // Register plugins
  app.register(cors, {
    origin: (process.env.CORS_ORIGIN || "http://localhost:3000").split(","),
  });

  // Default generously: the extension's sync is chatty (a whole-workspace PUT
  // per debounced tab event, per window), and the per-IP key means users
  // behind a shared NAT (offices) pool into one bucket. 1000/min still stops
  // abusive clients; tighten per-route later if needed.
  app.register(rateLimit, {
    max: parseInt(process.env.RATE_LIMIT_MAX || "1000", 10),
    timeWindow: parseInt(process.env.RATE_LIMIT_WINDOW || "60000", 10),
    redis: redis || undefined, // Use Redis for rate limiting if available
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

  // Central error handler. Keeps intentional 4xx messages (validation,
  // not-found, conflict, forbidden) but never forwards raw 5xx/internal error
  // messages (Prisma/Redis constraint names, connection fragments) to clients.
  // Routes that want the generic 500 simply rethrow; this is the single place
  // that decides what a client sees.
  app.setErrorHandler((error, request, reply) => {
    request.log.error(error);

    if (error instanceof ZodError) {
      return reply.code(400).send({
        error: "Bad Request",
        message: "Invalid input",
        details: error.flatten(),
      });
    }

    // Body too large -> actionable 413 instead of an opaque error.
    if ((error as { code?: string }).code === "FST_ERR_CTP_BODY_TOO_LARGE") {
      return reply.code(413).send({
        error: "Payload Too Large",
        message: "Request body exceeds the maximum allowed size",
      });
    }

    const statusCode =
      typeof error.statusCode === "number" && error.statusCode >= 400
        ? error.statusCode
        : 500;

    // Only expose the real message for client errors (4xx). 5xx messages are
    // generic in production; in dev/test we keep the detail to aid debugging.
    const exposeMessage =
      statusCode < 500 || process.env.NODE_ENV !== "production";

    return reply.code(statusCode).send({
      error:
        statusCode < 500
          ? error.name || "Bad Request"
          : "Internal Server Error",
      message: exposeMessage ? error.message : "An unexpected error occurred",
    });
  });

  // Register routes
  app.register(authRoutes, { prefix: "/api/v1/auth" });
  app.register(userRoutes, { prefix: "/api/v1/users" });
  app.register(workspaceRoutes, { prefix: "/api/v1/workspaces" });
  app.register(spaceGroupRoutes, { prefix: "/api/v1/space-groups" });
  app.register(backupRoutes, { prefix: "/api/v1/backups" });
  app.register(syncRoutes, { prefix: "/api/v1/sync" });

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

const app = buildApp();

// Start server
const start = async () => {
  try {
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
  app.log.info("SIGTERM received, shutting down gracefully");
  await app.close();
  process.exit(0);
});

process.on("SIGINT", async () => {
  app.log.info("SIGINT received, shutting down gracefully");
  await app.close();
  process.exit(0);
});

start();
