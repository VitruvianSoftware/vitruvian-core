# Common

## Overview
Component package providing implementation for `apps/mobile/vitruvian-watch/apps/common/src/main/kotlin/com/vitruviansoftware/watch/common`.

## Interface
- `[HomeControlModels.kt:SpeakerRoom]`
- `[HomeControlModels.kt:RoborockAction]`
- `[CodeWristModels.kt:SpecialistAgent]`
- `[CodeWristModels.kt:ApprovalDecision]`
- `[CodeWristModels.kt:VoiceAgentRouter]`
- `[PulseModels.kt:PulseTone]`
- `[RotaryVolumeMath.kt:TvRemoteCommand]`
- `[RotaryVolumeMath.kt:MediaTarget]`
- `[RotaryVolumeMath.kt:RotaryVolumeAccumulator]`
- `[RotaryVolumeMath.kt:RemoteWireCodec]`

## Invariants
- [RotaryVolumeMath.kt:71]: `require(pixelsPerStep > 0f) { "pixelsPerStep must be positive" }`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/mobile/vitruvian-watch/apps/common/src/main/kotlin/com/vitruviansoftware/watch/common/...`
