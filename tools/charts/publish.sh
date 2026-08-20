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

# publish.sh — package every co-located Helm chart (**/deploy/chart) and push
# it to GHCR as an OCI artifact (oci://ghcr.io/vitruviansoftware/charts/<name>).
# Versions come from each Chart.yaml `version`.
#
# WHY THIS IS A FILE AND NOT A `run:` BLOCK. It was 45 inline lines in
# charts-publish.yml, which meant the charts had NO Bazel target of any kind —
# and the delivery orchestrator's contract (spec §4.1) is that CI and the
# break-glass runbook execute the SAME target, proved by
# //tools/conformance:check resolving every delivery() unit's `run` label.
# There was nothing to point at. Now there is:
#
#   bash tools/charts/publish.sh        # what both workflows run
#   bazel run //tools/charts:publish    # the break-glass entry point
#
# Environment (all optional; absent means "publish everything"):
#   BEFORE_REV          the pre-push tip, for per-chart scoping
#   FORCED_PUSH         "true" ⇒ the diff base is untrustworthy
#   GITHUB_EVENT_NAME   "workflow_dispatch" ⇒ publish everything
#
# FAIL-OPEN, deliberately: any uncertainty publishes ALL charts. Re-pushing an
# unchanged chart version is a harmless overwrite, while missing a changed one
# leaves ArgoCD pulling a stale chart — the same asymmetry the deploy gate
# encodes (tools/ci/deploy-affected.sh).
set -euo pipefail

# Run from the REPO ROOT whichever way we were started. Under `bazel run` the
# cwd is the runfiles tree, where the `find . -path '*/deploy/chart/Chart.yaml'`
# below would match nothing and the break-glass path would cheerfully report
# "No charts (re)published this run" — a green no-op, the worst possible
# outcome for a break-glass tool. BUILD_WORKSPACE_DIRECTORY is bazel's pointer
# back to the real tree; the git fallback covers a direct `bash` invocation from
# anywhere, and CI (which runs this from the root already) is unaffected.
cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

ORG=vitruviansoftware
mkdir -p /tmp/charts

# Scope (#498): on push, publish only charts whose dir changed.
# Fail-open to ALL charts on dispatch, forced push, or an
# unresolvable diff base (zero SHA on ref creation).
publish_all=0
changed=""
if [ "${GITHUB_EVENT_NAME:-}" = "workflow_dispatch" ]; then
  publish_all=1
  echo "workflow_dispatch -> publishing all charts"
elif [ "${FORCED_PUSH:-false}" = "true" ] \
  || [ -z "${BEFORE_REV:-}" ] \
  || ! git rev-parse --verify --quiet "${BEFORE_REV}^{commit}" >/dev/null; then
  publish_all=1
  echo "untrustworthy diff base -> publishing all charts (fail-open)"
else
  changed="$(git diff --name-only "${BEFORE_REV}" HEAD -- || true)"
fi

found=0
while IFS= read -r chart; do
  dir="$(dirname "$chart")"
  reldir="${dir#./}"
  # Herestring, NOT `printf ... | grep -q`: under `set -o pipefail` grep -q
  # exits on its first match, so a push whose changed-path list exceeds the
  # 64 KiB pipe buffer makes the still-writing printf take SIGPIPE and the
  # pipeline report 141 -- inverting `! ...` and skipping a chart that DID
  # change.
  if [ "$publish_all" != 1 ] \
     && ! grep -q "^${reldir}/" <<<"$changed"; then
    echo "skipping ${reldir} (unchanged in this push)"
    continue
  fi
  name="$(awk -F': ' '/^name:/{print $2; exit}' "$chart")"
  echo "::group::Packaging ${name} from ${dir}"
  helm package "$dir" -d /tmp/charts
  helm push /tmp/charts/"${name}"-*.tgz "oci://ghcr.io/${ORG}/charts"
  echo "::endgroup::"
  found=1
done < <(find . -path '*/deploy/chart/Chart.yaml' -not -path './bazel-*/*')
[ "$found" = 1 ] || echo "No charts (re)published this run"
