# Wear OS (`apps/mobile/wearos`)

Wear OS watch faces, complication providers, and wrist companion apps built for the Pixel Watch 4 (`kenari_lte`).

## Watch Faces

| Face | Path | Description |
|---|---|---|
| **Daytona Platinum (`Ref. 126506`)** | [`faces/daytona-platinum/`](faces/daytona-platinum/README.md) | Ice Blue sunray dial, Chestnut Brown Cerachrom tachymeter bezel, baguette diamond hour markers, and 7 integrated complication slots (Steps, Heart Rate, Battery, Weather, Sunrise/Sunset, World Clock AMS & UTC, plus Day/Date). |

## Wear OS Companion Apps (`apps/mobile/wearos/apps/`)

| App | Package | Target | Description |
|---|---|---|---|
| **Vitruvian Pulse** | `dev.vitruvian.wear.pulse` | `//apps/mobile/wearos/apps/vitruvian-pulse:app` | Custom Wear OS Complication Data Source provider (`HomelabPulseComplicationService`, `MergeQueueComplicationService`, `RoborockPulseComplicationService`) + wrist dashboard feeding live Homelab k3s health, PR merge queue status, and Roborock battery/status into Daytona Platinum sub-dials. |
| **Vitruvian Remote** | `dev.vitruvian.wear.remote` | `//apps/mobile/wearos/apps/remote:app` | Wrist TV & media remote with physical Pixel Watch 4 rotary crown volume control (`RotaryVolumeAccumulator`), 5-way D-pad, power/input/playback controls, and multi-room target switching. |
| **Vitruvian Home** | `dev.vitruvian.wear.home` | `//apps/mobile/wearos/apps/home-control:app` | Smart-home wrist controller for switching `speaker-broadcast` room targets (*Lake Office*, *Master Bedroom*, *Living Room*, *Kitchen*, *Dining Room*, *Guest Room*, *All*, *Mute*) and triggering one-tap Roborock room cleans, mop washes, and docking. |
| **Vitruvian Nexus** | `dev.vitruvian.wear.nexus` | `//apps/mobile/wearos/apps/nexus-wrist:app` | Voice-to-Agent wrist dispatcher (`VoiceAgentRouter` routing spoken prompts to `ridge`, `scout`, `atlas`, `aegis`, `wren`, or `beacon`) and one-tap haptic PR approval/hold queue. |
| **Shared Domain (`common`)** | `dev.vitruvian.wear.common` | `//apps/mobile/wearos/apps/common:common_test` | Pure-JVM domain models, rotary volume hysteresis math, complication derivations, and wire payload codecs tested hermetically in CI. |
