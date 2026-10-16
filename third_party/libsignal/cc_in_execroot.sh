#!/bin/sh
# Copyright 2026 VitruvianSoftware
# Upstream: https://github.com/signalapp/libsignal (AGPL-3.0-only); this file
# is build glue for it, under the same licence.
# SPDX-License-Identifier: AGPL-3.0-only
#
# C compiler for cc-rs inside Bazel cargo build scripts (see the ring
# annotation in MODULE.bazel): run the toolchain's $CC from the execroot so its
# execroot-relative flags resolve. cc-rs passes absolute paths for everything
# else.
set -eu
cd "$COURIER_BAZEL_EXECROOT"
exec "$CC" "$@"
