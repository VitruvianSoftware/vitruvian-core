#!/usr/bin/env bash
set -euo pipefail

# Ensure standard user tool paths are accessible in Bazel sandbox
USER_HOME="${HOME:-}"
if [[ -z "${USER_HOME}" || "${USER_HOME}" == "/nonexistent" ]]; then
  if [[ -n "${USER:-}" ]]; then
    USER_HOME="$(eval echo "~${USER}")"
  elif [[ -n "${LOGNAME:-}" ]]; then
    USER_HOME="$(eval echo "~${LOGNAME}")"
  else
    USER_HOME="/tmp"
  fi
fi
export HOME="${USER_HOME}"
export PATH="${USER_HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
if [[ -z "${PLATFORMIO_CORE_DIR:-}" ]]; then
  if [[ -d "${USER_HOME}/.platformio" ]]; then
    export PLATFORMIO_CORE_DIR="${USER_HOME}/.platformio"
  elif [[ -d "/Users/james/.platformio" ]]; then
    export PLATFORMIO_CORE_DIR="/Users/james/.platformio"
  else
    export PLATFORMIO_CORE_DIR="${USER_HOME}/.platformio"
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
OUT_FIRMWARE=""
OUT_BOOTLOADER=""
OUT_PARTITIONS=""
OUT_ZIP=""
VERSION="${VERSION:-}"
GRADE="${GRADE:-beta}"

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
    --out_zip)
      OUT_ZIP="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --grade)
      GRADE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Convert relative paths to absolute if needed
if [[ -n "${OUT_FIRMWARE}" && "${OUT_FIRMWARE}" != /* ]]; then
  OUT_FIRMWARE="$(pwd)/${OUT_FIRMWARE}"
fi
if [[ -n "${OUT_BOOTLOADER}" && "${OUT_BOOTLOADER}" != /* ]]; then
  OUT_BOOTLOADER="$(pwd)/${OUT_BOOTLOADER}"
fi
if [[ -n "${OUT_PARTITIONS}" && "${OUT_PARTITIONS}" != /* ]]; then
  OUT_PARTITIONS="$(pwd)/${OUT_PARTITIONS}"
fi
if [[ -n "${OUT_ZIP}" && "${OUT_ZIP}" != /* ]]; then
  OUT_ZIP="$(pwd)/${OUT_ZIP}"
fi

# Locate PlatformIO
PIO_CMD=""
if command -v pio &>/dev/null; then
  PIO_CMD="pio"
elif [[ -x "${USER_HOME}/.local/bin/pio" ]]; then
  PIO_CMD="${USER_HOME}/.local/bin/pio"
elif command -v uv &>/dev/null; then
  PIO_CMD="uv run --with platformio platformio"
elif python3 -m platformio --version &>/dev/null; then
  PIO_CMD="python3 -m platformio"
else
  echo "Error: PlatformIO not found. Install via: uv tool install platformio OR pip install platformio" >&2
  exit 1
fi

echo "=== Building ESP32-S3 Firmware [Grade: ${GRADE}] ==="
echo "Project directory: ${PROJECT_DIR}"
echo "PlatformIO core:   ${PLATFORMIO_CORE_DIR}"

# Run PlatformIO build
${PIO_CMD} run -d "${PROJECT_DIR}"

BUILD_DIR="${PROJECT_DIR}/.pio/build/esp32s3"
if [[ ! -f "${BUILD_DIR}/firmware.bin" ]]; then
  echo "Error: Build finished but ${BUILD_DIR}/firmware.bin not found!" >&2
  exit 1
fi

# Determine Git SHA & Version
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
if [[ -z "${VERSION}" ]]; then
  if [[ -f "${PROJECT_DIR}/.release-please-manifest.json" ]]; then
    VERSION="$(grep -o '"[0-9]*\.[0-9]*\.[0-9]*"' "${PROJECT_DIR}/.release-please-manifest.json" | tr -d '"' || true)"
  fi
  if [[ -z "${VERSION}" ]]; then
    VERSION="0.1.0"
  fi
  if [[ "${GRADE}" == "beta" ]]; then
    SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo "dev")"
    VERSION="${VERSION}-beta.${SHORT_SHA}"
  fi
fi

BUILT_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Copy output files if requested
if [[ -n "${OUT_FIRMWARE}" ]]; then
  mkdir -p "$(dirname "${OUT_FIRMWARE}")"
  cp "${BUILD_DIR}/firmware.bin" "${OUT_FIRMWARE}"
fi

if [[ -n "${OUT_BOOTLOADER}" ]]; then
  mkdir -p "$(dirname "${OUT_BOOTLOADER}")"
  cp "${BUILD_DIR}/bootloader.bin" "${OUT_BOOTLOADER}"
fi

if [[ -n "${OUT_PARTITIONS}" ]]; then
  mkdir -p "$(dirname "${OUT_PARTITIONS}")"
  cp "${BUILD_DIR}/partitions.bin" "${OUT_PARTITIONS}"
fi

# Package zip bundle if requested
if [[ -n "${OUT_ZIP}" ]]; then
  STAGE_DIR="$(mktemp -d)"
  trap 'rm -rf "${STAGE_DIR}"' EXIT

  cp "${BUILD_DIR}/firmware.bin" "${STAGE_DIR}/firmware.bin"
  cp "${BUILD_DIR}/bootloader.bin" "${STAGE_DIR}/bootloader.bin"
  cp "${BUILD_DIR}/partitions.bin" "${STAGE_DIR}/partitions.bin"

  cat << EOF_JSON > "${STAGE_DIR}/build_info.json"
{
  "version": "${VERSION}",
  "grade": "${GRADE}",
  "commit": "${GIT_SHA}",
  "builtAt": "${BUILT_AT}",
  "board": "Waveshare ESP32-S3-Touch-LCD-1.69",
  "mcu": "ESP32-S3",
  "flash_size": "16MB",
  "framework": "arduino",
  "lvgl_version": "8.4.0"
}
EOF_JSON

  cat << 'EOF_FLASH' > "${STAGE_DIR}/flash.sh"
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-}"

if [[ -z "${PORT}" ]]; then
  PORT=$(ls /dev/cu.usbmodem* /dev/ttyACM* 2>/dev/null | head -n 1 || true)
fi

if [[ -z "${PORT}" ]]; then
  echo "Error: No ESP32-S3 serial port detected. Specify explicitly:"
  echo "  ./flash.sh /dev/cu.usbmodemXXXX"
  exit 1
fi

echo "=================================================="
echo "Flashing ESP32-S3 Mac Desktop Companion"
echo "Port: ${PORT}"
echo "=================================================="

ESPTOOL_CMD=""
if command -v esptool &>/dev/null; then
  ESPTOOL_CMD="esptool"
elif command -v uvx &>/dev/null; then
  ESPTOOL_CMD="uvx esptool"
elif python3 -m esptool --help &>/dev/null; then
  ESPTOOL_CMD="python3 -m esptool"
else
  echo "Error: esptool is required. Install via 'uv tool install esptool' or 'pip install esptool'."
  exit 1
fi

${ESPTOOL_CMD} -p "${PORT}" -b 460800 --before default_reset --after hard_reset write_flash \
  0x0000 "${SCRIPT_DIR}/bootloader.bin" \
  0x8000 "${SCRIPT_DIR}/partitions.bin" \
  0x10000 "${SCRIPT_DIR}/firmware.bin"

echo "Flash complete! Device should reboot into Mac Desktop Companion."
EOF_FLASH

  chmod +x "${STAGE_DIR}/flash.sh"

  mkdir -p "$(dirname "${OUT_ZIP}")"
  (cd "${STAGE_DIR}" && zip -q -r "${OUT_ZIP}" .)
  echo "Packaged distribution zip: ${OUT_ZIP}"
fi

echo "=== Firmware Build Successful [${VERSION} (${GRADE})] ==="
