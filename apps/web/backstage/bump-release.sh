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

# Move Backstage to one coherent upstream release.
#
# WHY. Backstage is ~200 packages released together; each release publishes a
# manifest of the exact versions that were built and tested as a set. Upstream's
# `backstage-cli versions:bump` moves every @backstage/* dependency to that set
# for this reason. Bumping packages one at a time (as Dependabot did here) ends
# in a mix of releases: on 2026-10-07 a lone backend-defaults bump needed a
# newer backend-plugin-api than the rest of the tree had, and the backend
# crashed at boot (#2854 -> #2865). Before this script the tree was 59 packages
# from 1.53, 45 from 1.54 and 38 from 1.55.
#
# `versions:bump` itself assumes Yarn; this repo is a pnpm workspace. This does
# the same thing: set every @backstage/* dependency to the manifest's version
# (keeping each range's ^ or ~), record the release in backstage.json, and
# refresh both lockfiles.
#
# Usage:  apps/web/backstage/bump-release.sh <release>     e.g. 1.55.3
#         apps/web/backstage/bump-release.sh main          latest monthly release
#
# Then read the release notes for BREAKING entries, run the backend and app
# tests, and let the backstage-image workflow boot the image on the PR (its
# smoke test is what catches a backend that cannot start).
set -euo pipefail

release="${1:?usage: bump-release.sh <release | main>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git -C "${here}" rev-parse --show-toplevel)"

if [ "${release}" = "main" ]; then
	url="https://versions.backstage.io/v1/tags/main/manifest.json"
else
	url="https://versions.backstage.io/v1/releases/${release}/manifest.json"
fi
manifest="$(curl -fsS "${url}")" || {
	echo "bump-release: no manifest at ${url}" >&2
	exit 1
}
version="$(jq -r '.releaseVersion' <<<"${manifest}")"
echo "bump-release: moving to Backstage ${version}"

# The snapshot the release test reads (name -> version, sorted for clean diffs).
jq '{releaseVersion, packages: ([.packages[] | {key: .name, value: .version}] | sort_by(.key) | from_entries)}' \
	<<<"${manifest}" >"${here}/release-manifest.json"
printf '{\n  "version": "%s"\n}\n' "${version}" >"${here}/backstage.json"

for pkg in "${here}"/packages/*/package.json; do
	tmp="$(mktemp)"
	jq --slurpfile m "${here}/release-manifest.json" '
    def bump: with_entries(
      if (.key | startswith("@backstage/")) and ($m[0].packages[.key] != null) and (.value | test("^[~^]?[0-9]"))
      then .value = ((.value | capture("^(?<p>[~^]?)").p) + $m[0].packages[.key])
      else . end);
    if .dependencies then .dependencies |= bump else . end
    | if .devDependencies then .devDependencies |= bump else . end' "${pkg}" >"${tmp}"
	mv "${tmp}" "${pkg}"
done

cd "${root}"
bazel run -- @pnpm//:pnpm install --dir "${root}" --lockfile-only
bazel mod deps --lockfile_mode=update
bazel run //tools/format -- "${here}"/packages/*/package.json "${here}/release-manifest.json" "${here}/backstage.json"
echo "bump-release: done. Now check the release notes and run the tests:"
echo "  https://github.com/backstage/backstage/blob/master/docs/releases/v${version%.*}.0.md"
