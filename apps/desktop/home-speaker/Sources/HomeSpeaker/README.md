# Homespeaker

## Overview
Component package providing implementation for `apps/desktop/home-speaker/Sources/HomeSpeaker`.

## Interface
- `[App.swift:HomeSpeakerApp]`
- `[App.swift:AppSide]`
- `[ChatAppSection.swift:ChatAppSection]`
- `[DoorWindow.swift:DoorWindow]`
- `[DoorWindow.swift:DoorCard]`
- `[DoorWindow.swift:CompareStep]`
- `[DoorWindow.swift:WhichHomeSpeakerSection]`
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
- Run: `bazel test //apps/desktop/home-speaker/Sources/HomeSpeaker/...`
