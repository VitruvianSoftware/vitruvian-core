# Remote

## Overview
Component package providing implementation for `apps/mobile/android-remote/src/main/kotlin/dev/vitruvian/remote`.

## Interface
- `[MainActivity.kt:MainActivity]`
- `[MainActivity.kt:HomeSpeakerNotificationReceiver]`
- `[RemoteApp.kt:RemoteApp]`
- Subdirectory: [bridge](./bridge/README.md)
- Subdirectory: [hid](./hid/README.md)
- Subdirectory: [overlays](./overlays/README.md)
- Subdirectory: [screens](./screens/README.md)
- Subdirectory: [shell](./shell/README.md)
- Subdirectory: [state](./state/README.md)
- Subdirectory: [tiles](./tiles/README.md)
- Subdirectory: [trackpad](./trackpad/README.md)

## Invariants
- None

## Side Effects
- [MainActivity.kt:33]: `import android.net.Uri`

## Verification
- Run: `bazel test //apps/mobile/android-remote/src/main/kotlin/dev/vitruvian/remote/...`
