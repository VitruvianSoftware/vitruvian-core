<!--
  Copyright (c) 2026 VitruvianSoftware
  SPDX-License-Identifier: MIT
-->

# Vitruvian Remote

A remote control and observability console for a Mac, built in the Vitruvian design language and shaped for foldables — specifically the Pixel 11 Pro Fold, folded, unfolded and in tabletop posture.

It drives the host (trackpad, keys, media, volume and brightness, power, clipboard, scripted macros, prompts to a coding agent), shows dashboards for the machine itself (CPU / GPU / Neural Engine, memory pressure, thermals, battery, disk, network, processes, Lima VMs and K3s nodes, Docker), and displays **modules** — per-app dashboards you can show or hide with **Show** and **Hide**.

## First run

A fresh install opens unpaired with the message **No Mac paired** and three choices: **Pair a Mac**, **Install guide**, and **See a demo**.

- **See a demo** loads simulated Mac data for this session only so you can explore the screens without a Mac. Demo state is not saved.
- A real install starts with no default macros and no homelab or other extra modules enabled. You can create, edit, and delete your own macros in **Settings**.

## Status & Transports

- **Bluetooth HID**: The phone pairs as a keyboard and mouse, so the Mac needs nothing installed. Pointer, click, drag, scroll, typing, media, volume and brightness keys, display sleep, lock, Spaces, Mission Control, Launchpad, Spotlight, screenshots, window controls and display mirror all work this way.
- **The Mac helper**: A small Rust daemon and menu bar app on the Mac reached over your local network or Tailscale. It answers telemetry questions (CPU, memory, battery, disk, network, thermals, processes, VMs, containers, K3s nodes) and runs paired actions (macros, console, Claude Code prompts, clipboard sync, volume control). See the [setup and pairing guide](https://github.com/VitruvianSoftware/vitruvian-remote#readme) to install and pair it.

## Documentation

- [Privacy](PRIVACY.md): What leaves the phone, what stays on the phone, and how crash reports and Phone Bridge are controlled.
- [Phone Bridge Architecture](phone-bridge.md): Protocol, streaming architecture, and device connection management.
- [Mac Agent API](macagent-api.md): Host agent daemon contract, REST endpoints, and authentication.
