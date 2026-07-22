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

# saas-cli — run the Neon and Upstash CLIs for TROUBLESHOOTING and read-mostly
# operational work, already authenticated, as `bazel run` targets (principles
# §2.2: all operational tooling is a discoverable bazel target, never a bare
# command a human has to assemble).
#
# AUTHENTICATION IS NOT A STEP. Both credentials already live in the shared
# infra-pipeline project's Secret Manager (seeded with //tools/gcp-secrets).
# This wrapper reads them per invocation and passes them to the CLI as
# environment variables, so:
#   - there is no `login` subcommand and no token cached on disk to go stale or
#     leak (`neonctl auth` writes ~/.config/neonctl/credentials.json; we never
#     invoke it);
#   - the credential is always the one CI uses, so what you see locally matches
#     what the pipeline sees;
#   - rotating the secret takes effect on the next invocation, everywhere.
#
# ⚠️ PROVISIONING BELONGS TO PULUMI, NOT HERE. tabula/infra/data owns the Neon
# projects and the Upstash database. Creating or deleting one through these CLIs
# puts it outside Pulumi state, and the next `pulumi up` will try to reconcile
# the difference — recreating what you deleted, or fighting what you made. Use
# these to LOOK (list, describe, connection strings, metrics) and for the
# occasional break-glass that has no Pulumi equivalent; change desired state in
# the stack.
#
# Usage:
#   bazel run //tools/saas-cli:neon    -- projects list
#   bazel run //tools/saas-cli:neon    -- connection-string <project-id>
#   bazel run //tools/saas-cli:upstash -- redis list
#   bazel run //tools/saas-cli:whoami                       # verify both credentials
#
# Everything after `--` is forwarded to the CLI verbatim.

set -euo pipefail

# Pinned so a run is reproducible and a surprise major cannot land mid-incident
# — the same reason tools/ci/migration-safety.sh pins Squawk.
NEONCTL_VERSION="${NEONCTL_VERSION:-2.15.0}"
UPSTASH_CLI_VERSION="${UPSTASH_CLI_VERSION:-1.0.2}"

# Where the management credentials live. Not per-env: these are account-level,
# cross-environment credentials (see tabula/infra/build/main.go).
CRED_DIR="${CRED_DIR:-tabula/infra/build}"

# Test seam for the hermetic harness; real runs get the defaults.
GCLOUD_BIN="${GCLOUD_BIN:-gcloud}"
NPX_BIN="${NPX_BIN:-npx}"

die() {
  echo "saas-cli: $*" >&2
  exit 1
}

SUBCOMMAND="${1:-}"
[ -n "$SUBCOMMAND" ] || die "internal: no subcommand (the sh_binary target bakes it)"
shift

# --- identity + project, from the map (never ambient gcloud) -----------------

if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  WS="$BUILD_WORKSPACE_DIRECTORY"
else
  WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
ID_MAP="${GCP_IDENTITY_MAP:-$WS/infrastructure/gcp-identities.tsv}"
ID_RESOLVER="${GCP_IDENTITY_RESOLVER:-$WS/tools/pulumi/resolve_identity.sh}"

[ -f "$ID_MAP" ] || die "identity map not found: $ID_MAP"
[ -f "$ID_RESOLVER" ] || die "identity resolver not found: $ID_RESOLVER"

IFS=$'\t' read -r ACCOUNT PROJECT < <(bash "$ID_RESOLVER" "$ID_MAP" "$CRED_DIR") || true
[ -n "${ACCOUNT:-}" ] || die "$CRED_DIR is not listed in $(basename "$ID_MAP")"
[ -n "${PROJECT:-}" ] && [ "$PROJECT" != "-" ] || die "$CRED_DIR has no project pinned in $(basename "$ID_MAP")"

_err="$(mktemp)"
trap 'rm -f "$_err"' EXIT

# secret <NAME> — the value, or a fatal error naming how to seed it.
#
# gcloud EXITS 0 while printing "ERROR: ... Reauthentication failed" to stderr on
# an expired credential, so neither the status code nor an empty result can be
# trusted alone — check both, and surface the real message.
secret() {
  local name="$1" out rc
  out="$("$GCLOUD_BIN" --account="$ACCOUNT" --project="$PROJECT" \
    secrets versions access latest --secret="$name" 2>"$_err")" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] || grep -q '^ERROR:' "$_err" 2>/dev/null; then
    echo "saas-cli: could not read $name from $PROJECT as $ACCOUNT:" >&2
    sed 's/^/  /' "$_err" >&2
    if grep -qi 'reauth\|auth tokens\|credentials' "$_err" 2>/dev/null; then
      echo "  → refresh the pinned identity:  gcloud auth login $ACCOUNT" >&2
    else
      echo "  → seed it:  bazel run //tools/gcp-secrets:seed -- $CRED_DIR $name" >&2
    fi
    exit 1
  fi
  [ -n "$out" ] || die "$name is empty in $PROJECT — seed it with //tools/gcp-secrets:seed"
  printf '%s' "$out"
}

case "$SUBCOMMAND" in
  neon)
    # Assign FIRST. `VAR="$(secret …)" exec cmd` puts `secret` in a command
    # substitution, so its fatal `exit 1` kills only that subshell and the exec
    # proceeds with an EMPTY credential — the failure becomes a confusing CLI
    # auth error instead of our actionable message. As a plain assignment,
    # `set -e` propagates it.
    key="$(secret NEON_API_KEY)"
    echo "→ neonctl@${NEONCTL_VERSION} as the ${PROJECT} NEON_API_KEY" >&2
    # --api-key is deliberately NOT used: argv is world-readable via `ps`.
    NEON_API_KEY="$key" exec "$NPX_BIN" --yes "neonctl@${NEONCTL_VERSION}" "$@"
    ;;

  upstash)
    email="$(secret UPSTASH_EMAIL)"
    key="$(secret UPSTASH_API_KEY)"
    echo "→ @upstash/cli@${UPSTASH_CLI_VERSION} as the ${PROJECT} UPSTASH_API_KEY" >&2
    UPSTASH_EMAIL="$email" UPSTASH_API_KEY="$key" \
      exec "$NPX_BIN" --yes "@upstash/cli@${UPSTASH_CLI_VERSION}" "$@"
    ;;

  whoami)
    # Prove both credentials actually work, rather than merely being present —
    # a seeded-but-revoked key looks identical to a good one until it is used.
    rc=0
    nkey="$(secret NEON_API_KEY)"
    uemail="$(secret UPSTASH_EMAIL)"
    ukey="$(secret UPSTASH_API_KEY)"
    echo "neon:"
    if NEON_API_KEY="$nkey" \
      "$NPX_BIN" --yes "neonctl@${NEONCTL_VERSION}" me 2>&1 | sed 's/^/  /'; then :; else
      echo "  ✗ neonctl me failed — the key is present but not usable" >&2
      rc=1
    fi
    echo "upstash:"
    if UPSTASH_EMAIL="$uemail" UPSTASH_API_KEY="$ukey" \
      "$NPX_BIN" --yes "@upstash/cli@${UPSTASH_CLI_VERSION}" redis list 2>&1 | sed 's/^/  /'; then :; else
      echo "  ✗ upstash redis list failed — the key is present but not usable" >&2
      rc=1
    fi
    exit "$rc"
    ;;

  *)
    die "unknown subcommand '$SUBCOMMAND' (expected: neon, upstash, whoami)"
    ;;
esac
