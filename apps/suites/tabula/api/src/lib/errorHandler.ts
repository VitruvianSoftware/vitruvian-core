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

/**
 * Central Fastify error handler. Keeps intentional 4xx messages (validation,
 * not-found, conflict, forbidden) but never forwards raw 5xx/internal error
 * messages (Prisma/Redis constraint names, connection fragments) to clients.
 * Routes that want the generic 500 simply rethrow; this is the single place
 * that decides what a client sees.
 *
 * Extracted from app.ts so the mapping is unit-testable without booting the
 * full server (and its generated Prisma client).
 */
import type { FastifyError, FastifyReply, FastifyRequest } from "fastify";
import { ZodError } from "zod";

/**
 * True for a Prisma error that means "the database schema doesn't match the
 * code" — almost always a pending migration that hasn't been applied to this
 * database: P2022 (missing column) or P2021 (missing table). Detected
 * structurally (name + code) so this module needs no dependency on the
 * generated Prisma client, and so a duck-typed error from any layer still
 * matches.
 */
export function isSchemaDriftError(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  const e = error as { name?: string; code?: string };
  return (
    e.name === "PrismaClientKnownRequestError" &&
    (e.code === "P2021" || e.code === "P2022")
  );
}

export function errorHandler(
  error: FastifyError,
  request: FastifyRequest,
  reply: FastifyReply,
) {
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

  // Schema drift (a pending migration hasn't been applied): the column/table a
  // query needs is missing. Surface a clean, retryable 503 instead of leaking
  // the raw Prisma invocation/stack to the client — in EVERY environment, since
  // dev/nonprod otherwise expose 5xx messages (this is the raw error users were
  // seeing in the Backups panel). The real error is already logged above, and
  // the startup guard normally stops a drifted revision before it serves.
  if (isSchemaDriftError(error)) {
    return reply.code(503).send({
      error: "Service Unavailable",
      message:
        "The service is temporarily unavailable. Please try again shortly.",
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
      statusCode < 500 ? error.name || "Bad Request" : "Internal Server Error",
    message: exposeMessage ? error.message : "An unexpected error occurred",
  });
}
