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

# setup.sh — configure npm trusted publishing (OIDC) for every publishable
# package in this repo, in one pass.
#
# WHY A TARGET AND NOT THE WEBSITE. The npm UI configures trusted publishing per
# PACKAGE, and it re-challenges 2FA on page NAVIGATION, not just on submit --
# measured 2026-08-21: opening a second package's settings page immediately
# raised a fresh security-key prompt. At 31 library packages that is ~62 hardware
# key touches with a human present for all of them.
#
# `npm trust` does the same thing over the registry API, and npm's own guidance
# is that only the FIRST request needs 2FA: the challenge offers "skip
# two-factor authentication for the next 5 minutes", which comfortably covers
# the whole sweep (31 packages at a 2s delay is roughly a minute).
#
# So: ONE key touch instead of sixty-two.
#
# Usage:
#   bazel run //tools/npm-trusted-publisher:setup            # configure what is missing
#   bazel run //tools/npm-trusted-publisher:setup -- --dry-run
#
# You must be logged in FIRST (`npm login`); this tool never handles credentials.
# Env: NPM (default npm), DELAY_SECONDS (default 2), WORKFLOW_FILE (release.yml)
# Exit: 0 all configured · 1 one or more failed · 2 setup/precondition error
set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
NPM="${NPM:-npm}"
DELAY_SECONDS="${DELAY_SECONDS:-2}"
WORKFLOW_FILE="${WORKFLOW_FILE:-release.yml}"
DRY_RUN=""
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

command -v "$NPM" >/dev/null 2>&1 || {
    echo "npm-trusted-publisher: npm not on PATH" >&2
    exit 2
}
# `npm trust` is recent; on an npm without it every call would fail one by one
# with an unhelpful usage error. Check once, up front.
if ! "$NPM" trust --help >/dev/null 2>&1; then
    echo "npm-trusted-publisher: this npm has no \`trust\` subcommand -- upgrade npm" >&2
    exit 2
fi
# Fail on the PRECONDITION, not 31 times on its symptom. Without a CLI session
# every call returns E401 "You must be logged in to publish packages", which
# reads like a permissions problem rather than a missing login.
if ! "$NPM" whoami >/dev/null 2>&1; then
    echo "npm-trusted-publisher: the npm CLI is not logged in." >&2
    echo "  Run: npm login" >&2
    echo "  (being signed in to npmjs.com in a browser is NOT the same session)" >&2
    exit 2
fi
echo "npm-trusted-publisher: authenticated as $("$NPM" whoami 2>/dev/null)"

# Which mirror repository publishes each package. The repo registered with npm
# must be the MIRROR, because the workflow that actually runs `npm publish` is
# the mirror's exported copy of release.yml -- registering vitruvian-core would
# look right and never match.
mirror_for() {
    case "$1" in
        pulumi/library/ts/packages/*) echo "VitruvianSoftware/pulumi-library" ;;
        mcp-slack/*) echo "VitruvianSoftware/mcp-slack" ;;
        *) echo "" ;;
    esac
}

manifests="$(find pulumi/library/ts/packages mcp-slack -maxdepth 2 -name package.json \
    -not -path '*/node_modules/*' 2>/dev/null | sort)"
[ -n "$manifests" ] || {
    echo "npm-trusted-publisher: found no package manifests -- the layout moved" >&2
    exit 2
}

configured=0
skipped=0
failed=0
while IFS= read -r mf; do
    [ -n "$mf" ] || continue
    read -r name private <<EOF2
$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("name",""), str(bool(d.get("private",False))).lower())
' "$mf")
EOF2
    [ -n "$name" ] && [ "$private" = "false" ] || continue
    repo="$(mirror_for "$mf")"
    if [ -z "$repo" ]; then
        echo "  ?? $name -- no mirror mapping for $mf; skipping" >&2
        failed=$((failed + 1))
        continue
    fi

    # Already configured? The registry allows only ONE configuration per
    # package and errors on a duplicate, so re-running must be safe.
    if "$NPM" trust list "$name" 2>/dev/null | grep -q "$WORKFLOW_FILE"; then
        echo "  ok $name (already configured)"
        skipped=$((skipped + 1))
        continue
    fi

    if [ -n "$DRY_RUN" ]; then
        echo "  DRY_RUN $name -> $repo $WORKFLOW_FILE"
        configured=$((configured + 1))
        continue
    fi

    if "$NPM" trust github "$name" --repo "$repo" --file "$WORKFLOW_FILE" \
        --allow-publish --yes >/dev/null 2>&1; then
        echo "  + $name -> $repo $WORKFLOW_FILE"
        configured=$((configured + 1))
    else
        echo "  ✗ $name -- npm trust github failed" >&2
        failed=$((failed + 1))
    fi
    sleep "$DELAY_SECONDS"
done <<EOF3
$manifests
EOF3

echo "npm-trusted-publisher: ${configured} configured, ${skipped} already set, ${failed} failed."
if [ "$failed" -gt 0 ]; then
    echo "  Re-run after fixing; already-configured packages are skipped, so this is safe to repeat." >&2
    exit 1
fi
echo "  Verify with: bazel run //tools/npm-publish-audit:check"
