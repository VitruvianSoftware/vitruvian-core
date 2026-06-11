#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# One-time GitHub App bootstrap via GitHub's App Manifest flow — invoked via
# `bazel run //tools/pulumi:create-app [-- <owner>]`.
#
# Run this ONCE PER ORG (e.g. your GitHub organization), NOT per repo. It creates
# a single shared least-privilege App (Administration: write + Contents: read) and
# sets ORG-LEVEL credentials that every repo in the org inherits:
#   PULUMI_APP_ID       org variable (App ID is non-sensitive)
#   APP_PRIVATE_KEY     org secret   (the App's PEM private key)
#   PULUMI_ACCESS_TOKEN org secret   (Pulumi Cloud token for state)
# The CI preview/apply workflows then mint short-lived installation tokens from
# these. After this runs, per-repo `:setup` only flips the two toggle variables
# and ensures the App is installed on the repo.
#
# The Manifest flow needs the operator's browser ONCE (to click "Create GitHub
# App") and only outbound HTTPS to github.com — no public endpoint, no inbound
# network. Re-running creates a NEW App; you normally need it only once per org.
set -euo pipefail

# --- Prerequisites ---------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  echo "! gh CLI not found. Install it: https://cli.github.com/ — then 'gh auth login'." >&2
  exit 1
fi
# The single-use conversion response is parsed locally for three fields, so a
# standalone jq is required (we can't re-POST the code through 'gh api --jq').
if ! command -v jq >/dev/null 2>&1; then
  echo "! jq not found. Install it: https://jqlang.github.io/jq/ — then re-run." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "! gh is not authenticated. Run 'gh auth login' (needs admin:org / repo scope) and retry." >&2
  exit 1
fi
echo "This bootstrap opens your browser once to create the App. Run it on a"
echo "browser-capable machine (or use the paste fallback below if you are remote)."
echo "----------------------------------------------------------------------"

# --- Determine the target owner (org or personal account) ------------------
OWNER="${1:-}"
if [ -z "$OWNER" ]; then
  DEFAULT_OWNER="$(gh api user --jq .login 2>/dev/null || true)"
  read -r -p "GitHub org or user to own the App [${DEFAULT_OWNER}]: " OWNER || true
  OWNER="${OWNER:-$DEFAULT_OWNER}"
fi
if [ -z "$OWNER" ]; then
  echo "! No owner determined. Pass one explicitly: bazel run //tools/pulumi:create-app -- <org>." >&2
  exit 1
fi

# An org and a personal account use different manifest-submission endpoints.
# Probe the org API; fall back to the user endpoint when it is not an org.
if gh api "orgs/$OWNER" >/dev/null 2>&1; then
  NEW_APP_URL="https://github.com/organizations/$OWNER/settings/apps/new"
  echo "✓ Target '$OWNER' is an organization."
else
  NEW_APP_URL="https://github.com/settings/apps/new"
  echo "✓ Target '$OWNER' treated as a personal account."
fi

# --- Build the App manifest ------------------------------------------------
# Least privilege: branch protection + repo settings need Administration:write;
# Pulumi's github provider reads repo state with Contents:read. No webhook events.
REDIRECT_URL="http://localhost:8723/cb"
MANIFEST="$(
  cat <<EOF
{
  "name": "${OWNER}-pulumi",
  "url": "https://github.com/${OWNER}",
  "redirect_url": "${REDIRECT_URL}",
  "public": false,
  "default_permissions": {
    "administration": "write",
    "contents": "read",
    "variables": "write"
  },
  "default_events": []
}
EOF
)"

# --- Write an auto-submitting browser form ---------------------------------
# GitHub's manifest flow takes a POST whose body carries the manifest JSON; a
# tiny self-submitting HTML form is the standard, endpoint-agnostic way to do it.
# The JSON contains double quotes, so the attribute is single-quoted (the JSON
# has no single quotes, so this is safe).
# Portable temp file that reliably ends in '.html' so the browser auto-renders
# the form. BSD/GNU 'mktemp -t' disagree on prefixes vs. suffixes, so create a
# plain temp file and rename it with the extension.
HTML_FILE="$(mktemp "${TMPDIR:-/tmp}/pulumi-create-app.XXXXXX")"
mv "$HTML_FILE" "$HTML_FILE.html"
HTML_FILE="$HTML_FILE.html"
# One cleanup covers every exit path (errors under 'set -e', Ctrl-C at prompts).
trap 'rm -f "$HTML_FILE"' EXIT
cat >"$HTML_FILE" <<EOF
<!doctype html>
<html>
  <body onload="document.getElementById('f').submit()">
    <p>Submitting GitHub App manifest for <strong>${OWNER}</strong>…</p>
    <p>If nothing happens, click the button below.</p>
    <form id="f" method="post" action="${NEW_APP_URL}">
      <input type="hidden" name="manifest" value='${MANIFEST}'>
      <button type="submit">Create GitHub App</button>
    </form>
    <script>document.getElementById('f').submit()</script>
  </body>
</html>
EOF

open_browser() {
  if command -v open >/dev/null 2>&1; then
    open "$HTML_FILE"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$HTML_FILE"
  else
    echo "! Could not find 'open' or 'xdg-open'. Open this file in a browser manually:" >&2
    echo "    $HTML_FILE" >&2
  fi
}
echo
echo "Opening the GitHub App creation page in your browser…"
open_browser
echo "In the browser: review the pre-filled permissions and click 'Create GitHub App'."

# --- Capture the one-time manifest 'code' ----------------------------------
# After you click "Create GitHub App", GitHub redirects your BROWSER to
# ${REDIRECT_URL}?code=… — that localhost URL will not load (nothing is serving
# it), which is expected. The PRIMARY path is to paste the code; if 'nc' is
# present we make a best-effort one-shot capture first, then fall back to paste.
CODE=""
# Best-effort one-shot listener; needs both 'nc' and 'timeout' (so it can't hang
# forever). This convenience is Linux-oriented — stock macOS 'nc'/'timeout' flags
# differ and it will simply be skipped there. The paste path below is the
# guaranteed primary path and works on its own, so a missing/incompatible 'nc' is
# harmless.
if command -v nc >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  echo
  echo "Listening on localhost:8723 for the redirect (best-effort)…"
  REQUEST="$(timeout 60 nc -l 8723 2>/dev/null | head -n 1 || true)"
  if [ -n "$REQUEST" ]; then
    # Pull code=<value> out of the request line: "GET /cb?code=abc123 HTTP/1.1".
    CODE="$(printf '%s' "$REQUEST" | sed -n 's/.*[?&]code=\([^ &]*\).*/\1/p')"
  fi
fi
if [ -z "$CODE" ]; then
  echo
  echo "After clicking 'Create GitHub App', your browser lands on a localhost URL"
  echo "that won't load — copy the 'code=' value from the address bar and paste it here."
  read -r -p "code: " CODE || true
fi
if [ -z "$CODE" ]; then
  echo "! No code captured; cannot complete App creation. Re-run and paste the code." >&2
  exit 1
fi

# --- Exchange the code for App credentials ---------------------------------
# The conversions endpoint is unauthenticated, but going through `gh api` is fine
# and reuses the operator's HTTPS/proxy config.
echo
echo "Exchanging the code for App credentials…"
# A failed POST (e.g. expired/invalid code) can return a non-JSON error body that
# would crash jq under 'set -e'; surface a clear message instead.
if ! CONVERSION="$(gh api --method POST "/app-manifests/$CODE/conversions")"; then
  echo "! Failed to exchange the code (the code may have expired or is invalid —" >&2
  echo "  re-run and paste a fresh code)." >&2
  exit 1
fi
APP_ID="$(printf '%s' "$CONVERSION" | jq -r '.id')"
APP_SLUG="$(printf '%s' "$CONVERSION" | jq -r '.slug')"
APP_PEM="$(printf '%s' "$CONVERSION" | jq -r '.pem')"
if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ] || [ -z "$APP_PEM" ] || [ "$APP_PEM" = "null" ]; then
  echo "! Conversion did not return an App id/pem (the code may have expired). Re-run." >&2
  exit 1
fi
echo "✓ Created GitHub App '$APP_SLUG' (id: $APP_ID)."

# --- Set org-level credentials (the PEM is never echoed) -------------------
echo
echo "Setting org-level credentials on '$OWNER' (App ID as a variable, key as a secret)…"
gh variable set PULUMI_APP_ID --org "$OWNER" --visibility all --body "$APP_ID"
printf '%s' "$APP_PEM" | gh secret set APP_PRIVATE_KEY --org "$OWNER" --visibility all
echo "✓ Set PULUMI_APP_ID (variable) and APP_PRIVATE_KEY (secret)."

# --- Pulumi Cloud access token (read silently, never echoed) ---------------
echo
read -rs -p "Pulumi Cloud access token (leave empty to set later): " PULUMI_TOKEN || true
echo
if [ -n "$PULUMI_TOKEN" ]; then
  printf '%s' "$PULUMI_TOKEN" | gh secret set PULUMI_ACCESS_TOKEN --org "$OWNER" --visibility all
  echo "✓ Set PULUMI_ACCESS_TOKEN (secret)."
else
  echo "! Skipped PULUMI_ACCESS_TOKEN. Set it later (CI needs it for Pulumi state):"
  echo "    printf '%s' '<token>' | gh secret set PULUMI_ACCESS_TOKEN --org \"$OWNER\" --visibility all"
fi

# --- Install the App -------------------------------------------------------
echo
echo "Done. Install the App on '$OWNER' (and the repos that should opt in):"
echo "    https://github.com/apps/$APP_SLUG/installations/new"
echo "Then per repo, run 'bazel run //infrastructure/pulumi/repo_config:setup' to"
echo "enable preview-on-PR / apply-on-merge."
