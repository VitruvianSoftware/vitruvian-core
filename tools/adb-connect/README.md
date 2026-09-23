# adb-connect

Zero-touch Android Wireless Debugging auto-discovery and connection tool.

## The Problem

Android 11+ Wireless Debugging uses ephemeral ports that change every time Wi-Fi
reconnects or debugging is toggled. When developers or autonomous coding agents
need to run `adb` commands, they historically had to manually inspect Developer
Options on the phone and paste the new port.

## The Solution

Android's `adbd` announces active Wireless Debugging sessions over local mDNS /
Bonjour (`_adb-tls-connect._tcp`). `adb-connect`:

1. **Browses local mDNS** for `_adb-tls-connect._tcp` announcements.
2. **Resolves the dynamic port**, device name, and serial number.
3. **Resolves reachability**, preferring the device's Tailscale mesh IP (to bypass
   any Wi-Fi AP client isolation), falling back to local LAN IP or hostname.
4. **Executes `adb connect`** automatically in under 2 seconds.

## Usage

```bash
# Connect to the discovered device automatically
bazel run //tools/adb-connect

# Or via the shorthand alias
bazel run //tools:adb-connect

# Check current connection status
bazel run //tools/adb-connect -- --status

# Output structured JSON (ideal for AI agent tool calls and scripts)
bazel run //tools/adb-connect -- --json

# Filter if multiple Android devices are active on the network
bazel run //tools/adb-connect -- --device "Pixel"

# Switch to fixed TCP/IP mode on port 5555 once connected
bazel run //tools/adb-connect -- --tcpip 5555

# Disconnect existing sessions before connecting
bazel run //tools/adb-connect -- --disconnect-first
```

## Running Tests

```bash
bazel test //tools/adb-connect/...
```
