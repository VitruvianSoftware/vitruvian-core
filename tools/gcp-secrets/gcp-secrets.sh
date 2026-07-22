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

# gcp-secrets — seed and inspect GCP Secret Manager secret VALUES, as a
# discoverable `bazel run` target rather than a `gcloud` incantation a human has
# to be handed (principles §2.2: all operational tooling is a bazel target;
# shipping an operational script you run by hand is the anti-pattern).
#
# WHAT THIS IS FOR — the narrow, legitimate out-of-band step. A secret's
# CONTAINER and its IAM are declared in Pulumi and applied by the pipeline
# (§2.3); what cannot be is the VALUE, because committing it — even
# Pulumi-encrypted — puts a secret in git history forever (§2.4). So the
# container arrives as code and the value is piped in here, once, by a human
# holding it. This is the same seam `//tools/sync-env-secrets` occupies for
# GitHub Actions secrets; that tool deliberately does NOT cover GCP Secret
# Manager, which is what this fills.
#
# SAFETY PROPERTIES (each pinned by gcp-secrets_test.sh):
#   - the value is read with `read -rs` (never echoed) and passed to gcloud on
#     STDIN via --data-file=-. It is NEVER an argv element: argv is world
#     readable via `ps`, so `gcloud secrets versions add X --data-value=…` would
#     leak the secret to every user on the box.
#   - the value never reaches stdout, stderr, or the shell history.
#   - already-seeded secrets are SKIPPED by default, so a re-run cannot silently
#     stack a second version and flip which value is `latest`.
#
# IDENTITY (§2.2 — never rely on ambient gcloud): the account and project are
# resolved from infrastructure/gcp-identities.tsv keyed on the app's infra dir,
# using the same resolver the Pulumi wrappers use. This machine has several
# gcloud accounts; picking the wrong one silently targets the wrong org.
#
# Usage (always via bazel):
#   bazel run //tools/gcp-secrets:status -- tabula/infra/build
#   bazel run //tools/gcp-secrets:seed   -- tabula/infra/build
#   bazel run //tools/gcp-secrets:seed   -- tabula/infra/build NEON_API_KEY
#   bazel run //tools/gcp-secrets:seed   -- tabula/infra/build --force NEON_API_KEY
#
# `seed` with no secret names walks every secret in the project that has NO
# version yet — the "I just applied the stack, now fill in the blanks" flow.
# --force adds a new version to an already-seeded secret (key rotation).

set -euo pipefail

# Test seam: the hermetic harness (gcp-secrets_test.sh) points these at fakes.
# CI and humans always get the real defaults.
GCLOUD_BIN="${GCLOUD_BIN:-gcloud}"

die() {
  echo "error: $*" >&2
  exit 1
}

SUBCOMMAND="${1:-}"
[ -n "$SUBCOMMAND" ] || die "internal: no subcommand (the sh_binary target bakes it)"
shift

INFRA_DIR="${1:-}"
if [ -z "$INFRA_DIR" ]; then
  cat >&2 <<'USAGE'
usage:
  bazel run //tools/gcp-secrets:status -- <infra-dir>
  bazel run //tools/gcp-secrets:seed   -- <infra-dir> [--force] [SECRET_NAME...]

<infra-dir> is the app's Pulumi infra directory as it appears in
infrastructure/gcp-identities.tsv, e.g. tabula/infra/build — the identity and
target project are resolved from there, never from ambient gcloud.
USAGE
  exit 2
fi
shift

FORCE=0
NAMES=()
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -*) die "unknown flag: $arg" ;;
    *) NAMES+=("$arg") ;;
  esac
done

# --- identity + project, from the map (never ambient) ------------------------

if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  WS="$BUILD_WORKSPACE_DIRECTORY"
else
  WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
ID_MAP="${GCP_IDENTITY_MAP:-$WS/infrastructure/gcp-identities.tsv}"
ID_RESOLVER="${GCP_IDENTITY_RESOLVER:-$WS/tools/pulumi/resolve_identity.sh}"

[ -f "$ID_MAP" ] || die "identity map not found: $ID_MAP"
[ -f "$ID_RESOLVER" ] || die "identity resolver not found: $ID_RESOLVER"

IFS=$'\t' read -r ACCOUNT PROJECT < <(bash "$ID_RESOLVER" "$ID_MAP" "$INFRA_DIR") || true
[ -n "${ACCOUNT:-}" ] || die "$INFRA_DIR is not listed in $(basename "$ID_MAP") — add it (account + project) before seeding secrets"
if [ -z "${PROJECT:-}" ] || [ "$PROJECT" = "-" ]; then
  die "$INFRA_DIR has no project pinned in $(basename "$ID_MAP") (found '-'); secrets need a concrete project"
fi

echo "→ GCP identity: $ACCOUNT   project: $PROJECT   ($INFRA_DIR)" >&2

gc() { "$GCLOUD_BIN" --account="$ACCOUNT" --project="$PROJECT" "$@"; }

# gc_checked — gc, but a FAILURE IS FATAL and never mistaken for an empty result.
#
# `gcloud` exits 0 while printing "ERROR: ... Reauthentication failed" to stderr
# when the pinned account's credentials have expired. So the obvious spelling —
# `gc secrets list 2>/dev/null` — converts a broken credential into a confident,
# empty "this project has no secrets", and `seed` would then cheerfully report
# there was nothing to do. Check the status code AND stderr, and surface the
# real message rather than swallowing it.
gc_checked() {
  local out rc
  out="$(gc "$@" 2>"$_gc_err")" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] || grep -q '^ERROR:' "$_gc_err" 2>/dev/null; then
    echo "error: gcloud $* failed as $ACCOUNT on $PROJECT:" >&2
    sed 's/^/  /' "$_gc_err" >&2
    if grep -qi 'reauth\|auth tokens\|credentials' "$_gc_err" 2>/dev/null; then
      echo "  → refresh the pinned identity:  gcloud auth login $ACCOUNT" >&2
    fi
    exit 1
  fi
  printf '%s\n' "$out"
}
_gc_err="$(mktemp)"
trap 'rm -f "$_gc_err"' EXIT

# version_count <secret> — number of ENABLED versions (destroyed ones don't count
# as seeded; a secret whose only version was destroyed needs a value again).
# NB both helpers assign gc_checked's output FIRST, then post-process. Piping it
# straight into grep/sed would put gc_checked in a pipeline subshell, so its
# fatal `exit 1` could not stop the caller — and the `|| true` that the
# legitimately-empty case needs would swallow the failure outright. Assign, let
# `|| exit 1` propagate, and only then tolerate emptiness.
version_count() {
  local out
  out="$(gc_checked secrets versions list "$1" --filter="state:ENABLED" --format="value(name)")" || exit 1
  printf '%s\n' "$out" | grep -c . || true
}

all_secrets() {
  local out
  out="$(gc_checked secrets list --format="value(name)")" || exit 1
  printf '%s\n' "$out" | sed 's|.*/||' | grep -v '^$' || true
}

# --- subcommands -------------------------------------------------------------

case "$SUBCOMMAND" in
  status)
    # Captured into a variable, NOT consumed via `< <(all_secrets)`: inside a
    # process substitution a fatal `exit 1` kills only the subshell and the loop
    # just sees no input, so an auth failure would print an empty table and exit
    # 0. As a plain assignment, `set -e` propagates the failure.
    secrets="$(all_secrets)"
    printf '%-32s %s\n' "SECRET" "ENABLED VERSIONS"
    unseeded=0
    while read -r s; do
      [ -n "$s" ] || continue
      n="$(version_count "$s")"
      printf '%-32s %s%s\n' "$s" "$n" "$([ "$n" = "0" ] && echo "   <- needs a value")"
      [ "$n" = "0" ] && unseeded=$((unseeded + 1))
    done <<<"$secrets"
    if [ "$unseeded" -gt 0 ]; then
      echo >&2
      echo "$unseeded secret(s) have no value yet. Seed them with:" >&2
      echo "  bazel run //tools/gcp-secrets:seed -- $INFRA_DIR" >&2
    fi
    ;;

  seed)
    if [ "${#NAMES[@]}" -eq 0 ]; then
      # Same reason as `status`: assign first so an auth failure is fatal rather
      # than an empty work-list that reports "nothing to do".
      discovered="$(all_secrets)"
      while read -r s; do
        [ -n "$s" ] || continue
        NAMES+=("$s")
      done <<<"$discovered"
      [ "${#NAMES[@]}" -gt 0 ] || die "no secrets found in $PROJECT — has the stack been applied?"
    fi

    seeded=0 skipped=0
    for s in "${NAMES[@]}"; do
      n="$(version_count "$s")"
      if [ "$n" != "0" ] && [ "$FORCE" -eq 0 ]; then
        echo "  $s: already has $n version(s) — skipping (use --force to rotate)"
        skipped=$((skipped + 1))
        continue
      fi

      # -s: never echo. -r: a backslash in a key is data, not an escape.
      # Prompt on stderr so `status`-style stdout stays pipeable.
      printf 'value for %s (input hidden, empty to skip): ' "$s" >&2
      IFS= read -rs value || true
      echo >&2

      if [ -z "$value" ]; then
        echo "  $s: skipped (no value entered)"
        skipped=$((skipped + 1))
        continue
      fi

      # printf %s, not echo: no trailing newline and no interpretation of a
      # leading -n/-e. Piped on STDIN so the value is never in argv (`ps`).
      if printf %s "$value" | gc secrets versions add "$s" --data-file=- >/dev/null 2>&1; then
        echo "  $s: seeded ✅"
        seeded=$((seeded + 1))
      else
        value=""
        die "$s: failed to add a version (identity $ACCOUNT may lack secretmanager.versions.add on $PROJECT)"
      fi
      value=""
    done

    echo
    echo "seeded $seeded, skipped $skipped"
    ;;

  *)
    die "unknown subcommand '$SUBCOMMAND' (expected: status, seed)"
    ;;
esac
