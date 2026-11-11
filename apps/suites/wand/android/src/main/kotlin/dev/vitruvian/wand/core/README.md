# Core

## Overview
Component package providing implementation for `apps/suites/wand/android/src/main/kotlin/dev/vitruvian/wand/core`.

## Interface
- `[Actions.kt:MediaKind]`
- `[Actions.kt:VolumeKind]`
- `[Actions.kt:BrightnessKind]`
- `[Actions.kt:SystemKind]`
- `[Actions.kt:NavKind]`
- `[Actions.kt:DPadDirection]`
- `[Actions.kt:WandButton]`
- `[Actions.kt:WandPress]`
- `[Actions.kt:WandTriggerMode]`
- `[Actions.kt:WandJson]`
- `[Actions.kt:MiniJsonParser]`
- `[GesturePlanner.kt:GlobalCommand]`
- `[GesturePlanner.kt:MediaCommand]`
- `[GesturePlanner.kt:VolumeCommand]`
- `[GesturePlanner.kt:ScrollDirection]`
- `[GesturePlanner.kt:GesturePlanner]`
- `[NativeEngine.kt:Log]`
- `[NativeEngine.kt:EngineScheduler]`
- `[NativeEngine.kt:WandNativeBackend]`
- `[NativeEngine.kt:JniWandNativeBackend]`

## Invariants
- None

## Side Effects
- [NativeEngine.kt:480]: `Log.e("Wand", "Failed to fetch native default config", e)`

## Verification
- Run: `bazel test //apps/suites/wand/android/src/main/kotlin/dev/vitruvian/wand/core/...`
