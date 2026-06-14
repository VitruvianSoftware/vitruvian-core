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

import {
  assertDatabaseSchemaCurrent,
  findMissingRequiredColumns,
  MigrationDriftError,
  REQUIRED_COLUMNS,
} from "../../src/lib/migrationGuard";
import { prisma } from "../../src/lib/prisma";

// Mock the Prisma client: the guard only ever calls $queryRaw.
jest.mock("../../src/lib/prisma", () => ({
  prisma: { $queryRaw: jest.fn() },
}));

const $queryRaw = prisma.$queryRaw as unknown as jest.Mock;

/** information_schema rows for every required column (a fully-migrated DB). */
const allColumnsPresent = () =>
  REQUIRED_COLUMNS.map((c) => ({ table_name: c.table, column_name: c.column }));

describe("migrationGuard", () => {
  const logger = {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    fatal: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    delete process.env.TABULA_SKIP_MIGRATION_CHECK;
  });

  describe("findMissingRequiredColumns", () => {
    it("returns [] when every required column exists", async () => {
      $queryRaw.mockResolvedValue(allColumnsPresent());
      await expect(findMissingRequiredColumns()).resolves.toEqual([]);
    });

    it("returns exactly the columns absent from the database", async () => {
      // Simulate the live DB that is missing the June sync/backup migrations.
      const present = allColumnsPresent().filter(
        (r) =>
          !(r.table_name === "workspaces" && r.column_name === "version") &&
          !(r.table_name === "backups" && r.column_name === "type"),
      );
      $queryRaw.mockResolvedValue(present);

      const missing = await findMissingRequiredColumns();

      expect(missing).toHaveLength(2);
      expect(missing).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ table: "workspaces", column: "version" }),
          expect.objectContaining({ table: "backups", column: "type" }),
        ]),
      );
    });

    it("retries the probe and succeeds after a transient startup failure", async () => {
      // The first DB connection (e.g. a cold Neon compute) fails, the next works.
      $queryRaw
        .mockRejectedValueOnce(new Error("connection terminated"))
        .mockResolvedValueOnce(allColumnsPresent());

      await expect(
        findMissingRequiredColumns({ backoffMs: 0 }),
      ).resolves.toEqual([]);
      expect($queryRaw).toHaveBeenCalledTimes(2);
    });
  });

  describe("assertDatabaseSchemaCurrent", () => {
    it("passes quietly and logs success when the schema is current", async () => {
      $queryRaw.mockResolvedValue(allColumnsPresent());
      await expect(
        assertDatabaseSchemaCurrent(logger),
      ).resolves.toBeUndefined();
      expect(logger.fatal).not.toHaveBeenCalled();
      expect(logger.info).toHaveBeenCalledTimes(1);
    });

    it("throws MigrationDriftError and logs an actionable fatal on drift", async () => {
      $queryRaw.mockResolvedValue(
        allColumnsPresent().filter(
          (r) =>
            !(r.table_name === "workspaces" && r.column_name === "version"),
        ),
      );

      await expect(assertDatabaseSchemaCurrent(logger)).rejects.toBeInstanceOf(
        MigrationDriftError,
      );
      expect(logger.fatal).toHaveBeenCalledTimes(1);
      const message = logger.fatal.mock.calls[0][1] as string;
      expect(message).toContain("workspaces.version");
      expect(message).toContain("20260610000000_add_sync_versioning");
      expect(message).toContain("prisma migrate deploy");
    });

    it("logs an ERROR (not a silent skip) and fails open when the probe can't run after retries", async () => {
      // DB unreachable for every attempt: don't permanently crash-loop, but make
      // the skipped check loud — this is the path that previously let a drifted
      // deploy serve silently.
      $queryRaw.mockRejectedValue(new Error("ECONNREFUSED"));

      await expect(
        assertDatabaseSchemaCurrent(logger, { attempts: 3, backoffMs: 0 }),
      ).resolves.toBeUndefined();
      expect(logger.error).toHaveBeenCalledTimes(1);
      expect(logger.fatal).not.toHaveBeenCalled();
      expect($queryRaw).toHaveBeenCalledTimes(3);
    });

    it("is bypassable via TABULA_SKIP_MIGRATION_CHECK and logs the bypass", async () => {
      process.env.TABULA_SKIP_MIGRATION_CHECK = "1";
      await expect(
        assertDatabaseSchemaCurrent(logger),
      ).resolves.toBeUndefined();
      expect($queryRaw).not.toHaveBeenCalled();
      expect(logger.warn).toHaveBeenCalledTimes(1);
    });
  });
});
