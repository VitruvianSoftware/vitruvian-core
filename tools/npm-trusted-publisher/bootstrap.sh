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

# bootstrap.sh — give a never-published package its FIRST publish, then hand off
# to setup.sh so trusted publishing governs it from then on.
#
# WHY THIS EXISTS. Trusted publishing attaches to a package that EXISTS on the
# registry. A name that has never been published cannot be configured, and the
# release workflow cannot create it either: it authenticates by OIDC alone, so
# it fails with ENEEDAUTH. That is a genuine cycle, and exactly one manual
# publish per new package breaks it. Afterwards the package is governed by OIDC
# like every other one -- this is a one-time step per package, not a workflow.
#
# It matters NOW because release-please has open PRs for three such packages
# (foundation-app, -cicd, -data). Since #1861 a failed publish FAILS the run
# instead of warning, so merging them turns the mirror red until this is done.
#
# Order is load-bearing: BUILD, then publish. `main` is dist/index.js, so
# publishing before the build ships a package whose entry point does not exist,
# and npm will happily accept it.
#
# Usage:
#   bazel run //tools/npm-trusted-publisher:bootstrap
#   bazel run //tools/npm-trusted-publisher:bootstrap -- --dry-run
#   bazel run //tools/npm-trusted-publisher:bootstrap -- --no-login
#
# Env: NPM (default npm), TS_DIR (default pulumi/library/ts), SETUP_SH
# Exit: 0 nothing to do or all published · 1 a publish failed · 2 precondition
set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT="$PWD"
NPM="${NPM:-npm}"
TS_DIR="${TS_DIR:-pulumi/library/ts}"
DRY_RUN=""
NO_LOGIN=""
for _a in "$@"; do
    case "$_a" in
        --dry-run) DRY_RUN=1 ;;
        --no-login) NO_LOGIN=1 ;;
        -h|--help) sed -n '/^# Usage:/,/^# Exit:/p' "$0"; exit 0 ;;
        *) echo "npm-trusted-publisher-bootstrap: unknown argument $_a" >&2; exit 2 ;;
    esac
done

# Publishing is an ACCOUNT-level, effectively irreversible action (npm restricts
# unpublish to a 72h window). Refuse to guess at credentials: either a session
# exists, or we run npm's own browser login, or we stop.
ensure_login() {
    "$NPM" whoami >/dev/null 2>&1 && return 0
    [ -z "$NO_LOGIN" ] || {
        echo "npm-trusted-publisher-bootstrap: not logged in and --no-login given." >&2
        exit 2
    }
    if [ -z "${NPM_TP_TTY_OK:-}" ] && ! { [ -r /dev/tty ] && : >/dev/tty; } 2>/dev/null; then
        echo "npm-trusted-publisher-bootstrap: not logged in, and there is no" >&2
        echo "  terminal to authenticate on. Run this from an interactive shell." >&2
        exit 2
    fi
    echo "npm-trusted-publisher-bootstrap: not logged in; starting npm login."
    "$NPM" login || { echo "  npm login failed." >&2; exit 2; }
    # A login that exits 0 without establishing a session is a real npm
    # behaviour; re-verify rather than trusting the exit code.
    "$NPM" whoami >/dev/null 2>&1 || {
        echo "  npm login reported success but no session exists." >&2
        exit 2
    }
}

# Which publishable packages are missing from the registry?
missing=""
for mf in $(find "$TS_DIR/packages" -maxdepth 2 -name package.json -not -path '*/node_modules/*' 2>/dev/null | sort); do
    read -r name private <<EOF2
$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("name",""), str(bool(d.get("private",False))).lower())
' "$mf")
EOF2
    [ -n "$name" ] && [ "$private" = "false" ] || continue
    # Already on the registry? Then it is NOT a bootstrap case, and republishing
    # it here would bypass the OIDC path we just spent this work establishing.
    "$NPM" view "$name" version >/dev/null 2>&1 && continue
    missing="$missing $mf"
done

if [ -z "$missing" ]; then
    echo "npm-trusted-publisher-bootstrap: every publishable package is already on"
    echo "  the registry; nothing to bootstrap."
    exit 0
fi

echo "npm-trusted-publisher-bootstrap: these packages have never been published:"
for mf in $missing; do
    echo "  $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$mf")"
done

if [ -n "$DRY_RUN" ]; then
    echo "  DRY_RUN: no build, no publish, no trust configuration."
    exit 0
fi

ensure_login
echo "npm-trusted-publisher-bootstrap: authenticated as $("$NPM" whoami 2>/dev/null)"

# BUILD FIRST. `main` points at dist/index.js; publishing before the build
# produces a package with no entry point and npm accepts it without complaint.
echo "npm-trusted-publisher-bootstrap: building the ts workspace..."
( cd "$TS_DIR" && "$NPM" install && "$NPM" run build ) || {
    echo "npm-trusted-publisher-bootstrap: the workspace build failed; not publishing." >&2
    exit 2
}

published=0
failed=0
for mf in $missing; do
    dir="$(dirname "$mf")"
    name="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$mf")"
    if ( cd "$dir" && "$NPM" publish --access public ); then
        echo "  + published $name"
        published=$((published + 1))
    else
        echo "  ✗ $name failed to publish" >&2
        failed=$((failed + 1))
    fi
done

echo "npm-trusted-publisher-bootstrap: ${published} published, ${failed} failed."
[ "$failed" -eq 0 ] || exit 1

# Hand off: a freshly-published package still has no trusted publisher, so the
# NEXT release would fail exactly as before. setup.sh is idempotent, so running
# it over everything is both correct and the cheapest thing to do.
setup="${SETUP_SH:-}"
for cand in "$setup" "$(dirname "$0")/setup.sh" "$ROOT/tools/npm-trusted-publisher/setup.sh"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { setup="$cand"; break; }
done
[ -f "$setup" ] || {
    echo "npm-trusted-publisher-bootstrap: published, but setup.sh was not found;" >&2
    echo "  run //tools/npm-trusted-publisher:setup to attach trusted publishers." >&2
    exit 1
}
echo "npm-trusted-publisher-bootstrap: attaching trusted publishers..."
exec bash "$setup"
