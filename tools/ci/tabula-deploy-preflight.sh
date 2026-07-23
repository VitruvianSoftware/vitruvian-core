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

# tabula-deploy-preflight.sh — decide whether an env's deploy can be SKIPPED
# because the live service already serves the exact desired state.
#
# tabula's revision name encodes image digest + config hash (see
# tabula/infra/app/revision). So the desired revision name computed from HEAD's
# config + the built digest, compared to the live serving revision name, is a
# content-address equality check: EQUAL means the running service already IS
# what a deploy would produce, so the migrate + blue-green + smoke are all
# redundant. This replaces the coarse "any change to the app dir or the deploy
# workflow file redeploys" trigger, which redeployed on smoke-test-only edits.
#
# SAFE BY CONSTRUCTION — FAIL OPEN. `unchanged` is true ONLY when the desired
# name was computed successfully AND the live name was read successfully AND
# they are equal. EVERY other path (revname error, gcloud error, gcloud's
# exit-0-with-ERROR reauth failure, an empty result, a first-ever deploy with no
# live revision) yields unchanged=false → deploy. A bug here can therefore only
# ever reproduce today's redundant deploy, NEVER cause a missed one.
#
# Environment:
#   DEPLOY_ENV        development | nonproduction | production
#   GCP_PROJECT_ID    the env's oss-floating project
#   GCP_REGION        default us-central1
#   SERVICE_NAME      base name; '-<env>' is appended (e.g. tabula-api)
#   IMAGE_DIGEST      the built image ref <image>@sha256:<hex>
#   PULUMI_DIR        dir holding the app stack + cmd/revname (tabula/infra/app)
#   CONFIG_FILE       Pulumi.<env>.yaml basename within PULUMI_DIR
#   GCLOUD_BIN, REVNAME  test hooks (defaults: gcloud, `go run ./cmd/revname`)
#
# Output: `unchanged=true|false` to $GITHUB_OUTPUT (and echoed).

set -uo pipefail

GCP_REGION="${GCP_REGION:-us-central1}"
GCLOUD_BIN="${GCLOUD_BIN:-gcloud}"
# The desired-name computer. Default reuses the app stack's own revision package
# (DRY — a bash reimplementation of the hash could drift and wrongly skip).
REVNAME="${REVNAME:-go run ./cmd/revname}"

deploy() { # <reason> — fail open: deploy.
  echo "preflight[${DEPLOY_ENV:-?}]: unchanged=false — $1"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "unchanged=false" >> "${GITHUB_OUTPUT}"
  exit 0
}
skip() {
  echo "preflight[${DEPLOY_ENV}]: unchanged=true — live already serves the desired revision (${1})"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "unchanged=true" >> "${GITHUB_OUTPUT}"
  exit 0
}

: "${DEPLOY_ENV:?}" "${GCP_PROJECT_ID:?}" "${SERVICE_NAME:?}" "${IMAGE_DIGEST:?}" "${PULUMI_DIR:?}" "${CONFIG_FILE:?}"

cd "${PULUMI_DIR}" 2>/dev/null || deploy "PULUMI_DIR ${PULUMI_DIR} not found"

# --- desired: what a deploy WOULD produce. Any failure -> deploy. ------------
err="$(mktemp)"
desired="$(GOWORK=off ${REVNAME} --config "${CONFIG_FILE}" --digest "${IMAGE_DIGEST}" 2>"${err}")"
rc=$?
if [ "${rc}" -ne 0 ] || [ -z "${desired}" ]; then
  echo "preflight[${DEPLOY_ENV}]: could not compute the desired revision name:" >&2
  sed 's/^/  /' "${err}" >&2
  rm -f "${err}"
  deploy "desired-name computation failed (rc=${rc})"
fi
rm -f "${err}"

# --- live: what is serving now. Any failure/empty -> deploy. -----------------
gerr="$(mktemp)"
live="$("${GCLOUD_BIN}" run services describe "${SERVICE_NAME}-${DEPLOY_ENV}" \
  --project "${GCP_PROJECT_ID}" --region "${GCP_REGION}" \
  --format='value(status.traffic[0].revisionName)' 2>"${gerr}")"
grc=$?
# gcloud can exit 0 while printing "ERROR: ... Reauthentication failed" — so an
# ERROR on stderr is a failure even when the code is 0. Fail open either way.
if [ "${grc}" -ne 0 ] || grep -q '^ERROR:' "${gerr}" 2>/dev/null; then
  echo "preflight[${DEPLOY_ENV}]: could not read the live revision:" >&2
  sed 's/^/  /' "${gerr}" >&2
  rm -f "${gerr}"
  deploy "live-revision read failed (rc=${grc})"
fi
rm -f "${gerr}"

if [ -z "${live}" ]; then
  deploy "no live revision (first-ever deploy for ${SERVICE_NAME}-${DEPLOY_ENV})"
fi

echo "preflight[${DEPLOY_ENV}]: desired=${desired} live=${live}"
if [ "${desired}" = "${live}" ]; then
  skip "${desired}"
fi
deploy "desired (${desired}) != live (${live})"
