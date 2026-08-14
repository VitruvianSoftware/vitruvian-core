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
#
# gcp-secret-or-fail.sh — fetch a GCP Secret Manager secret's latest version,
# or fail loudly with actionable context. Prints the secret value to stdout on
# success. Deduped from 3 near-identical inline "gcloud secrets versions
# access latest ... || fail" blocks (_deploy-cloud-run.yaml x2,
# tabula-data-stack.yaml).
#
# WHY an explicit exit-code check, not just an empty-string check: gcloud can
# exit 0 while still printing ERROR to stderr (a known footgun in this repo --
# see tools/deploy/cloud-run.sh's resolve_stable_revision), and a
# genuinely-missing secret returns PERMISSION_DENIED, not NOT_FOUND, so
# reading the WRONG secret id is indistinguishable from an IAM gap unless the
# raw gcloud stderr is surfaced.
#
# Usage: gcp-secret-or-fail.sh <secret-id> <project> [context-message]

set -euo pipefail

# secret_or_fail(rc, value, stderr_content, secret_id, project, context) --
# pure decision function, no gcloud call, so it is unit-testable standalone.
# Prints the value to stdout and returns 0 on success; prints an ::error:: to
# stderr (with the raw gcloud stderr attached, if any) and returns 1 on a
# nonzero exit code OR an empty value.
secret_or_fail() {
  local rc="$1" value="$2" stderr_content="$3" secret_id="$4" project="$5" context="$6"
  if [ "${rc}" -ne 0 ] || [ -z "${value}" ]; then
    echo "::error::secret ${secret_id} could not be read from ${project}${context:+ — ${context}}" >&2
    if [ -n "${stderr_content}" ]; then
      echo "gcloud stderr: ${stderr_content}" >&2
    fi
    return 1
  fi
  printf '%s' "${value}"
  return 0
}

main() {
  local secret_id="${1:?secret id required}" project="${2:?project required}" context="${3:-}"
  local stderr_file value rc
  stderr_file="$(mktemp)"
  # No cleanup trap: a `trap '...${stderr_file}...' EXIT` registered here
  # references a LOCAL variable, but when secret_or_fail (below) returns 1,
  # `set -e` unwinds the whole script -- by the time the EXIT trap actually
  # fires, main()'s local scope is gone, so ${stderr_file} is unbound and the
  # trap itself crashes with "unbound variable", masking the real ::error::
  # this function already printed (this took down two real deploy runs in
  # production before being caught). CI runners are ephemeral; an unremoved
  # mktemp file needs no explicit cleanup.

  # +e: capture gcloud's real exit code instead of letting -e abort here.
  set +e
  value="$(gcloud secrets versions access latest --secret="${secret_id}" --project="${project}" 2>"${stderr_file}")"
  rc=$?
  set -e

  secret_or_fail "${rc}" "${value}" "$(cat "${stderr_file}")" "${secret_id}" "${project}" "${context}"
}

# source-safe: main() runs only when executed, not sourced (lets a test
# script source this file and call secret_or_fail() directly).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  main "$@"
fi
