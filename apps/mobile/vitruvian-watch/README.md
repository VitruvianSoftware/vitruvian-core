# Vitruvian Watch (`apps/mobile/vitruvian-watch`)

Wear OS watch faces, complication providers, and wrist companion apps built for the Pixel Watch 4 (`kenari_lte`).

## Watch Faces

| Face | Path | Description |
|---|---|---|
| **Daytona Platinum (`Ref. 126506`)** | [`faces/daytona-platinum/`](faces/daytona-platinum/README.md) | Ice Blue sunray dial, Chestnut Brown Cerachrom tachymeter bezel, baguette diamond hour markers, and 7 integrated complication slots (Steps, Heart Rate, Battery, Weather, Sunrise/Sunset, World Clock AMS & UTC, plus Day/Date). |

## Vitruvian Watch Companion Apps (`apps/mobile/vitruvian-watch/apps/`)

| App | Package | Target | Description |
|---|---|---|---|
| **Vitruvian Pulse** | `com.vitruviansoftware.watch.pulse` | `//apps/mobile/vitruvian-watch/apps/vitruvian-pulse:app` | Custom Wear OS Complication Data Source provider (`HomelabPulseComplicationService`, `MergeQueueComplicationService`, `RoborockPulseComplicationService`) + wrist dashboard feeding live Homelab k3s health, PR merge queue status, and Roborock battery/status into Daytona Platinum sub-dials. |
| **Vitruvian Remote** | `com.vitruviansoftware.watch.remote` | `//apps/mobile/vitruvian-watch/apps/remote:app` | Wrist TV & media remote with physical Pixel Watch 4 rotary crown volume control (`RotaryVolumeAccumulator`), 5-way D-pad, power/input/playback controls, and multi-room target switching. |
| **Vitruvian Home** | `com.vitruviansoftware.watch.home` | `//apps/mobile/vitruvian-watch/apps/home-control:app` | Smart-home wrist controller for switching `speaker-broadcast` room targets (*Lake Office*, *Master Bedroom*, *Living Room*, *Kitchen*, *Dining Room*, *Guest Room*, *All*, *Mute*) and triggering one-tap Roborock room cleans, mop washes, and docking. |
| **Vitruvian Nexus** | `com.vitruviansoftware.watch.nexus` | `//apps/mobile/vitruvian-watch/apps/nexus-wrist:app` | Voice-to-Agent wrist dispatcher (`VoiceAgentRouter` routing spoken prompts to `ridge`, `scout`, `atlas`, `aegis`, `wren`, or `beacon`) and one-tap haptic PR approval/hold queue. |
| **Shared Domain (`common`)** | `com.vitruviansoftware.watch.common` | `//apps/mobile/vitruvian-watch/apps/common:common_test` | Pure-JVM domain models, rotary volume hysteresis math, complication derivations, and wire payload codecs tested hermetically in CI. |

## Subdirectories & Boundaries
- [apps](./apps/README.md): Subsystem blueprint grouping child modules under apps/mobile/vitruvian-watch/apps.
- [faces](./faces/README.md): Subsystem blueprint grouping child modules under apps/mobile/vitruvian-watch/faces.

