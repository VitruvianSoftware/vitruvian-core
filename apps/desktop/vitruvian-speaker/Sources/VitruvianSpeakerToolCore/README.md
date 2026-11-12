# Vitruvianspeakertoolcore

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/Sources/VitruvianSpeakerToolCore`.

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
- `[VitruvianSpeakerTool.swift:ToolLink]`
- `[VitruvianSpeakerTool.swift:VitruvianSpeakerTool]`
- `[OtherApp.swift:RunningAppHandle]`
- `[OtherApp.swift:ProgramRun]`
- `[OtherApp.swift:OtherAppProblem]`
- `[OtherApp.swift:OtherAppError]`
- `[OtherApp.swift:OtherAppControlling]`
- `[OtherApp.swift:SystemOtherApp]`

## Invariants
- None

## Side Effects
- [ExtensionSide.swift:138]: `engine: VitruvianSpeakerEngine, chatSession: URLSession = .shared, beeperSession: ...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/Sources/VitruvianSpeakerToolCore/...`
