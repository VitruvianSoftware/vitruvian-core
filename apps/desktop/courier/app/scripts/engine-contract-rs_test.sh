#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Runs the Rust engine-contract binary with the same arguments the shell test
# passes to engine_contract_test.sh.
set -euo pipefail
rust_bin="$1"
shift
exec "$rust_bin" "$@"
