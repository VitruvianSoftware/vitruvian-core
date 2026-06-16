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
 * Seed script for E2E test user
 *
 * Creates a test user and generates a JWT token for E2E testing.
 * Token is output to stdout for use in tests.
 *
 * Usage:
 *   npx ts-node prisma/seed-test-user.ts
 *   # or via npm script
 *   npm run db:seed:test
 */

import { PrismaPg } from "@prisma/adapter-pg";
import jwt from "jsonwebtoken";

import { PrismaClient } from "../src/generated/prisma/client";

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
const prisma = new PrismaClient({ adapter });

const TEST_USER = {
  // Use a deterministic UUID for the test user
  id: "00000000-0000-0000-0000-e2e000000000",
  email: "e2e-test@tabula.dev",
  name: "E2E Test User",
  tier: "free" as const,
};

// A second deterministic user dedicated to the cross-device convergence spec
// (extension/tests/sync-convergence.spec.ts). Those tests hold a workspace live
// across long two-device windows; isolating them on their own user keeps the
// parallel specs' workspace cleanups (which target the shared TEST_USER) from
// deleting it mid-test. Must match CONV_TEST_USER in extension/tests/
// e2e-helpers.ts.
const CONV_TEST_USER = {
  id: "00000000-0000-0000-0000-e2e000000002",
  email: "e2e-conv@tabula.dev",
  name: "E2E Convergence User",
  tier: "free" as const,
};

async function main() {
  console.log("[seed-test-user] Starting...");

  // Check for required environment variable
  const jwtSecret = process.env.JWT_SECRET;
  if (!jwtSecret) {
    console.error("ERROR: JWT_SECRET environment variable is required");
    process.exit(1);
  }

  // Upsert the test users
  for (const u of [TEST_USER, CONV_TEST_USER]) {
    const user = await prisma.user.upsert({
      where: { id: u.id },
      update: { email: u.email, name: u.name, tier: u.tier },
      create: { id: u.id, email: u.email, name: u.name, tier: u.tier },
    });
    console.log("[seed-test-user] User created/updated:", user.email);
  }

  // Generate a token for the primary test user (expires in 24 hours). It is
  // parsed out of this seed's stdout and injected into the pw_suite env as
  // E2E_TEST_TOKEN; the convergence user's token is minted in-test from
  // JWT_SECRET (see e2e-helpers.mintTestToken).
  const token = jwt.sign(
    {
      id: TEST_USER.id,
      email: TEST_USER.email,
      tier: TEST_USER.tier,
    },
    jwtSecret,
    { expiresIn: "24h" },
  );

  // Output token in a format that can be parsed
  console.log("[seed-test-user] Token generated successfully");
  console.log(`E2E_TEST_TOKEN=${token}`);

  // Also output user info for verification
  console.log(`E2E_TEST_USER_ID=${TEST_USER.id}`);
  console.log(`E2E_TEST_USER_EMAIL=${TEST_USER.email}`);
}

main()
  .catch((e) => {
    console.error("[seed-test-user] Error:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
