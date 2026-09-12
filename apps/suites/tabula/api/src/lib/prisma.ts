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
 * Prisma client singleton (engine-free: prisma-client generator + pg driver adapter)
 */
import { PrismaPg } from "@prisma/adapter-pg";

import { PrismaClient } from "../generated/prisma/client";

const globalForPrisma = global as unknown as { prisma: PrismaClient };

function createClient(): PrismaClient {
  const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
  return new PrismaClient({
    adapter,
    log:
      process.env.NODE_ENV === "development"
        ? ["query", "error", "warn"]
        : ["error"],
  });
}

// Resolved lazily, NOT at module load -- same reasoning as lib/workos.ts's
// getWorkOS(). This module is imported (transitively, via every
// *.service.ts) from app.ts's top-level `import { authRoutes } ...` chain,
// which Node fully evaluates before start()'s body ever runs
// bootstrapSecrets(). A top-level `export const prisma = createClient()`
// therefore captures process.env.DATABASE_URL at import time -- undefined,
// since Secret Manager hasn't been consulted yet -- baking that into the
// PrismaPg adapter permanently. The pg driver then silently falls back to
// ITS OWN default (127.0.0.1:5432) instead of the real database, for the
// life of the process: "Can't reach database server at 127.0.0.1:5432" on
// every query, no matter how correctly DATABASE_URL later resolves.
//
// A Proxy keeps every existing call site (`prisma.user.upsert(...)`,
// `prisma.$transaction(...)`) unchanged while deferring the actual
// PrismaClient construction to first property access, which happens well
// after bootstrapSecrets() has populated the real environment. Tests are
// unaffected: jest's setupFilesAfterEnv (tests/setup.ts) already sets
// DATABASE_URL before any test file's imports run, so first access there
// already saw the right value either way.
let _client: PrismaClient | undefined;
function getClient(): PrismaClient {
  if (!_client) {
    _client = globalForPrisma.prisma || createClient();
    if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = _client;
  }
  return _client;
}

export const prisma: PrismaClient = new Proxy({} as PrismaClient, {
  get(_target, prop, receiver) {
    return Reflect.get(getClient(), prop, receiver);
  },
});
