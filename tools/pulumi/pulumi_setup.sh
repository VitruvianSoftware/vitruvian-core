#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Guided Pulumi bootstrap — invoked via `bazel run //<project>:setup`.
#
# The calling `sh_binary` bakes in the project dir via `args = [<dir>]`:
#   $1  workspace-relative path to the Pulumi project directory
#
# This is a pragmatic, idempotent helper — not magic. It checks prerequisites,
# logs you in, helps pick or create a stack, and prints the one-time adoption
# hint. Re-running it is safe.
set -euo pipefail

PROJECT_DIR="${1:?usage: bazel run //<pulumi-project>:setup (dir is baked in by the macro)}"
shift || true

# `bazel run` executes from the runfiles dir; operate on the project dir instead.
cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be invoked via 'bazel run', not 'bazel test'}/$PROJECT_DIR"

echo "Pulumi setup for $PROJECT_DIR"
echo "----------------------------------------------------------------------"

# --- Prerequisites ---------------------------------------------------------
missing=0
if ! command -v pulumi >/dev/null 2>&1; then
  echo "! pulumi CLI not found. Install it: https://www.pulumi.com/docs/install/" >&2
  missing=1
fi
if ! command -v go >/dev/null 2>&1; then
  echo "! go toolchain not found. Install Go: https://go.dev/dl/ (Pulumi compiles the program with it)." >&2
  missing=1
fi
if [ "$missing" -ne 0 ]; then
  echo "Install the missing tool(s) above and re-run this command." >&2
  exit 1
fi
echo "✓ pulumi and go are installed."

# --- Make the standalone module build-ready --------------------------------
# These Pulumi modules are standalone Go modules (own go.mod), deliberately kept
# out of any repo-level go.work. Disable workspace mode so `go mod tidy` (and the
# `go build` Pulumi runs later) resolve from THIS module — otherwise, inside a
# monorepo with a go.work, they fail with "not a known dependency".
export GOWORK=off
echo "Resolving Go dependencies (go mod tidy)…"
go mod tidy
echo "✓ go.sum is up to date."

# --- Login (idempotent) ----------------------------------------------------
if pulumi whoami >/dev/null 2>&1; then
  echo "✓ Already logged in to Pulumi as '$(pulumi whoami 2>/dev/null)'."
else
  echo "Logging in to Pulumi (opens a browser, or use a PULUMI_ACCESS_TOKEN / 'pulumi login --local')…"
  pulumi login
fi

# --- Stack select / create -------------------------------------------------
if pulumi stack --show-name >/dev/null 2>&1; then
  echo "✓ Stack already selected: $(pulumi stack --show-name 2>/dev/null)."
else
  echo
  echo "Available stacks:"
  pulumi stack ls 2>/dev/null || echo "  (none yet)"
  read -r -p "Stack to select or create (e.g. dev): " STACK || true
  STACK="${STACK:-dev}"
  if pulumi stack select "$STACK" >/dev/null 2>&1; then
    echo "✓ Selected existing stack '$STACK'."
  else
    pulumi stack init "$STACK"
    echo "✓ Created and selected stack '$STACK'."
  fi
fi

# --- GitHub provider token (never echoed) ----------------------------------
echo
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "✓ GITHUB_TOKEN is set in the environment (value not shown)."
else
  echo "! GITHUB_TOKEN is NOT set. The GitHub provider needs it. Export a PAT/token"
  echo "  with repo + admin scope before running 'up' (it is read from the env, never stored here):"
  echo "      export GITHUB_TOKEN=<your-token>"
fi

# --- One-time adoption hint (repo_config) ----------------------------------
case "$PROJECT_DIR" in
  *repo_config)
    echo
    echo "Adoption note (repo_config): your repository already exists, so the first"
    echo "'up' IMPORTS it into state rather than creating it. Set the owner first:"
    echo "      bazel run //$PROJECT_DIR:config -- set repoOwner <your-org-or-user>"
    echo "then preview / apply:"
    echo "      bazel run //$PROJECT_DIR:preview"
    echo "      bazel run //$PROJECT_DIR:up"
    echo "If the import fails, fix repoName/repoOwner (and the token's account) and retry —"
    echo "no resource is created until the import resolves."
    ;;
  *)
    echo
    echo "Next steps:"
    echo "      bazel run //$PROJECT_DIR:preview"
    echo "      bazel run //$PROJECT_DIR:up"
    ;;
esac

echo
echo "Done. This helper is safe to re-run any time."
