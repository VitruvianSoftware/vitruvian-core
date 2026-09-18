# HomeSpeaker (macOS Menu Bar App & Configuration GUI)

<p align="center">
  <img src="docs/hero_banner.jpg" alt="HomeSpeaker Hero Banner" width="100%" />
</p>

**HomeSpeaker** is a native macOS menu bar application (`LSUIElement`) designed to provide a rich visual GUI and background daemon for broadcasting AI agent responses and team chat notifications directly to Google Home speakers and Nest Hub displays.

Housed in `vitruvian-core` under `apps/desktop/home-speaker/`.

---

## Features

* **Menu Bar Extra:** Lives in the macOS menu bar (`dot.radiowaves.left.and.right`) with zero dock footprint.
* **Instant Speaker Switching:** Quickly change the active target speaker or display (e.g. *Lake Office display*, *Master Bedroom*, *Kitchen*, or *Whole Home*).
* **Broadcast Mute/Unmute:** 1-click master switch to silence or enable spoken responses.
* **Quick Announcement:** Type any custom message directly from the menu bar popup to test or announce to the room immediately.
* **AI Coding Agent Integration:** 
  * Integrates with **Antigravity** and **Claude Code**.
  * Installs the deterministic Claude Code `Stop` lifecycle hook directly into `~/.claude/settings.json`.
* **Background Chat Monitor:**
  * Background monitoring service for Slack DMs/channels and Google Chat spaces.
  * Automated spoken announcements for incoming team messages.
* **Direct Cloud Connectivity:** Talks directly to Google's cloud MCP endpoint (`https://home.googleapis.com/mcp`) via HTTPS JSON-RPC with automatic OAuth refresh—no local MCP proxy daemon required.

---

## Building and Running

### Build via Swift Package Manager
```bash
cd apps/desktop/home-speaker

# Run tests (wraps `swift test` with the swift-testing plugin path the
# Command Line Tools toolchain needs; plain `swift test` fails without Xcode)
./scripts/test.sh

# Build executable
swift build -c release

# Run directly
.build/release/HomeSpeaker
```

### Build via Bazel (Monorepo)
```bash
bazel build //apps/desktop/home-speaker:HomeSpeaker
```

---

## Configuration & Persistence

All persistent configuration is managed in standard JSON format at:
* Configuration: `~/.gemini/speaker_broadcast.json`
* Google OAuth Tokens: `~/.gemini/antigravity/mcp_oauth_tokens.json`
* Broadcast Log History: `~/.gemini/speaker_history.json`

---

## License

Copyright (c) 2026 VitruvianSoftware. MIT Licensed.
