#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Runs a built binary with arguments as a Bazel test.
#
# usage: run_binary.sh <binary> [args...]
set -euo pipefail

exec "$@"
