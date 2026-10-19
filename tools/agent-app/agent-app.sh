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
#   bazel run //tools/agent-app -- pr-create [--agent <agent>] [gh pr create args]
#                                   # open a PR as the agent, in the fast lane
#   bazel run //tools/agent-app -- pr-edit [--agent <agent>] <pr> [gh pr edit args]
#   bazel run //tools/agent-app -- pr-comment [--agent <agent>] <pr> --body-file <f> | --body <s>
#   bazel run //tools/agent-app -- pr-ready [--agent <agent>] <pr> [gh pr ready args]
#   bazel run //tools/agent-app -- pr-close [--agent <agent>] <pr> [--comment <s>] [--delete-branch]
#   bazel run //tools/agent-app -- pr-enqueue [--agent <agent>] <pr> [gh pr merge args]
#                                   # arm auto-merge into the merge queue; never --admin
#   bazel run //tools/agent-app -- pr-hold [--agent <agent>] <pr> [--reason <s>]
#                                   # do-not-automerge on, auto-merge off, out of the queue
#   bazel run //tools/agent-app -- pr-unhold [--agent <agent>] <pr>
#                                   # label off only; run pr-enqueue to re-arm
#   bazel run //tools/agent-app -- run-rerun [--agent <agent>] <run-id> [--failed] [--job <id>]
#   bazel run //tools/agent-app -- run-cancel [--agent <agent>] <run-id>
#   bazel run //tools/agent-app -- workflow-run [--agent <agent>] <workflow.yaml> [-f k=v ...] [--ref main]
#                                   # only workflows in workflow-allowlist.txt, only from main
#   bazel run //tools/agent-app -- branch-delete [--agent <agent>] <branch>...
#                                   # delete branches on GitHub, only ones already on main
#
# Every pr-* and run command acts AS the agent app (default wren, or
# $AGENT_APP_AGENT): the token reaches gh through its environment only, and if
# it cannot be minted nothing runs. pr-enqueue too: the agent apps can arm
# auto-merge themselves (scout did on #3421), so it never needs your login;
# it refuses a PR held with do-not-automerge (pr-unhold first) or by a
# release gate's own label (the gate re-arms it when its condition clears).
# run-rerun, run-cancel and workflow-run need Actions write, which only wren
# has (permissions.tsv); they refuse for an agent without it.
#
# See docs/guides/creating-an-agent-github-app.md for the SOP these implement,
# and docs/guides/agent-github-identities.md for why per-agent Apps at all.

# Tracing off before anything else runs: under `bash -x` or SHELLOPTS=xtrace
# every line is echoed with its variables expanded, the token included.
{ set +x; } 2>/dev/null
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
  default_key_dir="$BUILD_WORKSPACE_DIRECTORY/tools/sync-env-secrets/agent-keys"
else
  default_key_dir="$(dirname "${BASH_SOURCE[0]}")/../sync-env-secrets/agent-keys"
fi
# A git worktree has no keys: they are gitignored and pulled into the main
# checkout only. So when the default folder is missing, use the main
# checkout's, found through git's shared directory. An AGENT_KEY_DIR the
# caller set is always used as given.
if [ -z "${AGENT_KEY_DIR:-}" ] && [ ! -d "$default_key_dir" ]; then
  if common="$(git -C "$(dirname "$default_key_dir")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" &&
    [ -d "$(dirname "$common")/tools/sync-env-secrets/agent-keys" ]; then
    default_key_dir="$(dirname "$common")/tools/sync-env-secrets/agent-keys"
  fi
fi
AGENT_KEY_DIR="${AGENT_KEY_DIR:-$default_key_dir}"

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

# The pr-* and run commands below all act AS an agent app, never as whoever
# gh happens to be logged in as. These helpers are the shared part.
#
# take_agent reads an optional leading `--agent <agent>`. It sets AGENT (wren
# unless $AGENT_APP_AGENT says otherwise) and AGENT_SHIFT, the number of
# arguments the caller must shift off. A function cannot shift its caller's
# arguments, hence the second variable.
take_agent() {
  AGENT="${AGENT_APP_AGENT:-wren}"
  AGENT_SHIFT=0
  if [ "${1:-}" = --agent ]; then
    [ -n "${2:-}" ] || return 1
    AGENT="$2"
    AGENT_SHIFT=2
  fi
}

# mint_token sets TOKEN to the agent's installation token, or stops with
# "<what> was NOT <done>" so the caller knows nothing happened. It never falls
# back to the ambient gh login: an action that silently runs as the machine
# owner is exactly what these commands exist to stop.
mint_token() {
  local agent="$1" not_done="$2"
  TOKEN="$(cmd_login "$agent")" && [ -n "$TOKEN" ] ||
    die "could not mint a token for the $agent app; $not_done"
}

# to_caller_dir: bazel run starts in the runfiles tree; gh needs the caller's
# checkout to find the repo and branch, and relative paths like --body-file are
# theirs.
to_caller_dir() {
  cd "${BUILD_WORKING_DIRECTORY:-.}" || die "cannot enter ${BUILD_WORKING_DIRECTORY:-.}"
}

# gh_as runs gh with the minted token in its environment only: never printed,
# never in argv. GITHUB_TOKEN is emptied because gh prefers it over nothing
# and an ambient one (a CI runner's, or the person's) must not win.
gh_as() {
  GH_TOKEN="$TOKEN" GITHUB_TOKEN="" "${GH_BIN:-gh}" "$@"
}
exec_gh_as() {
  GH_TOKEN="$TOKEN" GITHUB_TOKEN="" exec "${GH_BIN:-gh}" "$@"
}

# need_target rejects a missing or flag-shaped first argument, so
# `pr-edit --title x` does not edit "the PR for the current branch" by accident.
need_target() {
  local what="$1" usage="$2" target="${3:-}"
  [ -n "$target" ] && [ "${target#-}" = "$target" ] || die "usage: $usage   (missing <$what>)"
}

# The permissions each App is meant to have, and the workflows an agent may
# start. Same resolution as the registry: committed files, so the workspace
# copy is authoritative under bazel run. The two env overrides exist for the
# test and count ONLY under bazel test (TEST_SRCDIR/TEST_TMPDIR set): anywhere
# else, an agent could point them at a file of its own and start any workflow.
# branch-delete's gate, //tools/landed, resolves the same way and has the same
# test-only override: an agent able to name its own gate could delete anything.
if [ -z "${TEST_SRCDIR:-}${TEST_TMPDIR:-}" ]; then
  AGENT_PERMISSIONS=""
  WORKFLOW_ALLOWLIST=""
  AGENT_APP_LANDED=""
fi
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  AGENT_PERMISSIONS="${AGENT_PERMISSIONS:-$BUILD_WORKSPACE_DIRECTORY/tools/agent-app/permissions.tsv}"
  WORKFLOW_ALLOWLIST="${WORKFLOW_ALLOWLIST:-$BUILD_WORKSPACE_DIRECTORY/tools/agent-app/workflow-allowlist.txt}"
  AGENT_APP_LANDED="${AGENT_APP_LANDED:-$BUILD_WORKSPACE_DIRECTORY/tools/landed/landed.sh}"
else
  AGENT_PERMISSIONS="${AGENT_PERMISSIONS:-$(dirname "${BASH_SOURCE[0]}")/permissions.tsv}"
  WORKFLOW_ALLOWLIST="${WORKFLOW_ALLOWLIST:-$(dirname "${BASH_SOURCE[0]}")/workflow-allowlist.txt}"
  AGENT_APP_LANDED="${AGENT_APP_LANDED:-$(dirname "${BASH_SOURCE[0]}")/../landed/landed.sh}"
fi

# need_actions_write stops before minting anything when permissions.tsv says
# the agent's App cannot start, re-run or cancel workflow runs. GitHub would
# answer 403 anyway; this says why and which agent can, instead of a bare
# "Resource not accessible by integration".
need_actions_write() {
  local agent="$1" level who
  [ -r "$AGENT_PERMISSIONS" ] || die "cannot read $AGENT_PERMISSIONS; nothing was run"
  level="$(awk -F'\t' -v a="$agent" '!/^#/ && $1==a && $2=="actions" {print $3}' "$AGENT_PERMISSIONS")"
  case "$level" in write | admin) return 0 ;; esac
  who="$(awk -F'\t' '!/^#/ && $2=="actions" && ($3=="write" || $3=="admin") {printf "%s ", $1}' "$AGENT_PERMISSIONS")"
  [ -n "$who" ] || die "the $agent app has no Actions write, and no agent App does (permissions.tsv); nothing was run"
  die "the $agent app has no Actions write (permissions.tsv), so GitHub would refuse; use --agent ${who%% *} (has it: ${who% })"
}

# cmd_pr_create opens a pull request AS the agent app, in the fast lane:
#
#   bazel run //tools/agent-app -- pr-create --title "..." --body-file pr.md
#   bazel run //tools/agent-app -- pr-create --agent beacon --title "..." ...
#
# Two things make a PR skip the heavy PR tests (#3418): it is opened by an
# agent app, and it carries the agent-fast-lane label WHEN IT OPENS. A PR
# opened with the machine owner's own gh login is neither, and a label added
# later only counts from the next push. So this mints the agent's token, adds
# the label (once: not again if the caller already passed it) and hands every
# other argument to `gh pr create` unchanged. The merge queue still runs every
# test before anything lands.
#
# The token goes to gh through its environment only: never printed, never in
# argv. If it cannot be minted the PR is NOT opened, rather than opened as
# whoever gh is logged in as, which would quietly skip the fast lane.
FAST_LANE_LABEL="agent-fast-lane"

cmd_pr_create() {
  take_agent "$@" || die "usage: pr-create [--agent <agent>] [gh pr create args]"
  shift "$AGENT_SHIFT"

  # Already labelled? --label X, --label=X, -l X, -lX; X may be a,b,c.
  local arg prev="" labels has=0
  for arg in "$@"; do
    labels=""
    case "$prev" in --label | -l) labels="$arg" ;; esac
    case "$arg" in --label=*) labels="${arg#--label=}" ;; -l?*) labels="${arg#-l}" ;; esac
    if [ -n "$labels" ] && [[ ",${labels// /}," == *",${FAST_LANE_LABEL},"* ]]; then
      has=1
    fi
    prev="$arg"
  done

  mint_token "$AGENT" "the PR was NOT opened"

  local args=("$@")
  [ "$has" = 1 ] || args+=(--label "$FAST_LANE_LABEL")
  to_caller_dir
  exec_gh_as pr create "${args[@]}"
}

# cmd_pr_edit, cmd_pr_ready, cmd_pr_close: `gh pr <verb> <pr> [args]` as the
# agent, every argument after the PR passed through unchanged.
#
#   bazel run //tools/agent-app -- pr-edit 123 --title "..." --body-file pr.md --add-label x
#   bazel run //tools/agent-app -- pr-ready 123
#   bazel run //tools/agent-app -- pr-close 123 --comment "superseded by #124"
#
# Labels added here count for the fast lane only from the next push (see
# pr-create), so open the PR with pr-create rather than labelling it later.
pr_passthrough() {
  local verb="$1" usage="$2"
  shift 2
  take_agent "$@" || die "usage: $usage"
  shift "$AGENT_SHIFT"
  need_target pr "$usage" "${1:-}"
  mint_token "$AGENT" "the PR was NOT changed"
  to_caller_dir
  exec_gh_as pr "$verb" "$@"
}
cmd_pr_edit() { pr_passthrough edit "pr-edit [--agent <agent>] <pr> [gh pr edit args]" "$@"; }
cmd_pr_ready() { pr_passthrough ready "pr-ready [--agent <agent>] <pr> [gh pr ready args]" "$@"; }
cmd_pr_close() { pr_passthrough close "pr-close [--agent <agent>] <pr> [--comment <s>] [--delete-branch]" "$@"; }

# cmd_pr_comment posts a comment as the agent. The body must be given: without
# one gh opens an editor or prompts, which hangs an agent session.
#
#   bazel run //tools/agent-app -- pr-comment 123 --body-file note.md
cmd_pr_comment() {
  local usage="pr-comment [--agent <agent>] <pr> --body-file <f> | --body <s>"
  take_agent "$@" || die "usage: $usage"
  shift "$AGENT_SHIFT"
  need_target pr "$usage" "${1:-}"
  local arg has=0
  for arg in "${@:2}"; do
    case "$arg" in --body | --body=* | -b | -b?* | --body-file | --body-file=* | -F | -F?*) has=1 ;; esac
  done
  [ "$has" = 1 ] || die "usage: $usage   (give the body: without it gh waits for an editor)"
  mint_token "$AGENT" "the comment was NOT posted"
  to_caller_dir
  exec_gh_as pr comment "$@"
}

# A hold in this repo is TWO things, and the label alone is not one of them.
# Auto-merge is a setting on the PR, not a check: with it armed, GitHub merges
# the moment the checks pass, label or no label. do-not-automerge is the
# label the release gates treat as a person's hold (tools/ci/release-hold.sh,
# release-beta-gate.sh: PERSON_LABEL): they never remove it, and they re-arm
# auto-merge on a PR only when it does NOT carry it. Their own holds use other
# labels (dev-deploy-red, beta-not-built).
HOLD_LABEL="do-not-automerge"
# The gates' OWN holds, which pr-enqueue must not arm over either. Copies of
# HOLD_LABEL in tools/ci/release-hold.sh and tools/ci/release-beta-gate.sh;
# agent-app_test fails if either drifts from its script.
RELEASE_HOLD_LABEL="dev-deploy-red"
BETA_GATE_LABEL="beta-not-built"

# pr_node_id prints the PR's GraphQL node id, looked up exactly as gh resolves
# the PR (a number, a URL or a branch, with or without --repo).
pr_node_id() {
  local id
  id="$(gh_as pr view "$@" --json id --jq .id)" && [ -n "$id" ] || return 1
  printf '%s\n' "$id"
}

# hold_state prints "<auto-merge armed> <in queue> <labelled> <PR state>
# <gate hold>", e.g. "false false true OPEN -", read from GitHub by node id.
# <labelled> is do-not-automerge; <gate hold> is the first release-gate hold
# label on the PR, or - when there is none.
hold_state() {
  # shellcheck disable=SC2016 # $id is a GraphQL variable, not a shell one.
  gh_as api graphql -f id="$1" -f query='
    query($id: ID!) { node(id: $id) { ... on PullRequest {
      state
      autoMergeRequest { enabledAt }
      mergeQueueEntry { id }
      labels(first: 100) { nodes { name } }
    } } }' --jq '.data.node |
      [.labels.nodes[].name] as $labels |
      "\(.autoMergeRequest != null) \(.mergeQueueEntry != null) \($labels | index("'"$HOLD_LABEL"'") != null) \(.state) \(first($labels[] | select(. == "'"$RELEASE_HOLD_LABEL"'" or . == "'"$BETA_GATE_LABEL"'")) // "-")"'
}

# cmd_pr_enqueue arms auto-merge, so the PR joins main's merge queue once its
# checks pass, and confirms on GitHub that it took:
#
#   bazel run //tools/agent-app -- pr-enqueue 123
#
# WHO: the agent app, not your gh login. Arming auto-merge needs write access
# to the repo (GitHub's auto-merge docs) -- for an App, contents and
# pull_requests write, which every agent App has (permissions.tsv). This is
# not theory: on #3421 vitruvian-scout-agent[bot] armed auto-merge and added
# the PR to the queue, and it merged. The App is NOT a bypass actor on main's
# ruleset, and does not need to be: a bypass only matters for a direct merge,
# and that is the one thing this refuses to do.
#
# NEVER --admin. --admin merges past the queue and the required checks; it is
# the human maintainer's break-glass (AGENTS.md, "Never merge past the merge
# queue"). It is refused however it is spelled, before any token is minted.
#
# NEVER over a hold. A PR carrying do-not-automerge is refused: someone
# decided it must not land yet, and arming it would undo that silently. The
# way out is pr-unhold, which is a separate, visible decision. A PR carrying
# a release gate's own hold (dev-deploy-red, beta-not-built) is refused too:
# that gate re-arms the PR itself once its condition clears.
#
# The method: main's merge queue squashes and its ruleset allows only squash.
# gh needs no method when it sees the queue, but it does when it cannot (and
# it reads that with the same token), so --squash is added unless the caller
# chose one; --merge and --rebase are refused because the ruleset would,
# including inside a cluster of short flags such as -sm or -dr.
#
# "gh exited 0" is not the check. Afterwards this asks GitHub's GraphQL API
# whether the PR has an autoMergeRequest (armed, waiting for checks) or a
# mergeQueueEntry (already in the queue), prints which, and fails if neither.
cmd_pr_enqueue() {
  local usage="pr-enqueue [--agent <agent>] <pr> [gh pr merge args, never --admin]"
  take_agent "$@" || die "usage: $usage"
  shift "$AGENT_SHIFT"
  local arg value_for="" auto=0 method=0 repo=() i c
  for arg in "$@"; do
    # The value of a flag that takes one is not itself a flag: --subject "-m".
    if [ -n "$value_for" ]; then
      [ "$value_for" = repo ] && repo=(--repo "$arg")
      value_for=""
      continue
    fi
    case "$arg" in
      --admin | --admin=*)
        die "refusing --admin: it merges past the merge queue. That is the maintainer's break-glass, not an agent's; nothing was run" ;;
      --disable-auto | --disable-auto=*)
        die "--disable-auto turns auto-merge OFF; pr-enqueue only turns it on (to hold a PR: pr-hold). Nothing was run" ;;
      --merge | --merge=* | --rebase | --rebase=*)
        die "refusing $arg: main's ruleset allows only squash merges; nothing was run" ;;
      --auto | --auto=*) auto=1 ;;
      --squash | --squash=*) method=1 ;;
      --repo) value_for=repo ;;
      --repo=*) repo=(--repo "${arg#--repo=}") ;;
      --body | --body-file | --subject | --author-email | --match-head-commit) value_for=other ;;
      --*) ;;
      -?*)
        # One or more short flags: -s, -d, -sd. A letter that takes a value
        # (-b -t -A -F -R) ends the cluster; the rest, or the next argument,
        # is its value.
        for ((i = 1; i < ${#arg}; i++)); do
          c="${arg:i:1}"
          case "$c" in
            m | r) die "refusing $arg: it asks for a merge commit or a rebase, and main's ruleset allows only squash merges; nothing was run" ;;
            s) method=1 ;;
            R)
              if [ $((i + 1)) -lt ${#arg} ]; then repo=(--repo "${arg:i+1}"); else value_for=repo; fi
              break ;;
            b | t | A | F)
              [ $((i + 1)) -lt ${#arg} ] || value_for=other
              break ;;
          esac
        done ;;
    esac
  done
  need_target pr "$usage" "${1:-}"
  local pr="$1"

  mint_token "$AGENT" "auto-merge was NOT armed"
  to_caller_dir

  # GraphQL by node id, so the PR is looked up exactly as gh resolved it.
  local id st labelled pr_state gate
  id="$(pr_node_id "$pr" ${repo[@]+"${repo[@]}"})" || die "could not look $pr up; auto-merge was NOT armed"
  st="$(hold_state "$id")" || die "could not read $pr from GitHub; auto-merge was NOT armed"
  read -r _ _ labelled pr_state gate <<<"$st"
  [ "$labelled" != true ] ||
    die "$pr is held ($HOLD_LABEL); auto-merge was NOT armed. If the hold should end, run pr-unhold $pr first"
  # A release gate's own hold: the gate re-arms the PR itself once its
  # condition clears, so arming it now would only let it merge early.
  case "$gate" in
    "$RELEASE_HOLD_LABEL")
      die "$pr is held by release-hold ($gate: its development deploy is red); auto-merge was NOT armed. The gate re-arms the PR itself once development is green again, so leave it to the gate" ;;
    "$BETA_GATE_LABEL")
      die "$pr is held by release-beta-gate ($gate: its beta build is not green); auto-merge was NOT armed. The gate re-arms the PR itself once the beta is built, so leave it to the gate" ;;
    - | "") ;;
    *) die "$pr carries an unknown hold ($gate); auto-merge was NOT armed" ;;
  esac
  case "$pr_state" in
    OPEN) ;;
    MERGED)
      echo "agent-app: $pr is already merged"
      return 0 ;;
    *) die "$pr is ${pr_state:-unknown}, not open; auto-merge was NOT armed" ;;
  esac

  local args=("$@")
  [ "$auto" = 1 ] || args+=(--auto)
  [ "$method" = 1 ] || args+=(--squash)
  gh_as pr merge "${args[@]}" || die "gh pr merge failed; auto-merge was NOT armed on $pr"

  # GitHub moves a PR from auto-merge into the queue on its own; between the
  # two, for a moment, a read can see neither. So ask a few times.
  local state tries="${AGENT_APP_VERIFY_TRIES:-5}" a b
  for ((i = 1; i <= tries; i++)); do
    # shellcheck disable=SC2016 # $id is a GraphQL variable, not a shell one.
    state="$(gh_as api graphql -f id="$id" -f query='
      query($id: ID!) { node(id: $id) { ... on PullRequest {
        state
        autoMergeRequest { mergeMethod enabledBy { login } }
        mergeQueueEntry { position state }
      } } }' --jq '.data.node |
        if .mergeQueueEntry then "queue \(.mergeQueueEntry.position) \(.mergeQueueEntry.state)"
        elif .autoMergeRequest then "auto \(.autoMergeRequest.enabledBy.login // "unknown") \(.autoMergeRequest.mergeMethod)"
        else "none \(.state)" end')" || state=""
    case "$state" in
      queue\ *)
        read -r _ a b <<<"$state"
        echo "agent-app: $pr is in the merge queue (mergeQueueEntry: position $a, $b)"
        return 0 ;;
      auto\ *)
        read -r _ a b <<<"$state"
        echo "agent-app: $pr has auto-merge armed by $a (autoMergeRequest: $b); it joins the merge queue when its checks pass"
        return 0 ;;
      "none MERGED")
        echo "agent-app: $pr is already merged"
        return 0 ;;
    esac
    if [ "$i" -lt "$tries" ]; then sleep "${AGENT_APP_VERIFY_SLEEP:-2}"; fi
  done
  die "gh reported success, but GitHub shows neither autoMergeRequest nor mergeQueueEntry on $pr (${state:-no answer}); it is NOT queued"
}

# cmd_pr_hold keeps a PR from merging until someone releases it:
#
#   bazel run //tools/agent-app -- pr-hold 123 --reason "waiting on #120"
#   bazel run //tools/agent-app -- pr-unhold 123     # then pr-enqueue 123
#
# Order matters. The label goes on FIRST: the release gates re-arm any PR
# that does not carry it, so labelling last would leave a window in which a
# gate turning green re-arms what this just turned off. Then auto-merge goes
# off. Then the PR is read again and, if it is in the merge queue, taken out:
# turning auto-merge off does not do that, and an armed PR can enter the
# queue at any moment, including while turning auto-merge off is failing.
#
# Then it reads the PR back and fails unless GitHub shows all three: the
# label on, no auto-merge, no queue entry. The reason, if given, is posted
# only after that, so a comment never announces a hold that did not take.
#
# pr-unhold removes the label and nothing else. It does NOT re-arm auto-merge:
# releasing a hold and landing the PR are separate decisions, so the caller
# runs pr-enqueue when it is time.

# hold_args parses what pr-hold and pr-unhold accept after the PR: --reason
# (pr-hold only) and --repo. Anything else is refused rather than guessed at.
hold_args() {
  local usage="$1" allow_reason="$2"
  shift 2
  REASON=""
  REPO_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason | --reason=*)
        [ "$allow_reason" = 1 ] || die "usage: $usage   (unexpected '$1')"
        if [ "$1" = --reason ]; then
          [ $# -ge 2 ] || die "usage: $usage"
          REASON="$2"
          shift
        else
          REASON="${1#--reason=}"
        fi
        ;;
      -R | --repo)
        [ $# -ge 2 ] || die "usage: $usage"
        REPO_ARGS=(--repo "$2")
        shift
        ;;
      --repo=*) REPO_ARGS=(--repo "${1#--repo=}") ;;
      *) die "usage: $usage   (unexpected '$1')" ;;
    esac
    shift
  done
}

cmd_pr_hold() {
  local usage="pr-hold [--agent <agent>] <pr> [--reason <s>]"
  take_agent "$@" || die "usage: $usage"
  shift "$AGENT_SHIFT"
  need_target pr "$usage" "${1:-}"
  local pr="$1"
  shift
  hold_args "$usage" 1 "$@"

  mint_token "$AGENT" "the PR was NOT held"
  to_caller_dir
  local repo=(${REPO_ARGS[@]+"${REPO_ARGS[@]}"}) id st auto queue label state
  id="$(pr_node_id "$pr" ${repo[@]+"${repo[@]}"})" || die "could not look $pr up; the PR was NOT held"
  st="$(hold_state "$id")" || die "could not read $pr from GitHub; the PR was NOT held"
  read -r auto queue label state _ <<<"$st"
  [ "$state" = OPEN ] || die "$pr is ${state:-unknown}, not open; nothing to hold"

  # 1. The label, so no gate re-arms the PR while the rest happens.
  if [ "$label" != true ]; then
    gh_as pr edit "$pr" ${repo[@]+"${repo[@]}"} --add-label "$HOLD_LABEL" >/dev/null ||
      die "could not add $HOLD_LABEL to $pr; nothing was changed and the PR is NOT held"
  fi
  # 2. Auto-merge off. A failure is not the end: step 3 still runs, so a PR
  # that slipped into the queue meanwhile is taken out of it.
  local disable_failed=0
  if [ "$auto" = true ]; then
    gh_as pr merge "$pr" ${repo[@]+"${repo[@]}"} --disable-auto >/dev/null || disable_failed=1
  fi
  # 3. Out of the queue, read afresh.
  st="$(hold_state "$id")" || die "could not read $pr back from GitHub; it is labelled, but check the hold by hand"
  read -r auto queue label state _ <<<"$st"
  local dequeued=""
  if [ "$queue" = true ]; then
    # shellcheck disable=SC2016 # $id is a GraphQL variable, not a shell one.
    gh_as api graphql -f id="$id" -f query='
      mutation($id: ID!) { dequeuePullRequest(input: {id: $id}) { mergeQueueEntry { id } } }' >/dev/null ||
      die "could not take $pr out of the merge queue; it is labelled but NOT held"
    dequeued=" and taken out of the merge queue"
  fi
  [ "$disable_failed" = 0 ] ||
    die "could not turn auto-merge off on $pr; it is labelled${dequeued}, but NOT held: it can still merge"

  # 4. What GitHub says now is the answer.
  st="$(hold_state "$id")" || die "could not read $pr back from GitHub; check the hold by hand"
  read -r auto queue label state _ <<<"$st"
  [ "$auto" = false ] && [ "$queue" = false ] && [ "$label" = true ] ||
    die "GitHub still shows auto-merge armed: $auto, in the merge queue: $queue, $HOLD_LABEL: $label; $pr is NOT held"
  echo "agent-app: $pr is held: $HOLD_LABEL on, auto-merge off, not in the merge queue"

  if [ -n "$REASON" ]; then
    gh_as pr comment "$pr" ${repo[@]+"${repo[@]}"} --body "Held by the $AGENT agent: $REASON

The \`$HOLD_LABEL\` label is on and auto-merge is off. To release it: \`bazel run //tools/agent-app -- pr-unhold $pr\`, then \`pr-enqueue $pr\` when it should land." >/dev/null ||
      die "$pr is held, but the reason was NOT posted"
  fi
}

cmd_pr_unhold() {
  local usage="pr-unhold [--agent <agent>] <pr>"
  take_agent "$@" || die "usage: $usage"
  shift "$AGENT_SHIFT"
  need_target pr "$usage" "${1:-}"
  local pr="$1"
  shift
  hold_args "$usage" 0 "$@"

  mint_token "$AGENT" "the hold was NOT released"
  to_caller_dir
  local repo=(${REPO_ARGS[@]+"${REPO_ARGS[@]}"}) id st auto queue label state
  id="$(pr_node_id "$pr" ${repo[@]+"${repo[@]}"})" || die "could not look $pr up; the hold was NOT released"
  gh_as pr edit "$pr" ${repo[@]+"${repo[@]}"} --remove-label "$HOLD_LABEL" >/dev/null ||
    die "could not remove $HOLD_LABEL from $pr; the hold was NOT released"
  st="$(hold_state "$id")" || die "could not read $pr back from GitHub; check the label by hand"
  read -r auto queue label state _ <<<"$st"
  [ "$label" = false ] || die "GitHub still shows $HOLD_LABEL on $pr; the hold was NOT released"
  echo "agent-app: $pr: $HOLD_LABEL removed. Auto-merge was NOT re-armed; run pr-enqueue $pr when it should land"
}

# cmd_run_rerun, cmd_run_cancel: re-run or cancel a workflow run as the agent.
#
#   bazel run //tools/agent-app -- run-rerun 18000000000 --failed
#   bazel run //tools/agent-app -- run-cancel 18000000000
#
# Both need Actions write, which only some Apps have; see need_actions_write.
run_passthrough() {
  local verb="$1" usage="$2" not_done="$3"
  shift 3
  take_agent "$@" || die "usage: $usage"
  shift "$AGENT_SHIFT"
  [[ "${1:-}" =~ ^[0-9]+$ ]] || die "usage: $usage   (<run-id> is the number in the run's URL)"
  need_actions_write "$AGENT"
  mint_token "$AGENT" "$not_done"
  to_caller_dir
  exec_gh_as run "$verb" "$@"
}
cmd_run_rerun() { run_passthrough rerun "run-rerun [--agent <agent>] <run-id> [--failed] [--job <id>]" "the run was NOT re-run" "$@"; }
cmd_run_cancel() { run_passthrough cancel "run-cancel [--agent <agent>] <run-id>" "the run was NOT cancelled" "$@"; }

# cmd_workflow_run starts a workflow by hand, as the agent, but only one listed
# in workflow-allowlist.txt. Starting a workflow can deploy, publish or push to
# other repositories; the list is the set an agent may start without asking,
# and it changes by pull request like any other code.
#
#   bazel run //tools/agent-app -- workflow-run catalog-bump.yaml
#   bazel run //tools/agent-app -- workflow-run delivery-drift.yaml --ref main -f k=v
#
# The workflow is named by its file name, exactly as listed: gh would also
# accept a display name or an id, and an allowlist that has to match three
# spellings is one that can be got round. For the same reason the only
# arguments taken are inputs (-f/-F) and --ref main: another ref runs THAT
# branch's copy of the workflow, which can be anything, and --repo would start
# a workflow in another repository the allowlist knows nothing about.
cmd_workflow_run() {
  local usage="workflow-run [--agent <agent>] <workflow.yaml> [-f k=v ...] [--ref main]"
  take_agent "$@" || die "usage: $usage"
  shift "$AGENT_SHIFT"
  need_target workflow "$usage" "${1:-}"
  local wf="$1"
  shift
  local args=("$@") ref
  while [ $# -gt 0 ]; do
    case "$1" in
      -f | -F | --raw-field | --field)
        [ $# -ge 2 ] || die "usage: $usage"
        shift ;;
      -f?* | -F?* | --raw-field=* | --field=*) ;;
      --ref | -r | --ref=* | -r?*)
        case "$1" in
          --ref | -r)
            [ $# -ge 2 ] || die "usage: $usage"
            ref="$2"
            shift ;;
          --ref=*) ref="${1#--ref=}" ;;
          *) ref="${1#-r}" ;;
        esac
        [ "$ref" = main ] ||
          die "refusing --ref $ref: another ref runs that branch's copy of the workflow. Only main; nothing was run" ;;
      -R | -R?* | --repo | --repo=*)
        die "refusing $1: workflow-run starts workflows in this repository only; nothing was run" ;;
      *) die "usage: $usage   (unexpected '$1')" ;;
    esac
    shift
  done
  [ -r "$WORKFLOW_ALLOWLIST" ] || die "cannot read $WORKFLOW_ALLOWLIST; nothing was run"
  local allowed
  allowed="$(awk '!/^#/ && NF {print $1}' "$WORKFLOW_ALLOWLIST")"
  grep -qxF -- "$wf" <<<"$allowed" ||
    die "refusing to start '$wf': not in $(basename "$WORKFLOW_ALLOWLIST") (allowed: ${allowed//$'\n'/, })"
  need_actions_write "$AGENT"
  mint_token "$AGENT" "the workflow was NOT started"
  to_caller_dir
  exec_gh_as workflow run "$wf" ${args[@]+"${args[@]}"}
}

# cmd_branch_delete deletes branches on GitHub, as the agent, and only branches
# whose work is already on main:
#
#   bazel run //tools/agent-app -- branch-delete --agent atlas old/branch other/branch
#
# Each branch must pass `landed --remote-branch`: the proofs //tools/worktree
# uses before it deletes a local branch, asked of origin's copy. There is no
# override. A branch that fails holds work main does not have, and deleting
# that is a person's call, made on GitHub. Also refused: main, a name that is
# not a plain branch name, and a branch with an open PR (pr-close <n>
# --delete-branch closes it and deletes the branch). A merge-queue branch
# (gh-readonly-queue/<base>/pr-<n>-<sha>) is deleted once PR <n> is merged or
# closed: GitHub made it for that PR's queue entry, and nothing reads it after.
#
# GitHub cannot delete a ref only if it still points where it did, so the SHA
# is read again just before each delete, and a branch that moved since it was
# checked is kept. Branches that pass are deleted even when others are kept;
# the command fails if any was kept.
BRANCH_NAME_RE='^[A-Za-z0-9._][A-Za-z0-9._/-]*$'

# remote_sha prints the branch's SHA on GitHub, or fails. Only a 40-hex SHA
# counts: a failed read prints gh's error body, the same text both times,
# which must never pass for "unchanged".
remote_sha() {
  local sha
  sha="$(gh_as api "repos/{owner}/{repo}/git/ref/heads/$1" --jq .object.sha 2>/dev/null)" || return 1
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s' "$sha"
}

cmd_branch_delete() {
  local usage="branch-delete [--agent <agent>] <branch>..."
  take_agent "$@" || die "usage: $usage"
  shift "$AGENT_SHIFT"
  need_target branch "$usage" "${1:-}"
  [ -r "$AGENT_APP_LANDED" ] || die "cannot read $AGENT_APP_LANDED; nothing was deleted"
  mint_token "$AGENT" "nothing was deleted"
  to_caller_dir
  local br open pr state gate sha now kept=0
  for br in "$@"; do
    if ! [[ "$br" =~ $BRANCH_NAME_RE ]] || [[ "$br" == refs/* ]] || [[ "$br" == *..* ]]; then
      echo "kept $br: not a plain branch name" >&2
      kept=$((kept + 1))
      continue
    fi
    case "$br" in main | master | HEAD)
      echo "kept $br: never deleted" >&2
      kept=$((kept + 1))
      continue ;;
    esac
    if ! open="$(gh_as pr list --head "$br" --state open --json number --jq '.[].number')"; then
      echo "kept $br: could not ask GitHub for its open pull requests" >&2
      kept=$((kept + 1))
      continue
    fi
    if [ -n "$open" ]; then
      echo "kept $br: PR #${open//$'\n'/, #} is open on it; to close it and delete the branch: pr-close ${open%%$'\n'*} --delete-branch" >&2
      kept=$((kept + 1))
      continue
    fi
    if [[ "$br" =~ ^gh-readonly-queue/[^/]+/pr-([0-9]+)- ]]; then
      pr="${BASH_REMATCH[1]}"
      state="$(gh_as pr view "$pr" --json state --jq .state 2>/dev/null || true)"
      case "$state" in
        MERGED | CLOSED) ;;
        *)
          echo "kept $br: the merge-queue branch of PR #$pr, which is ${state:-unreadable}" >&2
          kept=$((kept + 1))
          continue ;;
      esac
      if ! sha="$(remote_sha "$br")"; then
        echo "kept $br: could not read its SHA on GitHub" >&2
        kept=$((kept + 1))
        continue
      fi
    else
      if ! gate="$(GH_TOKEN="$TOKEN" GITHUB_TOKEN="" bash "$AGENT_APP_LANDED" --remote-branch "$br" 2>&1)"; then
        echo "kept $br: not landed" >&2
        printf '    %s\n' "${gate//$'\n'/$'\n'    }" >&2
        kept=$((kept + 1))
        continue
      fi
      sha="$(git rev-parse --verify -q "refs/remotes/origin/$br^{commit}" || true)"
    fi
    if ! now="$(remote_sha "$br")"; then
      echo "kept $br: could not read its SHA on GitHub" >&2
      kept=$((kept + 1))
      continue
    fi
    if [ -z "$sha" ] || [ "$now" != "$sha" ]; then
      echo "kept $br: it moved since it was checked (${sha:0:8} -> ${now:0:8}); run again" >&2
      kept=$((kept + 1))
      continue
    fi
    if gh_as api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$br" >/dev/null; then
      echo "deleted $br (${sha:0:8})"
    else
      echo "kept $br: GitHub refused the delete" >&2
      kept=$((kept + 1))
    fi
  done
  [ "$kept" -eq 0 ] || die "$kept branch(es) kept; see above"
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
    pr-create) cmd_pr_create "$@" ;;
    pr-edit) cmd_pr_edit "$@" ;;
    pr-comment) cmd_pr_comment "$@" ;;
    pr-ready) cmd_pr_ready "$@" ;;
    pr-close) cmd_pr_close "$@" ;;
    pr-enqueue) cmd_pr_enqueue "$@" ;;
    pr-hold) cmd_pr_hold "$@" ;;
    pr-unhold) cmd_pr_unhold "$@" ;;
    run-rerun) cmd_run_rerun "$@" ;;
    run-cancel) cmd_run_cancel "$@" ;;
    workflow-run) cmd_workflow_run "$@" ;;
    branch-delete) cmd_branch_delete "$@" ;;
    -h | --help | help) usage 0 ;;
    *) die "unknown command: $cmd (try --help)" ;;
  esac
}

main "$@"
