# Vitruvianspeaker

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/Sources/VitruvianSpeaker`.

## Interface
- `[App.swift:VitruvianSpeakerApp]`
- `[App.swift:AppSide]`
- `[ChatAppSection.swift:ChatAppSection]`
- `[DoorWindow.swift:DoorWindow]`
- `[DoorWindow.swift:DoorCard]`
- `[DoorWindow.swift:CompareStep]`
- `[DoorWindow.swift:WhichVitruvianSpeakerSection]`
- `[Entry.swift:Entry]`
- `[MenuBarView.swift:MenuBarViewModel]`
- `[MenuBarView.swift:MenuBarView]`
- `[SettingsView.swift:SettingsViewModel]`
- `[SettingsView.swift:SettingsView]`
- `[SpeakerVolumeControl.swift:SpeakerVolumeModel]`
- `[SpeakerVolumeControl.swift:SpeakerVolumeControl]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/Sources/VitruvianSpeaker/...`
