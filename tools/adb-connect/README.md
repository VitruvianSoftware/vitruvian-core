# adb-connect

Zero-touch Android Wireless Debugging auto-discovery, pairing, and connection tool.

## The Problem

Android 11+ Wireless Debugging uses ephemeral ports that change every time Wi-Fi
reconnects or debugging is toggled. When multiple Android devices (phones and
Android TVs) are active on the same network:

1. Ephemeral TLS ports must be discovered dynamically over mDNS.
2. Blindly selecting the last mDNS service can accidentally target a legacy
   `_adb._tcp` Android TV instead of the primary development phone.
3. Calling `adb connect <ip>:<port>` when macOS `adb` has already auto-attached a
   paired phone via its `_adb-tls-connect._tcp` mDNS service creates a duplicate
   transport for the same physical device, breaking `adb -s` and `:boot_smoke`.

## The Solution

`adb-connect` combines mDNS discovery (`_adb-tls-connect._tcp`, `_adb._tcp`, and
`_adb-tls-pairing._tcp`) with a built-in device profile catalog and duplicate
transport prevention:

1. **Declarative Device Profiles & Aliases**: Built-in profiles map stable aliases
   and roles (`fold` / `primary` -> Pixel 11 Pro Fold `yogi`; `pixel4` / `secondary`
   -> Pixel 4 XL `coral`; `watch` / `pw4` -> Pixel Watch 4 `kenari_lte`; `tv` / `sony`
   -> Living Room Sony TV) without hardcoding ephemeral DHCP IPs. Optional per-machine
   serial overrides can be stored in `~/.config/vitruvian/adb-devices.json`.
2. **Phone-First Default Selection & Ambiguity Refusal**: Defaults to the primary
   Wireless Debugging phone (`fold`) and never auto-selects a Wear OS watch or legacy
   `_adb._tcp` TV when no `--device` filter is passed. Refuses ambiguous substring
   filters (e.g. `--device pixel` when multiple Pixels are active) with a clear
   candidate list.
3. **Duplicate Transport Prevention & Cleanup**: Checks `adb devices -l` by hardware
   serial before connecting. If a phone or watch is already attached via its
   `_adb-tls-connect._tcp` mDNS transport, it reuses that session and disconnects
   any redundant `<ip>:<port>` transport for the same device.
4. **Zero-Port mDNS Pairing (`--pair`)**: Discovers `_adb-tls-pairing._tcp` on the
   local LAN so you only need the 6-digit pairing code shown on the device screen.

## Known Device Aliases

| Alias (`--device`) | Device | Codename | Role | Transport |
|---|---|---|---|---|
| `fold`, `primary`, `yogi` | Pixel 11 Pro Fold | `yogi` | `primary` (default) | `_adb-tls-connect._tcp` |
| `pixel4`, `secondary`, `coral` | Pixel 4 XL | `coral` | `secondary` | `_adb-tls-connect._tcp` |
| `watch`, `pw4`, `kenari`, `kenari_lte`, `wear` | Pixel Watch 4 | `kenari_lte` | `watch` | `_adb-tls-connect._tcp` |
| `tv`, `sony`, `bravia` | Living Room Sony TV | `bravia` | `tv` | `_adb._tcp` (port 5555) |

## Usage

```bash
# Connect to the default primary phone (Pixel 11 Pro Fold)
bazel run //tools/adb-connect

# Target a specific device by alias
bazel run //tools/adb-connect -- --device fold
bazel run //tools/adb-connect -- --device pixel4
bazel run //tools/adb-connect -- --device watch
bazel run //tools/adb-connect -- --device tv

# Connect all discovered Wireless Debugging phones at once
bazel run //tools/adb-connect -- --all

# Discover all mDNS-advertised Android devices on the network
bazel run //tools/adb-connect -- --discover

# Pair a new phone using only its 6-digit code (auto-discovers pairing IP & port)
bazel run //tools/adb-connect -- --pair 123456

# Resolve the exact ADB transport serial for ANDROID_SERIAL (e.g. for :boot_smoke)
export ANDROID_SERIAL="$(bazel run //tools/adb-connect -- --print-serial --device pixel4)"

# Check current ADB connection status
bazel run //tools/adb-connect -- --status

# Output structured JSON (ideal for AI agent tool calls and scripts)
bazel run //tools/adb-connect -- --json
```

## Rust build

`src/` is a Rust port of `adb_connect.py` with the same flags, help text,
output, JSON and exit codes. It uses only the Rust standard library.
`//tools/adb-connect` still runs the Python version; the Rust one runs alongside it:

```bash
bazel run //tools/adb-connect:adb-connect -- --status
```

The parity test (`:adb_connect_rs_parity_test`) runs both versions against
the same scripted `adb`, `dns-sd` and `tailscale` stand-ins and fails if their
output, exit codes or the commands they run ever differ. Known gaps, none of
which matter for real `dns-sd`/`adb` output: digits in ports and pairing codes
are ASCII-only (Python's regex also accepts other Unicode digits), and when the
tool crashes on a malformed profile file, the Rust traceback shows only the
final exception line.

## Running Tests

```bash
bazel test //tools/adb-connect/...
```
