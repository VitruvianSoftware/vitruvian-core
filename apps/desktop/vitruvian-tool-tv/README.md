# Vitruvian TV Extension (`dev.vitruvian.tv`)

A Protocol 2 Vitruvian extension, written in Rust on the SDK's Rust kit (`vitruvian-tool-kit`), for controlling a Sony BRAVIA 4K Google TV over Network ADB (`_adb._tcp`) from the Vitruvian Dynamic Island, Command Bar, Radial Menu, and Shortcuts.

## Features

- **Dynamic Island Panel (`tv`):**
  - Displays live wake state (`Awake` / `Standby`), foreground app (`Projectivy Home`, `SmartTube 4K`, `AerialViews 4K`, `Disney+`, `Netflix`), and available RAM (`MemAvailable`).
  - **1-Click Controls:** Atomic power toggle (`Wake` / `Sleep`), start 4K Aerial screensaver (`AerialViews`), cast HTTP(S) video URLs from the macOS clipboard directly to SmartTube, launch TV apps, switch HDMI inputs (`HDMI 1–4`), and adjust volume/mute.
- **Closed-Island Status (`contributes.status`):**
  - Displays a live indicator (`TV`, `YT`, or `4K`) on the closed island while the TV is awake.
- **Settings Panel (`settings`):**
  - Configure the TV ADB endpoint (`tvAddress`, default `192.168.86.31:5555`), toggle closed-island status, and trigger background cache trimming (`pm trim-caches`).

## Building & Validating

The program is `src/main.rs`, built by Bazel into `bin/tool`, a native Mac
program. It adds no crate: the kit's `serde` and `serde_json` come from the
repository's existing crate universe, so `Cargo.lock` and `MODULE.bazel` are
untouched. adb is found at Homebrew's path, `/usr/local/bin`, the Android SDK's
`platform-tools`, then `PATH`.

```sh
# Build the self-contained extension folder: vitruvian-tool.json and bin/tool
bazel build //apps/desktop/vitruvian-tool-tv:tool-folder

# Unit tests (src/main.rs, adb mocked) and the Vitruvian SDK conformance suite
bazel test //apps/desktop/vitruvian-tool-tv/...

# Build and zip the release asset without uploading it (macOS only)
bash apps/desktop/vitruvian-tool-tv/scripts/publish-tool.sh --dry-run
```

Outside the installed app's data folder (anything not under `Application
Support`) the tool runs dry and never starts adb, which is how the conformance
suite exercises it. Set `VITRUVIAN_TV_LIVE=1` to talk to a real TV from
elsewhere.

To add the built folder in the Vitruvian macOS app, open **Settings → Extensions → Add from Folder…** and select `bazel-bin/apps/desktop/vitruvian-tool-tv/built/vitruvian-tv` (or install directly under `~/Library/Application Support/com.vitruviansoftware.vitruvian/Tools/dev.vitruvian.tv`).
