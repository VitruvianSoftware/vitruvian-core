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

import { PrismaPg } from "@prisma/adapter-pg";

import { PrismaClient } from "../src/generated/prisma/client";

const prisma = new PrismaClient({
  adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }),
});

async function main() {
  const modelName = process.argv[2];

  if (!modelName) {
    console.error("Error: Model name required");
    process.exit(1);
  }

  // Case-insensitive lookup for model name in Prisma Client
  // Prisma models are usually PascalCase (e.g. User, Workspace) on the client instance
  // but accessed via lowercase property in some contexts?
  // Actually, on new PrismaClient({ adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }) }), it's `prisma.user`, `prisma.workspace`.
  // The dmmf or simple key iteration can find the correct key.

  const lowerModelName = modelName.toLowerCase();
  const validModels = Object.keys(prisma).filter(
    (key) => !key.startsWith("_") && !key.startsWith("$"),
  );

  const targetModel = validModels.find(
    (m) => m.toLowerCase() === lowerModelName,
  );

  if (!targetModel) {
    console.error(
      `Error: Model "${modelName}" not found. Available models: ${validModels.join(", ")}`,
    );
    process.exit(1);
  }

  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const data = await (prisma as any)[targetModel].findMany({
      take: 50, // Limit to 50 for CLI view
    });
    // eslint-disable-next-line no-console
    console.log(JSON.stringify(data));
  } catch (e) {
    console.error("Error querying database:", e);
    process.exit(1);
  } finally {
    await prisma.$disconnect();
  }
}

main();
