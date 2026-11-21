# Vitruvian Remote

Formerly **android-remote**. Releases up to 0.1.39 are tagged `android-remote-v*`; later ones are `vitruvian-remote-v*`.

A remote control and observability console for a Mac, built in the
[Vitruvian](../../../packages/design-system/web/README.md) design language and shaped for a
foldable — specifically the Pixel 11 Pro Fold, folded, unfolded and in tabletop
posture.

It drives the host (trackpad, keys, media, volume and brightness, power,
clipboard, scripted macros, prompts to a coding agent), shows dashboards for the
machine itself (CPU / GPU / Neural Engine, memory pressure, thermals, battery,
disk, network, processes, Lima VMs and K3s nodes, Docker), and displays **modules** —
per-app dashboards you can show or hide, with their own widgets and controls.

## Status

**Control and observability are both real, with a paired Mac agent. Every
number on screen is either measured or labelled as unavailable.**

Two transports:

- **Bluetooth HID** — the phone pairs as a keyboard and mouse, so the Mac
  needs nothing installed. Pointer, click, drag, scroll, typing, media,
  volume and brightness keys, display sleep, lock, Spaces, Mission Control,
  Launchpad, Spotlight, screenshots, window controls and the display-mirror
  toggle (⌘F1) all work this way.
- **The agent** — [`macagent/`](macagent/README.md), a small Rust daemon on the
  Mac, reached over Tailscale. It reports the version of the installed release.
  It answers the questions HID cannot: CPU,
  memory, battery, disk, network, thermals, top processes, Lima VMs,
  containers, K3s nodes, Claude Code sessions, volume, and PromQL through
  Grafana for GPU / Neural Engine / SoC *power*. Once **paired** with the
  six-digit code or QR code, it also runs the macros, the console, prompts to
  Claude Code, clipboard push/pull, volume set, and restart. The contract is
  [`macagent/API.md`](macagent/API.md).
- **The menu bar app** — [`macmenu/`](macmenu/README.md), a small macOS app
  that shows whether the agent is up and a phone is linked, and pairs,
  unpairs and restarts it without a terminal. It is separate from
  Vitruvian Speaker on purpose.

The Home screen carries a status tag: `LIVE` (your Mac helper is answering),
`SIMULATED` (when you choose **See a demo** on the start screen with no Mac paired), or
`UNREACHABLE` (a paired Mac is not answering; readings freeze rather than pretend).

## First run

A fresh install opens unpaired. The first screen says **No Mac paired** and offers three choices: **Pair a Mac**, **Install guide**, and **See a demo**.

- **See a demo** runs simulated dashboards for the current session only. Demo state is not saved, and **Exit demo** returns to the unpaired screen.
- A real install starts with no default macros and no homelab or other extra modules enabled. Built-in sample macros appear only in demo mode.
- You can create, edit, and delete macros in **Settings**.
- In **Modules → Gallery**, modules are turned on and off with **Show** and **Hide** (they are not installed or removed).

## Pairing

1. On your phone, open Vitruvian Remote and tap **Pair a Mac**. A six-digit code appears.
2. On your Mac, install the Mac helper by following the [setup guide](https://github.com/VitruvianSoftware/vitruvian-remote#readme).
3. Click the Vitruvian Remote icon in your Mac's menu bar. Before the Mac helper is installed and running, the menu shows **Copy Install Command** instead of pairing options. Once the Mac helper is running, the menu shows **Pair with QR Code…** and **Pair with a Code…**:
   - **Pair with QR Code…** shows a QR code on your Mac. Scan it with your phone's camera, open the link, tap **Open in Vitruvian Remote**, and confirm on your phone. QR pairing requires Tailscale on your Mac; if Tailscale is not connected, the Mac helper tells you to use the six-digit code instead.
   - **Pair with a Code…** asks for the six-digit code shown on your phone.

## Privacy

Vitruvian Remote has no account and no ads. Crash reports are on by default and can be turned off in **Settings → About → Privacy**. Remote control and telemetry requests go only to the Macs you add, trackpad and keys go over Bluetooth, and Phone Bridge stays off until you turn it on. See the [Privacy guide](docs/PRIVACY.md) for the full list of what leaves the phone and what stays on it.

## About and Support

You can open the About screen from **Settings → About**. It shows the installed version, a **Support** section with **Donate** and **Star on GitHub**, and links for **Source code**, **Privacy**, **License** (MIT), **Open-source licenses**, **Help and feedback** (GitHub Issues), and **Setup guide** ("Install the Mac helper").

Tapping **Donate** opens `https://vitruviansoftware.dev/donate/vitruvian-remote/` in your browser (with a source query tag added by the app), which forwards to the payment page. Apps never embed Stripe URLs.

What is honestly **not** readable on macOS without root or extra tools, and
is shown as such rather than guessed: SoC temperature and fan speed (the
battery's own sensor is shown instead), GPU / ANE *load* (power is shown, from
`tools/ops/macos-power-agent` via Prometheus), display brightness (the keys work; no
read-back), and now-playing media (the transport keys work; no title). Tokens
used by Claude Code are not exposed by its CLI. Wake-on-LAN sends a real magic
packet but only reaches a Mac on the same LAN as the phone.

## Build

```sh
export ANDROID_HOME=/path/to/android-sdk   # API 35 platform + build-tools
bazel build //apps/mobile/vitruvian-remote:app
adb install -r bazel-bin/apps/mobile/vitruvian-remote/app.apk
```

The Android SDK is the one non-hermetic toolchain in this repo: Google does not
redistribute it under a licence that permits vendoring, so `ANDROID_HOME` has to
point at a local install. Nothing else in the monorepo is affected — without it
only the two Android packages fail to build.

Depends on `//packages/design-system/android:lib`, which is where every colour, size
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

## Download & Distribution

Pre-compiled release APKs with multi-ABI support (`arm64-v8a` and `x86_64`) and SHA-256 checksum sidecars are published with every release:

- **Permanent Vanity Download:** [`vitruviansoftware.dev/downloads/latest/vitruvian-remote.apk`](https://vitruviansoftware.dev/downloads/latest/vitruvian-remote.apk)
- **Downloads Portal:** [`vitruviansoftware.dev/downloads/#mobile`](https://vitruviansoftware.dev/downloads/#mobile)
- **GitHub Releases:** [`VitruvianSoftware/vitruvian-core/releases?q=vitruvian-remote`](https://github.com/VitruvianSoftware/vitruvian-core/releases?q=vitruvian-remote)

Releases are managed via release-please (`release-please-config.json`, `.release-please-manifest.json`) and automated via `.github/workflows/vitruvian-remote-release.yaml`. When a release PR merges on `main`, the workflow compiles the APK with `tools/src/publish.rs` and attaches `VitruvianRemote-X.Y.Z.apk` to the tag.

## Updates

**In the app.** Settings → About checks for a newer version when it opens (at most
once an hour) and shows "Update available: X.Y.Z" with what changed. **Update**
downloads the APK and installs it over the app, so Macs, pairings and settings
stay. The first time, Android asks you to allow Vitruvian Remote to "Install
unknown apps"; the app explains why before sending you there.

What it trusts, in order:

1. **The feed's signature.** `vitruviansoftware.dev/updates/android/vitruvian-remote.json`
   names the release's APK, its size and SHA-256. It is signed with the same
   Ed25519 key as the Mac app's tool catalogue (`catalog/public-key.txt`), by
   `catalog-publish`, over the bytes merged to `main`. The app refuses a feed
   that doesn't verify, names another package, or points anywhere but this
   repository's own `vitruvian-remote-v*` releases.
2. **The download.** Size and SHA-256 must match the feed, and the bytes are hashed
   again as they go into Android's installer.
3. **The signer.** The APK must be signed by the installed app's certificate (or a
   key that certificate rotated to). Android would refuse anything else; checking
   first turns that into a clear sentence and never a reinstall that loses data.

On Android 12+ the install asks for no second confirmation when Android allows
it, which it does for an app updating itself. It does not claim update
ownership (Android 14), so Obtainium and `adb install` keep working.

How a release reaches the feed: the release workflow writes
`vitruvian-remote-update.json` with the APK, checks it against the APK on the
release, and opens a pull request that updates `catalog/android/vitruvian-remote.json`
and merges itself; `catalog-publish` then signs it into the website. The code is
`src/main/kotlin/dev/vitruvian/remote/update/`, tested by `:update_feed_test` and
`:ed25519_test`.

**Without the app's help: Obtainium.** [Obtainium](https://github.com/ImranR98/Obtainium)
(on F-Droid) can follow the GitHub releases directly. Add
`https://github.com/VitruvianSoftware/vitruvian-core`, set **Filter release
titles by regular expression** to `^vitruvian-remote-v`, and **Filter APKs by
regular expression** to `VitruvianRemote-.*\.apk$`. Obtainium checks the signer
matches on every update, as Android does.

There is no F-Droid repository: it would need the APKs hosted on the website and
a second signing key, for what Obtainium already does with no setup on our side.


## What is missing

- **Exec runs as the user with no per-command policy.** A paired phone can run
  anything the user can. That is the product, but a per-macro allow-list
  would be a reasonable next fence.
- **No screenshot tests.** The design system's definition of done asks for a
  preview per component in both themes, screenshot-tested; the previews are not
  written yet.
- **Module gallery.** The "Xcode builds" module was removed (it was never wired).
  "Add by URL" was removed from the module gallery. "Install guide" opens
  `https://github.com/VitruvianSoftware/vitruvian-remote#readme`. Antigravity, Ollama,
  Grafana, Docker, Lima, Sony TV, and Vitruvian Speaker are wired.
- **Vitruvian Speaker.** (`Apps → Vitruvian Speaker`, backed by
  [`macagent/rs/src/speaker.rs`](macagent/rs/src/speaker.rs) and
  [`Vitruvian Speaker`](../../desktop/vitruvian-speaker/README.md)). The door row (app vs
  Vitruvian extension) is offered on the phone only when the extension is
  installed. Choosing the extension without it returns 400; switching doors
  copies nothing and repoints only stale hooks when choosing the extension.
  Google Cloud OAuth setup is always shown on the phone so credentials can be
  configured directly. Chat access (`has_chat_access`) reflects Google Chat
  consent only. The phone can install, update, and remove Vitruvian Speaker hooks for
  Antigravity and OpenCode as well as Claude Code. See the
  [Vitruvian Speaker docs](../../desktop/vitruvian-speaker/README.md) for available controls.

## Design source

The design is `packages/design-system/web/ANDROID.md` plus the tokens in
`packages/design-system/web/src/tokens.json`, and this app is a direct
implementation of a Claude Design handoff built on both. Colours, type, spacing
and copy are final and token-derived; if a value here disagrees with
`tokens.json`, `tokens.json` is right.

## Subdirectories & Boundaries
- [macagent](./macagent/README.md): Contract for apps/mobile/vitruvian-remote/macagent
- [macmenu](./macmenu/README.md): Contract for apps/mobile/vitruvian-remote/macmenu
- [src](./src/README.md): Subsystem blueprint grouping child modules under apps/mobile/vitruvian-remote/src.
- [tools](./tools/README.md): Subsystem blueprint grouping child modules under apps/mobile/vitruvian-remote/tools.

