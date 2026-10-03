# Vitruvian (desktop)

A macOS menu-bar utility hub: per-app volume mixer, system monitor, app switcher,
window snapping, Dock previews, clipboard history, a Dynamic Island-style notch,
screen capture and recording, AI agent usage tracking and more, all behind one
menu-bar icon.

> **Status: renamed, not yet released.** Vitruvian is a GPL-3.0-or-later fork of
> [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils), renamed with its
> own bundle ID and icon. **Do not distribute any build yet**: the
> public source mirror, signing and a release feed don't exist yet, and the
> onboarding GIFs still show upstream's mark. See [`UPSTREAM.md`](UPSTREAM.md) for
> provenance, the licensing rules and the remaining release blockers.

Requirements: macOS 14 or newer on Apple Silicon, and the Xcode pinned in the
repository's `.xcode-version`.

## Build and test

Everything goes through Bazel with the `macos-app` config, which provides
Apple's CC toolchain for linking:

```sh
# The .app bundle (bazel-bin/apps/desktop/vitruvian/Vitruvian.zip)
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian

# Upstream's unit tests, the app's --selftest, and the fan helper's --selftest
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests \
  //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:fan_helper_selftest

# One test group (list them with --test_arg=--list)
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=notch
```

To run the app, unzip the bundle and open it:

```sh
ditto -x -k bazel-bin/apps/desktop/vitruvian/Vitruvian.zip /tmp/vitruvian
open /tmp/vitruvian/Vitruvian.app
```

The bundle is signed ad hoc. macOS ties Accessibility and Screen Recording
grants to the exact binary, so they have to be granted again after each rebuild.

The macOS targets are tagged `manual`, so a Linux `bazel build //...` skips them.
CI builds and tests them in the `vitruvian-desktop-macos` pipeline unit on the
`xcode-27` runner.

### Hand-kept source lists

Upstream's `build.sh` lists by hand which sources go into the unit-test binary,
the fan helper and the Now Playing adapter. `bazel/sources.bzl` is generated
from those lists and from what `Tests/generate_sources.py` emits. After an
upstream sync, or after changing any of those lists, regenerate it:

```sh
bazel run //apps/desktop/vitruvian:sync_sources
```

`//apps/desktop/vitruvian:sources_in_sync_test` fails if you forget. It runs on
Linux too.

`build.sh` is kept because upstream's tests read it as text and its lists feed
`bazel/sources.bzl`. It no longer builds the app: it compiles everything as one
module, and the app is now split into modules (see below). Use Bazel.

## Layout

| Path | What |
| --- | --- |
| `Sources/Vitruvian/Core/` | The `VitruvianCore` module, the whole folder: preferences keys, the feature catalog, localization, strings and the pure `*Support` logic |
| `Sources/Vitruvian/Design/` | The `VitruvianDesign` module: AppKit and SwiftUI building blocks shared by services and views (panels, backdrops, editors) |
| `Sources/Vitruvian/FanControlKit/` | The `FanControlKit` module: fan-control policy and the SMC temperature model, shared with the fan helper |
| `Sources/Vitruvian/` (rest) | The app: `Services/` behavior, `UI/` views, `App/` lifecycle, `Support/` diagnostics |
| `Sources/FanControlHelper/` | Privileged launchd helper for fan control |
| `Sources/NowPlayingAdapter/` | Dylib that `/usr/bin/perl` loads to read Now Playing |
| `Sources/HIDEventSystem/`, `Sources/VMStatisticsCompat/` | C module maps for private or compat headers |
| `Tests/` | Upstream's custom test runner, `generate_sources.py` extractor and fixtures |
| `Resources/` | Info.plist, entitlements, launchd plist, localized InfoPlist strings, brand masters, GIFs and images |
| `Tools/` | Icon generator (run by the build) and upstream's signing, notarization and DMG scripts |
| `bazel/` | Build glue: generated source lists, genrule scripts and test wrappers |

Architecture review notes and the planned refactor are tracked in the PRs that
follow the import.
