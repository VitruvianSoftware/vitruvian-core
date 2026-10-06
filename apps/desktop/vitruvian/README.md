# Vitruvian (desktop)

A macOS menu-bar utility hub: per-app volume mixer, system monitor, app switcher,
window snapping, Dock previews, clipboard history, a Dynamic Island-style notch,
screen capture and recording, AI agent usage tracking and more, all behind one
menu-bar icon.

> **Status: released.** Vitruvian is a GPL-3.0-or-later fork of
> [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils), renamed with its
> own bundle ID and icon. Each release on this repository's
> [Releases](https://github.com/VitruvianSoftware/vitruvian-core/releases) page
> (tags `vitruvian-vX.Y.Z`) carries `Vitruvian-X.Y.Z.dmg` and the source it was
> built from. See [`UPSTREAM.md`](UPSTREAM.md) for provenance, the licensing
> rules and what is still open.

Requirements: macOS 14 or newer on Apple Silicon, and the Xcode pinned in the
repository's `.xcode-version`.

## Install

1. Download `Vitruvian-X.Y.Z.dmg` from the latest `vitruvian-v*` release.
2. Open it and drag Vitruvian into Applications.
3. Open Vitruvian. Releases are not notarized yet, so macOS blocks the first
   open. Allow it under System Settings › Privacy & Security › Open Anyway, or
   remove the download's quarantine flag once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Vitruvian.app
   ```

## Releases

`.github/workflows/vitruvian-release.yaml` runs release-please over conventional
commits under `apps/desktop/vitruvian/`. A `feat` or `fix` commit opens a
release PR that bumps `CHANGELOG.md`, `Resources/Info.plist` and
`.release-please-manifest.json`. Merging that PR tags `vitruvian-vX.Y.Z` and
creates the GitHub Release. The same workflow then builds the app from the tag
on the `xcode-27` runner and runs `Tools/package-release.sh`, which:

- signs the app: with the `VITRUVIAN_SIGNING_CERT_P12` /
  `VITRUVIAN_SIGNING_CERT_PASSWORD` Developer ID when those secrets exist,
  ad hoc otherwise;
- notarizes it when the `VITRUVIAN_NOTARY_*` secrets exist;
- packages `Vitruvian-X.Y.Z.dmg` and attaches it to the release.

To package an existing tag again, run the workflow by hand with that tag. Tags
before `vitruvian-v3.6.0` predate `Tools/package-release.sh` and cannot be
packaged.

## Build and test

Everything goes through Bazel with the `macos-app` config, which provides
Apple's CC toolchain for linking:

```sh
# The .app bundle (bazel-bin/apps/desktop/vitruvian/Vitruvian.zip)
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian

# Upstream's unit tests, the app's --selftest, and the fan helper's --selftest
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests \
  //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:fan_helper_selftest

# One test group (the names are in Tests/TestGroups.swift)
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
| `Sources/Vitruvian/Services/` | The `VitruvianServices` module: the singletons that own live system state, and the work behind each feature |
| `Sources/Vitruvian/FanControlKit/` | The `FanControlKit` module: fan-control policy and the SMC temperature model, shared with the fan helper |
| `Sources/Vitruvian/UI/` | The `VitruvianUI` module: the SwiftUI views and the windows that host them |
| `Sources/Vitruvian/` (rest) | The app: `App/` lifecycle, `Support/` diagnostics, `main.swift` |
| `Sources/FanControlHelper/` | Privileged launchd helper for fan control |
| `Sources/NowPlayingAdapter/` | Dylib that `/usr/bin/perl` loads to read Now Playing |
| `Sources/HIDEventSystem/`, `Sources/VMStatisticsCompat/` | C module maps for private or compat headers |
| `Tests/` | Upstream's custom test runner, `generate_sources.py` extractor and fixtures |
| `Resources/` | Info.plist, entitlements, launchd plist, localized InfoPlist strings, brand masters, GIFs and images |
| `Tools/` | Icon generator (run by the build), upstream's signing, notarization and DMG scripts, and `package-release.sh`, which the release workflow runs |
| `bazel/` | Build glue: generated source lists, genrule scripts and test wrappers |

Architecture review notes and the planned refactor are tracked in the PRs that
follow the import.
