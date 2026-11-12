# Agent Guide — Vitruvian Wand

This document outlines architectural rules, codebase layout, testing patterns, and Bazel workflows for agents working on Vitruvian Wand.

---

## Directory Layout

Vitruvian Wand splits platform-agnostic business logic from platform-specific I/O and UI:

```
apps/suites/vitruvian-wand/
├── AGENTS.md               # This guide
├── README.md               # User-facing overview, features, and default bindings
├── docs/                   # Architecture, setup, and acceptance testing guides
│   ├── architecture.md     # Pipeline and dataflow specification
│   ├── setup-macos.md      # macOS pairing and accessibility guide
│   ├── setup-linux.md      # Linux BlueZ and uinput udev configuration
│   ├── setup-android.md    # Android mobile installation and permissions
│   ├── setup-android-tv.md # Android TV Scan & Pair and ADB setup
│   └── uat.md              # Real-hardware manual acceptance test checklist
├── core/                   # `vitruvian-wand-core`: Pure Rust library
│   └── testdata/           # Hardware packet recording fixtures (`.replay`)
├── desktop/                # `vitruvian-wand`: Desktop binary for macOS & Linux
└── android/                # Universal Android APK for phones and TV
```

---

## The Core Invariant: Pure and Deterministic

`vitruvian-wand-core` must remain completely free of side effects and I/O:

1. **No System Clock**: Use explicit timestamps passed into input samples. Do not call `std::time::Instant::now()` or `SystemTime::now()` inside `core`.
2. **No I/O or Networking**: Do not perform Bluetooth calls, file operations, or OS event injection inside `core`.
3. **Pure Function Interface**: The engine processes incoming packet bytes with a timestamp and returns an action stream:
   ```rust
   // Conceptual core interface
   fn step(&mut self, timestamp_us: u64, packet: &[u8; 20]) -> Vec<Action>;
   ```
4. **Reproducibility**: Feeding the same sequence of timestamped packets into `vitruvian-wand-core` must always produce the exact same sequence of `Action` outputs on every platform and architecture.

---

## Testing Without Physical Hardware

No CI runner has access to a physical Daydream controller. All core testing must run hermetically:

- **Golden Packet Fixtures**: Recorded controller sessions are stored under `core/testdata/*.replay`.
- **Replay File Format**: Each line contains a microsecond timestamp followed by 20 raw hex bytes: `<timestamp_us> <20 hex bytes>`.
- **Clock Mocking**: Button state machines (short, long, double presses) and pointer smoothing filters must be validated against deterministic synthetic clocks.
- **Output Fakes**: The desktop (`CGEvent` / `uinput`) and Android (`AccessibilityService`) output layers must sit behind testable traits with mock or fake implementations.
- **Manual Hardware UAT**: Real-hardware validation is reserved for manual sign-off by James using the checklist in [docs/uat.md](docs/uat.md).

---

## Clean-Room Rule

Vitruvian Wand uses ideas from the public README of `kaminoer/Dream-Mouse` as functional requirements only:

- **Strict Isolation**: Do not inspect, copy, or incorporate any source code, reverse-engineered binaries, graphical assets, icons, or documentation text from Dream-Mouse.
- **Permitted Protocol Reference**: The Daydream BLE wire protocol and bit unpack formulas are derived solely from [mrdoob/daydream-controller.js](https://github.com/mrdoob/daydream-controller.js) (MIT License). Credit this source in decoder doc comments.
- **Original Implementation**: All Rust algorithms, state machines, gesture detectors, and UI components must be written from scratch.

---

## Standard Bazel Targets

Always use Bazel entrypoints for building, testing, and formatting. Never invoke raw `cargo` or `gradle`:

```bash
# Run all unit and replay tests for vitruvian-wand-core
bazel test //apps/suites/vitruvian-wand/core/...

# Format code and markdown across the workspace
bazel run //tools/format -- apps/suites/vitruvian-wand

# Build desktop binary
bazel build //apps/suites/vitruvian-wand/desktop:vitruvian-wand

# Build universal Android APK
bazel build //apps/suites/vitruvian-wand/android:vitruvian_wand_apk
```
