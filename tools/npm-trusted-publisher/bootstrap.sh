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
# it fails with ENEEDAUTH. Exactly one manual publish per package breaks that
# cycle. Afterwards OIDC governs it like every other package.
#
# WHY IT PUBLISHES FROM THE MIRROR, NOT FROM HERE. In this monorepo a package's
# dependencies are written `"@pulumi/gcp": "catalog:"` -- the pnpm catalog
# reference from //pnpm-workspace.yaml. `catalog:` is a pnpm-only protocol, so
# publishing this tree would upload a package that NO consumer can install
# (`EUNSUPPORTEDPROTOCOL`), and npm only allows unpublish within 72h. Copybara's
# export_transformations rewrite `catalog:` back to concrete ranges precisely so
# the mirror builds standalone, which is why the release workflow lives there.
# The mirror is the only correct publish origin; this clones it and publishes
# from that tree.
#
# The first version of this script ran `npm install` in the monorepo's ts/
# directory, copied from the mirror's workflow. It failed loudly on `catalog:`
# rather than publishing something broken -- but it was one working build away
# from doing real damage, so the manifest guard below is not optional.
#
# Order is load-bearing: BUILD, then publish. `main` is dist/index.js, so
# publishing before the build ships a package whose entry point does not exist,
# and npm accepts it without complaint.
#
# Usage:
#   bazel run //tools/npm-trusted-publisher:bootstrap
#   bazel run //tools/npm-trusted-publisher:bootstrap -- --dry-run
#   bazel run //tools/npm-trusted-publisher:bootstrap -- --no-login
#
# Env: NPM, MIRROR_REPO (default VitruvianSoftware/pulumi-library), MIRROR_DIR
#      (use an existing checkout instead of cloning), SETUP_SH
# Exit: 0 nothing to do or all published · 1 a publish failed · 2 precondition
set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT="$PWD"
NPM="${NPM:-npm}"
MIRROR_REPO="${MIRROR_REPO:-VitruvianSoftware/pulumi-library}"
# This account is `two-factor auth: auth-and-writes`, so `npm publish` is itself
# 2FA-protected. Budget the same generous window as the trust sweep (#1879).
OTP_WAIT_SECONDS="${OTP_WAIT_SECONDS:-900}"
OTP_POLL_SECONDS="${OTP_POLL_SECONDS:-5}"
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
    "$NPM" whoami >/dev/null 2>&1 || {
        echo "  npm login reported success but no session exists." >&2
        exit 2
    }
}

# Refuse to publish a manifest whose dependencies cannot be resolved by a
# consumer. `catalog:` and `workspace:` are pnpm-internal; `file:`/`link:` point
# at paths that will not exist for anyone else. If this fires against the mirror
# it means copybara's rewrite regressed -- fix the export, do not bypass this.
unresolvable_deps() { # <manifest> -> prints offending "name: spec" lines
    python3 - "$1" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
bad = []
for field in ("dependencies", "peerDependencies", "optionalDependencies"):
    for name, spec in (d.get(field) or {}).items():
        if isinstance(spec, str) and spec.split(":")[0] in ("catalog", "workspace", "file", "link"):
            bad.append("%s -> %s (%s)" % (name, spec, field))
print("\n".join(bad))
PYEOF
}

# `npm publish` on an `auth-and-writes` account returns EOTP with an auth URL,
# exactly like `npm trust`. Failing per package here would abandon the run while
# the user is still completing the browser flow -- the precise defect that made
# the setup target configure nothing (#1879). Retry the SAME call instead, and
# never swallow npm's output: the URL is the only way forward.
publish_with_otp_wait() { # <dir> -> 0 published
    local dir="$1" waited=0 shown=""
    while :; do
        if _out="$( ( cd "$dir" && "$NPM" publish --access public ) 2>&1 )"; then
            printf '%s\n' "$_out"
            return 0
        fi
        printf '%s' "$_out" | grep -q 'EOTP' || { printf '%s\n' "$_out" >&2; return 1; }
        [ "$waited" -lt "$OTP_WAIT_SECONDS" ] || { printf '%s\n' "$_out" >&2; return 1; }
        if [ -z "$shown" ]; then
            shown=1
            echo
            echo "npm-trusted-publisher-bootstrap: npm needs a one-time authentication"
            echo "  before it will accept a publish. Open the URL below, authenticate,"
            echo "  and CHOOSE \"skip for the next 5 minutes\" -- that covers every"
            echo "  package in this run."
            printf '%s\n' "$_out"
            echo "  waiting for that authentication to complete (up to ${OTP_WAIT_SECONDS}s)..."
        fi
        sleep "$OTP_POLL_SECONDS"
        waited=$((waited + OTP_POLL_SECONDS))
    done
}

mirror="${MIRROR_DIR:-}"
cleanup_mirror=""
if [ -z "$mirror" ]; then
    mirror="$(mktemp -d)"
    cleanup_mirror="$mirror"
    echo "npm-trusted-publisher-bootstrap: cloning $MIRROR_REPO (the publish origin)..."
    git clone --depth 1 --quiet "https://github.com/${MIRROR_REPO}.git" "$mirror" || {
        echo "  could not clone $MIRROR_REPO" >&2; exit 2; }
fi
trap '[ -n "$cleanup_mirror" ] && rm -rf "$cleanup_mirror"' EXIT

[ -d "$mirror/ts/packages" ] || {
    echo "npm-trusted-publisher-bootstrap: $mirror/ts/packages not found -- the" >&2
    echo "  mirror layout moved; this script assumes ts/packages/*." >&2
    exit 2
}

missing=""
for mf in $(find "$mirror/ts/packages" -maxdepth 2 -name package.json -not -path '*/node_modules/*' 2>/dev/null | sort); do
    read -r name private <<EOF2
$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("name",""), str(bool(d.get("private",False))).lower())
' "$mf")
EOF2
    [ -n "$name" ] && [ "$private" = "false" ] || continue
    "$NPM" view "$name" version >/dev/null 2>&1 && continue
    missing="$missing $mf"
done

if [ -z "$missing" ]; then
    echo "npm-trusted-publisher-bootstrap: every publishable package is already on"
    echo "  the registry; nothing to bootstrap."
    exit 0
fi

echo "npm-trusted-publisher-bootstrap: these packages have never been published:"
bad_any=""
for mf in $missing; do
    name="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$mf")"
    bad="$(unresolvable_deps "$mf")"
    if [ -n "$bad" ]; then
        echo "  ✗ $name — dependencies a consumer cannot resolve:"
        printf '%s\n' "$bad" | sed 's/^/      /'
        bad_any=1
    else
        echo "  $name"
    fi
done
[ -z "$bad_any" ] || {
    echo "npm-trusted-publisher-bootstrap: refusing to publish. These specs are" >&2
    echo "  pnpm-internal or path-based and would be unusable for every consumer." >&2
    echo "  Copybara rewrites them on export (_LIBRARY_CATALOG_VERSIONS in" >&2
    echo "  tools/copybara/copy.bara.sky); if they survived, that rewrite regressed." >&2
    exit 2
}

if [ -n "$DRY_RUN" ]; then
    echo "  DRY_RUN: no build, no publish, no trust configuration."
    exit 0
fi

ensure_login
echo "npm-trusted-publisher-bootstrap: authenticated as $("$NPM" whoami 2>/dev/null)"

echo "npm-trusted-publisher-bootstrap: building the mirror's ts workspace..."
( cd "$mirror/ts" && "$NPM" install && "$NPM" run build ) || {
    echo "npm-trusted-publisher-bootstrap: the workspace build failed; not publishing." >&2
    exit 2
}

published=0
failed=0
for mf in $missing; do
    dir="$(dirname "$mf")"
    name="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$mf")"
    if publish_with_otp_wait "$dir"; then
        echo "  + published $name"
        published=$((published + 1))
    else
        echo "  ✗ $name failed to publish" >&2
        failed=$((failed + 1))
    fi
done

echo "npm-trusted-publisher-bootstrap: ${published} published, ${failed} failed."
[ "$failed" -eq 0 ] || exit 1

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
