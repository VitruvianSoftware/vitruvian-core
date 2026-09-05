# mac-controller Firmware Flashing & Host Setup Guide

This guide provides step-by-step instructions for building and flashing the ESP32-S3 firmware using Bazel, PlatformIO, or esptool, setting up the macOS companion daemon, and troubleshooting common issues.

---

## 1. Prerequisites

### Hardware:
- Waveshare ESP32-S3-Touch-LCD-1.69 board.
- USB-C to USB-C or USB-A to USB-C cable (**must support USB data**, not charge-only).

### Software Tools:
- **macOS** 13+ (Ventura, Sonoma, Sequoia).
- **Bazel** (`bazelisk`) or **PlatformIO** (`uv tool install platformio` or `brew install platformio`).
- **Python** 3.10+ and **uv** (`brew install uv`).
- **GitHub CLI** (`gh`) logged into your account (`gh auth login`).

---

## 2. Flashing with Bazel (Recommended Monorepo Flow)

The monorepo provides hermetic Bazel wrappers for building and flashing.

### Step 1: Build Firmware Artifacts
```bash
bazel build //iot/esp32-s3:firmware
```
Outputs are compiled in `bazel-bin/iot/esp32-s3/`:
- `firmware.bin` (Application binary)
- `bootloader.bin` (ESP32-S3 second-stage bootloader)
- `partitions.bin` (Partition layout)
- `esp32-s3-mac-controller.zip` (Self-contained release zip)

### Step 2: Flash to Connected ESP32-S3
Plug your board into a USB-C port on your Mac, then run:
```bash
bazel run //iot/esp32-s3:flash
```
Bazel will auto-detect the serial port matching `/dev/cu.usbmodem*` and flash the binaries at 460,800 baud.

### Step 3: Flash with Explicit Serial Port
If multiple USB serial devices are connected:
```bash
bazel run //iot/esp32-s3:flash -- /dev/cu.usbmodem1101
```

---

## 3. Flashing with PlatformIO

If developing outside of Bazel or using the PlatformIO IDE / CLI:

```bash
# Compile firmware
pio run -d iot/esp32-s3

# Upload firmware over USB
pio run -d iot/esp32-s3 -t upload

# Open serial debug monitor
pio device monitor -d iot/esp32-s3 -b 115200
```

---

## 3b. Flashing Over the Air (no cable)

Once the device has joined a network it can be reflashed wirelessly. Both paths
are gated on the device's OTA password — by default `vitruvian-<last 3 octets of
the Wi-Fi MAC>`, which the Settings deck prints alongside the MAC.

### Browser upload (no toolchain):
Open `http://vitruvian-companion.local/update` (user `vitruvian`, password as
above) and upload `firmware.bin`. The page shows live upload progress and the
device reboots into the new image on completion.

### PlatformIO / espota:
```bash
pio run -d iot/esp32-s3 -t upload \
  --upload-port vitruvian-companion.local \
  --upload-flags "--auth=vitruvian-A1B2C3"
```

Notes:
- Only `firmware.bin` is flashed over the air. A bootloader or partition-table
  change still needs the USB path above.
- OTA is unavailable while the Wi-Fi provisioning portal is up: both bind port
  80, so the portal takes it exclusively.
- An interrupted upload is safe — the running image is untouched until the new
  one verifies.

---

## 4. Standalone Flashing with `flash.sh` / `esptool`

For flashing distributed binary release zips without compiling from source:

```bash
# Extract distribution zip
unzip esp32-s3-mac-controller.zip -d mac-ctrl-release
cd mac-ctrl-release

# Run standalone flash script
./flash.sh /dev/cu.usbmodemXXXX
```

### Manual `esptool` Command:
```bash
esptool.py -p /dev/cu.usbmodemXXXX -b 460800 --before default_reset --after hard_reset write_flash \
  0x0000 bootloader.bin \
  0x8000 partitions.bin \
  0x10000 firmware.bin
```

---

## 5. Running the macOS Companion Daemon

### Interactive Execution:
```bash
uv run iot/esp32-s3/host_companion/mac_stats_daemon.py
```

### Expected Startup Output:
```
ESP32-S3 Mac Desktop Companion Daemon starting...
Connected to ESP32-S3 over USB CDC /dev/cu.usbmodem1101
[APP] Focus -> VS Code (com.microsoft.VSCode) via usb
[INIT] Primed USB CDC /dev/cu.usbmodem1101: app=VS Code, agent=idle, ci=passing
```

Unplug the cable and the same daemon finds the device on the LAN instead:
```
Waiting for the ESP32-S3 on USB (/dev/cu.usbmodem*) or vitruvian-companion.local...
Connected to ESP32-S3 over Wi-Fi UDP 192.168.1.42:8266
[INIT] Primed Wi-Fi UDP 192.168.1.42:8266: app=VS Code, agent=idle, ci=passing
```

### Transport Selection Flags:
| Flag | Effect |
|---|---|
| *(none)* | USB when the cable is in, Wi-Fi (mDNS-discovered) when it is not |
| `--wifi-host HOST` | Pin the device address instead of discovering it |
| `--wifi-port PORT` | Override the UDP port (default 8266) |
| `--usb-only` | Never fall back to Wi-Fi |
| `--wifi-only` | Never use USB, even when tethered |
| `--wifi-sync` | One-shot: beam this Mac's Wi-Fi credentials to a tethered device and exit |

### Automatic Background Startup (macOS launchd):
To run the daemon automatically in the background whenever you log into macOS, create a user LaunchAgent:

1. Create `~/Library/LaunchAgents/com.vitruvian.mac-controller.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vitruvian.mac-controller</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/uv</string>
        <string>run</string>
        <string>/Users/YOUR_USERNAME/Workspace/gh/application/vitruvian/vitruvian-core/iot/esp32-s3/host_companion/mac_stats_daemon.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/mac_controller.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/mac_controller.err</string>
</dict>
</plist>
```
2. Load and start the service:
```bash
launchctl load ~/Library/LaunchAgents/com.vitruvian.mac-controller.plist
```

---

## 6. Troubleshooting & Recovery

### Issue 1: Serial Port Not Detected (`/dev/cu.usbmodem*` missing)
- **Cause**: Cable is power-only, or the ESP32-S3 is in a sleep or unconfigured USB state.
- **Solution**:
  1. Replace cable with a high-speed data-rated USB-C cable.
  2. Put the board into **ROM Bootloader Mode**:
     - Press and **HOLD** the `BOOT` button on the bottom of the board.
     - Press and **RELEASE** the `RST` (Reset) button.
     - **RELEASE** the `BOOT` button.
     - Verify the port appears: `ls /dev/cu.usbmodem*` or `ls /dev/cu.*`.

### Issue 2: Permission Denied or "Resource Busy" on Serial Port
- **Cause**: Another process (e.g. an existing daemon instance, `screen`, or a serial monitor) has opened the port.
- **Solution**:
  ```bash
  lsof | grep /dev/cu.usbmodem
  kill -9 <PID>
  ```

### Issue 3: Corrupted NVS Preferences or Stuck Screen
- **Cause**: Flash memory corrupted or invalid preferences written to NVS.
- **Solution**: Perform a complete flash erase:
  ```bash
  uvx esptool -p /dev/cu.usbmodemXXXX erase_flash
  bazel run //iot/esp32-s3:flash
  ```

### Issue 4: Frontmost Application Detection Not Triggering
- **Cause**: macOS Accessibility or System Events permissions restricted.
- **Solution**:
  1. Ensure Terminal or your IDE has permission under:  
     `System Settings > Privacy & Security > Accessibility`
  2. Test `lsappinfo` directly in terminal:
     ```bash
     /usr/bin/lsappinfo front
     ```
