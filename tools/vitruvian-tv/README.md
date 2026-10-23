# Vitruvian TV Extension (`dev.vitruvian.tv`)

A Protocol 2 Vitruvian extension for controlling a Sony BRAVIA 4K Google TV over Network ADB (`_adb._tcp`) from the Vitruvian Dynamic Island, Command Bar, Radial Menu, and Shortcuts.

## Features

- **Dynamic Island Panel (`tv`):**
  - Displays live wake state (`Awake` / `Standby`), foreground app (`Projectivy Home`, `SmartTube 4K`, `AerialViews 4K`, `Disney+`, `Netflix`), and available RAM (`MemAvailable`).
  - **1-Click Controls:** Atomic power toggle (`Wake` / `Sleep`), start 4K Aerial screensaver (`AerialViews`), cast HTTP(S) video URLs from the macOS clipboard directly to SmartTube, launch TV apps, switch HDMI inputs (`HDMI 1–4`), and adjust volume/mute.
- **Closed-Island Status (`contributes.status`):**
  - Displays a live indicator (`TV`, `YT`, or `4K`) on the closed island while the TV is awake.
- **Settings Panel (`settings`):**
  - Configure the TV ADB endpoint (`tvAddress`, default `192.168.86.31:5555`), toggle closed-island status, and trigger background cache trimming (`pm trim-caches`).

## Building & Validating

```sh
# Build the self-contained extension folder (with bundled vitruvian_tool_kit in lib/)
bazel build //tools/vitruvian-tv:tool-folder

# Run unit tests + Vitruvian SDK conformance suite
bazel test //tools/vitruvian-tv:vitruvian_tv_test
```

To add the built folder in the Vitruvian macOS app, open **Settings → Extensions → Add from Folder…** and select `bazel-bin/tools/vitruvian-tv/built/vitruvian-tv` (or `~/.config/vitruvian/vitruvian-tv-tool`).
