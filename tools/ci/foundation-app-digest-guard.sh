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
# foundation-app-digest-guard.sh — export per-app image digests for the Pulumi
# program, and FAIL CLOSED if any workload enabled in Pulumi.production.yaml
# has no digest supplied. Deduped out of foundation-app-deploy.yaml's inline
# copy for standalone testability.
#
# WHY: an enabled workload with no digest renders a Service with an EMPTY
# image. On a leaf that has ADOPTED a live service that is not a no-op, the
# apply STRIPS the image off something that is serving traffic. The caller's
# own preview step catches this before it reaches an apply; this is the
# belt-and-suspenders enforcement at apply time, since the preview is a
# separate job a caller could (in principle) bypass.
#
# Usage: foundation-app-digest-guard.sh <app_image_digests> <pulumi-file>
#   app_image_digests  "<app>=<digest>,<app>=<digest>,..." (may be empty)
#   pulumi-file         path to the leaf's Pulumi.production.yaml
#
# Side effects (main() only): writes "<APP>_IMAGE_DIGEST=<digest>" to
# $GITHUB_ENV for every supplied pair, and exits 1 with an ::error:: if any
# enabled workload has no digest.

set -euo pipefail

# missing_digest_apps(pulumi_file_contents, app_image_digests) -- pure
# function, no filesystem/env access, so it is unit-testable standalone.
# Prints the space-separated list of app names that are `_workload_enabled:
# "true"` in pulumi_file_contents but have no matching entry in
# app_image_digests.
missing_digest_apps() {
  local pulumi_file_contents="$1" app_image_digests="$2"
  local missing="" app
  while IFS= read -r line; do
    app="$(printf '%s' "${line}" | sed -E 's/.*:([a-z0-9-]+)_workload_enabled:.*/\1/')"
    [ -n "${app}" ] || continue
    case ",${app_image_digests}," in
      *",${app}="*) ;;
      *) missing="${missing} ${app}" ;;
    esac
  done < <(printf '%s' "${pulumi_file_contents}" | grep -E '_workload_enabled: *"true"' || true)
  printf '%s' "${missing# }"
}

main() {
  local app_image_digests="${1:-}" pulumi_file="${2:?pulumi file required}"

  # Export each "<app>=<digest>" as <APP>_IMAGE_DIGEST for the program.
  if [ -n "${app_image_digests}" ]; then
    local pairs pair app digest var
    IFS=',' read -ra pairs <<< "${app_image_digests}"
    for pair in "${pairs[@]}"; do
      app="${pair%%=*}"; digest="${pair#*=}"
      [ -n "${app}" ] && [ -n "${digest}" ] || continue
      var="$(printf '%s' "${app}" | tr '[:lower:]-' '[:upper:]_')_IMAGE_DIGEST"
      echo "${var}=${digest}" >> "${GITHUB_ENV}"
      echo "exporting ${var}"
    done
  fi

  local missing
  missing="$(missing_digest_apps "$(cat "${pulumi_file}")" "${app_image_digests}")"
  if [ -n "${missing}" ]; then
    echo "::error::workload enabled but no image digest supplied for:${missing} — deploying would render an EMPTY image and strip it off the live service. Pass app_image_digests as '<app>=<ref>'."
    exit 1
  fi
  echo "digest guard: OK"
}

# source-safe: main() runs only when executed, not sourced (lets a test
# script source this file and call missing_digest_apps() directly).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  main "$@"
fi
