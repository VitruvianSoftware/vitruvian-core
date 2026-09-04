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

### Build Firmware Artifacts
```bash
bazel build //iot/esp32-s3:firmware
```
Outputs in `bazel-bin/iot/esp32-s3/`:
- `firmware.bin`
- `bootloader.bin`
- `partitions.bin`
- `esp32-s3-mac-controller.zip` (self-contained bundle with binary files, manifest, and `flash.sh`)

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

## CI/CD Release Ladder

```text
PR against main ──> Bazel Compile Check
                         │
Push to main ────────────┴──> Is Release-Please PR?
                               │
            ┌──────────────────┴──────────────────┐
            ▼ No (Code landed on main)            ▼ Yes (Release PR merged)
    [BETA FIRMWARE GRADE]                 [PRODUCTION FIRMWARE GRADE]
    - Built via Bazel                     - Built via Bazel
    - Stamped: 0.1.0-beta.<commit>        - Stamped: X.Y.Z
    - Attached to rolling prerelease:     - Attached to official GitHub Release:
      `esp32-s3-beta-latest`                `esp32-s3-vX.Y.Z`
```
