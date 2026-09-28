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

# set-key.sh — store (or rotate) a GitHub App's private key as a repo secret.
#
#   bazel run //tools/github-app-key -- <app> --create       # create the App AND store its key
#   bazel run //tools/github-app-key -- <app>                # finds the .pem in ~/Downloads
#   bazel run //tools/github-app-key -- <app> --pem <path>
#   bazel run //tools/github-app-key -- --list
#
# --create uses GitHub's App Manifest flow: it opens a pre-filled "new App"
# page with the permissions listed in APPS, you click Create once, and GitHub
# hands this script the new App's key directly. The key never lands in
# ~/Downloads. You then install the App, and the checks below run as usual.
#
# Without --create, the one step GitHub cannot automate is "Generate a private
# key" in the App's settings page, which downloads a .pem. Everything after
# that is here, so an operator never hand-types `gh secret set` for a
# credential:
#
#   1. Check the file really is a private key.
#   2. Prove it belongs to the RIGHT App: sign a short-lived App JWT with it and
#      ask GitHub which App that is. A key for the wrong App (or a stale key
#      GitHub has already revoked) fails here, not later as a red workflow.
#   3. Check the App is installed on the repo, and -- for Apps that must stay
#      subject to the merge queue -- that it is NOT on any ruleset bypass list.
#   4. Store it with `gh secret set` over stdin. The key is never printed,
#      logged, or placed on a command line.
#   5. Offer to delete the downloaded .pem.
#
# To add an App, add a line to APPS below (client ID may be left empty until
# --create has made the App; commit the ID it prints). Client IDs are public
# (they already appear in workflow files); only the private key is secret.
#
# (//tools/pulumi:create-app is the separate one-time bootstrap of the Pulumi
# provider App, with org-level credentials. Use this tool for every other App.)

set -euo pipefail

REPO="${GITHUB_APP_KEY_REPO:-VitruvianSoftware/vitruvian-core}"
DOWNLOADS="${GITHUB_APP_KEY_DOWNLOADS:-${HOME}/Downloads}"

# name | App slug | client ID | secret name | secret stores | must-not-bypass | permissions (for --create)
APPS='
renovate|vitruvian-renovate|Iv23liR87u9iun3Br4GZ|RENOVATE_APP_PRIVATE_KEY|actions|yes|contents=write,issues=write,pull_requests=write
copybara-sync|vitruvian-copybara-sync|Iv23li2K1dcn4V98uOW3|SYNC_APP_PRIVATE_KEY|actions dependabot|no|contents=write,pull_requests=write
'

if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; RESET="$(printf '\033[0m')"
  GREEN="$(printf '\033[32m')"; YELLOW="$(printf '\033[33m')"; RED="$(printf '\033[31m')"
else
  BOLD=""; RESET=""; GREEN=""; YELLOW=""; RED=""
fi
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
die()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ask()  { # ask "prompt" -> 0 on yes. --yes answers yes; no tty answers no.
  [ "${ASSUME_YES}" = 1 ] && return 0
  [ -t 0 ] || return 1
  local reply; printf '? %s [y/N] ' "$1"; read -r reply
  case "${reply:-}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

usage() {
  cat <<USAGE
Usage: bazel run //tools/github-app-key -- <app> [--create | --pem <path>] [--yes]
       bazel run //tools/github-app-key -- --list

  <app>        one of: $(printf '%s' "$APPS" | awk -F'|' 'NF{printf "%s ", $1}')
  --create     create the App first (GitHub's manifest flow), then store its key
  --pem PATH   the downloaded private key (default: newest <slug>.*.private-key.pem in ~/Downloads)
  --yes        don't prompt; stores the key and deletes the .pem
USAGE
}

APP=""; PEM=""; ASSUME_YES=0; CREATE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) printf '%s' "$APPS" | awk -F'|' 'NF{printf "%-15s %-26s -> %s (%s)\n", $1, $2, $4, $5}'; exit 0;;
    --pem) PEM="${2:-}"; shift 2;;
    --yes) ASSUME_YES=1; shift;;
    --create) CREATE=1; shift;;
    -h|--help) usage; exit 0;;
    -*) usage >&2; exit 2;;
    *) APP="$1"; shift;;
  esac
done
[ -n "$APP" ] || { usage >&2; exit 2; }

row="$(printf '%s' "$APPS" | awk -F'|' -v a="$APP" '$1==a')"
[ -n "$row" ] || die "unknown app '$APP' (try --list)"
IFS='|' read -r _ SLUG CLIENT_ID SECRET STORES NO_BYPASS PERMS <<<"$row"
[ "$CREATE" = 1 ] && [ -n "$PEM" ] && die "--create and --pem don't mix: --create gets the key from GitHub"

printf '\n%sStore the %s private key as %s%s\n\n' "$BOLD" "$SLUG" "$SECRET" "$RESET"

for tool in gh openssl; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found on PATH"
done
gh auth status >/dev/null 2>&1 || die "gh is not signed in -- run 'gh auth login'"

# ---- 0. create the App (--create only) --------------------------------------
TEMP_PEM=0
if [ "$CREATE" = 1 ]; then
  OWNER="${REPO%%/*}"
  manifest="$(printf '%s' "$PERMS" | awk -v slug="$SLUG" -v owner="$OWNER" 'BEGIN{FS=","}
    { for (i = 1; i <= NF; i++) { split($i, kv, "="); perms = perms (i > 1 ? "," : "") "\"" kv[1] "\":\"" kv[2] "\"" } }
    END { printf "{\"name\":\"%s\",\"url\":\"https://github.com/%s\",\"redirect_url\":\"http://localhost:8723/cb\",\"public\":false,\"default_permissions\":{%s},\"default_events\":[]}", slug, owner, perms }')"
  form="$(mktemp "${TMPDIR:-/tmp}/github-app-create.XXXXXX")"; mv "$form" "$form.html"; form="$form.html"
  cat >"$form" <<HTML
<!doctype html><html><body onload="document.getElementById('f').submit()">
<p>Opening GitHub's new-App page for <strong>${SLUG}</strong>...</p>
<form id="f" method="post" action="https://github.com/organizations/${OWNER}/settings/apps/new">
<input type="hidden" name="manifest" value='${manifest}'><button type="submit">Create GitHub App</button>
</form></body></html>
HTML
  printf '  Creating %s with: %s\n' "$SLUG" "$PERMS"
  if [ -z "${GITHUB_APP_KEY_NO_BROWSER:-}" ] && command -v open >/dev/null 2>&1; then open "$form"
  elif [ -z "${GITHUB_APP_KEY_NO_BROWSER:-}" ] && command -v xdg-open >/dev/null 2>&1; then xdg-open "$form"
  else printf '  Open this file in a browser: %s\n' "$form"; fi
  printf '  In the browser: check the permissions and click "Create GitHub App".\n'
  printf '  The browser then lands on a localhost page that will not load -- that is expected.\n'
  printf '? Paste the code= value from that address bar: '
  read -r code || true
  rm -f "$form"
  [ -n "${code:-}" ] || die "no code pasted -- re-run"
  # The code works once. Take everything in one call; the key comes back
  # base64-encoded so it survives the one-line read and is never printed.
  conv="$(gh api --method POST "/app-manifests/${code}/conversions" \
    --jq '"\(.slug) \(.client_id) \(.pem | @base64)"' 2>/dev/null)" \
    || die "GitHub did not accept that code (they expire after an hour, and work once) -- re-run"
  read -r new_slug CLIENT_ID pem_b64 <<<"$conv"
  [ "$new_slug" = "$SLUG" ] || die "GitHub created '${new_slug}', expected '${SLUG}' -- was the name changed on the form? Delete that App and re-run"
  PEM="$(umask 077; mktemp "${TMPDIR:-/tmp}/github-app-key.XXXXXX")"
  TEMP_PEM=1
  trap 'rm -f "$PEM"' EXIT
  printf '%s' "$pem_b64" | openssl base64 -d -A >"$PEM"
  unset pem_b64 conv
  ok "created ${SLUG} (client ID ${CLIENT_ID})"
  printf '  Now install it: https://github.com/apps/%s/installations/new\n' "$SLUG"
  printf '  Choose "Only select repositories" and pick %s.\n' "${REPO#*/}"
  printf '? Press Enter once it is installed... '
  read -r _ || true
fi
[ -n "$CLIENT_ID" ] || die "no client ID for ${APP} yet -- run with --create, or add it to APPS"

# ---- 1. the file ------------------------------------------------------------
if [ -z "$PEM" ]; then
  # GitHub names the download <slug>.<yyyy-mm-dd>.private-key.pem
  # shellcheck disable=SC2012 # GitHub picks these names; ls -t gives "newest"
  PEM="$(ls -t "${DOWNLOADS}/${SLUG}".*.private-key.pem 2>/dev/null | head -n1 || true)"
  [ -n "$PEM" ] || die "no ${SLUG}.*.private-key.pem in ${DOWNLOADS} -- generate one at https://github.com/organizations/${REPO%%/*}/settings/apps/${SLUG} or pass --pem"
fi
[ -f "$PEM" ] || die "not a file: $PEM"
openssl pkey -in "$PEM" -noout >/dev/null 2>&1 || die "$PEM is not a readable private key"
ok "private key file: $PEM"

# ---- 2. prove it is this App's key ------------------------------------------
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
unsigned="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' "$((now - 60))" "$((now + 300))" "$CLIENT_ID" | b64url)"
jwt="${unsigned}.$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$PEM" -binary | b64url)"
# gh sends our Authorization header in place of the operator's own token.
app_api() { gh api -H "Authorization: Bearer ${jwt}" "$@"; }

got_slug="$(app_api /app --jq .slug 2>/dev/null)" \
  || die "GitHub rejected this key for ${SLUG} -- wrong App, or a key already deleted in the App's settings"
[ "$got_slug" = "$SLUG" ] || die "this key belongs to '${got_slug}', not '${SLUG}'"
APP_ID="$(app_api /app --jq .id)"
ok "GitHub confirms the key belongs to ${SLUG} (App id ${APP_ID})"

# ---- 3. installed, and not a bypass actor -----------------------------------
app_api "repos/${REPO}/installation" --jq .id >/dev/null 2>&1 \
  || die "${SLUG} is not installed on ${REPO} -- install it (Only select repositories) and re-run"
ok "installed on ${REPO}"

if [ "$NO_BYPASS" = yes ]; then
  for rs in $(gh api "repos/${REPO}/rulesets" --jq '.[].id'); do
    bypass="$(gh api "repos/${REPO}/rulesets/${rs}" --jq '.bypass_actors[]? | select(.actor_type=="Integration") | .actor_id')"
    if printf '%s\n' "$bypass" | grep -qx "$APP_ID"; then
      die "${SLUG} is on the bypass list of ruleset ${rs} -- remove it; this App must go through the merge queue like everyone else"
    fi
  done
  ok "not on any ruleset bypass list"
fi

# ---- 4. store ---------------------------------------------------------------
for store in $STORES; do
  flag=""; [ "$store" = dependabot ] && flag="--app dependabot"
  # shellcheck disable=SC2086 # $flag is intentionally unquoted (empty or two words)
  gh secret set "$SECRET" --repo "$REPO" $flag <"$PEM" >/dev/null
  ok "stored ${SECRET} (${store} secrets)"
done
[ "$SECRET" = SYNC_APP_PRIVATE_KEY ] && warn "repo-config (Pulumi) also writes this secret, from the same CI secret -- nothing else to update"

# ---- 5. clean up ------------------------------------------------------------
if [ "$TEMP_PEM" = 1 ]; then
  rm -f "$PEM" && ok "removed the temporary copy of the key"
  row_client="$(printf '%s' "$APPS" | awk -F'|' -v a="$APP" '$1==a {print $3}')"
  [ "$row_client" = "$CLIENT_ID" ] || warn "commit this client ID into APPS in tools/github-app-key/set-key.sh: ${CLIENT_ID}"
elif ask "Delete ${PEM} now that it is stored?"; then
  rm -f "$PEM" && ok "deleted ${PEM}"
else
  warn "left ${PEM} in place -- delete it once you're done"
fi
printf '\n%sDone.%s\n' "$BOLD" "$RESET"
