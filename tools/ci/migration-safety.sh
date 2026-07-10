#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# migration-safety.sh -- Squawk migration-safety gate for Tabula's Prisma
# migrations (issue #819).
#
# WHY: the blue-green Cloud Run rollout (_deploy-cloud-run.yaml) runs
# `prisma migrate deploy` BEFORE the new revision takes traffic, so the OLD
# revision keeps serving against the just-migrated schema during the traffic
# shift. A backward-INCOMPATIBLE migration (drop/rename a column the old code
# reads, narrow a type, add a validated constraint) breaks the live revision
# the instant it applies -- and can't be rolled back to. Squawk, tuned by
# tabula/api/prisma/.squawk.toml, fails exactly that class.
#
# Deliberate, post-soak destructive changes are done as *_contract migrations
# (docs/engineering/application-development-principles.md#expandcontract-
# migrations) and are EXEMPT here -- they're applied only via the explicit
# contract phase (migrate-deploy.cjs --phase contract), never auto-applied
# during a rollout, so gating them would be wrong.
#
# Usage:
#   tools/ci/migration-safety.sh              # self-test only (always reports)
#   tools/ci/migration-safety.sh <base-ref>   # self-test + lint migrations
#                                             #   added/modified since <base-ref>
#
# Exit non-zero if the self-test regresses OR any non-contract migration added/
# modified since <base-ref> is backward-incompatible.
#
# NB: `set +e` -- this script drives its own exit code via explicit checks and
# an accumulated `rc`; a GitHub `run:` step's inherited `-e` does not propagate
# into this separate `bash <script>` process, but we set it explicitly so the
# behaviour is identical run locally or in CI.
set +e -u -o pipefail

SQUAWK_VERSION="2.59.0"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$ROOT/tabula/api/prisma/.squawk.toml"
MIG_DIR="tabula/api/prisma/migrations"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Pinned Squawk (https://squawkhq.com). npx fetches the platform binary for the
# pinned version; the pin is what makes the gate reproducible.
squawk() { npx --yes "squawk-cli@${SQUAWK_VERSION}" -c "$CONFIG" "$@"; }

fail() { echo "::error::migration-safety: $*" >&2; exit 1; }
note() { echo "migration-safety: $*"; }

# 1) Self-test: prove the tuned rule set still catches the hazard class AND still
#    accepts safe additive DDL. Runs on every invocation (so the required check
#    always reports, and a mis-tuning of .squawk.toml is caught here, not in a
#    silent false-green). Fixtures are inline so there are no stray .sql files.
selftest() {
  local bad="$TMP/backward_incompatible.sql" good="$TMP/backward_compatible.sql"
  # Backward-INCOMPATIBLE: drop a column + narrow a type. An old revision still
  # SELECTing "email" / expecting the wider type breaks the instant this applies.
  cat > "$bad" <<'SQL'
ALTER TABLE "users" DROP COLUMN "email";
ALTER TABLE "users" ALTER COLUMN "id" SET DATA TYPE VARCHAR(100);
SQL
  # Backward-COMPATIBLE (expand): add a nullable column; old code ignores it.
  cat > "$good" <<'SQL'
ALTER TABLE "users" ADD COLUMN "nickname" text;
SQL
  if ! squawk "$good" >/dev/null 2>&1; then
    fail "self-test FAILED -- a backward-COMPATIBLE fixture (ADD nullable COLUMN) was REJECTED. tabula/api/prisma/.squawk.toml is mis-tuned and would block safe expand migrations."
  fi
  if squawk "$bad" >/dev/null 2>&1; then
    fail "self-test FAILED -- a backward-INCOMPATIBLE fixture (DROP COLUMN + type narrow) PASSED. The gate is not catching hazards; check that ban-drop-column / changing-column-type are not in excluded_rules."
  fi

  # Escape hatch: a per-statement `-- squawk-ignore <rule>` lets a change the
  # author has VERIFIED is safe (e.g. a type WIDENING that Squawk flags
  # conservatively) flow through as a normal expand migration -- WITHOUT the
  # heavyweight *_contract path. It must be scoped: ignoring one rule must NOT
  # suppress a different hazard on another statement.
  local ign="$TMP/ignore_ok.sql" ignscoped="$TMP/ignore_scoped.sql"
  printf -- '-- squawk-ignore changing-column-type\nALTER TABLE "users" ALTER COLUMN "name" SET DATA TYPE VARCHAR(500);\n' > "$ign"
  printf -- '-- squawk-ignore changing-column-type\nALTER TABLE "users" DROP COLUMN "email";\n' > "$ignscoped"
  if ! squawk "$ign" >/dev/null 2>&1; then
    fail "self-test FAILED -- a widening with '-- squawk-ignore changing-column-type' was REJECTED. The documented escape hatch no longer works; safe-but-flagged changes have no remedy except *_contract."
  fi
  if squawk "$ignscoped" >/dev/null 2>&1; then
    fail "self-test FAILED -- '-- squawk-ignore changing-column-type' suppressed an UNRELATED hazard (DROP COLUMN). The ignore must be rule-scoped, not a blanket bypass."
  fi
  note "self-test OK (drop/type-narrow rejected, add-nullable accepted, scoped squawk-ignore honored)."
}

# Layer-2 guard: the deploy wrapper's expand phase refuses to sweep in a pending
# *_contract migration, keyed off the `contractsInStatus` parser in
# migrate-deploy.cjs. Guard that parser here so a regression is caught in CI,
# not on a live deploy (the parser is pure, so no database is needed).
phase_guard_selftest() {
  if node -e '
    const { contractsInStatus } = require(process.argv[1]);
    const eq = (n, g, w) => {
      if (JSON.stringify(g) !== JSON.stringify(w)) {
        console.error(`phase-guard parse FAILED: ${n} -> ${JSON.stringify(g)}`);
        process.exit(1);
      }
    };
    eq("contract-pending", contractsInStatus(
      "Following migration have not yet been applied:\n20260701000000_add_col\n20260702000000_drop_ws_id_contract"),
      ["20260702000000_drop_ws_id_contract"]);
    eq("expand-only", contractsInStatus(
      "Following migration have not yet been applied:\n20260701000000_add_col"), []);
    eq("up-to-date", contractsInStatus("Database schema is up to date!"), []);
    eq("substring-not-suffix", contractsInStatus(
      "Following migration have not yet been applied:\n20260701000000_contract_terms"), []);
  ' "$ROOT/tabula/api/prisma/migrate-deploy.cjs"; then
    note "phase-guard parser self-test OK."
  else
    fail "phase-guard parser self-test FAILED -- migrate-deploy.cjs contractsInStatus() regressed; the expand phase may no longer refuse pending *_contract migrations."
  fi
}

# 2) Lint the migrations this branch adds/modifies, skipping deliberate contracts.
lint_changed() {
  local base="$1" changed f rc=0
  # Three-dot diff => against the merge base, so only THIS branch's migrations
  # (needs full history; the workflow checks out with fetch-depth: 0).
  changed="$(git -C "$ROOT" diff --name-only --diff-filter=AM "${base}...HEAD" -- "$MIG_DIR" | grep '/migration\.sql$' || true)"
  if [ -z "$changed" ]; then
    note "no added/modified migrations since ${base} -- nothing to lint."
    return 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      */*_contract/migration.sql)
        note "SKIP deliberate contract migration: $f"
        continue ;;
    esac
    if squawk "$ROOT/$f"; then
      note "OK: $f"
    else
      echo "::error file=${f}::Backward-incompatible migration. Two remedies: (1) DELIBERATE destructive change -> make it a *_contract migration so it is applied only via \`--phase contract\`, post-soak, never auto-applied during a blue-green rollout; (2) you have VERIFIED this statement is backward-COMPATIBLE (e.g. a type widening Squawk flags conservatively) -> add \`-- squawk-ignore <rule>\` on the line above it. See docs/engineering/application-development-principles.md#expandcontract-migrations."
      rc=1
    fi
  done <<EOF
$changed
EOF
  return "$rc"
}

selftest
phase_guard_selftest
if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
  lint_changed "$1" || exit 1
fi
note "all checks passed."
