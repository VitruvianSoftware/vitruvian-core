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

# agent-app — the API half of standing up a per-agent GitHub App identity.
#
# App CREATION is not scriptable: GitHub's Apps REST API has fourteen endpoints
# and none of them creates an App. The only creation path is the App-manifest
# flow, whose final step IS an API call -- but the `code` it consumes exists only
# after a signed-in human approves the handshake in a browser. So the manual part
# is two clicks per agent; everything either side of them is here.
#
#   bazel run //tools/agent-app -- convert <manifest-code> <out.pem>
#   bazel run //tools/agent-app -- installations <app-id> <key.pem>
#   bazel run //tools/agent-app -- repos <app-id> <key.pem> <installation-id>
#   bazel run //tools/agent-app -- token <app-id> <key.pem> <installation-id>
#
# See docs/guides/creating-an-agent-github-app.md for the SOP these implement,
# and docs/guides/agent-github-identities.md for why per-agent Apps at all.

set -euo pipefail

API="${GITHUB_API_URL:-https://api.github.com}"

die() {
  echo "agent-app: $*" >&2
  exit 1
}

usage() {
  sed -n '/^# agent-app —/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

# b64url encodes stdin as base64url with padding stripped, the encoding JWT
# requires. Plain base64 is NOT interchangeable here: + / = are all significant
# in a JWT and GitHub rejects the token without explaining why.
b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# app_jwt prints a short-lived RS256 JWT for an App. GitHub caps the lifetime at
# 10 minutes and rejects a future iat outright, so iat is backdated 60s to absorb
# clock skew between this machine and GitHub -- the single most common cause of
# a "'Issued at' claim ('iat') is in the future" that reads like a bad key.
app_jwt() {
  local app_id="$1" key="$2" now header payload signing_input sig
  [ -r "$key" ] || die "cannot read private key: $key"
  now="$(date +%s)"
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$app_id" | b64url)"
  signing_input="${header}.${payload}"
  sig="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$key" -binary | b64url)"
  printf '%s.%s' "$signing_input" "$sig"
}

# api_get/api_post keep the Authorization header out of argv, where it would be
# visible to any other process on the machine via `ps`.
api_call() {
  local method="$1" path="$2" token="$3"
  curl -sSf -X "$method" "${API}${path}" \
    -H @<(printf 'Authorization: Bearer %s\n' "$token") \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28"
}

cmd_convert() {
  local code="${1:-}" out="${2:-}"
  [ -n "$code" ] && [ -n "$out" ] || die "usage: convert <manifest-code> <out.pem>"
  [ -e "$out" ] && die "refusing to overwrite existing key: $out"
  # The code is single-use and expires an hour after the browser handshake. The
  # pem in this response is the ONLY copy GitHub will ever hand out -- there is
  # no "download it again". Write it before printing anything else.
  local resp
  resp="$(curl -sSf -X POST "${API}/app-manifests/${code}/conversions" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28")" ||
    die "manifest conversion failed -- the code is single-use and expires in 1h; redo the browser step"
  local old_umask
  old_umask="$(umask)"
  umask 077
  printf '%s' "$resp" | jq -re '.pem' > "$out" || die "response contained no pem"
  umask "$old_umask"
  printf '%s' "$resp" | jq -r '"app_id=\(.id)\nslug=\(.slug)\nowner=\(.owner.login)\nkey=" + $out' --arg out "$out"
  echo "agent-app: key written to $out (mode 600). GitHub will not issue it again." >&2
}

cmd_installations() {
  local app_id="${1:-}" key="${2:-}"
  [ -n "$app_id" ] && [ -n "$key" ] || die "usage: installations <app-id> <key.pem>"
  api_call GET /app/installations "$(app_jwt "$app_id" "$key")" |
    jq -r '.[] | "installation_id=\(.id)\taccount=\(.account.login)\tselection=\(.repository_selection)"'
}

cmd_repos() {
  local app_id="${1:-}" key="${2:-}" inst="${3:-}"
  [ -n "$app_id" ] && [ -n "$key" ] && [ -n "$inst" ] || die "usage: repos <app-id> <key.pem> <installation-id>"
  local tok
  tok="$(cmd_token "$app_id" "$key" "$inst")"
  api_call GET /installation/repositories "$tok" | jq -r '.repositories[].full_name'
}

cmd_token() {
  local app_id="${1:-}" key="${2:-}" inst="${3:-}"
  [ -n "$app_id" ] && [ -n "$key" ] && [ -n "$inst" ] || die "usage: token <app-id> <key.pem> <installation-id>"
  # Installation tokens expire after 1 hour. That is the point -- it is why the
  # long-lived secret is the key and never the token, so this is a step in the
  # harness rather than something to paste anywhere.
  api_call POST "/app/installations/${inst}/access_tokens" "$(app_jwt "$app_id" "$key")" |
    jq -re '.token'
}

main() {
  local cmd="${1:-}"
  [ -n "$cmd" ] || usage 1
  shift || true
  case "$cmd" in
    convert) cmd_convert "$@" ;;
    installations) cmd_installations "$@" ;;
    repos) cmd_repos "$@" ;;
    token) cmd_token "$@" ;;
    -h | --help | help) usage 0 ;;
    *) die "unknown command: $cmd (try --help)" ;;
  esac
}

main "$@"
