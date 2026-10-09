# GravaStar mouse LED as a status indicator — design

**Date:** 2026-10-07 · **Status:** approved for implementation (PR is the review gate)
**Owner:** platform-team (`packages/`) · **Hardware:** GravaStar Mercury mouse,
CompX chipset, USB `3554:F549`, over the 2.4 GHz dongle, macOS.

## 1. What this is, in one paragraph

James's mouse has an RGB LED that the vendor's web tool (controlhub.top, WebHID)
can set. We reverse-engineered that protocol and have a working Python script
(`~/.dotfile/bin/gravastar-mouse`). This design brings the capability into
vitruvian-core as a typed Swift package so that anything running on the Mac —
Claude Code hooks, CI watchers, HomeSpeaker, an ntfy subscriber — can turn the
mouse into a status light: **blue = working, green = passed, red = failed,
amber = warning, magenta = needs attention**, and then put it back the way the
user had it.

## 2. Why Swift, why `packages/peripherals/`

| Option | Verdict |
|---|---|
| **Swift + IOKit (chosen)** | Zero third-party dependencies; `IOKit.hid` ships in the macOS SDK. Matches the repo's other Mac-side code (`home-speaker`, `nexus-agent/macos`, `android-remote/macagent`), which are Swift packages with a hand-written `BUILD`, `swift_library` + `swift_test`, macOS-constrained and `manual`, run by an `xcode-27` pipeline unit. The natural in-process consumers (HomeSpeaker, the Mac agent) are Swift. |
| Python + `hidapi` | The prototype language, but it would put a native wheel into the shared pip hub (`requirements/all.txt`) for a Mac-only peripheral, and every Linux lane would resolve it. |
| TypeScript + `node-hid` | Native addon under rules_js; `nexus-agent/src` is plain JS. |
| Go + cgo `hidapi` | cgo against Apple frameworks under the hermetic LLVM toolchain is unproven here. |

Placement: `packages/peripherals/` — a shared library under the `packages/`
layer (see `tools/boundaries/package_groups.bzl`: apps may depend on packages,
not the reverse). It inherits `packages/OWNERS` (platform-team). No release
unit yet: it is consumed in-tree and via `bazel run`; a release model can be
added when something ships it.

## 3. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ packages/peripherals  (Swift package "Peripherals")              │
│                                                                  │
│  CompXProtocol      pure codec. Frames, CRC, flash map, lighting │
│  (no IOKit)         record encode/decode. Unit-tested anywhere.  │
│        ▲                                                         │
│  CompXHID           HIDTransport protocol; IOKitHIDTransport     │
│  (macOS)            (IOHIDManager); GravaStarMouse facade;       │
│        ▲            MockTransport for tests.                     │
│  StatusSignals      StatusSignal enum → LightingConfig presets;  │
│        ▲            StatusIndicator protocol; MouseStatusIndicator│
│        │            with baseline save/restore.                  │
│  gravastar-mouse    CLI: status|off|color|breathe|rainbow|set|   │
│  (executable)       signal|restore. Hand-rolled arg parsing.     │
└──────────────────────────────────────────────────────────────────┘
```

Dependency direction is strictly downward: protocol → device → semantics → CLI.
Nothing in `CompXProtocol` imports IOKit, so the codec tests need no hardware
and no entitlements.

### 3.1 `CompXProtocol` (pure)

- `CompXDevice`: `vendorID = 0x3554`, `productID = 0xF549`,
  `vendorUsagePage = 0xFF05`, `reportID = 8`, `payloadLength = 16`.
- `Command`: `encryptionHandshake = 1`, `writeFlash = 7`, `readFlash = 8`.
- `FlashAddress.lighting = 0x00A0` (the vendor's `Tt.Light`, 160).
- `Frame` — a 16-byte payload `[cmd, 0, addrHi, addrLo, len, data[0..<10], crc]`.
  `crc = (0x55 - (reportID + Σ payload[0..<15])) & 0xFF`, i.e. the report-ID byte
  plus the 16 payload bytes sum to `0x55` mod 256. `Frame.encode()` returns the
  17 bytes hidapi writes (`reportID` first); callers using IOKit send the 16
  payload bytes with `reportID` passed separately.
- `LightingConfig { mode: LightingMode, color: RGB, speed: Level, brightness: Level }`
  - `LightingMode: UInt8` — `off=0, rainbow=1, breathe=2, fixed=3, neon=4,
    rainbowBreathe=5, fixedRainbow=6`; `CaseIterable`, `CustomStringConvertible`,
    `init?(name:)` accepting the Python aliases (`single-breath`, `static`).
  - `RGB { r,g,b: UInt8 }` with `init?(hex:)` and `init?(name:)` for the ten
    named colours in the prototype; `hexString`.
  - `Level` — a `UInt8` validated to `0...9`; failable init.
  - `encodeRecord() -> [UInt8]` — 7 bytes `[mode, r, g, b, speed, brightness, innerCRC]`,
    `innerCRC = (0x55 - Σ first 6) & 0xFF`.
  - `static func decode(record:)` — from the 6+ bytes at the record offset.
- `Requests`: `handshake(nonce: [UInt8])` (cmd 1, `len=8`, 4 nonce bytes + 4 zero),
  `readLighting()` (cmd 8, addr `0x00A0`, `len=10`),
  `writeLighting(_:)` (cmd 7, addr `0x00A0`, `len=7`, record).
- `Responses`: `parseReadLighting(_ report: [UInt8], includesReportID: Bool)` and
  `isWriteAck(_:includesReportID:)`. **Index shift:** hidapi returns
  `[8, cmd, 0, addrHi, addrLo, len, mode, r, g, b, speed, brightness, …]` with the
  report ID at `[0]`; an `IOHIDDeviceRegisterInputReportCallback` buffer omits it,
  so `cmd` is at `[0]` and `mode` at `[5]`. The parser takes the flag; the
  transport says which shape it delivers.
- Errors: `CompXError` — `malformedResponse`, `notAcknowledged`, `badCRC`,
  `valueOutOfRange`.

### 3.2 `CompXHID` (macOS)

- `protocol HIDTransport { func write(reportID: UInt8, payload: [UInt8]) throws;
  func read(timeout: Duration) throws -> [UInt8]; var reportsIncludeReportID: Bool;
  func close() }`.
- `IOKitHIDTransport`: `IOHIDManagerCreate`, matching dictionary
  `{VendorID, ProductID, PrimaryUsagePage: 0xFF05}` — on macOS each top-level
  collection of interface 1 appears as its own `IOHIDDevice`; the vendor page
  is the one that answers (verified: the prototype selects `usage_page == 65285`).
  Output via `IOHIDDeviceSetReport(kIOHIDReportTypeOutput, reportID, …)`.
  Input via `IOHIDDeviceRegisterInputReportCallback` scheduled on a private
  thread's run loop; `read` waits on a semaphore with timeout and returns the
  queued report (report ID *not* included → `reportsIncludeReportID = false`).
  `kIOHIDOptionsTypeNone` (never seize the device — it is also the pointer).
  Error when no device matches: `CompXError.deviceNotFound`.
- `GravaStarMouse`: `init(transport:)`, `static func open() throws` (IOKit),
  `handshake()` (sends nonce; ~20 ms; reads and discards one report),
  `readLighting() throws -> LightingConfig` (~30 ms settle),
  `writeLighting(_:) throws` (~40 ms settle; throws `notAcknowledged` unless the
  echo is cmd 7). Timings match the proven prototype; expose them as a
  `Timing` struct so tests use zero.
- `MockTransport` (test target): scripted responses; records writes so tests
  assert exact bytes.

### 3.3 `StatusSignals`

- `enum StatusSignal: String, CaseIterable { off, working, success, failure,
  warning, attention }` — the vocabulary notification sources speak. Deliberately
  small; new states are a one-line table edit.
- `StatusPresets.lighting(for:)`:

  | signal | mode | colour | speed | brightness |
  |---|---|---|---|---|
  | `working` | breathe | blue `#0000FF` | 5 | 7 |
  | `success` | fixed | green `#00FF00` | 5 | 7 |
  | `failure` | breathe | red `#FF0000` | 7 | 9 |
  | `warning` | fixed | amber `#FF8000` | 5 | 7 |
  | `attention` | breathe | magenta `#FF00FF` | 5 | 7 |
  | `off` | off | — | 0 | 0 |

  Same colour code as James's diagrams: green passed, red failed, blue in
  flight, amber waiting.
- **The Vitruvian app does not use this table for GitHub status.** Its GitHub
  sink (`GitHubPeripheralSink`) calls the CLI directly (`breathe <color>` or
  `color <color>`), with colours and modes from user preferences. Its one
  extra state, **awaiting approval** (something is paused for James's
  approval), is sent as `breathe blue --speed 9`: fast breathing blue, the
  fastest speed (range 0-9). It has no `StatusSignal` case. On the mouse it
  outranks everything: awaiting approval > red > amber > green > grey. See
  `2026-10-07-notch-github-feature-design.md` section 5.
- `protocol StatusIndicator { func signal(_: StatusSignal) throws; func restore() throws }`.
- `MouseStatusIndicator: StatusIndicator` wraps `GravaStarMouse` + a
  `BaselineStore`. On `signal`, it reads the current config; if it is **not** one
  of the preset configs, it is the user's own look and is saved as the baseline
  (`~/Library/Application Support/Vitruvian/peripherals/gravastar-baseline.json`,
  overridable for tests). `restore()` writes the saved baseline back and keeps
  the file. If no baseline exists, `restore()` is a no-op that reports so.
  Separate CLI processes therefore cooperate through the file, not memory.

### 3.4 `gravastar-mouse` CLI

Subcommands mirror the prototype so the dotfile script can be retired:
`status` (default), `off`, `color <name|#hex> [--brightness N]`,
`breathe <color> [--speed N] [--brightness N]`, `rainbow [--speed] [--brightness]`,
`set --mode M [--color C] [--speed N] [--brightness N]`, plus the new
`signal <working|success|failure|warning|attention|off> [--restore-after SECONDS]`
and `restore`. `--json` on `status` prints the config as JSON for scripts.
Exit codes: 0 ok, 1 device/protocol error, 2 usage error. No ArgumentParser
dependency (zero-dep rule, like HomeSpeaker).

Run as `bazel run //packages/peripherals:gravastar-mouse -- signal success`.

### 3.5 Error handling

Every failure path throws a typed `CompXError`; the CLI maps it to a one-line
stderr message and exit 1. A missing mouse is a normal condition for a
notification source (laptop undocked), so `MouseStatusIndicator` exposes
`isAvailable` and the CLI exits 1 quietly with `mouse not found` — callers in
hooks should treat that as non-fatal (the HomeSpeaker Claude hook convention:
never block the agent).

## 4. Testing

- **Codec (`CompXProtocolTests`)** — golden bytes lifted from the prototype:
  read-lighting frame for `0x00A0/10`, write frame for fixed cyan 7/5, inner
  record CRC, outer CRC = `0x55` invariant, handshake frame shape with a fixed
  nonce, parse of the real captured response
  `[8,8,0,0,0xA0,10,3,0,255,255,5,7,…]` with and without the report-ID byte,
  `Level` rejects 10, `RGB(hex:)` accepts `#00ffcc`/`00FFCC`, rejects `#xyz`.
- **Device (`CompXHIDTests`)** — `GravaStarMouse` over `MockTransport`:
  handshake→read→write call order and exact bytes; `notAcknowledged` when the
  ack echo is wrong; `malformedResponse` on a short read.
- **Signals (`StatusSignalsTests`)** — preset table is total over
  `StatusSignal.allCases`; baseline saved only when the current config is not a
  preset; `restore` writes it back; no-baseline restore is a no-op.
- **CLI** — argument parsing is a pure function (`CLI.parse([String]) -> Command`)
  so it is unit-tested without a device.
- **Hardware (manual, by the implementer and in the PR body):**
  `status` reproduces the prototype's reading; `signal failure` → red breathe;
  `restore` → back to the user's fixed cyan 7/5 (the state recorded on
  2026-10-07 before any change).
- Bazel: `swift_test` targets are macOS-only and `manual`; a `pipeline_unit`
  on `runner = "xcode-27"` runs them in presubmit, mirroring `nexus-agent-macos`.
  `presubmit.yaml` is regenerated with `bazel run //tools/pipeline:gen`.

## 5. Out of scope (follow-ups, not this change)

- Wiring HomeSpeaker's Claude Code `Stop` hook or the esp32 `agent_ci_monitor`
  to call `signal`. This change provides the capability and documents the
  one-liner; adopting it is per-consumer.
- Other CompX flash regions (DPI, polling rate, buttons). The protocol module
  is laid out so they are additive (`FlashAddress` + a record type).
- Linux/Windows transports. `HIDTransport` is the seam.
- A release/publish model for the package.

## 6. Protocol reference (what was reverse-engineered)

Source: CompX ControlHub (controlhub.top) WebHID JavaScript, confirmed on
hardware 2026-10-07 over the 2.4 GHz dongle (`manufacturer "compx"`,
`product "2.4G Dual Mode Mouse"`, `release 0x0134`).

```
USB 3554:F549, interface 1, vendor usage page 0xFF05, numbered output/input
reports, report ID 8, 16-byte payload.

payload[0]   command        1 = handshake ("EncryptionData"), 7 = WriteFlashData,
                            8 = ReadFlashData
payload[1]   0
payload[2:4] flash address  big-endian; lighting = 0x00A0
payload[4]   data length    handshake 8, read-lighting 10, write-lighting 7
payload[5:15] data          up to 10 bytes
payload[15]  crc            (0x55 - reportID - Σ payload[0:15]) mod 256

Lighting record (7 bytes at 0x00A0):
  [mode, r, g, b, speed(0-9), brightness(0-9), crc]   crc = (0x55 - Σ first 6) mod 256
  mode: 0 off · 1 rainbow · 2 single-colour breathe · 3 fixed · 4 neon ·
        5 rainbow breathe · 6 fixed rainbow

Sequence: open vendor-page device → handshake (4 random bytes, read+discard
reply, ~20 ms) → read (reply echoes cmd 8 then the record, ~30 ms) → write
(reply echoes cmd 7 = ack, ~40 ms).
```
