# Homespeakertoolcore

## Overview
Component package providing implementation for `apps/desktop/home-speaker/Sources/HomeSpeakerToolCore`.

## Interface
- `[Account.swift:GoogleAccount]`
- `[Account.swift:SecretStoreAccount]`
- `[Account.swift:NoGoogleAccount]`
- `[Account.swift:ChatCredentials]`
- `[Account.swift:SecretStoreChatCredentials]`
- `[Account.swift:NoChatCredentials]`
- `[Config.swift:ConfigStore]`
- `[Config.swift:FileConfigStore]`
- `[EngineDriver.swift:EngineDriver]`
- `[ExtensionSide.swift:ExtensionLocation]`
- `[ExtensionSide.swift:RestoreReport]`
- `[ExtensionSide.swift:ExtensionSide]`
- `[HomeSpeakerTool.swift:ToolLink]`
- `[HomeSpeakerTool.swift:HomeSpeakerTool]`
- `[OtherApp.swift:RunningAppHandle]`
- `[OtherApp.swift:ProgramRun]`
- `[OtherApp.swift:OtherAppProblem]`
- `[OtherApp.swift:OtherAppError]`
- `[OtherApp.swift:OtherAppControlling]`
- `[OtherApp.swift:SystemOtherApp]`

## Invariants
- None

## Side Effects
- [ExtensionSide.swift:138]: `engine: HomeSpeakerEngine, chatSession: URLSession = .shared, beeperSession: ...`

## Verification
- Run: `bazel test //apps/desktop/home-speaker/Sources/HomeSpeakerToolCore/...`
