#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# `bazel test` wrapper for a standalone Pulumi Go module — invoked via
# `pulumi_go_test()` (defs.bzl), never directly.
#
# The calling `sh_test` bakes in one arg via `args = [native.package_name()]`:
#   $1  repo-relative path to the Pulumi project directory
#
# Under `bazel test` the CWD is the runfiles root (same convention as
# resolve_identity_test.sh), so that relative path resolves directly — no
# BUILD_WORKSPACE_DIRECTORY dance like the `bazel run` wrappers need.
set -euo pipefail

PROJECT_DIR="$1"
cd "$PROJECT_DIR"

if ! command -v go >/dev/null 2>&1; then
  echo "go toolchain not found on PATH. This target runs locally only" >&2
  echo "(tagged no-remote-exec) and needs a real 'go' install, same as" >&2
  echo "pulumi_cmd.sh needs 'pulumi' on PATH." >&2
  exit 1
fi

# This Pulumi module is a standalone Go module (its own go.mod), deliberately
# kept out of any repo-level go.work (see pulumi_cmd.sh) — disable workspace
# mode so `go test` resolves dependencies from THIS module.
export GOWORK=off

exec go test ./...
