#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Generic Pulumi subcommand wrapper — invoked via `bazel run`, never directly.
#
# The calling `sh_binary` bakes in two leading args via `args = [<dir>, <subcmd>]`:
#   $1  workspace-relative path to the Pulumi project directory
#   $2  the pulumi subcommand to run (preview|up|destroy|refresh|config|...)
# Anything a developer appends after `--` is forwarded verbatim to pulumi, e.g.
#   bazel run //infrastructure/pulumi/platform/repo_config:up -- --stack dev --yes
#
# Pulumi compiles and runs the Go program itself; Bazel only launches the CLI
# from the real workspace tree (not the sandboxed runfiles dir).
set -euo pipefail

# `bazel run` executes from the runfiles dir; operate on the project dir instead.
PROJECT_DIR="$1"
SUBCMD="$2"
shift 2

if ! command -v pulumi >/dev/null 2>&1; then
  echo "pulumi CLI not found on PATH. Run 'bazel run //$PROJECT_DIR:setup' first," >&2
  echo "or install it from https://www.pulumi.com/docs/install/." >&2
  exit 1
fi

cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be invoked via 'bazel run', not 'bazel test'}/$PROJECT_DIR"

# These Pulumi modules are standalone Go modules (their own go.mod), deliberately
# kept out of any repo-level go.work. Disable workspace mode so Pulumi's internal
# `go build` resolves dependencies from THIS module — otherwise, inside a monorepo
# that has a go.work, the build fails with "not a known dependency".
export GOWORK=off

# --- GCP identity injection -------------------------------------------------
# Pin GCP auth to the account declared for this project in
# infrastructure/gcp-identities.tsv, so it never depends on the ambient `gcloud`
# account. The resolver is read from the workspace tree (consistent with how
# this wrapper already runs the working-tree Go program). Projects not listed in
# the map are unaffected.
_id_map="${BUILD_WORKSPACE_DIRECTORY}/infrastructure/gcp-identities.tsv"
_id_resolver="${BUILD_WORKSPACE_DIRECTORY}/tools/pulumi/resolve_identity.sh"
if [ -n "${GOOGLE_OAUTH_ACCESS_TOKEN:-}" ] || [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] || [ -n "${CLOUDSDK_AUTH_ACCESS_TOKEN:-}" ]; then
  # Ambient GCP credentials are already present -- do NOT override with a pinned
  # per-identity token. Two cases:
  #   * CI: google-github-actions/auth (keyless WIF) exports
  #     GOOGLE_APPLICATION_CREDENTIALS pointing at the WIF credential file, so the
  #     job runs as its per-env deploy SA -- exactly what the gcp-identities.tsv
  #     rows for the app dirs note ("CI runs as the per-env deploy SA").
  #   * Break-glass local: an operator (or a wrapping deploy target) exports
  #     GOOGLE_OAUTH_ACCESS_TOKEN itself, e.g. an ADC token when the pinned
  #     account's user token can't be interactively refreshed
  #     (`GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth application-default print-access-token)`).
  # This is what lets CI and a laptop run the SAME deploy code path -- auth is
  # chosen at the edge, not baked into the wrapper. Pure-local runs (no ambient
  # creds) still get the deterministic gcp-identities.tsv pin below.
  echo "→ GCP auth: ambient credentials present -- honoring them (skipping the gcp-identities.tsv pin) for $PROJECT_DIR" >&2
elif [ -f "$_id_map" ] && [ -f "$_id_resolver" ]; then
  IFS=$'\t' read -r _gcp_account _gcp_project < <(bash "$_id_resolver" "$_id_map" "$PROJECT_DIR") || true
  if [ -n "${_gcp_account:-}" ]; then
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "ERROR: $PROJECT_DIR is pinned to GCP identity '$_gcp_account'" >&2
      echo "(infrastructure/gcp-identities.tsv) but the gcloud CLI is not installed:" >&2
      echo "    https://cloud.google.com/sdk/docs/install" >&2
      exit 1
    fi
    # //tools/gcp-token resolves the token the same way everywhere: local gcloud
    # first, then — when this machine has no credentials of its own, i.e. a Claude
    # Code cloud session — minted over the tailnet from a homelab node that does.
    # That is what lets a cloud session run this wrapper at all: the org enforces
    # iam.disableServiceAccountKeyCreation, so there is no key to hand a sandbox,
    # and the session holds only a ~1h token instead. See tools/gcp-token/README.md.
    _minter="${BUILD_WORKSPACE_DIRECTORY}/tools/gcp-token/gcp-token.sh"
    if [ -x "$_minter" ]; then
      _gcp_token="$(bash "$_minter" "$_gcp_account")" || _gcp_token=""
    else
      _gcp_token="$(gcloud auth print-access-token --account="$_gcp_account" 2>/dev/null)" || _gcp_token=""
    fi
    if [ -z "$_gcp_token" ]; then
      echo "ERROR: $PROJECT_DIR is pinned to GCP identity '$_gcp_account'" >&2
      echo "(infrastructure/gcp-identities.tsv) but no valid credentials were found," >&2
      echo "locally or via the tailnet broker (see the checklist above)." >&2
      echo "Log in with:  gcloud auth login $_gcp_account" >&2
      exit 1
    fi
    export GOOGLE_OAUTH_ACCESS_TOKEN="$_gcp_token"
    if [ -n "${_gcp_project:-}" ] && [ "$_gcp_project" != "-" ]; then
      export GOOGLE_CLOUD_PROJECT="$_gcp_project" CLOUDSDK_CORE_PROJECT="$_gcp_project"
    fi
    echo "→ GCP identity: $_gcp_account (project ${_gcp_project:-unset}) for $PROJECT_DIR" >&2
  fi
fi
# ---------------------------------------------------------------------------

# --- dev-local cluster + backend + stack pin -------------------------------
# The dev-local project targets the local k3s cluster (kubeconfig context
# "default"), the Pulumi Cloud backend, and the "local" stack. Pin all three
# here so `bazel run //…dev-local:*` self-targets them regardless of the
# ambient environment, the global pulumi `current` backend, or which
# checkout it runs from — mirroring the gitops wrapper (tools/gitops/gitops_cmd.sh),
# which already defaults KUBECONFIG the same way. Without this, a shell that lacks
# an explicit KUBECONFIG falls back to a dead context and Pulumi can't reach the
# cluster — the Helm provider then defaults to kubeVersion v1.20.0 and chart
# templating fails. Other Pulumi projects are unaffected; a caller-supplied
# --stack/-s still wins.
if [ "$PROJECT_DIR" = "infrastructure/pulumi/platform/dev-local" ]; then
  : "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
  export KUBECONFIG
  # The dev-local stack (ipv1337/monorepo/local) lives in the Pulumi Cloud
  # backend, but `current` in ~/.pulumi/credentials.json is GLOBAL state shared
  # with every other Pulumi project/session — a sibling project on the file
  # backend (`pulumi login --local`) flips it, so `--stack local` then resolves
  # against the wrong backend ("no stack named 'local' found"). Pin the cloud
  # backend so dev-local is immune. An explicit PULUMI_BACKEND_URL still wins.
  : "${PULUMI_BACKEND_URL:=https://api.pulumi.com}"
  export PULUMI_BACKEND_URL
  # Default --stack to "local" unless the caller already chose a stack. Match
  # whole flag tokens (space- and equals-forms) so a forwarded VALUE containing
  # "--stack"/"-s" can't false-match, and so an explicit --stack=NAME isn't
  # silently overridden by an appended "--stack local" (cobra is last-wins).
  _has_stack=
  for _a in "$@"; do
    case "$_a" in --stack|--stack=*|-s|-s=*) _has_stack=1; break ;; esac
  done
  [ -n "$_has_stack" ] || set -- --stack local "$@"
fi

# --- foundation stacks: Pulumi Cloud (ipv1337) backend + org pin ------------
# The foundation stages (gcp-bootstrap, gcp-org, org-folders, gcp-environments,
# gcp-networks) all live on the Pulumi Cloud backend under org `ipv1337` (see
# each project's BUILD: "Backend: Pulumi Cloud (ipv1337)"). As with dev-local
# above, `current` in ~/.pulumi/credentials.json is GLOBAL state shared with
# every other Pulumi project — a sibling project on a self-managed backend
# (`pulumi login --local`, which dev-local's README instructs) flips it. A bare
# `--stack development` then resolves against that wrong backend, so `pulumi
# stack ls` lists an unrelated `organization/…` (the self-managed backend's
# pseudo-org) instead of the foundation stacks. Pin the cloud backend so these
# projects self-target it, and org-qualify a bare `--stack NAME` to
# `ipv1337/NAME` so it resolves regardless of the caller's Pulumi default org
# (the multi-env stacks are selected as `development`/`nonproduction`/
# `production`, not fully qualified). An explicit PULUMI_BACKEND_URL, or a
# `--stack` value that is already org-qualified (`org/NAME`), still wins.
case "$PROJECT_DIR" in
  infrastructure/pulumi/foundation/*)
    : "${PULUMI_BACKEND_URL:=https://api.pulumi.com}"
    export PULUMI_BACKEND_URL

    # Rebuild the forwarded args, qualifying a bare `--stack`/`-s` value with the
    # `ipv1337/` org. Rotate the positional params (consume one from the front,
    # append one to the back, exactly $# times) so this stays bash 3.2-safe (no
    # arrays) and preserves order. Handles `--stack NAME`, `--stack=NAME`,
    # `-s NAME`, and `-s=NAME`; a value already containing `/` is left as-is.
    _n=$#
    _i=0
    _want_stack_value=
    while [ "$_i" -lt "$_n" ]; do
      _a="$1"
      shift
      _i=$((_i + 1))
      if [ -n "$_want_stack_value" ]; then
        case "$_a" in */*) : ;; *) _a="ipv1337/$_a" ;; esac
        _want_stack_value=
        set -- "$@" "$_a"
        continue
      fi
      case "$_a" in
        --stack | -s)
          _want_stack_value=1
          set -- "$@" "$_a"
          ;;
        --stack=* | -s=*)
          _flag="${_a%%=*}"
          _val="${_a#*=}"
          case "$_val" in */*) : ;; *) _val="ipv1337/$_val" ;; esac
          set -- "$@" "$_flag=$_val"
          ;;
        *)
          set -- "$@" "$_a"
          ;;
      esac
    done
    ;;
esac

# --- concurrent-update (409) retry ------------------------------------------
# Pulumi Cloud INDIVIDUAL accounts serialize updates across the ENTIRE ACCOUNT,
# not per stack: while any one stack is updating, every other stack's update is
# rejected outright with
#
#   error: [409] Conflict: You have a running update for the stack '<other>'.
#   Individual user accounts do not support concurrent updates.
#
# That is a queueing limit, not a failure of this deployment -- so failing the
# job is the wrong response. It cost a PRODUCTION promotion on 2026-08-20:
# oauth-user-inspector v1.11.0's production rollout (run 32355118334) was
# rejected two seconds after an unrelated tabula-web DEVELOPMENT update began,
# and production stayed on the previous revision. See
# docs/engineering/pulumi-concurrent-updates.md.
#
# Retrying is the deterministic fix HERE, and does not contradict "never re-run
# IaC to fix a race": there is no race between resources to lose. The lock is
# held by a different stack and is guaranteed to be released; we are waiting for
# a queue, and this loop IS the wait. It retries ONLY on that exact 409 text,
# so every other failure -- including a genuine `pulumi up` error -- still fails
# on the first attempt, immediately.
case "$SUBCMD" in
  up | destroy | refresh | import) _lock_retryable=1 ;;
  *) _lock_retryable= ;;
esac

_max_attempts="${PULUMI_LOCK_MAX_ATTEMPTS:-6}"
if [ -z "$_lock_retryable" ] || [ "$_max_attempts" -le 1 ]; then
  exec pulumi "$SUBCMD" "$@"
fi

# Output is combined and teed so the loop can inspect it for the 409 while the
# caller still sees everything live. `set +e` around the pipeline because this
# script runs under `set -e` (and CI adds -o pipefail): we need the exit status
# of pulumi itself, via PIPESTATUS, not tee's.
_attempt=1
_backoff="${PULUMI_LOCK_BACKOFF_SECONDS:-20}"
_out="$(mktemp)"
trap 'rm -f "$_out"' EXIT

while :; do
  set +e
  pulumi "$SUBCMD" "$@" 2>&1 | tee "$_out"
  _rc="${PIPESTATUS[0]}"
  set -e

  [ "$_rc" -eq 0 ] && exit 0

  if [ "$_attempt" -ge "$_max_attempts" ] ||
    ! grep -qiF 'do not support concurrent updates' "$_out"; then
    exit "$_rc"
  fi

  echo "pulumi_cmd: another stack in this Pulumi account is mid-update (409); attempt ${_attempt}/${_max_attempts}, retrying in ${_backoff}s" >&2
  sleep "$_backoff"
  _attempt=$((_attempt + 1))
  _backoff=$((_backoff * 2))
done
