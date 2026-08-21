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
#   bazel run //tools/npm-trusted-publisher:setup -- --no-login   # never shell out to login
#
# If the npm CLI is not logged in this runs `npm login` for you, which opens a
# browser for you to authenticate in. No credential is ever prompted for,
# handled, or stored by this script.
# Env: NPM (default npm), DELAY_SECONDS (default 2), WORKFLOW_FILE (release.yml)
# Exit: 0 all configured · 1 one or more failed · 2 setup/precondition error
set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
NPM="${NPM:-npm}"
DELAY_SECONDS="${DELAY_SECONDS:-2}"
WORKFLOW_FILE="${WORKFLOW_FILE:-release.yml}"
# 180s was not enough for a browser + security-key round trip; that timeout
# is the bug this tool shipped with. Wait far longer than the flow needs.
OTP_WAIT_SECONDS="${OTP_WAIT_SECONDS:-900}"
OTP_POLL_SECONDS="${OTP_POLL_SECONDS:-5}"
DRY_RUN=""
NO_LOGIN=""
for _a in "$@"; do
    case "$_a" in
        --dry-run) DRY_RUN=1 ;;
        --no-login) NO_LOGIN=1 ;;
        *) echo "npm-trusted-publisher: unknown flag: $_a" >&2; exit 2 ;;
    esac
done

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
# Handle the PRECONDITION here rather than failing 31 times on its symptom.
# Without a CLI session every call returns E401 "You must be logged in to
# publish packages", which reads like a permissions problem rather than a
# missing login -- and being signed in to npmjs.com in a browser is a DIFFERENT
# session from the CLI's.
#
# We run `npm login` for you rather than telling you to run it: one command
# should do the job, the same way //tools/sync-env-secrets:unlock prompts once
# instead of making you export a session by hand. `npm login` defaults to the
# WEB auth type, so it opens a browser and you authenticate there -- this script
# never sees, prompts for, or stores a credential.
ensure_login() {
    "$NPM" whoami >/dev/null 2>&1 && return 0

    if [ -n "$NO_LOGIN" ]; then
        echo "npm-trusted-publisher: not logged in and --no-login was passed." >&2
        echo "  Run: npm login" >&2
        exit 2
    fi
    # `npm login` is INTERACTIVE. With no terminal it would hang forever rather
    # than fail, which is the worse outcome in CI or a nested shell -- so refuse
    # explicitly instead, the same guard //tools/gomod uses for its prompt.
    # ACTUALLY OPEN IT. `[ -r /dev/tty ]` reports readable in contexts where the
    # open then fails with "Device not configured" (verified in a Bazel test
    # sandbox), so the cheap test passes and the guard it protects never fires.
    #
    # NPM_TP_TTY_OK is a test seam: the Bazel sandbox cannot allocate a pty, so
    # the tests that must exercise the WITH-terminal branches assert one rather
    # than provide one. Nothing in normal use sets it.
    if [ -z "${NPM_TP_TTY_OK:-}" ] && ! (: </dev/tty) 2>/dev/null; then
        echo "npm-trusted-publisher: the npm CLI is not logged in, and there is no" >&2
        echo "  terminal to authenticate on. Run \`npm login\` first, then re-run." >&2
        exit 2
    fi

    echo "npm-trusted-publisher: the npm CLI is not logged in -- starting \`npm login\`."
    echo "  It opens your browser; authenticate there. Nothing is typed or stored here."
    # Inherit stdio rather than forcing /dev/tty: npm login prints a URL and
    # waits, and forcing the tty breaks anywhere the terminal is indirect.
    if ! "$NPM" login; then
        echo "npm-trusted-publisher: \`npm login\` did not complete." >&2
        exit 2
    fi
    # Verify rather than assume: `npm login` can exit 0 on a flow the registry
    # did not actually accept, and proceeding would fail 31 times downstream.
    if ! "$NPM" whoami >/dev/null 2>&1; then
        echo "npm-trusted-publisher: still not authenticated after \`npm login\`." >&2
        exit 2
    fi
}
ensure_login
echo "npm-trusted-publisher: authenticated as $("$NPM" whoami 2>/dev/null)"

# Being logged in is NOT enough: `npm trust github` is a 2FA-protected WRITE and
# returns EOTP until a one-time authentication is completed. npm signals that by
# PRINTING A URL to open --
#
#   npm error code EOTP
#   npm error Open this URL in your browser to authenticate:
#   npm error   https://www.npmjs.com/auth/cli/<id>
#
# so any call whose output is swallowed leaves the user with a silent failure
# and no way to proceed.
#
# Gate on the WRITE itself, and wait GENEROUSLY. EVERY `npm trust` call --
# `list` included -- is 2FA-protected, so a separate probe buys nothing the real
# call does not, and it introduced the failure that actually happened: the probe
# polled for 180s, gave up, and exited 2 while the user was still working
# through the browser + security-key flow. They finished moments later, leaving
# a LIVE session and ZERO packages configured -- reported as a 2FA expiry, which
# sent the next investigation at the wrong thing entirely. Surface npm's own URL
# and retry the SAME call until that authentication lands.
trust_github() {
    local name="$1" repo="$2" waited=0 shown=""
    while :; do
        _out="$("$NPM" trust github "$name" --repo "$repo" --file "$WORKFLOW_FILE" \
            --allow-publish --yes 2>&1)" && return 0
        printf '%s' "$_out" | grep -q 'EOTP' || return 1
        [ "$waited" -lt "$OTP_WAIT_SECONDS" ] || return 1
        if [ -z "$shown" ]; then
            shown=1
            echo
            echo "npm-trusted-publisher: npm needs a one-time authentication before it"
            echo "  will accept trust changes. Open the URL below, authenticate, and"
            echo "  CHOOSE \"skip for the next 5 minutes\" -- that covers every package"
            echo "  in this run, so you only do this once."
            # Output deliberately NOT redirected: the URL is the whole point.
            printf '%s\n' "$_out"
            echo "  waiting for that authentication to complete (up to ${OTP_WAIT_SECONDS}s)..."
        fi
        sleep "$OTP_POLL_SECONDS"
        waited=$((waited + OTP_POLL_SECONDS))
    done
}

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
unpublished=0
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
    # A trusted publisher can only be attached to a package that EXISTS. For a
    # name never published, every trust call returns E404 -- and there is no way
    # out of that from here: the package needs one first publish before trusted
    # publishing can take over. Report it rather than counting it as a failure.
    if ! "$NPM" view "$name" version >/dev/null 2>&1; then
        echo "  -- $name is not on the registry yet; publish it once, then re-run"
        unpublished=$((unpublished + 1))
        continue
    fi
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

    # Capture rather than discard: a swallowed error here is unactionable, and
    # the two failures that actually occur -- an existing configuration, and an
    # expired 2FA window -- need to be told apart from each other.
    if trust_github "$name" "$repo"; then _rc=0; else _rc=$?; fi
    if [ "${_rc:-0}" -eq 0 ]; then
        echo "  + $name -> $repo $WORKFLOW_FILE"
        configured=$((configured + 1))
    elif printf '%s' "$_out" | grep -qiE 'already (exists|configured)|duplicate'; then
        echo "  ok $name (already configured)"
        skipped=$((skipped + 1))
    elif printf '%s' "$_out" | grep -q 'EOTP'; then
        echo "  ✗ $name -- gave up waiting for two-factor authentication." >&2
        echo "    Complete the browser authentication, then re-run; configured" >&2
        echo "    packages are skipped, so it resumes where it stopped." >&2
        failed=$((failed + 1))
        break
    else
        echo "  ✗ $name -- $(printf '%s' "$_out" | grep -i 'npm error' | head -2 | tr '\n' ' ')" >&2
        failed=$((failed + 1))
    fi
    sleep "$DELAY_SECONDS"
done <<EOF3
$manifests
EOF3

echo "npm-trusted-publisher: ${configured} configured, ${skipped} already set, ${failed} failed, ${unpublished} not yet on the registry."
if [ "$unpublished" -gt 0 ]; then
    echo "  The ${unpublished} unpublished package(s) cannot be configured until they exist on npm." >&2
    echo "  Trusted publishing attaches to a PACKAGE, so each needs one first publish." >&2
fi
if [ "$failed" -gt 0 ]; then
    echo "  Re-run after fixing; already-configured packages are skipped, so this is safe to repeat." >&2
    exit 1
fi
echo "  Verify with: bazel run //tools/npm-publish-audit:check"
