# mac-controller Wire Protocol Specification

This specification defines the bidirectional communication protocol between the macOS host companion daemon and the ESP32-S3 Mac Controller.

The protocol is **transport-agnostic**: every packet below is byte-identical over USB CDC and over the Wi-Fi UDP link, and `packet_router.cpp` decodes both with one dispatcher. Nothing in §2–§4 depends on which channel carried it.

---

## 1. Transport & Framing

Common to both channels:

- **Message Framing**: Newline-delimited JSON (`\n`).
- **Maximum Packet Length**: 1,024 bytes.
- **Encoding**: UTF-8.

### 1.1 Channel A — USB CDC (tethered)

- **Physical Layer**: USB 2.0 Full-Speed Native OTG.
- **Port Device Node**: `/dev/cu.usbmodem*` (macOS).
- **Baud Rate**: 115,200 baud.
- **Data Bits / Parity / Stop Bits**: 8-N-1 (8 data bits, no parity, 1 stop bit).
- **Flow Control**: None (software or hardware).

### 1.2 Channel B — Wi-Fi UDP (untethered)

- **Discovery**: mDNS. The firmware publishes `vitruvian-companion.local` and the service `_vitruvian._tcp` on port 8266, with TXT records `version`, `chip=esp32s3`, and `id` (the station MAC without separators).
- **Socket**: UDP, device port **8266**. The host binds an ephemeral local port and uses it for both directions; the device replies to the source address of the last packet it accepted.
- **Datagram content**: one or more newline-framed JSON objects. A datagram larger than 1,024 bytes is truncated and counted as a drop.
- **Source filtering**: the host discards datagrams from any address other than the companion's.
- **Reliability**: none, by design. The stream is 1 Hz telemetry that tolerates loss, and a connectionless socket means a sleeping or re-addressed Mac never leaves the firmware wedged in a half-open connection.

### 1.3 Channel arbitration

`packet_router_active_channel()` picks the live channel; a channel counts as live for **3,000 ms** after its last *recognised* packet (an unparseable or unknown datagram on :8266 does not hold the link open).

| Condition | Active channel | Deck 0 badge | Colour |
|---|---|---|---|
| USB packet within 3 s | USB CDC | `● USB` | `#30D158` green |
| Else Wi-Fi packet within 3 s | Wi-Fi UDP | Wi-Fi glyph + `Wi-Fi` | `#64D2FF` cyan |
| Else, station connected | none | `● <ip>` | `#30D158` green |
| Else | none | `● Standby` | `#FF9F0A` orange |

USB deliberately outranks Wi-Fi: it is the lower-latency, always-powered path. Upstream commands (§3) are emitted over the active channel, so a button press reaches the Mac whether or not the cable is in.

---

## 2. Downstream Packets (Host → ESP32-S3)

### 2.1 System Telemetry Packet (`type: "stats"`)
Transmitted periodically at **1.0 Hz** by the host daemon. Resets the device link watchdog timer.

#### JSON Schema:
```json
{
  "type": "stats",
  "cpu": 24,
  "ram": 58,
  "time": "04:15 PM"
}
```

#### Fields:
| Field | Type | Required | Description |
|---|---|---|---|
| `type` | string | Yes | Literal `"stats"`. If omitted, backward compatibility fallback checks for `"cpu"`. |
| `cpu` | integer | Yes | Total host CPU load percentage (`0` to `100`). |
| `ram` | integer | Yes | Host physical RAM usage percentage (`0` to `100`). |
| `time` | string | Yes | Formatted local time string (e.g. `"12:30 PM"`). |

#### Firmware Watchdog Behavior:
If no valid packet is received by the ESP32-S3 within **4,000 ms**, the device enters link timeout mode:
- Header status dot updates to orange (`● Standby`).
- CPU and RAM bars animate to `0%`.
- Reconnection restores green indicator (`● Linked`).

---

### 2.2 App Shortcut Profile Packet (`type: "app"`)
Transmitted upon initial serial connection and whenever the active macOS frontmost application changes (debounced at **250 ms**).

#### JSON Schema:
```json
{
  "type": "app",
  "app": "VS Code",
  "color": "0x007ACC",
  "buttons": [
    {"label": "Pal",   "mod": 10, "key": 112, "cons": 0, "color": "0x007ACC"},
    {"label": "File",  "mod": 8,  "key": 112, "cons": 0, "color": "0x007ACC"},
    {"label": "Term",  "mod": 1,  "key": 96,  "cons": 0, "color": "0x30D158"},
    {"label": "Split", "mod": 8,  "key": 92,  "cons": 0, "color": "0x007ACC"},
    {"label": "Git",   "mod": 3,  "key": 103, "cons": 0, "color": "0xFF9F0A"},
    {"label": "Fmt",   "mod": 6,  "key": 102, "cons": 0, "color": "0xBF5AF2"}
  ]
}
```

#### Fields:
| Field | Type | Description |
|---|---|---|
| `type` | string | Literal `"app"`. |
| `app` | string | Display name of active application (e.g., `"VS Code"`, `"Chrome"`, `"Terminal"`). |
| `color` | string / uint | 24-bit hex RGB color for header accent elements (e.g., `"0x007ACC"` or `"#007ACC"`). |
| `buttons` | array | Exactly 6 shortcut button definition objects. |

#### Button Object Schema:
| Field | Type | Description |
|---|---|---|
| `label` | string | Label text (max 31 characters, supports `\n` for 2-line rendering). |
| `mod` | integer | 8-bit modifier bitmask (see Modifier Specification below). |
| `key` | integer | ASCII char code or special non-printing keycode (`0` if consumer action). |
| `cons` | integer | USB Consumer Control usage code (`0` if hotkey). |
| `color` | string / uint | Button border and active accent color. |

#### Modifier Bitmask Specification:
```
Bit 0 (0x01): Control (KEY_LEFT_CTRL)
Bit 1 (0x02): Shift   (KEY_LEFT_SHIFT)
Bit 2 (0x04): Option  (KEY_LEFT_ALT)
Bit 3 (0x08): Command (KEY_LEFT_GUI / ⌘)
```
*Examples*:
- `Cmd + Shift + P`: `MOD_CMD | MOD_SHIFT = 8 + 2 = 10`
- `Cmd + Option + I`: `MOD_CMD | MOD_ALT = 8 + 4 = 12`
- `Ctrl + Shift + G`: `MOD_CTRL | MOD_SHIFT = 1 + 2 = 3`

#### Special Keycodes & Consumer Control Values:
| Key / Action | Identifier | Value (Dec / Hex) |
|---|---|---|
| Up Arrow | `KEY_UP_ARROW` | `218` (`0xDA`) |
| Down Arrow | `KEY_DOWN_ARROW` | `217` (`0xD9`) |
| Left Arrow | `KEY_LEFT_ARROW` | `216` (`0xD8`) |
| Right Arrow | `KEY_RIGHT_ARROW` | `215` (`0xD7`) |
| Return / Enter | `KEY_RETURN` | `176` (`0xB0`) |
| Escape | `KEY_ESC` | `177` (`0xB1`) |
| Tab | `KEY_TAB` | `179` (`0xB3`) |
| Backspace | `KEY_BACKSPACE` | `178` (`0xB2`) |
| F11 | `KEY_F11` | `204` (`0xCC`) |
| Audio Mute | `CONSUMER_CONTROL_MUTE` | `226` (`0x00E2`) |
| Volume Up | `CONSUMER_CONTROL_VOLUME_INCREMENT` | `233` (`0x00E9`) |
| Volume Down | `CONSUMER_CONTROL_VOLUME_DECREMENT` | `234` (`0x00EA`) |
| Play / Pause | `CONSUMER_CONTROL_PLAY_PAUSE` | `205` (`0x00CD`) |

---

### 2.3 Agent & CI Telemetry Packet (`type: "agent_ci"`)
Transmitted every **5.0 seconds** or immediately upon any agent or CI state transition.

#### JSON Schema:
```json
{
  "type": "agent_ci",
  "agent": {
    "name": "Antigravity",
    "state": "running",
    "task": "Implementing Milestone 5",
    "detail": "Implementing Milestone 5",
    "active_agents": 3
  },
  "ci": {
    "repo": "vitruvian-core",
    "branch": "feat/mac-controller",
    "dirty": true,
    "dirty_files": 2,
    "status": "passing",
    "state": "passing",
    "pr": 482,
    "passed": 14,
    "total": 14
  }
}
```

#### Fields:
- **`agent` Sub-Object**:
  - `name` (string): Detected agent framework (`"Antigravity"`, `"Claude Code"`, `"Teamwork"`, `"None"`).
  - `state` (string): Agent execution state:
    - `"running"`: Active subagent processes running, progress file updated within 45s (Blue badge).
    - `"review"`: Process running, idle for 45s–300s, waiting for user/code review (Orange badge).
    - `"error"`: Explicit error/failure keyword detected in `progress.md` (Red badge).
    - `"idle"`: No active agent process (Gray badge).
  - `task` / `detail` (string): Active task summary (max 63 characters).
  - `active_agents` (integer): Count of concurrent active agents and subagents.
- **`ci` Sub-Object**:
  - `repo` (string): Monorepo or workspace directory name.
  - `branch` (string): Active Git branch name.
  - `dirty` (boolean): `true` if uncommitted or untracked files exist.
  - `dirty_files` (integer): Count of modified and untracked files.
  - `status` / `state` (string): CI check state:
    - `"passing"`: 100% of PR checks passed (Green badge).
    - `"failing"`: At least one check failed or errored (Red badge).
    - `"pending"`: Checks in progress or queued (Yellow badge).
    - `"none"`: No open PR or checks associated with branch (Muted gray badge).
    - `"unknown"`: GitHub CLI error or rate limit.
  - `pr` (integer): GitHub pull request number (`0` if no PR).
  - `passed` (integer): Number of passing checks.
  - `total` (integer): Total number of CI checks reported.

---

### 2.4 Deck Visibility Configuration Packet (`type: "deck_config"`)
Allows the macOS companion to remotely configure which decks are navigable in the swipe carousel.

#### JSON Schema:
```json
{
  "type": "deck_config",
  "system": true,
  "smart": true,
  "agent": false
}
```

#### Fields:
| Field | Type | Description |
|---|---|---|
| `type` | string | Literal `"deck_config"`. |
| `system` | boolean | Enable or disable System Deck (Deck 0). |
| `smart` | boolean | Enable or disable Smart Deck (Deck 1). |
| `agent` | boolean | Enable or disable Agent & CI Deck (Deck 2). |

---

### 2.5 Wi-Fi Provisioning Packet (`cmd: "wifi_set"`)
The host companion's answer to a device-initiated `wifi_sync` request (Zero-Typing Companion Sync), or an explicit `--wifi-sync` terminal run. The firmware persists the credentials to NVS namespace `wifi_config`, enables the radio, starts a station connection, and immediately reports a `wifi_status` frame back.

#### JSON Schema:
```json
{"cmd":"wifi_set","ssid":"MyHomeNetwork","pass":"SecretPass123"}
```

#### Fields:
| Field | Type | Required | Description |
|---|---|---|---|
| `cmd` | string | Yes | Literal `"wifi_set"`. Dispatched by `cmd` (not `type`) and takes priority over any `type` key present. |
| `ssid` | string | Yes | Network name, 1–32 UTF-8 octets (802.11 limit). Longer values are rejected. |
| `pass` | string | Yes | WPA2 passphrase, 0–63 characters. Empty string = open network. |

### 2.6 Radio Status Query (`cmd: "wifi_status"`)
```json
{"cmd":"wifi_status"}
```
The firmware replies with one `wifi_status` and one `ble_status` telemetry frame (see §3.5). Alias: `{"cmd":"radio_status"}`.

### 2.7 Cloud Monitor Configuration (`cmd: "cloud_config"`)
Configures the autonomous GitHub Actions poller (§5). Persisted to NVS namespace `cloud_ci`; every field is optional and only the supplied ones are applied.

#### JSON Schema:
```json
{"cmd":"cloud_config","repo":"VitruvianSoftware/vitruvian-core","token":"ghp_...","enabled":true}
```

#### Fields:
| Field | Type | Required | Description |
|---|---|---|---|
| `cmd` | string | Yes | Literal `"cloud_config"`. Also accepted as `{"type":"cloud_config"}`. |
| `repo` | string | No | `owner/repo` to watch. Changing it re-primes the chime state so the first result for a new repo is silent. |
| `token` | string | No | GitHub PAT with `actions:read`. Empty string clears it. Never echoed to the log — only its presence is reported. |
| `enabled` | boolean | No | Master switch for the poller. |

---

## 3. Upstream Action Commands (ESP32-S3 → Host)

When the user taps interactive buttons on the ESP32-S3 touch display, action packets are serialized and transmitted to macOS over USB CDC serial.

### 3.1 Trigger CI Check Poll (`run_checks`)
Sent when the user taps `Run Checks (gh pr)` on Deck 2:
```json
{"cmd":"run_checks","action":"run_checks"}
```
**Host Action**: The host daemon triggers an immediate background poll of `gh pr checks` and pushes an updated `agent_ci` packet.

### 3.2 Open Pull Request in Browser (`open_pr`)
Sent when the user taps `Open PR (Browser)` on Deck 2:
```json
{"cmd":"open_pr","action":"open_pr"}
```
**Host Action**: Launches the default browser opening `gh pr view <pr_number> --web` (or `gh repo view --web` if no PR is active).

### 3.3 Focus Active AI Agent (`focus_agent`)
```json
{"cmd":"focus_agent","action":"focus_agent"}
```
**Host Action**: Dispatches an AppleScript activating the frontmost agent window (e.g. Antigravity).

### 3.4 Wi-Fi Credential Sync Request (`wifi_sync`)
Sent when the user taps `[Sync from Mac]` on the Settings Deck Wi-Fi card:
```json
{"cmd":"wifi_sync"}
```
**Host Action**: The daemon detects the Mac's active Wi-Fi SSID (`networksetup -getairportnetwork`, falling back to `ipconfig getsummary`), resolves the passphrase (`VITRUVIAN_WIFI_PASS` env override → macOS keychain → interactive prompt when on a TTY), and replies with a `wifi_set` packet (§2.5). The background daemon never prompts; run `mac_stats_daemon.py --wifi-sync` for the interactive one-shot flow.

### 3.5 Wireless Radio Telemetry (`type: "wifi_status"` / `type: "ble_status"`)
Emitted on every radio state transition and every 5 seconds while either channel has a reachable host. Over UDP these frames double as the host's liveness signal: the daemon tears the session down and re-discovers after 20 s without one.
```json
{"type":"wifi_status","state":"connected","enabled":true,"ssid":"MyHomeNetwork","ip":"192.168.1.50"}
{"type":"ble_status","state":"advertising","enabled":true,"host":"","adv_seconds":58}
```

#### Fields:
| Field | Type | Description |
|---|---|---|
| `state` (wifi) | string | `"off"` \| `"offline"` \| `"connecting"` \| `"connected"` \| `"portal"`. |
| `state` (ble) | string | `"off"` \| `"standby"` \| `"advertising"` \| `"connected"`. |
| `enabled` | boolean | NVS-persisted radio enable flag. |
| `ssid` / `ip` | string | Station network and lease; empty unless connected. |
| `host` | string | Connected/bonded BLE central address; empty if never paired. |
| `adv_seconds` | integer | Remaining pairing-window seconds (0 = open-ended reconnect advertising). |

---

## 4. Autonomous Cloud Monitor (ESP32-S3 → GitHub)

When the device is on Wi-Fi and **neither** channel has carried a host packet for 15 s, `cloud_ci.cpp` takes over Deck 2 and polls GitHub directly. No host is involved, so this is not part of the host protocol above — it is documented here because it drives the same deck.

- **Request**: `GET https://api.github.com/repos/{owner}/{repo}/actions/runs?per_page=1&exclude_pull_requests=true`
- **Headers**: `User-Agent: Vitruvian-ESP32-S3`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, and `Authorization: Bearer <token>` when one is configured.
- **Cadence**: every 60 s by default (clamped to 15–3600 s). A failing poll backs off geometrically to a 15-minute ceiling, never faster than the configured interval.
- **Fields read**: `workflow_runs[0]`'s `name`, `status`, `conclusion`, `head_branch`, `head_sha` (first 7 chars), and `run_number`. Everything else is dropped by an ArduinoJson parse filter.
- **TLS**: certificates are verified against the roots pinned in `src/github_ca.h`. The handshake and body read run on a dedicated FreeRTOS task pinned to core 0, so the LVGL loop on core 1 never blocks.
- **Chimes**: a change of `conclusion` (or the same conclusion on a new `run_number`) plays the pass or fail melody. The first result after boot primes silently. `cancelled` / `skipped` / `neutral` / `action_required` are displayed but not sounded. The Settings deck mute (NVS `settings:chimes_muted`) silences all of it.

Rate limits: unauthenticated requests are capped at 60/hour per IP, which the 60 s default would exhaust. Configure a token via §2.7 for sustained polling.

---

## 5. Diagnostic & Debug Messages (ESP32-S3 → Host)

For hardware validation, the firmware emits standard formatted text lines:
- **Touch Event**: `TOUCH_EVENT: x=120, y=140`
- **I2C Diagnostic**: `[DIAG] I2C 0x15 Ping: ACK/OK (code 0)`
- **Settings Event**: `[SETTINGS] Deck 1 (Smart) set to DISABLED`
