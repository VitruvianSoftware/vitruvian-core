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
 * Hermetic `prisma migrate deploy`: the one Prisma 6 command that executes a
 * native schema-engine binary. The engine is vendored via http_file (pinned
 * to the @prisma/engines-version hash) and its runfiles path arrives in
 * PRISMA_SCHEMA_ENGINE_BINARY, resolved here to an absolute path because the
 * Prisma CLI resolves that env var against its own cwd.
 *
 * Expand/contract phase (issue #819): `migrate deploy` always applies ALL
 * pending migrations, and the blue-green rollout runs it BEFORE the new
 * revision takes traffic -- so the OLD revision keeps serving against the new
 * schema during the shift. A backward-INCOMPATIBLE ("contract") migration
 * therefore must NOT be auto-applied in that window; it is applied deliberately,
 * after the new revision has soaked. We encode that as a phase:
 *   --phase expand   (default) refuses to run if any PENDING migration is a
 *                    deliberate *_contract migration (it would be swept in by
 *                    `migrate deploy`). This is the phase the auto-deploy uses.
 *   --phase contract applies everything, including *_contract migrations. This
 *                    is the explicit, post-soak path an operator runs by hand.
 * A migration is "contract" iff its directory name ends in `_contract` -- the
 * same convention the migration-safety gate (tools/ci/migration-safety.sh)
 * exempts from the backward-incompatibility lint.
 */
const { spawnSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const schemaArgIdx = process.argv.indexOf("--schema");
const schema =
  schemaArgIdx > 0
    ? process.argv[schemaArgIdx + 1]
    : "tabula/api/prisma/schema.prisma";

const phaseArgIdx = process.argv.indexOf("--phase");
const phase = phaseArgIdx > 0 ? process.argv[phaseArgIdx + 1] : "expand";
if (phase !== "expand" && phase !== "contract") {
  console.error(
    `migrate-deploy: --phase must be "expand" or "contract" (got "${phase}")`,
  );
  process.exit(2);
}

const env = { ...process.env, PRISMA_HIDE_UPDATE_MESSAGE: "1" };
if (env.PRISMA_SCHEMA_ENGINE_BINARY) {
  env.PRISMA_SCHEMA_ENGINE_BINARY = path.resolve(
    env.PRISMA_SCHEMA_ENGINE_BINARY,
  );
}
// The query engine is only existence-checked by `migrate deploy` (never
// executed); a placeholder defeats the CLI's downloader. prisma/prisma#28083.
if (env.PRISMA_QUERY_ENGINE_LIBRARY) {
  env.PRISMA_QUERY_ENGINE_LIBRARY = path.resolve(
    env.PRISMA_QUERY_ENGINE_LIBRARY,
  );
}

// Prisma 7 reads the migration datasource URL from prisma.config.ts (schema
// files can no longer carry `url`). The config sits next to the prisma/ dir;
// pass it explicitly because Bazel invokes this from the workspace root, not
// the package dir where the CLI would auto-discover it.
const config = path.join(path.dirname(schema), "..", "prisma.config.ts");

// Pure parse (unit-testable without Prisma or a database): the contract
// migrations Prisma lists under "…have not yet been applied". A migration is a
// contract iff its directory name ends in `_contract`.
function contractsInStatus(statusOutput) {
  const marker = statusOutput.search(/not yet been applied/i);
  if (marker === -1) return [];
  const names = statusOutput.slice(marker).match(/\d{14}_[A-Za-z0-9_]+/g) || [];
  return [...new Set(names)].filter((n) => n.endsWith("_contract"));
}

// When imported (by a test) rather than run, expose only the pure parser and
// stop before resolving Prisma -- which is linked into Bazel runfiles, not a
// plain node_modules, so `require.resolve` would throw outside the deploy.
if (require.main !== module) {
  module.exports = { contractsInStatus };
  return;
}

const prismaCli = require.resolve("prisma/build/index.js");

// Contract migration directories present in the source tree (name ends in
// `_contract`). Cheap and dependency-free -- resolved the same way the deploy
// already resolves the schema (workspace-relative from the run cwd).
function contractDirsOnDisk() {
  const dir = path.join(path.dirname(schema), "migrations");
  try {
    return fs
      .readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isDirectory() && e.name.endsWith("_contract"))
      .map((e) => e.name);
  } catch {
    return [];
  }
}

// EXPAND-phase guard. `migrate deploy` applies ALL pending migrations, so if a
// pending one is a contract it would be swept in during the blue-green window.
// The common case has NO contract migrations at all -- then there is nothing to
// guard and we never even run `migrate status` (no extra latency or failure
// surface on a normal deploy). Only when a contract EXISTS on disk do we consult
// `migrate status` to distinguish a pending contract (refuse) from one already
// applied by an earlier `--phase contract` run (proceed). If status can't be
// read (e.g. the deploy hands Prisma a placeholder query engine and some future
// Prisma needs a real one), we fail CLOSED rather than risk sweeping a contract.
if (phase === "expand" && contractDirsOnDisk().length > 0) {
  const st = spawnSync(
    process.execPath,
    [
      prismaCli,
      "migrate",
      "status",
      `--schema=${schema}`,
      `--config=${config}`,
    ],
    { env, encoding: "utf8" },
  );
  const out = `${st.stdout || ""}${st.stderr || ""}`;
  if (!/not yet been applied|up to date/i.test(out)) {
    console.error(
      "migrate-deploy: a *_contract migration exists but `migrate status` could " +
        "not be read, so we cannot confirm it is already applied. Refusing the " +
        "EXPAND phase to avoid sweeping a backward-incompatible migration into a " +
        "blue-green rollout. Apply contracts deliberately via `--phase contract`. " +
        "Status output:\n" +
        out,
    );
    process.exit(3);
  }
  const pending = contractsInStatus(out);
  if (pending.length > 0) {
    console.error(
      "migrate-deploy: refusing to apply in the EXPAND phase -- `migrate deploy` " +
        `would sweep in ${pending.length} pending *_contract migration(s):\n` +
        pending.map((c) => `  - ${c}`).join("\n") +
        "\nContract (backward-incompatible) migrations must be applied deliberately, " +
        "AFTER the new revision has soaked, via `--phase contract`. See " +
        "docs/engineering/application-development-principles.md#expandcontract-migrations.",
    );
    process.exit(3);
  }
}

const res = spawnSync(
  process.execPath,
  [prismaCli, "migrate", "deploy", `--schema=${schema}`, `--config=${config}`],
  {
    stdio: "inherit",
    env,
  },
);
process.exit(res.status === null ? 1 : res.status);
