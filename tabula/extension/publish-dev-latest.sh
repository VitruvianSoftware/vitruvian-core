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

# publish-dev-latest.sh — build, stamp and publish the rolling "dev-latest"
# extension bundle: the fixed prerelease tag `tabula-extension-dev-latest`
# whose two assets are overwritten on every main commit that touches the
# extension. Consumed by `tabcli ext update` and the in-extension update banner
# (#45). Release-please owns tabula-extension-v* tags; this fixed tag never
# collides with them.
#
# WHY THIS IS A FILE AND NOT A `run:` BLOCK (delivery-orchestrator Phase 3):
# this was the LAST delivery unit whose `run` target was not runnable — its
# publish lived as three inline workflow steps and its declaration could only
# name //tabula/extension:chrome_zip, a genrule. The spec's contract is that CI
# and the break-glass runbook execute the SAME thing (§4.1); now they do:
#
#   bash tabula/extension/publish-dev-latest.sh        # what CI runs
#   bazel run //tabula/extension:publish-dev-latest    # break-glass, Actions down
#
# The build identity is injected POST Bazel build on purpose: the webpack
# action must stay hermetic (tabula/extension/webpack.config.js), so the bundle
# ships a placeholder build_info.json that this script replaces with the real
# commit.
#
# Environment (all optional — CI supplies the first two, a laptop needs none):
#   BUILDBUDDY_API_KEY  cache-only remote-cache auth; absent ⇒ a local build
#   GH_TOKEN            token for `gh release`; absent ⇒ gh's own auth
#   GITHUB_SHA          the commit to stamp; absent ⇒ HEAD
#   RUNNER_TEMP         scratch dir; absent ⇒ a fresh mktemp -d
#   TAG                 the rolling prerelease tag
set -euo pipefail

# Run from the repo root whichever way we were started: under `bazel run` the
# cwd is the runfiles tree, where `bazel-bin/...` does not resolve.
cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT="$(pwd)"

TAG="${TAG:-tabula-extension-dev-latest}"
WORK="${RUNNER_TEMP:-$(mktemp -d)}"
SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"

# Cache-only (see --config=remotecache-ci in tools/remote.bazelrc): reuse the
# chrome_zip build CI already cached; outputs stay local for the cp below. With
# no key (a laptop) this degrades to a plain local build rather than failing —
# `--remote_header=x-buildbuddy-api-key=` with an empty value is an auth error,
# not a cache miss.
if [ -n "${BUILDBUDDY_API_KEY:-}" ]; then
	bazel build --config=remotecache-ci --remote_header=x-buildbuddy-api-key="$BUILDBUDDY_API_KEY" //tabula/extension:chrome_zip
else
	echo "publish-dev-latest: no BUILDBUDDY_API_KEY — building locally"
	bazel build //tabula/extension:chrome_zip
fi

cp bazel-bin/tabula/extension/tabula-extension-chrome.zip \
	"$WORK/tabula-extension-chrome.zip"
chmod +w "$WORK/tabula-extension-chrome.zip"
VERSION="$(node -p "require('./tabula/extension/package.json').version")"
cd "$WORK"
printf '{"commit":"%s","builtAt":"%s","version":"%s"}\n' \
	"$SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VERSION" \
	>build_info.json
# zip updates the existing (placeholder) entry in place
zip -q tabula-extension-chrome.zip build_info.json

# Back to the repo root: `gh release` resolves the target repository from the
# git remote of its cwd, and $WORK is not a git repo — from there every gh call
# dies with "failed to run git: not a git repository" (the failure CI hit on
# the first orchestrated run of this unit; the legacy stamp step's cd could not
# leak into the publish step, so this never bit as separate workflow steps).
cd "$ROOT"

gh release view "$TAG" >/dev/null 2>&1 ||
	gh release create "$TAG" --prerelease \
		--title "tabula-extension dev-latest (rolling)" \
		--notes "Rolling dev bundle; assets overwritten on every main commit."
# build_info.json is also published standalone so tooling can check the latest
# identity without downloading the bundle (M2 pinning).
gh release upload "$TAG" \
	"$WORK/tabula-extension-chrome.zip" \
	"$WORK/build_info.json" \
	--clobber
gh release edit "$TAG" \
	--notes "commit: ${SHA} — built $(date -u +%Y-%m-%dT%H:%M:%SZ)"
