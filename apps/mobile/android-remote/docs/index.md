# Vitruvian Remote

A remote control and observability console for a Mac, built in the Vitruvian design language and shaped for foldables — specifically the Pixel 11 Pro Fold, folded, unfolded and in tabletop posture.

It drives the host (trackpad, keys, media, volume and brightness, power, clipboard, scripted macros, prompts to a coding agent), shows dashboards for the machine itself (CPU / GPU / Neural Engine, memory pressure, thermals, battery, disk, network, processes, Lima VMs and K3s nodes, Docker), and hosts **modules** — installable per-app dashboards with their own widgets and macros.

## Status & Transports

- **Bluetooth HID**: The phone pairs as a keyboard and mouse, so the Mac needs nothing installed. Pointer, click, drag, scroll, typing, media, volume and brightness keys, display sleep, lock, Spaces, Mission Control, Launchpad, Spotlight, screenshots, window controls and display mirror all work this way.
- **The Agent**: A small Go daemon on the Mac reached over Tailscale. Answers telemetry questions (CPU, memory, battery, disk, network, thermals, processes, VMs, containers, K3s nodes) and runs paired actions (macros, console, Claude Code prompts, clipboard sync, volume control).

## Documentation
- [Phone Bridge Architecture](phone-bridge.md): Protocol, streaming architecture, and device connection management.
- [Mac Agent API](macagent-api.md): Host agent daemon contract, REST endpoints, and authentication.
