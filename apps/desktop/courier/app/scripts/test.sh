#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Runs CourierCoreTests under SwiftPM. Under Bazel the protocol's files are the test's `data`; here the
# conformance test finds them through COURIER_PROTOCOL_DIR.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export COURIER_PROTOCOL_DIR="${here}/../protocol"

cd "${here}"
exec swift test "$@"
