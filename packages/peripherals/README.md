# peripherals

Turns the RGB light on a GravaStar mouse into a status light for the Mac.
Anything that runs on the Mac (a Claude Code hook, a CI watcher, HomeSpeaker)
can make the mouse glow **blue while working, green on success, red on
failure**, then put back the lighting you had before.

It is a Swift package with no third-party dependencies. It talks to the mouse
over IOKit HID, the same way the vendor's web tool (controlhub.top) does.
Supported hardware: GravaStar Mercury, CompX chipset, USB `3554:F549`, over
the 2.4 GHz dongle, on macOS 14 or later.

## Use it

```sh
bazel run --config=macos-app //packages/peripherals:gravastar-mouse -- status
bazel run --config=macos-app //packages/peripherals:gravastar-mouse -- signal failure
bazel run --config=macos-app //packages/peripherals:gravastar-mouse -- restore
```

`--config=macos-app` is required for every Swift target in this repo, not
just this one: without it Bazel uses the hermetic LLVM toolchain, which cannot
compile Swift for macOS.

| Command | What it does |
|---|---|
| `status [--json]` | Show the current lighting (the default command) |
| `signal <name> [--restore-after SECONDS]` | Show a status signal (see below) |
| `restore` | Put back the lighting saved before the last signal |
| `color <color> [--brightness N]` | Solid colour |
| `breathe <color> [--speed N] [--brightness N]` | One colour, fading in and out |
| `rainbow [--speed N] [--brightness N]` | Rainbow cycle |
| `off` | Light off |
| `set --mode M [--color C] [--speed N] [--brightness N]` | Anything else |

Colours are names (`red green blue cyan magenta purple yellow orange white
pink`) or hex (`#00ffcc`). Speed and brightness are 0 to 9. Add `--trace`
before the command to print every byte sent to and received from the mouse.

Exit codes: **0** ok, **1** the mouse is missing or did not answer, **2** bad
command line.

## Signals

| Signal | Looks like | Means |
|---|---|---|
| `working` | blue `#0000FF`, breathing (speed 5, brightness 7) | something is in flight |
| `success` | green `#00FF00`, solid (5, 7) | it passed |
| `failure` | red `#FF0000`, breathing faster and brighter (7, 9) | it failed |
| `warning` | amber `#FF8000`, solid (5, 7) | waiting or degraded |
| `attention` | magenta `#FF00FF`, breathing (5, 7) | a person is needed |
| `off` | light off | |

The colours follow the same code as the repo's diagrams: green passed, red
failed, blue in flight, amber waiting. To add a signal, add a case to
`StatusSignal` and a row to `StatusPresets` in `Sources/StatusSignals/`.

### Putting your own lighting back

Before showing a signal, the tool reads the mouse. If the mouse is showing
anything other than one of the signals above, that is your own look, and it
is saved to:

```
~/Library/Application Support/Vitruvian/peripherals/gravastar-baseline.json
```

`restore` writes that back. The file is kept, so restoring twice is harmless.
Because the baseline is a file, separate runs work together: one hook can
signal and a later one can restore. If nothing was ever saved, `restore` says
so and changes nothing.

`--restore-after SECONDS` waits and then restores, but only if the mouse is
still showing that same signal. A newer signal, or a change you made by hand
in the meantime, is left alone.

## Wiring a notification source

A missing mouse is normal (the laptop is undocked), so callers should never
fail because of it. The tool exits 1 with `mouse not found`; ignore it.

Build once and put the binary on your `PATH`, so hooks don't pay Bazel's
start-up cost:

```sh
bazel build --config=macos-app //packages/peripherals:gravastar-mouse
install -m 755 bazel-bin/packages/peripherals/gravastar-mouse ~/.local/bin/
```

**Claude Code hook.** In `~/.claude/settings.json`, show green for ten
seconds whenever Claude finishes a turn:

```json
{"hooks": {"Stop": [{"hooks": [{"type": "command",
  "command": "gravastar-mouse signal success --restore-after 10 >/dev/null 2>&1 &"}]}]}}
```

The trailing `&` keeps the hook from waiting out the ten seconds.

**Shell.** Light up while a long command runs, then show how it went:

```sh
gravastar-mouse signal working 2>/dev/null
if make test; then s=success; else s=failure; fi
gravastar-mouse signal "$s" --restore-after 30 2>/dev/null &
```

**Swift.** Depend on `//packages/peripherals:StatusSignals`:

```swift
import CompXHID
import StatusSignals

let mouse = try GravaStarMouse.open()
defer { mouse.close() }
try MouseStatusIndicator(mouse: mouse).signal(.failure)
```

## Layout

| Module | Job |
|---|---|
| `CompXProtocol` | The byte format: frames, checksums, the lighting record. No IOKit, so it tests anywhere. |
| `CompXHID` | `HIDTransport` (the seam), the IOKit transport, and the `GravaStarMouse` facade. |
| `StatusSignals` | Signal to colour presets, plus baseline save and restore. |
| `GravaStarCLI` | Argument parsing (a pure function) and command execution. |
| `gravastar-mouse` | The executable: three lines that call `GravaStarCLI`. |

`Package.swift` and `BUILD` describe the same targets and must stay in step.
Tests need no mouse: `bazel test --config=macos-app //packages/peripherals:PeripheralsTests`,
or `swift test` in this directory.

## Protocol reference

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

Notes from building the IOKit side (verified on hardware 2026-10-07):

- On macOS all of interface 1's collections are **one** `IOHIDDevice`, whose
  primary usage page is `0xFF05`. Matching on vendor ID, product ID and that
  usage page finds it. The mouse's other reports arrive on the same callback,
  so anything that is not report 8 is dropped.
- Output reports go through `IOHIDDeviceSetReport` with the report ID both as
  the argument **and** as the first buffer byte, as hidapi does on macOS.
- The input-report callback buffer **includes** the report ID at `[0]`, the
  same 17 bytes hidapi returns. The parsers still take an `includesReportID`
  flag, and both shapes are tested.
- The device is opened with `kIOHIDOptionsTypeNone`. Never seize it: it is
  also the pointer.

## License

Copyright (c) 2026 VitruvianSoftware. MIT Licensed.
