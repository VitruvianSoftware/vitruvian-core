# Common

## Overview
Component package providing implementation for `apps/mobile/wearos/apps/common/src/main/kotlin/dev/vitruvian/wear/common`.

## Interface
- `[HomeControlModels.kt:SpeakerRoom]`
- `[HomeControlModels.kt:RoborockAction]`
- `[NexusWristModels.kt:SpecialistAgent]`
- `[NexusWristModels.kt:ApprovalDecision]`
- `[NexusWristModels.kt:VoiceAgentRouter]`
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
- Run: `bazel test //apps/mobile/wearos/apps/common/src/main/kotlin/dev/vitruvian/wear/common/...`
