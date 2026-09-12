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
 * Startup guard against schema drift — a database that is BEHIND the deployed
 * code because a `prisma migrate deploy` never ran for this rollout.
 *
 * The deploy workflow runs migrations before shifting traffic, but an
 * out-of-band rollout (a manual image bump / `pulumi up` that skips the migrate
 * step) can put NEW code in front of an OLD database. Every query that touches a
 * not-yet-added column then throws Prisma P2022 at request time — which users
 * see as "Sync failed" and raw Prisma errors (the workspace PUT needs
 * `workspaces.version`; the backups panel needs `backups.type`). Checking the
 * load-bearing columns at boot converts that silent, user-facing breakage into a
 * loud, immediate deploy failure: the process exits non-zero, so Cloud Run keeps
 * the previous healthy revision serving instead of rolling out the broken one.
 */
import type { FastifyBaseLogger } from "fastify";
import { prisma } from "./prisma";

interface RequiredColumn {
  table: string;
  column: string;
  migration: string;
}

/**
 * Schema invariants the running code cannot function without, each tagged with
 * the migration that introduced it. Deliberately a small, hand-curated set (not
 * a full schema diff) — enough to catch "the database is behind the code". Add a
 * row when a migration introduces a column the code hard-depends on.
 */
export const REQUIRED_COLUMNS: readonly RequiredColumn[] = [
  // 20260610000000_add_sync_versioning — optimistic-concurrency + device lease
  // that every cross-device workspace PUT reads/writes.
  {
    table: "workspaces",
    column: "version",
    migration: "20260610000000_add_sync_versioning",
  },
  {
    table: "workspaces",
    column: "active_device_id",
    migration: "20260610000000_add_sync_versioning",
  },
  {
    table: "workspaces",
    column: "active_device_seen_at",
    migration: "20260610000000_add_sync_versioning",
  },
  {
    table: "space_groups",
    column: "version",
    migration: "20260610000000_add_sync_versioning",
  },
  // 20260610010000_add_backup_name_type — backups list/stats select these.
  {
    table: "backups",
    column: "name",
    migration: "20260610010000_add_backup_name_type",
  },
  {
    table: "backups",
    column: "type",
    migration: "20260610010000_add_backup_name_type",
  },
];

/** Thrown when the database is missing columns the deployed code requires. */
export class MigrationDriftError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MigrationDriftError";
  }
}

/** Tuning for the information_schema probe (overridable in tests). */
export interface ProbeOptions {
  /** Total attempts before giving up (default 5). */
  attempts?: number;
  /** Base backoff between attempts, grows linearly per attempt (default 1000ms). */
  backoffMs?: number;
}

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

/**
 * Return the REQUIRED_COLUMNS absent from the connected database.
 *
 * The information_schema probe is RETRIED. The very first database connection at
 * startup can fail or time out — e.g. a Neon serverless compute waking from
 * suspend — and a single attempt previously made the guard fail open, silently
 * letting a drifted deploy serve traffic (the exact gap that shipped a broken
 * backups/sync release). The deploy ran `migrate deploy` against the same
 * database moments earlier, so it IS reachable; a transient cold start must not
 * defeat the check. Rejects only if every attempt fails.
 */
export async function findMissingRequiredColumns(
  opts: ProbeOptions = {},
): Promise<RequiredColumn[]> {
  const attempts = opts.attempts ?? 5;
  const backoffMs = opts.backoffMs ?? 1000;

  let lastErr: unknown;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      // information_schema.columns exposes table_name/column_name as the
      // Postgres `name` type (domain sql_identifier). Prisma's $queryRaw
      // cannot deserialize `name` ("Failed to deserialize column of type
      // 'name'"), which crashed this probe at startup and stopped the API
      // from ever becoming healthy. Cast to text so Prisma can map them.
      const rows = await prisma.$queryRaw<
        { table_name: string; column_name: string }[]
      >`SELECT table_name::text AS table_name, column_name::text AS column_name FROM information_schema.columns WHERE table_schema = 'public'`;
      const present = new Set(
        rows.map((r) => `${r.table_name}.${r.column_name}`),
      );
      return REQUIRED_COLUMNS.filter(
        (c) => !present.has(`${c.table}.${c.column}`),
      );
    } catch (err) {
      lastErr = err;
      if (attempt < attempts) {
        await sleep(backoffMs * attempt);
      }
    }
  }
  throw lastErr;
}

/**
 * Fail fast when the database is behind the deployed code.
 *
 * On drift (the check ran and found missing columns): log an actionable fatal
 * and throw, so the caller exits non-zero — Cloud Run then keeps the previous
 * healthy revision rather than serving a broken one.
 *
 * On an inability to RUN the check (DB unreachable, missing privileges): warn
 * and return. We never block startup on a check we could not complete — the
 * request path still surfaces real connectivity errors, and the next
 * deploy/restart re-checks. Bypass entirely with TABULA_SKIP_MIGRATION_CHECK=1.
 */
export async function assertDatabaseSchemaCurrent(
  logger: Pick<FastifyBaseLogger, "info" | "warn" | "error" | "fatal">,
  opts: ProbeOptions = {},
): Promise<void> {
  if (process.env.TABULA_SKIP_MIGRATION_CHECK === "1") {
    // A bypass is legitimate (emergency), but it must be visible — a silent
    // skip is how a drifted database goes unnoticed.
    logger.warn(
      "migration drift check BYPASSED via TABULA_SKIP_MIGRATION_CHECK=1",
    );
    return;
  }

  let missing: RequiredColumn[];
  try {
    missing = await findMissingRequiredColumns(opts);
  } catch (err) {
    // Could not probe even after retries. This is the path that previously let
    // a drifted deploy serve, so make it LOUD (error, not a quiet warn). We
    // still start — permanently crash-looping on a database outage would be
    // worse than serving — but the gap is now visible to logs/alerts.
    logger.error(
      { err },
      "migration drift check could NOT run after retries (information_schema " +
        "unreachable); starting WITHOUT schema verification",
    );
    return;
  }

  if (missing.length > 0) {
    const columns = missing.map((m) => `${m.table}.${m.column}`).join(", ");
    const migrations = [...new Set(missing.map((m) => m.migration))].join(", ");
    const message =
      `Database schema is behind the deployed code: missing column(s) ${columns}. ` +
      `Apply the pending migration(s) (${migrations}) with 'prisma migrate deploy' ` +
      `before serving traffic. Refusing to start.`;
    logger.fatal({ missing }, message);
    throw new MigrationDriftError(message);
  }

  // Confirm the guard actually ran and passed, so its effect is observable.
  logger.info(
    `migration drift check passed: all ${REQUIRED_COLUMNS.length} required columns present`,
  );
}
