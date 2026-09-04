#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-}"

if [[ "${PORT}" == "-h" || "${PORT}" == "--help" ]]; then
  echo "Usage: $0 [/dev/cu.usbmodemXXXX]"
  echo "Flashes ESP32-S3 firmware to the specified port, or auto-detects if omitted."
  exit 0
fi

if [[ -z "${PORT}" ]]; then
  PORT=$(ls /dev/cu.usbmodem* /dev/ttyACM* 2>/dev/null | head -n 1 || true)
fi

if [[ -z "${PORT}" ]]; then
  echo "Error: No ESP32-S3 serial port detected. Specify explicitly:"
  echo "  ./flash.sh /dev/cu.usbmodemXXXX"
  exit 1
fi

echo "=================================================="
echo "Uploading Firmware to ESP32-S3 on ${PORT}"
echo "=================================================="

# Check if pre-compiled binaries exist in runfiles or local directory
BUILD_DIR="${SCRIPT_DIR}/.pio/build/esp32s3"
if [[ -f "${SCRIPT_DIR}/firmware.bin" && -f "${SCRIPT_DIR}/bootloader.bin" && -f "${SCRIPT_DIR}/partitions.bin" ]]; then
  ESPTOOL_CMD=""
  if command -v esptool &>/dev/null; then
    ESPTOOL_CMD="esptool"
  elif command -v uvx &>/dev/null; then
    ESPTOOL_CMD="uvx esptool"
  elif python3 -m esptool --help &>/dev/null; then
    ESPTOOL_CMD="python3 -m esptool"
  fi

  if [[ -n "${ESPTOOL_CMD}" ]]; then
    ${ESPTOOL_CMD} -p "${PORT}" -b 460800 --before default_reset --after hard_reset write_flash \
      0x0000 "${SCRIPT_DIR}/bootloader.bin" \
      0x8000 "${SCRIPT_DIR}/partitions.bin" \
      0x10000 "${SCRIPT_DIR}/firmware.bin"
    exit 0
  fi
fi

# Fall back to PlatformIO upload
PIO_CMD=""
if command -v pio &>/dev/null; then
  PIO_CMD="pio"
elif [[ -x "${HOME}/.local/bin/pio" ]]; then
  PIO_CMD="${HOME}/.local/bin/pio"
elif command -v uv &>/dev/null; then
  PIO_CMD="uv run --with platformio platformio"
fi

if [[ -n "${PIO_CMD}" ]]; then
  ${PIO_CMD} run -d "${SCRIPT_DIR}" --target upload --upload-port "${PORT}"
  exit 0
fi

echo "Error: Neither esptool nor platformio found." >&2
exit 1
