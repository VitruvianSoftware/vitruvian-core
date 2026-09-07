# Vitruvian Remote

A remote control and observability console for a Mac, built in the
[Vitruvian](../packages/design-system/README.md) design language and shaped for a
foldable — specifically the Pixel 11 Pro Fold, folded, unfolded and in tabletop
posture.

It drives the host (trackpad, keys, media, volume and brightness, power,
clipboard, scripted macros, prompts to a coding agent), shows dashboards for the
machine itself (CPU / GPU / Neural Engine, memory pressure, thermals, battery,
disk, network, processes, Lima VMs and K3s nodes, Docker), and hosts **modules** —
installable per-app dashboards with their own widgets and macros.

## Status

**Control and observability are both real, with a paired Mac agent. Every
number on screen is either measured or labelled as unavailable.**

Two transports:

- **Bluetooth HID** — the phone pairs as a keyboard and mouse, so the Mac
  needs nothing installed. Pointer, click, drag, scroll, typing, media,
  volume and brightness keys, display sleep, lock, Spaces, Mission Control,
  Launchpad, Spotlight, screenshots, window controls and the display-mirror
  toggle (⌘F1) all work this way.
- **The agent** — [`macagent/`](macagent/README.md), a small Go daemon on the
  Mac, reached over Tailscale. It answers the questions HID cannot: CPU,
  memory, battery, disk, network, thermals, top processes, Lima VMs,
  containers, K3s nodes, Claude Code sessions, volume, and PromQL through
  Grafana for GPU / Neural Engine / SoC *power*. Once **paired** with the
  six-digit code, it also runs the macros, the console, prompts to Claude
  Code, clipboard push/pull, volume set, and restart. The contract is
  [`macagent/API.md`](macagent/API.md).

The Home screen carries a tag that is never hidden: `LIVE`, `SIMULATED`
(no agent configured — the app runs on `state/MockHost.kt` exactly as it
shipped) or `UNREACHABLE` (an agent is configured and not answering; the
numbers freeze rather than pretend).

What is honestly **not** readable on macOS without root or extra tools, and
is shown as such rather than guessed: SoC temperature and fan speed (the
battery's own sensor is shown instead), GPU / ANE *load* (power is shown, from
`ops/macos-power-agent` via Prometheus), display brightness (the keys work; no
read-back), and now-playing media (the transport keys work; no title). Tokens
used by Claude Code are not exposed by its CLI. Wake-on-LAN sends a real magic
packet but only reaches a Mac on the same LAN as the phone.

## Build

```sh
export ANDROID_HOME=/path/to/android-sdk   # API 35 platform + build-tools
bazel build //mobile/android/remote:app
adb install -r bazel-bin/mobile/android/remote/app.apk
```

The Android SDK is the one non-hermetic toolchain in this repo: Google does not
redistribute it under a licence that permits vendoring, so `ANDROID_HOME` has to
point at a local install. Nothing else in the monorepo is affected — without it
only the two Android packages fail to build.

Depends on `//packages/design-system-android:lib`, which is where every colour, size
and font comes from. Nothing in this app defines a design value of its own.

## Layout

| Path        | What                                                                                             |
| ----------- | ------------------------------------------------------------------------------------------------ |
| `state/`    | `RemoteState` (one observable holder), the models, `MockHost` and the `SharedPreferences` layer. |
| `shell/`    | Posture detection, the adaptive shell, and the dock pane.                                        |
| `screens/`  | Home, Remote, Mac, Apps, Console, Hosts.                                                         |
| `overlays/` | Confirmation dialogs, the macro editor, the offline banner and the unpaired empty state.         |

## Postures

The shell is one composition for all three:

| Posture                     | Window       | Shell                                                                                                                   |
| --------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Folded (outer 6.4″)         | 412 × 924 dp | One column. 55 dp top bar, 55 dp glass tab bar, five tabs.                                                              |
| Unfolded (inner 8″)         | 840 × 820 dp | 89 dp rail (six destinations, dock toggle, host status). Content pane plus a 300 dp dock.                               |
| Tabletop (hinge horizontal) | 840 × 820 dp | Rail stays. Content above the hinge, dock below it, dashed rule between. On Remote the dock becomes trackpad and media. |

Width decides the shell (`WindowSizeClass`: compact → tab bar, anything wider →
rail) and `FoldingFeature` decides tabletop (`HORIZONTAL` + `HALF_OPENED`). Boards
re-flow through `AutoGrid`, which is `repeat(auto-fit, minmax(N, 1fr))` — so a
screen does not know which posture it is in.

Verify against a real Pixel 11 Pro Fold: the dp figures above are extrapolated
from the 9/10 Pro Fold and are the only invented values in the design.

## What is missing

- **Exec runs as the user with no per-command policy.** A paired phone can run
  anything the user can. That is the product, but a per-macro allow-list
  would be a reasonable next fence.
- **No release pipeline.** `:app` is debug-signed. A release needs a signing
  config, a `versionCode` source and a distribution channel decided.
- **No screenshot tests.** The design system's definition of done asks for a
  preview per component in both themes, screenshot-tested; the previews are not
  written yet.
- **Module gallery entries without a source** (Antigravity, Ollama, Xcode,
  Grafana panel) render an honest "not wired to this Mac yet" dashboard.

## Design source

The design is `packages/design-system/ANDROID.md` plus the tokens in
`packages/design-system/src/tokens.json`, and this app is a direct
implementation of a Claude Design handoff built on both. Colours, type, spacing
and copy are final and token-derived; if a value here disagrees with
`tokens.json`, `tokens.json` is right.
