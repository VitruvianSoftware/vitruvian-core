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

# Compile the ESP32-S3 firmware with PlatformIO and copy the three flashable
# images to the paths Bazel asked for. This is the body of the
# //iot/esp32-s3:firmware genrule.
#
# THE GENRULE'S ENVIRONMENT IS NOT YOUR SHELL'S. Bazel hands a `local`-tagged
# action exactly two variables -- PATH=/bin:/usr/bin:/usr/local/bin and TMPDIR
# (verified empirically; there is no --action_env in .bazelrc) -- and the
# execroot has no .git. So this script:
#   * derives the home directory from the passwd database (`~user` expansion),
#     never from HOME/USER, which are absent;
#   * does NOT stamp version/grade/commit -- there is no release context and no
#     git here. Stamping is publish.sh's job, which runs OUTSIDE Bazel with the
#     delivery rung's env, and packages the images this script produces.
set -euo pipefail

USER_HOME="$(eval echo "~$(id -un)")"
export HOME="${HOME:-${USER_HOME}}"
export PATH="${USER_HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-${USER_HOME}/.platformio}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
OUT_FIRMWARE=""
OUT_BOOTLOADER=""
OUT_PARTITIONS=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--project_dir)
		PROJECT_DIR="$2"
		shift 2
		;;
	--out_firmware)
		OUT_FIRMWARE="$2"
		shift 2
		;;
	--out_bootloader)
		OUT_BOOTLOADER="$2"
		shift 2
		;;
	--out_partitions)
		OUT_PARTITIONS="$2"
		shift 2
		;;
	*)
		echo "Unknown argument: $1" >&2
		exit 1
		;;
	esac
done

# `uv tool install platformio` (what CI runs) lands `pio` in ~/.local/bin, which
# is on PATH above. The fallbacks cover a developer machine without it.
PIO_CMD=""
if command -v pio &>/dev/null; then
	PIO_CMD="pio"
elif command -v uvx &>/dev/null; then
	PIO_CMD="uvx --from platformio pio"
elif python3 -m platformio --version &>/dev/null; then
	PIO_CMD="python3 -m platformio"
else
	echo "Error: PlatformIO not found. Install via: uv tool install platformio" >&2
	exit 1
fi

echo "=== Building ESP32-S3 Firmware ==="
echo "Project directory: ${PROJECT_DIR}"
echo "PlatformIO core:   ${PLATFORMIO_CORE_DIR}"

${PIO_CMD} run -d "${PROJECT_DIR}"

BUILD_DIR="${PROJECT_DIR}/.pio/build/esp32s3"
for img in firmware bootloader partitions; do
	if [[ ! -f "${BUILD_DIR}/${img}.bin" ]]; then
		echo "Error: Build finished but ${BUILD_DIR}/${img}.bin not found!" >&2
		exit 1
	fi
done

copy_out() {
	local src="$1" dst="$2"
	[[ -n "${dst}" ]] || return 0
	mkdir -p "$(dirname "${dst}")"
	cp "${src}" "${dst}"
}
copy_out "${BUILD_DIR}/firmware.bin" "${OUT_FIRMWARE}"
copy_out "${BUILD_DIR}/bootloader.bin" "${OUT_BOOTLOADER}"
copy_out "${BUILD_DIR}/partitions.bin" "${OUT_PARTITIONS}"

echo "=== Firmware Build Successful ==="
