# ESP32-S3 Mac Desktop Companion — User Guide & Operator Manual

The **ESP32-S3 Mac Desktop Companion** (Waveshare ESP32-S3-Touch-LCD-1.69) is a standalone, battery-capable touch controller and desk companion designed for macOS. It provides real-time system and AI agent monitoring, contextual application shortcuts, and desktop control via USB, Bluetooth, or Wi-Fi.

---

## 1. Physical Hardware & Controls

```text
               ┌───────────────────────────────┐
               │         [Display 1.69"]       │
               │           240 x 280           │
               │                               │
               │   Tile 0: System Deck         │
               │   Tile 1: Smart Deck          │
               │   Tile 2: Agent & CI Deck     │
               │   Tile 3: Settings Deck       │
               │                               │
               └───────────────────────────────┘
                     │         │         │
                 [KEY 1]    [BOOT]    [KEY 2]
                  Reset      Boot      Power
```

### Power Button (`Key 2` / Top Right)
The device features an active hardware power latch circuit (`SYS_EN` on GPIO 41) that holds battery power on once booted.
- **Power On (from cold off)**: Press and hold `Key 2` for ~1 second until the screen lights up. The firmware immediately asserts the power latch to keep the device running on battery.
- **Display Sleep / Wake (Short Press, < 1.2s)**: Instantly turns off the backlight while keeping MCU and wireless connections active. Press again to wake.
- **Wake-on-Touch**: When the display is asleep, tapping anywhere on the capacitive touchscreen immediately wakes the screen back up.
- **Graceful Shutdown (Long Press, >= 2.5s)**: Plays a descending alert chime, dims the backlight to zero, and releases the hardware power latch (`GPIO 41 LOW`), completely cutting battery power with zero quiescent battery drain.

### Boot & Reset Buttons
- **Reset Button (`Key 1` / Top Left)**: Performs an immediate hardware reset.
- **Boot Button (`Boot` / Middle)**:
  - **1-Button Recovery**: If the device is ever in an unbootable state or bootloader flash mode is needed, unplug USB, hold down the middle **Boot** button, plug in the USB cable, and release the button. The ESP32-S3 ROM bootloader is immediately active.

### Battery & Charging
- **Battery Connection**: Connected via the 2-pin JST lithium battery port on the back. Compatible with standard 3.7V LiPo / Lithium-ion batteries (3.2V - 4.2V).
- **Charging**: Plug in USB-C 5V power. The onboard TP4056-compatible PMIC charges the cell. A green lightning bolt icon appears next to the battery percentage in the header.

---

## 2. Operating Modes: Tethered vs. Untethered

The device operates in two distinct modes depending on whether the USB-C cable is connected.

```mermaid
flowchart TD
    BTN["System Button Pressed on ESP32"] --> CHK{"Is USB Connected?"}
    CHK -->|Yes (Tethered)| USB["Native USB HID Keyboard & Consumer Control<br/>• Direct electrical keystrokes over USB cable<br/>• Zero software required on Mac"]
    CHK -->|No (Untethered on Battery)| WIRELESS{"Untethered Wireless Routing"}
    
    WIRELESS -->|Option A: Bluetooth| BLE{"Is Bluetooth Paired?"}
    BLE -->|Yes (Recommended)| BLE_SEND["NimBLE HID Keyboard<br/>• Native macOS Bluetooth keyboard<br/>• Direct wireless control, no daemon needed"]
    BLE -->|No| UDP
    
    WIRELESS -->|Option B: Wi-Fi| UDP["UDP Packet to Port 8266<br/>{'cmd':'hid_action', ...}"]
    UDP --> DAEMON{"Is mac_stats_daemon.py<br/>running on Mac?"}
    DAEMON -->|Yes| MAC_EXEC["Daemon executes action via AppleScript / pmset<br/>• Streams live CPU/RAM & Smart Deck profiles"]
    DAEMON -->|No| DROPPED["Action cannot be executed (Mac is not listening)"]
```

### Tethered Mode (Plugged into USB)
- When plugged into your Mac via USB-C, the ESP32 acts as a composite USB device:
  1. **USB HID Keyboard & Consumer Control**: System buttons send keystrokes directly over the physical USB wires into macOS. Works out of the box with zero host software.
  2. **USB CDC Serial**: Used by the companion daemon to stream host statistics.
- Header link status displays: `● USB` (green).

### Untethered Mode (Running on Battery)
- When the USB cable is unplugged, physical USB electrical signals cannot travel to the Mac.
- **To control your Mac on battery, you must use either Bluetooth or the Wi-Fi companion daemon**:
  1. **Option A: Bluetooth BLE (Standalone, Recommended)**: The ESP32 acts as a wireless Bluetooth keyboard. Once paired, buttons work directly without running any script on the Mac.
  2. **Option B: Wi-Fi Companion Daemon**: The ESP32 beams commands over Wi-Fi UDP to `mac_stats_daemon.py` on your Mac.

---

## 3. Wireless Setup Guide

### Setting up Bluetooth Control (No Mac daemon required)
1. On the ESP32, swipe horizontally to the right to reach the **Settings Deck** (Tile 3).
2. Scroll down to the **Bluetooth** card.
3. Tap **[Pair with Mac]**. The device activates Bluetooth LE advertising for 60 seconds.
4. On your Mac, open **System Settings -> Bluetooth**.
5. Look under **Nearby Devices** for **"Vitruvian Companion"** and click **Connect**.
6. Once connected, macOS recognizes the device as an external Bluetooth keyboard. System shortcuts (Mute, Sleep, Mission Control, Desktops) will now control your Mac wirelessly.

### Setting up Wi-Fi & The Host Companion Daemon
The Wi-Fi companion daemon provides bidirectional communication: it executes untethered shortcuts and continuously streams Mac CPU/RAM metrics and active application profiles to the device.

1. **Connect the ESP32 to Wi-Fi**:
   - *Quick Sync (Tethered)*: Plug the device into your Mac via USB, swipe to **Settings Deck**, and tap **[Sync from Mac]**. The host daemon will automatically beam your Mac's Wi-Fi network and credentials to the device.
   - *Web Portal*: In Settings Deck, tap **[Setup Network]**. Connect your phone/Mac to the temporary Wi-Fi access point `Vitruvian-Setup-XXXX` and open `http://192.168.4.1` to enter your SSID and password.
2. **Start the Mac Companion Daemon**:
   In a terminal on your Mac, run:
   ```bash
   uv run iot/esp32-s3/host_companion/mac_stats_daemon.py
   ```
   *Note: If mDNS is disabled or blocked on your local network, specify the device's IP address directly (shown in the Settings Deck):*
   ```bash
   uv run iot/esp32-s3/host_companion/mac_stats_daemon.py --wifi-host 192.168.86.65
   ```
3. Once running, the device's header will display the Wi-Fi icon with your local IP address (`● 192.168.x.x`), and CPU/RAM bars will begin updating in real time.

---

## 4. Carousel Deck Walkthrough

The interface is structured as a swipeable carousel of 4 Decks. Swipe left or right to switch between them.

### Deck 0: System Deck
- **Header**:
  - Left column: Real-time clock (`HH:MM:SS`), Battery percentage & icon, Link status badge.
  - Right column: Real-time CPU usage bar and RAM usage bar.
- **6 Core Desktop Shortcuts**:
  - 🪟 **Mission Control**: Triggers macOS Mission Control (`Ctrl + Up`).
  - 🖥️ **Show Desktop**: Minimizes all windows to reveal desktop (`F11`).
  - ◀️ **Space Left**: Switches to the previous macOS desktop space (`Ctrl + Left`).
  - ▶️ **Space Right**: Switches to the next macOS desktop space (`Ctrl + Right`).
  - 🔇 **Mute Audio**: Toggles macOS system audio mute.
  - 🌙 **Display Sleep**: Sleeps Mac displays immediately (`pmset displaysleepnow`).

### Deck 1: Smart Deck
- **Context-Aware Dynamic App Shortcuts**:
  - Automatically updates based on whichever application is currently frontmost on your Mac (e.g. VS Code, Chrome, Terminal, Slack, Xcode, Finder).
  - The header displays the active app name with a colored accent indicator.
  - The 6 buttons dynamically adapt their labels, colors, and shortcut bindings to the active app.

### Deck 2: Agent & CI Deck
- **AI Agent Monitoring**:
  - Shows the status of local AI coding agents (Antigravity, Claude Code): `Idle`, `Running`, `Review Required`, or `Error`.
- **CI / GitHub Pipeline Monitoring**:
  - Displays current repository branch, open PR number, and check status (`Passing`, `In-Progress`, `Failing`).
  - Tapping **[Run Checks]** triggers repository checks via the companion daemon.
  - Tapping **[Open PR]** opens the active PR in your Mac browser.
- **Autonomous Cloud Monitor**:
  - When untethered without a Mac daemon running, the device directly polls the GitHub API over Wi-Fi, showing a `CLOUD` badge.

### Deck 3: Settings Deck
Vertically scrollable settings stack:
- **Display Brightness**: Slider adjusting backlight PWM from 5% to 100%.
- **Deck Visibility Toggles**: Interactive switches to show or hide the System Deck, Smart Deck, or Agent Deck.
- **Auto-Rotation Toggle**: Enables or disables 4-way automatic rotation via the QMI8658 IMU.
- **Wi-Fi Card**: Radio switch, current IP, **[Sync from Mac]**, and **[Setup Network]** portal buttons.
- **Bluetooth Card**: Radio switch, paired host MAC, and **[Pair with Mac]** button.
- **Audio Chimes**: Toggle touch clicks and CI pass/fail notification tones.
- **Device Info Card**: Firmware version, build commit, MAC address, and live battery voltage.

---

## 5. Screen Rotation & Ergonomics

The device includes an onboard **QMI8658 6-axis IMU** supporting automatic **4-way rotation**:
- **Portrait (0°)**: Standard vertical orientation with USB port facing down.
- **Landscape CW (90°)**: Wide view with USB port facing left.
- **Inverted Portrait (180°)**: Vertical orientation with USB port facing up.
- **Landscape CCW (270°)**: Wide view with USB port facing right.

When rotated into landscape, the UI automatically reflows:
- Headers widen to 266px.
- The button grid transforms from 2x3 into a 3x2 layout.
- Touch coordinates automatically remap so gestures and taps remain 100% accurate.
- If placed flat on a table, the orientation locks automatically to prevent jitter.

---

## 6. Status Indicators & Glossary

| Symbol / Badge | Meaning | Description |
|---|---|---|
| `⚡ 98%` (Green) | Charging | Battery is actively charging over USB. |
| `🔋 85%` (Green) | Battery Full | Battery level >= 80%. |
| `🔋 65%` (Cyan) | Battery Good | Battery level between 50% and 79%. |
| `🔋 38%` (Orange) | Battery Moderate | Battery level between 25% and 49%. |
| `🔋 18%` (Orange-Red) | Battery Low | Battery level between 10% and 24%. Recharge soon. |
| `🪫 5%` (Red) | Battery Critical | Battery level < 10%. Immediate recharge required. |
| `● USB` (Green) | Tethered USB Link | Active bidirectional USB CDC link with Mac host. |
| `● 192.168.x.x` (Cyan) | Wi-Fi UDP Link | Connected to local Wi-Fi and actively communicating with Mac daemon. |
| `● Standby` (Orange) | Standby Link | Wi-Fi connected but no Mac daemon is actively streaming. |
| `● CLOUD` (Blue) | Cloud Mode | Untethered autonomous mode polling GitHub Actions API directly. |

---

## 7. Troubleshooting & FAQs

### Why don't the system buttons control my Mac when running on battery?
When unplugged, physical USB keystrokes cannot travel across the air. You must connect the device to your Mac using either:
1. **Bluetooth**: In Settings Deck, tap **[Pair with Mac]**, then connect to **"Vitruvian Companion"** in macOS Bluetooth settings.
2. **Wi-Fi Companion**: Run `uv run iot/esp32-s3/host_companion/mac_stats_daemon.py` in your Mac terminal.

### The device turns off as soon as I release the power button from cold boot.
Ensure you hold the power button for approximately **1 second** when turning it on. The firmware requires ~200ms to boot the bootloader and assert the `SYS_EN` hardware power latch on GPIO 41. Releasing too quickly before the latch engages drops power.

### How do I completely power off the device to save battery?
Press and hold the power button (`Key 2`) for **2.5 seconds**. You will hear a descending buzzer chime, the display will fade out, and the power circuit will disconnect completely.

### How do I update firmware over Wi-Fi (OTA)?
Open your web browser on the same Wi-Fi network and navigate to:
```text
http://<device-ip>/update
# e.g., http://192.168.86.65/update
```
Log in with username `vitruvian` and your device password (displayed in Settings Deck Card 5), select the new `firmware.bin`, and click **Upload**.
