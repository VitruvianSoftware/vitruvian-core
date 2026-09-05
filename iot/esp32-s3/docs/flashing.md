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
bazel build //mac-controller:firmware
```
Outputs are compiled in `bazel-bin/mac-controller/`:
- `firmware.bin` (Application binary)
- `bootloader.bin` (ESP32-S3 second-stage bootloader)
- `partitions.bin` (Partition layout)
- `esp32-s3-mac-controller.zip` (Self-contained release zip)

### Step 2: Flash to Connected ESP32-S3
Plug your board into a USB-C port on your Mac, then run:
```bash
bazel run //mac-controller:flash
```
Bazel will auto-detect the serial port matching `/dev/cu.usbmodem*` and flash the binaries at 460,800 baud.

### Step 3: Flash with Explicit Serial Port
If multiple USB serial devices are connected:
```bash
bazel run //mac-controller:flash -- /dev/cu.usbmodem1101
```

---

## 3. Flashing with PlatformIO

If developing outside of Bazel or using the PlatformIO IDE / CLI:

```bash
# Compile firmware
pio run -d mac-controller

# Upload firmware over USB
pio run -d mac-controller -t upload

# Open serial debug monitor
pio device monitor -d mac-controller -b 115200
```

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
uv run mac-controller/host_companion/mac_stats_daemon.py
```

### Expected Startup Output:
```
ESP32-S3 Mac Desktop Companion Daemon starting...
Connected to ESP32-S3 on port: /dev/cu.usbmodem1101
[INIT] Sent initial app profile: VS Code
[INIT] Sent initial stats: {'type': 'stats', 'cpu': 12, 'ram': 54, 'time': '04:30 PM'}
[INIT] Sent initial agent/CI: agent=idle, ci=passing
```

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
        <string>/Users/YOUR_USERNAME/Workspace/gh/application/vitruvian/vitruvian-core/mac-controller/host_companion/mac_stats_daemon.py</string>
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
  bazel run //mac-controller:flash
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
