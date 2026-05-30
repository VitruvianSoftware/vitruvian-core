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

exec pulumi "$SUBCMD" "$@"
