# ESP32-S3 Mac Desktop Companion & Touch Controller

Custom firmware for the **Waveshare ESP32-S3-Touch-LCD-1.69** development board, turning it into a desk companion that streams live Mac hardware metrics and triggers native macOS desktop shortcuts via USB HID.

## Hardware Specifications
- **MCU**: ESP32-S3 Xtensa Dual-Core @ 240MHz (16MB Flash, 8MB PSRAM)
- **Display**: 1.69" 240x280 IPS ST7789V2 SPI LCD
- **Touch**: CST816T Capacitive Touch Screen (I2C)
- **USB**: Native USB OTG in composite mode (CDC Serial + HID Keyboard & Consumer Control)
- **Haptics/Audio**: Onboard buzzer for tactile click feedback

## Architecture
- **Firmware (`src/`)**:
  - LVGL 8.4 TileView UX (Swipe horizontally between Mac Status/Controls and Device Settings).
  - Screen 1: Live CPU/RAM usage meters, live clock, link status, and 6 touch buttons:
    - 🪟 **Mission Control** (`Ctrl + Up`)
    - 🖥️ **Show Desktop** (`F11`)
    - ◀️ **Space Left** (`Ctrl + Left`)
    - ▶️ **Space Right** (`Ctrl + Right`)
    - 🔇 **Mute Audio** (Consumer Control Mute)
    - 🔍 **Spotlight Search** (`Cmd + Space`)
  - Screen 2: Hardware PWM display brightness slider (LEDC on GPIO 15) and hardware diagnostics.
- **Host Companion (`host_companion/`)**:
  - Lightweight Python daemon (`mac_stats_daemon.py`) streaming CPU/RAM/time updates over serial.

## Building with Bazel

PlatformIO is a [uv](https://docs.astral.sh/uv/) tool: `uv tool install platformio`.

### Build Firmware Images
```bash
bazel build //iot/esp32-s3:firmware
```
Outputs in `bazel-bin/iot/esp32-s3/`: `firmware.bin`, `bootloader.bin`, `partitions.bin`.

The images are unstamped on purpose. A Bazel action sees neither your shell's
environment nor `.git`, so the version / grade / commit stamp
(`build_info.json`) and the distributable zip are produced by the publisher,
which runs outside Bazel.

### Flash to Connected Board
```bash
bazel run //iot/esp32-s3:flash
# Or specify serial port:
bazel run //iot/esp32-s3:flash -- /dev/cu.usbmodemXXXX
```

### Run Host Stats Companion
```bash
uv run iot/esp32-s3/host_companion/mac_stats_daemon.py
```

## Release Ladder

The firmware is the `esp32-s3` **delivery unit** declared in `BUILD`
(`delivery(...)`). Its two rungs are rendered into the generated
`.github/workflows/delivery.yaml` by `bazel run //tools/ci:gen`, under the
delivery orchestrator's affected-detection, gating and kill switch:

```text
PR against main ──> iot-esp32-s3.yaml: bazel build //iot/esp32-s3:firmware

Push to main ─────> delivery.yaml esp32-s3-beta            [BETA GRADE]
   (affected)         publish.sh GRADE=beta
                      stamped 0.1.0-beta.<sha>, assets clobbered on the
                      rolling prerelease esp32-s3-beta-latest, tag moved to HEAD

Push to main ─────> iot-esp32-s3-release.yaml (release-please)
                      opens / updates the release PR; merging it cuts
                      the GitHub Release esp32-s3-vX.Y.Z
                                │
Release published ─> delivery.yaml esp32-s3-production     [PRODUCTION GRADE]
   (esp32-s3-v*)      publish.sh GRADE=production RELEASE_TAG=esp32-s3-vX.Y.Z
                      stamped X.Y.Z, assets attached to that release
```

Every rung runs the same script as the break-glass path:

```bash
# rolling beta from the checked-out HEAD
bazel run //iot/esp32-s3:publish

# production: check out the release tag first
GRADE=production RELEASE_TAG=esp32-s3-vX.Y.Z bazel run //iot/esp32-s3:publish
```

Each published bundle (`esp32-s3-mac-controller.zip`) contains the three
images, `build_info.json`, and this directory's `flash.sh`.
