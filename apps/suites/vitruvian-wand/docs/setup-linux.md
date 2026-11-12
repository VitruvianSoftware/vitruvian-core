# Linux Setup Guide

This guide explains how to pair your Daydream controller using BlueZ, configure `uinput` permissions for event injection, and understand display server differences.

---

## 1. Pair with BlueZ

Pair the controller using `bluetoothctl`:

1. Put the Daydream controller into pairing mode by pressing and holding the **Home button** until the LED blinks.
2. Open a terminal and launch the Bluetooth control tool:
   ```bash
   bluetoothctl
   ```
3. Scan for devices and connect:
   ```bash
   scan on
   # Locate "Daydream controller" and copy its MAC address (e.g. AA:BB:CC:DD:EE:FF)
   pair AA:BB:CC:DD:EE:FF
   trust AA:BB:CC:DD:EE:FF
   connect AA:BB:CC:DD:EE:FF
   ```
4. Exit `bluetoothctl` once connected:
   ```bash
   exit
   ```

---

## 2. Configure uinput Permissions

Vitruvian Wand creates virtual mouse and keyboard devices through the Linux kernel's `/dev/uinput` interface. By default, `/dev/uinput` requires root privileges.

To allow Vitruvian Wand to inject inputs as a standard user:

1. Create a udev rule file at `/etc/udev/rules.d/99-uinput.rules`:
   ```udev
   KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
   ```
2. Add your user account to the `input` group:
   ```bash
   sudo usermod -aG input $USER
   ```
3. Reload udev rules and trigger device updates:
   ```bash
   sudo udevadm control --reload-rules && sudo udevadm trigger
   ```
4. Log out and log back in for the new group permissions to take effect.

---

## 3. Display Servers: X11 vs Wayland

Vitruvian Wand uses kernel-level `uinput` events, which work identically on both X11 and Wayland sessions:

- **Pointer & Button Input**: Pointer movement, clicks, drags, and scrolling work on both display servers without modification.
- **Radial Menu**:
  - **X11**: The radial menu opens centered directly under the current pointer position.
  - **Wayland**: Security protocols prevent unprivileged applications from querying global pointer coordinates or positioning windows at arbitrary coordinates. On Wayland sessions, Vitruvian Wand falls back to opening the radial menu centered on the active display output.

---

## 4. Running Vitruvian Wand

Launch Vitruvian Wand using Bazel:

```bash
# Build the Linux desktop binary
bazel build //apps/suites/vitruvian-wand/desktop:vitruvian-wand

# Run Vitruvian Wand GUI
bazel run //apps/suites/vitruvian-wand/desktop:vitruvian-wand
```

When Vitruvian Wand starts, it launches in a disconnected state. Click **Connect** on the **Connection** tab to begin scanning and streaming. You can also run diagnostics using the CLI:

```bash
# Verify Bluetooth adapter status and /dev/uinput write permissions
bazel run //apps/suites/vitruvian-wand/desktop:vitruvian-wand -- doctor
```
