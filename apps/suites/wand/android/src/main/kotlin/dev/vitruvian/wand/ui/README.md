# Ui

## Overview
Component package providing implementation for `apps/suites/wand/android/src/main/kotlin/dev/vitruvian/wand/ui`.

## Interface
- `[WandScreens.kt:queryInstalledLauncherApps]`
- `[WandScreens.kt:tryEnableAccessibilityViaSecureSettings]`
- `[WandScreens.kt:WandAppScreen]`

## Invariants
- None

## Side Effects
- [WandScreens.kt:130]: `Log.w(TAG, "Failed to query launcher activities", e)`

## Verification
- Run: `bazel test //apps/suites/wand/android/src/main/kotlin/dev/vitruvian/wand/ui/...`
