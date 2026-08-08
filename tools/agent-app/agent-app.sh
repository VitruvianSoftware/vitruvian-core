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
#   bazel run //tools/agent-app -- env <agent>        # the one agents actually use
#   bazel run //tools/agent-app -- login <agent>      # token only
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


# AGENT_REGISTRY maps an agent name to its app id and installation id. Committed
# and NOT secret -- both are public identifiers. The private key is not in it.
# Under `bazel run`, BASH_SOURCE points at bazel-bin, not the runfiles tree, so
# resolving the registry relative to the script finds nothing. It is a COMMITTED
# file, so the workspace copy is authoritative either way.
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  AGENT_REGISTRY="${AGENT_REGISTRY:-$BUILD_WORKSPACE_DIRECTORY/tools/agent-app/agents.tsv}"
else
  AGENT_REGISTRY="${AGENT_REGISTRY:-$(dirname "${BASH_SOURCE[0]}")/agents.tsv}"
fi
# The keys are GITIGNORED workspace files, so they are NOT in bazel's runfiles.
# Resolving them relative to this script works when run directly and silently
# points into the read-only runfiles tree under `bazel run` -- where the key does
# not exist. BUILD_WORKSPACE_DIRECTORY is bazel's pointer back to the real tree;
# same reason //tools/sync-env-secrets does it.
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  AGENT_KEY_DIR="${AGENT_KEY_DIR:-$BUILD_WORKSPACE_DIRECTORY/tools/sync-env-secrets/agent-keys}"
else
  AGENT_KEY_DIR="${AGENT_KEY_DIR:-$(dirname "${BASH_SOURCE[0]}")/../sync-env-secrets/agent-keys}"
fi

# cmd_login is the whole point of this tool for an agent: one argument, its own
# name, and it gets a token for its OWN identity. The four-argument `token` form
# stays for humans debugging, but an agent that has to look up two numeric ids
# will eventually paste the wrong one and act as another agent without noticing.
known_agents() { awk -F'\t' '!/^#/ && NF>=3 {printf "%s ", $1}' "$AGENT_REGISTRY"; }

cmd_login() {
  local agent="${1:-}"
  [ -n "$agent" ] || die "usage: login <agent>   (one of: $(known_agents))"
  [ -r "$AGENT_REGISTRY" ] || die "cannot read agent registry: $AGENT_REGISTRY"

  local app_id inst_id
  app_id="$(awk -F'\t' -v a="$agent" '!/^#/ && $1==a {print $2}' "$AGENT_REGISTRY")"
  inst_id="$(awk -F'\t' -v a="$agent" '!/^#/ && $1==a {print $3}' "$AGENT_REGISTRY")"
  [ -n "$app_id" ] && [ -n "$inst_id" ] \
    || die "unknown agent '$agent' -- known: $(known_agents)"

  local key="$AGENT_KEY_DIR/$agent.pem"
  [ -r "$key" ] || die "no key at $key -- run: bazel run //tools/sync-env-secrets:agent-keys-pull"

  cmd_token "$app_id" "$key" "$inst_id"
}


# cmd_env prints every export an agent needs, so session setup is one line:
#
#   eval "$(bazel run //tools/agent-app -- env beacon)"
#
# GH_TOKEN alone is NOT enough, and that is the trap this exists to close: it
# changes who PUSHES, not who AUTHORED. A commit pushed by beacon[bot] with the
# ambient git config still carries the machine owner's name in the history --
# the PR looks right and the commit log is wrong.
#
# GIT_AUTHOR_*/GIT_COMMITTER_* are used rather than `git config` deliberately:
# they are process-scoped, so they cannot leak into a shared checkout and
# mis-attribute the next agent's work.
cmd_env() {
  local agent="${1:-}"
  [ -n "$agent" ] || die "usage: env <agent>   (one of: $(known_agents))"
  local slug="vitruvian-${agent}-agent"
  local bot_id token
  bot_id="$(awk -F'\t' -v a="$agent" '!/^#/ && $1==a {print $4}' "$AGENT_REGISTRY")"
  [ -n "$bot_id" ] || die "no bot_user_id for '$agent' in $AGENT_REGISTRY"
  token="$(cmd_login "$agent")" || exit 1

  printf 'export GH_TOKEN=%s\n' "$token"
  printf 'export GIT_AUTHOR_NAME=%s\n' "'${slug}[bot]'"
  printf 'export GIT_AUTHOR_EMAIL=%s\n' "'${bot_id}+${slug}[bot]@users.noreply.github.com'"
  printf 'export GIT_COMMITTER_NAME=%s\n' "'${slug}[bot]'"
  printf 'export GIT_COMMITTER_EMAIL=%s\n' "'${bot_id}+${slug}[bot]@users.noreply.github.com'"
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
    login) cmd_login "$@" ;;
    env) cmd_env "$@" ;;
    -h | --help | help) usage 0 ;;
    *) die "unknown command: $cmd (try --help)" ;;
  esac
}

main "$@"
