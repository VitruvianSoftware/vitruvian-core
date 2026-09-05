# ESP32-S3 Mac Desktop Companion & Touch Controller

Custom firmware for the **Waveshare ESP32-S3-Touch-LCD-1.69** development board, turning it into a desk companion that streams live Mac hardware metrics and triggers native macOS desktop shortcuts via USB HID.

## Hardware Specifications
- **MCU**: ESP32-S3 Xtensa Dual-Core @ 240MHz (16MB Flash, 8MB PSRAM)
- **Display**: 1.69" 240x280 IPS ST7789V2 SPI LCD
- **Touch**: CST816T Capacitive Touch Screen (I2C)
- **USB**: Native USB OTG in composite mode (CDC Serial + HID Keyboard & Consumer Control)
- **Wireless**: 2.4 GHz 802.11 b/g/n Wi-Fi + Bluetooth 5 LE (NimBLE HID keyboard & consumer control)
- **Haptics/Audio**: Onboard buzzer (GPIO 42, LEDC PWM) for tactile clicks and CI pass/fail chimes

## Canonical Codebase Location
`iot/esp32-s3/` is the **canonical, sole source of truth** in this repository for the ESP32-S3 Mac Desktop Companion. All features, firmware updates, and daemon enhancements must be developed directly within this directory.

## Architecture
- **Firmware (`src/`)**:
  - LVGL 8.4 dynamic TileView UX with configurable swipe carousel (re-indexes dynamically with zero UI jitter).
  - **System Deck (Deck 0)**: Real-time CPU & RAM usage bars, system clock, link badge, and 6 core desktop shortcuts with haptic audio feedback:
    - 🪟 **Mission Control** (`Ctrl + Up`)
    - 🖥️ **Show Desktop** (`F11`)
    - ◀️ **Space Left** (`Ctrl + Left`)
    - ▶️ **Space Right** (`Ctrl + Right`)
    - 🔇 **Mute Audio** (Consumer Control Mute)
    - 🌙 **Display Sleep** (`pmset displaysleepnow` / Display Sleep)
  - **Smart Deck (Deck 1)**: Context-aware macro deck that dynamically adapts its 6 shortcut buttons, accent colors, and USB HID bindings to the frontmost active macOS application (e.g. VS Code, Chrome, Terminal, Slack, or Global fallback).
  - **Agent & CI Deck (Deck 2)**: Real-time workflow dashboard displaying local AI agent execution status (idle, running, review required) and GitHub PR / CI check indicators (`🟢 Passing`, `🟡 In-Progress`, `🔴 Failing`). Falls back to a **standalone cloud mode** (`CLOUD` badge) when no Mac daemon is streaming — see *Untethered mode* below.
  - **Settings Deck (Deck 3)** — vertically scrollable card stack:
    - Hardware PWM display brightness slider (LEDC channel on GPIO 15).
    - Interactive **Deck Visibility Toggles**: enable or disable individual Decks (System, Smart, Agent) with settings persisted across boots in ESP32 NVS flash.
    - **Wi-Fi card** (`wifi_manager.cpp`): radio toggle, live status, and multi-modal provisioning — least friction first:
      1. **[Sync from Mac]** (default): zero-typing companion sync; the device asks the tethered daemon for the Mac's current network via `{"cmd":"wifi_sync"}` over USB CDC.
      2. **[Web Portal]** (standalone fallback): temporary `Vitruvian-Setup-XXXX` SoftAP serving a scan-and-join portal at `http://192.168.4.1`.
    - **Bluetooth card** (`ble_hid.cpp`): radio toggle plus one-touch **[Pair BLE]** opening a 60-second advertising window; once paired, macros route over BLE HID whenever the USB cable is unplugged (`mac_hid.cpp` dual-transport dispatcher).
    - **Audio Chimes card** (`buzzer.cpp`): mute toggle for the CI chimes and touch clicks, persisted in NVS (`settings:chimes_muted`), plus the OTA endpoint hint.
- **Host Companion (`host_companion/`)**:
  - Python daemon (`mac_stats_daemon.py`) streaming CPU/RAM/time telemetry, frontmost app profiles (`app_profiles.py`), and local AI agent / git CI status (`agent_ci_monitor.py`) over USB CDC serial at 115200 baud.
  - **Wi-Fi provisioning**: answers device `wifi_sync` requests (SSID via `networksetup`, passphrase via `VITRUVIAN_WIFI_PASS` env or the macOS keychain), or run `uv run iot/esp32-s3/host_companion/mac_stats_daemon.py --wifi-sync` for an explicit interactive one-shot.
  - **Dual transport**: the same daemon streams over USB CDC when the cable is in and over UDP when it is not, discovering the device by mDNS. See *Untethered mode*.

## Untethered mode

The companion does not need the cable. Once it has joined a network it
advertises itself over mDNS and accepts the identical wire protocol
(`docs/protocol.md`) over UDP:

```text
vitruvian-companion.local        A record
_vitruvian._tcp  port 8266       version / chip / id TXT records
```

- **Link arbitration** (`packet_router.cpp`): USB CDC wins while it is carrying
  packets, Wi-Fi UDP takes over within 3 s of the cable going quiet, and the
  Deck 0 badge follows — `● USB` (green), a Wi-Fi glyph (cyan), `● <ip>` when
  reachable but idle, `● Standby` (orange) when neither.
- **Button actions** are answered back over whichever channel is live, so
  `Run Checks` and `Open PR` keep working across the LAN.
- **Autonomous cloud monitor** (`cloud_ci.cpp`): after 15 s with no host packets
  on either channel, the device polls the GitHub Actions API itself over TLS and
  chimes on every conclusion change. Configure it over the wire:

  ```json
  {"cmd":"cloud_config","repo":"owner/repo","token":"ghp_...","enabled":true}
  ```

  Certificates are verified against the roots pinned in `src/github_ca.h`; the
  TLS fetch runs on its own FreeRTOS task so the carousel never stutters.
- **Over-the-air updates** (`ota_manager.cpp`): `http://vitruvian-companion.local/update`
  in a browser, or `pio run -t upload --upload-port vitruvian-companion.local`.
  Both are gated on the device-derived password shown by `ota_manager_password()`
  (default `vitruvian-<last 3 MAC octets>`, HTTP user `vitruvian`).

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
# Auto: USB when the cable is in, Wi-Fi (mDNS-discovered) when it is not
uv run iot/esp32-s3/host_companion/mac_stats_daemon.py

# Pin the device instead of discovering it (no mDNS on this network)
uv run iot/esp32-s3/host_companion/mac_stats_daemon.py --wifi-host 192.168.1.42

# Force one transport
uv run iot/esp32-s3/host_companion/mac_stats_daemon.py --usb-only
uv run iot/esp32-s3/host_companion/mac_stats_daemon.py --wifi-only
```

Discovery uses the OS resolver first (macOS resolves `.local` through
mDNSResponder, so no extra dependency is needed). On hosts whose resolver does
not speak mDNS, install `zeroconf` and the daemon will browse for
`_vitruvian._tcp` instead.

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
