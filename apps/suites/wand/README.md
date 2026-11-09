# Wand

Wand turns a Google Daydream controller into a wireless air mouse for macOS, Linux, Android phones, and Android TV.

Swipe the touchpad to move your pointer, or wave the controller through the air using gyro mode. Every button supports customizable short, long, and double-press actions, including clicks, keyboard shortcuts, media controls, navigation, and a quick-access radial menu.

> **Status: Ready for Hardware Acceptance.** The pure engine (`wand-core`), desktop binary (`wand`), and universal Android APK are built and ready for testing.

---

## Features

- **Dual Pointer Modes**: Toggle seamlessly between touchpad swipe navigation and motion-based gyro air mouse navigation.
- **Natural Gestures**: Click, drag by holding click while moving, tap-to-click, and scroll via volume buttons or touchpad swipes.
- **Extensive Button Customization**: Configure 6 input controls (Touchpad Click, Touchpad Tap, App, Home, Volume Up, Volume Down) across short, long, and double-press triggers (18 distinct slots).
- **Desktop Radial Menu**: Hold a button to reveal an 8-slot circular action selector directly under your cursor (macOS and Linux X11) or centered on screen (Wayland).
- **Test Mode**: Live on-screen visualizer displaying real-time touch coordinates, button states, and IMU motion without moving your system pointer.
- **Fine-Tuned Sensitivity**: Adjust touch deadzones, gyro X/Y speeds, acceleration curves, exponential moving average (EMA) smoothing, and scroll rates.
- **Battery Monitoring & Calibration**: Sensor bias recalibration when placed on a flat surface, live battery percentage reporting, and low-battery alerts below 15%.
- **Android & Android TV Integration**: On-screen overlay cursor, background accessibility service, leanback launcher support, and in-app pairing.
- **Hardware-Free Deterministic Testing**: Core decoding and input state machines run without I/O or Bluetooth dependencies, replayable via captured session fixtures.

---

## Default Controls

Default bindings match standard air mouse conventions:

| Control | Trigger | Desktop (macOS / Linux) | Android (Phone / TV) |
|---|---|---|---|
| **Touchpad** | Swipe (Touch mode) | Move cursor | Move overlay cursor |
| **Touchpad** | Swipe (Gyro mode) | Scroll content | Scroll content (Phone) / D-pad focus step (TV) |
| **Touchpad Click** | Short press / Hold | Left click (press = down, release = up; drag by moving) | Tap / Drag (press = down, release = up; drag by moving) |
| **Touchpad Tap** | Short press | Left click (toggleable) | Tap / Select (toggleable) |
| **App Button** | Short press | Toggle gyro mode | Toggle gyro mode |
| **Home Button** | Short press | Right click | Back |
| **Home Button** | Long press | *(Unbound by default)* | Home |
| **Volume Up** | Short press | Scroll up (one step per press) | Scroll up (one step per press) |
| **Volume Down** | Short press | Scroll down (one step per press) | Scroll down (one step per press) |

The radial menu is not bound to any button by default. It is opt-in: configure any button or press type (for example, a long press on Home or App) to **Radial menu** in the Bindings settings tab.

*Note: Samsung Gear VR controllers are not supported yet.*

---

## Desktop CLI and Subcommands

The desktop binary (`wand`) supports GUI launch, diagnostics, session recording, and deterministic replay:

- **Launch GUI & Tray**:
  ```bash
  bazel run //apps/suites/wand/desktop:wand
  ```
  Launches the `eframe`/`egui` configuration and visualizer window with a system tray menu.

- **System Diagnostics (`doctor`)**:
  ```bash
  bazel run //apps/suites/wand/desktop:wand -- doctor
  ```
  Inspects Bluetooth adapter availability, OS input permissions (macOS Accessibility trust or Linux `/dev/uinput` write permissions), configuration file path, and binary version.

- **Record Controller Session (`record`)**:
  ```bash
  bazel run //apps/suites/wand/desktop:wand -- record <file>
  ```
  Connects to a nearby Daydream controller over BLE and logs timestamped packets (`<t_us> <40 hex chars>`) to `<file>` until stopped with `Ctrl-C`.

- **Deterministic Replay (`replay`)**:
  ```bash
  # Replay packets and print emitted actions to stdout without OS injection
  bazel run //apps/suites/wand/desktop:wand -- replay <file>

  # Replay and inject actions into the host operating system
  bazel run //apps/suites/wand/desktop:wand -- replay <file> --inject
  ```
  Streams a recorded packet file through `wand_core::Engine` and prints each emitted `Action`. With `--inject`, it also generates native OS mouse, click, and keyboard events.

---

## Quick Start & Setup Guides

Platform setup instructions:

- [macOS Setup Guide](docs/setup-macos.md): Bluetooth pairing and Accessibility permissions.
- [Linux Setup Guide](docs/setup-linux.md): BlueZ pairing, uinput udev rules, and Wayland notes.
- [Android Setup Guide](docs/setup-android.md): Sideloading APK, restricted settings, and accessibility permissions.
- [Android TV Setup Guide](docs/setup-android-tv.md): Scan & Pair, ADB permissions, and leanback navigation.
- [Architecture & Data Pipeline](docs/architecture.md): Event flow and deterministic pipeline design.
- [User Acceptance Testing](docs/uat.md): Manual verification checklist for physical hardware.
- [Agent Guide](AGENTS.md): Development conventions, clean-room rules, and test harnesses.

---

## Building and Testing

Build and test Wand using Bazel targets:

```bash
# Run pure engine unit tests and replay test suites
bazel test //apps/suites/wand/core/...

# Build desktop binary
bazel build //apps/suites/wand/desktop:wand

# Build Android phone & TV universal APK
bazel build //apps/suites/wand/android:wand_apk
```

---

## Credits and Clean-Room Provenance

- **Bluetooth Protocol**: Wire packet structure, service UUIDs, and sensor bit unpacking are derived from [mrdoob/daydream-controller.js](https://github.com/mrdoob/daydream-controller.js) (MIT License).
- **Feature Ideas**: Feature concepts and default mapping layouts were inspired by the public README of [kaminoer/Dream-Mouse](https://github.com/kaminoer/Dream-Mouse).
- **Clean-Room Guarantee**: Wand is a completely independent, clean-room implementation. Only Dream-Mouse's public README was read, as a feature list. No code, assets, icons, screenshots or text from it are used (its repository contains no source code).
