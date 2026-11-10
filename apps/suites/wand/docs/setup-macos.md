# macOS Setup Guide

This guide explains how to pair your Daydream controller and configure the required macOS system permissions.

---

## 1. Pair the Controller

1. Turn on Bluetooth in **System Settings > Bluetooth**.
2. Press and hold the **Home button** (the bottom recessed circle) on your Daydream controller until the LED indicator begins pulsing.
3. Select **Daydream controller** from the list of nearby devices and confirm pairing.

The controller LED remains solid when successfully connected over Bluetooth Low Energy.

---

## 2. Required Permissions

Wand requires two macOS system permissions to operate:

### Bluetooth Permission
- **Why it is needed**: Wand scans for your paired Daydream controller, connects to its BLE GATT services, and reads real-time IMU and touchpad notifications.
- **How to grant**: When you launch Wand for the first time, macOS displays a prompt asking for Bluetooth access. Note that when launching Wand from a terminal window (such as Terminal, iTerm2, Alacritty, or Ghostty), macOS requests Bluetooth permission for that terminal application rather than Wand itself. Click **Allow**. You can verify or change this anytime in **System Settings > Privacy & Security > Bluetooth**.

### Accessibility Permission
- **Why it is needed**: macOS restricts apps from generating system-wide mouse movements and keyboard events. Wand uses `CGEventPost` to move your cursor, execute clicks and drags, and dispatch key combinations.
- **How to grant**: Wand automatically detects if Accessibility permission is missing and offers a button to open the settings pane. Alternatively, open **System Settings > Privacy & Security > Accessibility** and toggle the switch next to **Wand** (or your terminal application if running directly via CLI) to enable it.

---

## 3. Running Wand

Launch Wand using Bazel:

```bash
# Build the macOS desktop binary
bazel build //apps/suites/wand/desktop:wand

# Run Wand GUI
bazel run //apps/suites/wand/desktop:wand
```

When Wand starts, it launches in a disconnected state. To begin streaming pointer motion, click **Connect** on the application window's **Connection** tab (or select **Connect** from the macOS menu bar tray icon). Wand will then scan for your Daydream controller and connect. If the connection drops later, automatic reconnection will attempt to re-establish it.

You can also run diagnostic and testing subcommands via the CLI. For example, run `bazel run //apps/suites/wand/desktop:wand -- doctor` to check your Bluetooth adapter status and accessibility permissions.
