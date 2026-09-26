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

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A lighter CCTV testing preset; startup, credentials, and LAN warnings belong
# to the normal launcher. Explicit environment overrides remain supported.
export CCTV_SOURCES_FILE="${CCTV_SOURCES_FILE:-config/cctv_sources.austin.json}"
export CCTV_PREFER_AUSTIN="${CCTV_PREFER_AUSTIN:-1}"
export CCTV_AUSTIN_MAX_SOURCES="${CCTV_AUSTIN_MAX_SOURCES:-36}"
export CCTV_MAX_SOURCES="${CCTV_MAX_SOURCES:-48}"

exec bash "$ROOT_DIR/scripts/dev-fresh.sh"
