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
#   bazel run //infrastructure/pulumi/repo_config:up -- --stack dev --yes
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
if [ -f "$_id_map" ] && [ -f "$_id_resolver" ]; then
  IFS=$'\t' read -r _gcp_account _gcp_project < <(bash "$_id_resolver" "$_id_map" "$PROJECT_DIR") || true
  if [ -n "${_gcp_account:-}" ]; then
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "ERROR: $PROJECT_DIR is pinned to GCP identity '$_gcp_account'" >&2
      echo "(infrastructure/gcp-identities.tsv) but the gcloud CLI is not installed:" >&2
      echo "    https://cloud.google.com/sdk/docs/install" >&2
      exit 1
    fi
    if ! _gcp_token="$(gcloud auth print-access-token --account="$_gcp_account" 2>/dev/null)"; then
      echo "ERROR: $PROJECT_DIR is pinned to GCP identity '$_gcp_account'" >&2
      echo "(infrastructure/gcp-identities.tsv) but no valid credentials were found." >&2
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

# --- dev-local cluster + stack pin -----------------------------------------
# The dev-local project targets the local k3s cluster (kubeconfig context
# "default") and the "local" stack. Pin both here so `bazel run //…dev-local:*`
# self-targets the cluster/stack regardless of the ambient environment or which
# checkout it runs from — mirroring the gitops wrapper (tools/gitops/gitops_cmd.sh),
# which already defaults KUBECONFIG the same way. Without this, a shell that lacks
# an explicit KUBECONFIG falls back to a dead context and Pulumi can't reach the
# cluster — the Helm provider then defaults to kubeVersion v1.20.0 and chart
# templating fails. Other Pulumi projects are unaffected; a caller-supplied
# --stack/-s still wins.
if [ "$PROJECT_DIR" = "infrastructure/pulumi/dev-local" ]; then
  : "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
  export KUBECONFIG
  case " $* " in
    *" --stack "*|*" -s "*) : ;;
    *) set -- --stack local "$@" ;;
  esac
fi

exec pulumi "$SUBCMD" "$@"
