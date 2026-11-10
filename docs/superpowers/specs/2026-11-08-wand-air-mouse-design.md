---
status: draft
date: 2026-11-08
---

# Wand: a Daydream controller as an air mouse, in Rust

> **Working name.** "Wand" is a placeholder. The product must not use the name, icon,
> screenshots or wording of Dream-Mouse.

## 1. What this is

Wand turns a Google Daydream controller into a wireless mouse for **macOS, Linux,
Android phones and Android TV**. Swipe the touchpad to move the pointer, or wave the
controller (gyro mode). Every button can be bound to clicks, keys, media, navigation,
app launches or a radial menu.

It takes its feature list from the public README of
[kaminoer/Dream-Mouse](https://github.com/kaminoer/Dream-Mouse). That repository
contains **no source code** (only a README) and is "All rights reserved", so this is a
**clean-room** build: we use its feature list as requirements and nothing else — no
code, icon, screenshots or text.

The Daydream wire format comes from
[mrdoob/daydream-controller.js](https://github.com/mrdoob/daydream-controller.js)
(MIT). Credit it in the README and in the decoder's doc comment.

## 2. Scope

**v1 = full Dream-Mouse parity for the Daydream controller.**

In scope:
- Touchpad mouse mode and gyro mouse mode, toggleable.
- Click, drag (hold click + move), tap-to-click, scroll (volume keys, touchpad
  scrolling in gyro mode, horizontal scroll optional).
- Per-button **short / long / double** press bindings (5 Daydream buttons: click,
  app, home, vol+, vol−; plus touchpad tap = 6 slots × 3 = 18).
- Trigger modes for desktop actions: once, hold (while pressed), toggle.
- Actions: left/right click, scroll 4 ways, media (play/pause, next, prev), volume,
  brightness, keyboard keys and chords (desktop), system actions (copy, paste,
  app switcher), toggle gyro, launch app, radial menu (desktop), Android navigation
  (back, home, recents, notifications, quick settings), D-pad (Android TV),
  screen off (Android), voice/assistant (Android).
- Radial menu (desktop): hold a bound button, 8 slots, move toward one, release to run.
  Labels, colours and actions configurable.
- Test mode: live visualiser of touch point, buttons and motion; pointer output off.
- Settings: touch sensitivity, gyro X/Y speed, gyro deadzone, touch deadzone,
  acceleration curve (1.0 = linear), EMA smoothing, reverse scroll, scroll strength,
  touchpad tap on/off per mode, auto-reconnect, reset to defaults.
- Recalibrate (controller flat on a surface), battery level with a low-battery
  (<15 %) alert.
- Android: overlay cursor (show/hide, size), foreground notification with
  Disconnect / Recalibrate, accessibility-permission flow.
- Android TV: in-app **Scan & Pair**, the ADB `WRITE_SECURE_SETTINGS` path to
  enable the accessibility service on TVs that hide that setting, and touchpad
  swipes moving **D-pad focus** in gyro mode.

Out of scope for v1 (the design leaves room):
- **Gear VR controller.** James has no Gear VR to test with. `Controller` is a trait;
  a Gear VR decoder is a later, separate change.
- Windows (not asked for).

## 3. Architecture

```
Daydream controller ── BLE notify, 20-byte packets, service 0xFE55 ──┐
                                                                     ▼
            Transport (per platform)                     wand-core (pure Rust, no I/O)
  desktop: btleplug (CoreBluetooth / BlueZ)  ──bytes──▶  decode → calibrate → pointer engine
  Android: Kotlin BluetoothGatt ──JNI──────▶                         button/gesture engine
                                                                     binding resolver
                                                                         │ Action stream
            Output (per platform)            ◀───────────────────────────┘
  macOS: CGEvent   Linux: uinput   Android: AccessibilityService (via JNI callback)
```

`wand-core` is deterministic: it takes `(bytes, timestamp)` and returns `Vec<Action>`.
No threads, clocks or Bluetooth inside it. That is what makes it testable without a
controller and identical on all four platforms.

### 3.1 Layout

```
apps/suites/wand/
  AGENTS.md  README.md  BUILD  catalog-info.yaml  CHANGELOG.md
  core/        Rust lib  wand-core      (protocol, engines, config, replay format)
  desktop/     Rust bin  wand           (macOS + Linux: transport, output, UI, tray)
  android/     Kotlin app + Rust cdylib wand-jni (phone + TV, one APK)
  docs/
```

### 3.2 `wand-core`

- `protocol::daydream::decode(&[u8; 20]) -> Sample` — buttons, touch (x, y in 0..1,
  touching flag = x or y non-zero), orientation, accel, gyro (rad/s), seq, time.
  Port the bit layout from mrdoob's decoder. **Known suspect:** its `xOri` reads
  `(byte3 & 0x80) >> 5`; every other field shifts the carried bit into bit 0, so
  this is probably `>> 7`. Decide from recorded real packets, and pin the decision
  in a test.
- `Controller` trait: `name()`, `service_uuid()`, `notify_uuid()`, `decode()`.
  `Daydream` implements it. BLE: advertised name `Daydream controller`, service
  `0000fe55-0000-1000-8000-00805f9b34fb`, notify characteristic
  `00000001-1000-1000-8000-00805f9b34fb`; battery via standard Battery Service
  `0x180F` / `0x2A19`.
- `calibration` — gyro bias from N samples while still; reject if motion exceeds a
  threshold (report "keep it flat").
- `pointer` — touch mode (delta of touch position × sensitivity, touch deadzone,
  ignore the first sample after touch-down to avoid jumps), gyro mode (bias-corrected
  gyro × X/Y speed, deadzone, acceleration curve `v' = sign(v)·|v|^curve`, EMA
  smoothing α). Output: `Action::Move { dx, dy }` in device-independent units.
- `buttons` — per button state machine producing short / long / double press with
  configurable thresholds (defaults: long 500 ms, double gap 300 ms). A button with
  no double binding fires short immediately on release (no 300 ms delay). Trigger
  modes once / hold / toggle.
- `bindings` — `Config { profile per controller, slots: Map<(Button, Press), Binding> }`,
  `Binding { action, trigger_mode }`. Defaults match the Dream-Mouse README table
  (touchpad click/tap = left click; home = right click on desktop, back/home on
  Android; app = toggle gyro; vol± = scroll).
- `radial` — given cursor offset from the menu origin, which of 8 slots is selected
  (dead centre = none).
- `config` — serde, TOML on desktop, JSON on Android; versioned; unknown keys kept.
- `replay` — a simple file format of `(t_us, 20 bytes)` lines so packets recorded on
  one machine replay anywhere. `wand record` / `wand replay` on desktop.

### 3.3 Desktop (`wand`, macOS + Linux)

- Transport: `btleplug`. Scan by name/service, connect, subscribe, auto-reconnect.
- Output trait `Injector { move_rel, button, scroll, key, media, ... }`:
  - macOS: `CGEventPost` (core-graphics). Needs Accessibility permission; detect and
    deep-link to the settings pane. Media/brightness keys as `NSSystemDefined` events.
    Ship as a signed `.app` (Developer ID) with `NSBluetoothAlwaysUsageDescription`.
  - Linux: a `uinput` virtual mouse + keyboard (works on X11 **and** Wayland). Ship a
    udev rule for `/dev/uinput`; detect and explain missing access.
- UI: `eframe`/`egui` settings window (Connection, Options, Button Bindings, Radial
  Menu, Test Mode tabs) + tray icon (`tray-icon`). Follow the Vitruvian design tokens
  (`packages/design-system`) for colours and type — read them, don't invent them.
- Radial menu: borderless, transparent, always-on-top window at the cursor. Wayland
  does not let apps place windows at the cursor: fall back to centring on the active
  output, and say so in the docs.
- Launch-app action: macOS `open -b <bundle id>`, Linux `.desktop` entry via `gio launch`.

### 3.4 Android (`android/`, phone + TV in one APK)

- Kotlin shell; all decoding/engines in Rust via `wand-jni` (`jni` crate), built for
  `aarch64-linux-android` and `armv7-linux-androideabi` (many TVs are 32-bit ARM).
- Transport: Kotlin `BluetoothGatt` (Android's own BLE stack is the reliable path);
  each notification goes to Rust; Rust returns actions; Kotlin performs them.
- `AccessibilityService`: `dispatchGesture` for tap / long-press / drag / scroll swipes,
  `performGlobalAction` for back/home/recents/notifications/quick settings,
  `AccessibilityNodeInfo.focusSearch` for D-pad focus moves on TV, media keys via
  `AudioManager.dispatchMediaKeyEvent`.
- Overlay cursor: `TYPE_ACCESSIBILITY_OVERLAY` view; size setting; hides when
  disconnected.
- A persistent notification (Disconnect, Recalibrate) posted by the accessibility
  service. No separate foreground service: the system keeps an enabled
  accessibility service alive, so one would add a second always-on component for
  nothing. minSdk 26.
- UI in Compose from `packages/design-system-android` only (no local colours/sizes),
  same tabs as desktop minus Radial Menu. TV: leanback launcher entry, D-pad-navigable
  layout chosen at runtime by `UiModeManager`; Scan & Pair screen; ADB grant
  instructions with the exact command for *this* package id and a **Try enable** button.

## 4. Testing

No CI machine has a Daydream controller, so:

- `wand-core` unit tests cover every decoder field (golden packets), calibration,
  each pointer setting, every press type and trigger mode with a fake clock,
  radial slot selection, config round-trip and defaults.
- Replay tests: recorded packet files in `core/testdata/` drive the full engine and
  assert the action stream. James records the first real files with `wand record`.
- Desktop and Android output layers sit behind traits with fakes; the engine-to-output
  wiring is tested against the fakes.
- Android: JVM unit tests for the Kotlin glue; instrumentation where Bazel allows.
- **Real-hardware acceptance is James's**: a by-hand checklist in `docs/uat.md`
  (connect, both modes, every default binding, radial menu, TV focus moves, ADB path).

## 5. Acceptance criteria (plain terms)

1. On a Mac, pair the Daydream controller, open Wand, press Connect: swiping the
   touchpad moves the pointer; pressing it clicks; holding it and moving drags.
2. Pressing the App button switches to gyro mode: waving moves the pointer, and
   small hand tremors don't (deadzone works).
3. Volume keys scroll; Home right-clicks (desktop) / goes back, hold for home (Android).
4. Any button can be rebound for short, long and double press, and the choice
   survives a restart.
5. Holding a radial-bound button shows 8 slices at the cursor; releasing over one
   runs it (macOS, Linux X11; Wayland centred).
6. Test mode shows touch, buttons and motion live, and the pointer doesn't move.
7. Battery level shows, and an alert appears under 15 %.
8. The same works on a Linux desktop (X11 and Wayland) via uinput.
9. On an Android phone, after granting accessibility, a cursor overlay appears and
   taps, drags, scrolls, back/home work.
10. On Android TV, Scan & Pair finds and pairs the controller in the app; the ADB
    command shown enables the service; in gyro mode touchpad swipes move focus
    between tiles.

## 6. Build and release

- Bazel only. Rust crates come from the root `Cargo.toml` workspace / `@crates`.
  The repository's default Rust toolchain is 1.75.0, too old for current `btleplug`,
  `eframe` and `jni`, and the crate universe has no Android triples — see the forge
  investigation (plan task 1).
- One product, `wand`, in `release-please-config.json`; desktop artifacts
  (macOS `.app` signed, Linux binary + udev rule) and one APK.
- License headers on every new file; conventional commits.
