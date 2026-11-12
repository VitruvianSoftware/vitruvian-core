# Vitruvian Deck (vitruvian-deck) — agent guide

> Scoped to `apps/embedded/vitruvian-deck/`. Repo-wide rules live in the root
> [`AGENTS.md`](../../../AGENTS.md); the developer SOP is
> [`CONTRIBUTING.md`](../../../CONTRIBUTING.md), which wins on any conflict. This directory is
> the canonical, sole source of truth for Vitruvian Deck firmware and its host daemon.

## What this is

C++ firmware (PlatformIO `espressif32`, LVGL 8.4) for the Waveshare ESP32-S3-Touch-LCD-1.69: a
Mac desk companion that shows live Mac metrics and agent/CI status and sends macOS shortcuts over
USB HID or BLE HID. `src/` is the firmware, `include/` its pin and LVGL config,
`host-companion/` the Rust daemon (`vitruvian-deck`) that streams telemetry over USB CDC or UDP (mDNS), and
`tests/` the Rust test suite for the daemon, wire protocol, and ArduinoJson stress tests. The wire
protocol is [`docs/protocol.md`](docs/protocol.md); firmware and daemon move together.

## Build, test, run

- **Toolchain.** PlatformIO is a uv tool: `uv tool install platformio --with pip` (a uv tool venv
  ships without pip, and PlatformIO shells out to `python -m pip`; without it CI hit "No module
  named pip" and a corrupt toolchain unpack). Bazel does not fetch it;
  the firmware `genrule` shells out to `pio` and is tagged `manual`, `local`, `no-remote-exec`
  and `requires-network`, so it is never in `bazel build //...` and never runs on the remote
  executors.
- **Build.** `bazel build //apps/embedded/vitruvian-deck:firmware` →
  `bazel-bin/apps/embedded/vitruvian-deck/{firmware,bootloader,partitions}.bin`.
- **Flash.** `bazel run //apps/embedded/vitruvian-deck:flash [-- /dev/cu.usbmodemXXXX]`. PlatformIO,
  esptool and OTA alternatives are in [`docs/flashing.md`](docs/flashing.md).
- **Host tests (what CI runs).** From the repo root:
  `bazel test //apps/embedded/vitruvian-deck/...` —
  the exact step in `.github/workflows/iot-vitruvian-deck.yaml`, which then builds the firmware.
- **Daemon.** `bazel run //apps/embedded/vitruvian-deck:vitruvian-deck`
  (`--usb-only`, `--wifi-only`, `--wifi-host <ip>`, `--wifi-sync`).

## Conventions & landmines

- **Images are unstamped by design.** A Bazel action sees no `HOME`, no `.git` and none of the
  caller's environment, so version/grade/commit stamping (`build_info.json`) and the zip happen
  in the Rust `publish` tool (`host-companion/src/publish/`), outside Bazel. Do not add `--stamp` or a workspace-status dependency to the
  genrule.
- **Release ladder** is the `vitruvian-deck` delivery unit declared in `BUILD` (`delivery(...)`):
  a PR runs `iot-vitruvian-deck.yaml`; a push to `main` publishes `vitruvian-deck-beta` (rolling
  `vitruvian-deck-beta-latest` prerelease) through the generated `delivery-vitruvian-deck.yaml`; release-please
  (`iot-vitruvian-deck-release.yaml`) cuts `vitruvian-deck-vX.Y.Z`, which publishes `vitruvian-deck-production`.
  Editing the `delivery()` block means `bazel run //tools/ci:gen` to regenerate `delivery-vitruvian-deck.yaml`.
  Break-glass: `bazel run //apps/embedded/vitruvian-deck:publish`
  (`GRADE=production RELEASE_TAG=vitruvian-deck-vX.Y.Z` for a release build).
- **Protocol changes touch three places in one PR:** `src/` (firmware), `host-companion/`
  (daemon) and `docs/protocol.md`, plus a test in `tests/`.
- **The device talks to GitHub on its own** (`cloud_ci.cpp`, after 15 s without a host) against
  roots pinned in `src/github_ca.h`; a CA rotation is a firmware release, not a config change.
- **Persisted settings live in NVS** (deck visibility, chime mute, Wi-Fi, OTA password). A new
  setting needs a default that survives an upgrade from an older image.
- `docs/` is a TechDocs site (`mkdocs.yml`); `bazel run //tools/techdocs:check` must still
  compile it after a docs change.
