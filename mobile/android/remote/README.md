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

**Control is real. Observability is not.**

The app drives a Mac today over Bluetooth HID, with **nothing installed on the
Mac** — it pairs as a keyboard and mouse, so macOS needs no agent, no
permissions and no daemon. Pointer, click, drag, two-finger scroll, typing,
media, volume, brightness, display sleep, lock, Spaces, Mission Control,
Launchpad, Spotlight, screenshots and the window controls all reach a real
machine.

One consequence is easy to miss: the volume and brightness **percentages are
the app's own running guess**, not the Mac's real levels. The key press is
real and the Mac responds to it, but nothing reports back, so the meters drift
out of step the moment anyone touches the keyboard on the Mac itself.

Everything the phone *reads* is still fake. Every dashboard — CPU, memory,
thermals, battery, disk, network, processes, Lima, K3s, Docker — is driven by
`state/MockHost.kt`. HID is a one-way channel: it can press keys, it cannot
ask a question.

The same limit rules out anything that has to *run* rather than *type*: the
macros are shell and AppleScript commands, clipboard push/pull needs the host's
pasteboard, Wake-on-LAN needs a packet on the network, and the pairing code
needs something to pair with. Those need the agent — see
[What is missing](#what-is-missing).

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

The Mac side. A small agent on the host (Go, like `devx`/`homelab`) exposing
over Tailscale:

- **Metrics** — `powermetrics`/IOKit, `vm_stat`, `limactl list`, `docker ps`, and
  a PromQL proxy to `grafana.homelab.local`. This is the whole reason the agent
  is needed: it is everything the phone cannot get by pressing a key.
- **Exec** — `pbcopy`/`pbpaste` for the clipboard, and SSH exec for the macros.
  Note that the *controls* this section used to list — media keys, volume,
  brightness, lock — now work over Bluetooth HID and no longer need the agent.
- **Pairing** — the six-digit code this app's Hosts screen shows.
- **A module registry** — manifest plus data source (SSH · HTTP · PromQL · MCP)
  plus widget set.

Agent prompts should route through [`nexus-agent`](../nexus-agent/README.md)
rather than a second bridge.

Also outstanding on this side:

- **No release pipeline.** `:app` is debug-signed. A release needs a signing
  config, a `versionCode` source and a distribution channel decided.
- **No screenshot tests.** The design system's definition of done asks for a
  preview per component in both themes, screenshot-tested; the previews are not
  written yet.
- **Wake-on-LAN is simulated.** The button, the delay and the log line are real;
  the magic packet is not sent.
- **Mirror to Studio Display is a local toggle.** It flips a switch in the app
  and logs a line; nothing reaches the Mac.
- **Clipboard push/pull is simulated.** Pull returns a fixed string.

## Design source

The design is `packages/design-system/ANDROID.md` plus the tokens in
`packages/design-system/src/tokens.json`, and this app is a direct
implementation of a Claude Design handoff built on both. Colours, type, spacing
and copy are final and token-derived; if a value here disagrees with
`tokens.json`, `tokens.json` is right.
