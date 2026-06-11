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

import { PrismaClient } from "../src/generated/prisma/client";
import jwt from "jsonwebtoken";

const prisma = new PrismaClient();

const TEST_USER = {
  // Use a deterministic UUID for the test user
  id: "00000000-0000-0000-0000-e2e000000000",
  email: "e2e-test@tabula.dev",
  name: "E2E Test User",
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

  // Upsert the test user
  const user = await prisma.user.upsert({
    where: { id: TEST_USER.id },
    update: {
      email: TEST_USER.email,
      name: TEST_USER.name,
      tier: TEST_USER.tier,
    },
    create: {
      id: TEST_USER.id,
      email: TEST_USER.email,
      name: TEST_USER.name,
      tier: TEST_USER.tier,
    },
  });

  console.log("[seed-test-user] User created/updated:", user.email);

  // Generate a token (expires in 24 hours)
  const token = jwt.sign(
    {
      id: user.id,
      email: user.email,
      tier: user.tier,
    },
    jwtSecret,
    { expiresIn: "24h" },
  );

  // Output token in a format that can be parsed
  console.log("[seed-test-user] Token generated successfully");
  console.log(`E2E_TEST_TOKEN=${token}`);

  // Also output user info for verification
  console.log(`E2E_TEST_USER_ID=${user.id}`);
  console.log(`E2E_TEST_USER_EMAIL=${user.email}`);
}

main()
  .catch((e) => {
    console.error("[seed-test-user] Error:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
