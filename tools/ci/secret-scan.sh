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

# secret-scan.sh — gitleaks gate over the commits a change INTRODUCES.
#
# Why diff-scoped and not full history: this repo has 23 known historical
# findings, including a BuildBuddy key that was committed, de-committed and
# ROTATED (docs/repo-assessment.md §7.1 item C) and an old local-dev k3s
# kubeconfig. A full-history scan would be permanently red, and a permanently
# red gate is a gate everyone learns to ignore. Scanning only the range means
# the check can fail on exactly one thing: a secret THIS change adds.
#
# GitHub's native secret scanning + push protection (managed in repo_config)
# already cover known PROVIDER patterns. This adds the generic/custom classes
# they miss -- `secret_scanning_non_provider_patterns` is disabled on this repo
# -- and, unlike alert-based scanning, it BLOCKS the merge.
#
# Environment:
#   BASE_REV   explicit base revision (push / merge_group lanes).
#   BASE_REF   target branch for the PR lane; the base is its merge-base.
#   Neither set -> scan the working tree only (local use).
#
# Run locally: bash tools/ci/secret-scan.sh

set -euo pipefail

GITLEAKS_VERSION="8.30.1"
# sha256 of gitleaks_${VERSION}_linux_x64.tar.gz from the release checksums file.
GITLEAKS_SHA256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

# --- resolve the scan range. -------------------------------------------------
# FAIL SAFE: if we cannot work out what the change added, scan the working tree
# rather than silently scanning nothing.
BASE_REV="${BASE_REV:-}"
BASE_REF="${BASE_REF:-}"
RANGE=""

if [ -n "${BASE_REV}" ] && git rev-parse --verify --quiet "${BASE_REV}^{commit}" >/dev/null 2>&1; then
  RANGE="${BASE_REV}..HEAD"
elif [ -n "${BASE_REF}" ]; then
  if base="$(git merge-base "origin/${BASE_REF}" HEAD 2>/dev/null)"; then
    RANGE="${base}..HEAD"
  fi
fi

# --- install gitleaks (pinned + checksum-verified, same shape as the
# --- actionlint / kubeconform / squawk gates). -------------------------------
BIN_DIR="$(mktemp -d)"
trap 'rm -rf "${BIN_DIR}"' EXIT

if command -v gitleaks >/dev/null 2>&1 && [ "${USE_SYSTEM_GITLEAKS:-}" = "1" ]; then
  GITLEAKS="$(command -v gitleaks)"
else
  tarball="${BIN_DIR}/gitleaks.tar.gz"
  url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  echo "secret-scan: fetching gitleaks v${GITLEAKS_VERSION}..."
  curl -fsSL -o "${tarball}" "${url}"
  actual="$(sha256sum "${tarball}" | awk '{print $1}')"
  if [ "${actual}" != "${GITLEAKS_SHA256}" ]; then
    echo "::error::gitleaks checksum mismatch — expected ${GITLEAKS_SHA256}, got ${actual}" >&2
    exit 1
  fi
  tar -xzf "${tarball}" -C "${BIN_DIR}" gitleaks
  GITLEAKS="${BIN_DIR}/gitleaks"
fi

# --- scan. -------------------------------------------------------------------
# --redact so a finding never prints the secret itself into a public CI log.
set +e
if [ -n "${RANGE}" ]; then
  echo "secret-scan: scanning commits in ${RANGE}"
  "${GITLEAKS}" git --no-banner --redact --config .gitleaks.toml \
    --log-opts="${RANGE}" .
  rc=$?
else
  echo "secret-scan: no diff base resolved — scanning the working tree (fail-safe)."
  "${GITLEAKS}" dir --no-banner --redact --config .gitleaks.toml .
  rc=$?
fi
set -e

# A gitleaks exec failure and a real finding are both non-zero exits, and
# without this check they render identically -- "gitleaks found a candidate
# secret" -- even though nothing was scanned. Concretely: this script always
# fetches the LINUX release tarball (line ~76), so a local run on macOS
# downloads it, passes the checksum, and then fails to exec with the shell's
# reserved 126 ("found but not executable" -- an ELF binary on Darwin) or 127
# ("command not found"). Both are shell-level exec failures, not a gitleaks
# verdict, and must not be reported as one.
if [ "${rc}" -eq 126 ] || [ "${rc}" -eq 127 ]; then
  cat >&2 <<MSG
::error::secret-scan: gitleaks did not run (exit ${rc}) -- this is an exec
failure, NOT a secret finding. The fetched binary is Linux-only; on macOS (or
any non-Linux host) it cannot execute.
  * Install gitleaks locally (e.g. \`brew install gitleaks\`) and re-run with
    USE_SYSTEM_GITLEAKS=1, or run this script on Linux/in CI.
MSG
  exit "${rc}"
fi

if [ "${rc}" -ne 0 ]; then
  cat >&2 <<'MSG'
::error::secret-scan: gitleaks found a candidate secret in the commits this change adds.
  * If it IS a secret: remove it, then ROTATE it -- it is in the branch history
    and rewriting that history does not un-share it.
  * If it is a false positive that is safe BY CONSTRUCTION (e.g. ciphertext),
    add a scoped allowlist entry to .gitleaks.toml explaining why.
  * For a genuine one-off, put a `gitleaks:allow` comment on that line.
MSG
  exit "${rc}"
fi

echo "secret-scan: no secrets found in the added commits."
