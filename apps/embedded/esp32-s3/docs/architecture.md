# mac-controller Architecture & Subsystems

This document describes the architectural design of the ESP32-S3 Mac Controller, detailing the composite USB OTG stack, graphics rendering pipeline, capacitive touch driver, haptic feedback mechanism, dynamic carousel navigation engine, and host companion architecture.

---

## 1. System Architecture Overview

The system operates across two asynchronous domains. They communicate over a USB Type-C link when tethered, or over the LAN when not — the packet router (§8) makes the two indistinguishable to everything above it. A third, host-free mode exists: when neither channel is carrying packets, the device talks to GitHub itself (§9).

```
┌────────────────────────────────────────────────────────┐
│                      macOS Host                        │
│                                                        │
│  ┌────────────────────┐      ┌──────────────────────┐  │
│  │ Frontmost App      │      │ Agent & CI Monitor   │  │
│  │ Detector           │      │ (Background Thread)  │  │
│  │ (lsappinfo 250ms)  │      │ (pgrep, git, gh pr)  │  │
│  └─────────┬──────────┘      └──────────┬───────────┘  │
│            │                            │              │
│            ▼                            ▼              │
│  ┌──────────────────────────────────────────────────┐  │
│  │        mac_stats_daemon.py (Host Daemon)         │  │
│  └────────────────────────┬─────────────────────────┘  │
└───────────────────────────┼────────────────────────────┘
                            │ Channel A: USB-C Cable (OTG Full Speed)
                            │   - USB CDC Serial (115200 8-N-1)
                            │   - USB HID Keyboard & Consumer Control
                            │ Channel B: Wi-Fi LAN (untethered)
                            │   - UDP :8266, same newline-framed JSON
                            │   - mDNS vitruvian-companion.local
┌───────────────────────────┼────────────────────────────┐
│                           ▼                            │
│  ┌──────────────────────────────────────────────────┐  │
│  │           ESP32-S3 Native USB OTG Core           │  │
│  └────────────┬─────────────────────────┬───────────┘  │
│               │ Inbound JSON Packets    │ HID Key Press│
│               ▼                         ▲              │
│  ┌──────────────────────────┐   ┌───────┴───────────┐  │
│  │ packet_router.cpp        │◄──┤ net_telemetry.cpp │  │
│  │ (ArduinoJson 7, one      │   │ (WiFiUDP :8266)   │  │
│  │  decoder per channel)    │   ├───────────────────┤  │
│  │                          │   │ mac_hid Subsystem │  │
│  │                          │   │ (TinyUSB/BLE HID) │  │
│  └────────────┬─────────────┘   └───────────────────┘  │
│               │                                        │
│               ▼                                        │
│  ┌──────────────────────────┐   ┌───────────────────┐  │
│  │ ui.cpp Carousel Engine   │   │ CST816T Touch     │  │
│  │ (LVGL 8.4 TileView)      │◄──┤ Driver (I2C 0x15) │  │
│  │ - System Deck (Tile 0)   │   └───────────────────┘  │
│  │ - Smart Deck (Tile 1)    │                          │
│  │ - Agent & CI Deck (Tile 2)   ┌───────────────────┐  │
│  │ - Settings Deck (Tile 3) │──►│ ST7789V2 IPS LCD  │  │
│  └──────────────────────────┘   │ (SPI + DMA)       │  │
│                                 └───────────────────┘  │
│                   ESP32-S3 Firmware                    │
└────────────────────────────────────────────────────────┘
```

---

## 2. Composite USB OTG Mode

The ESP32-S3 microchip features an on-chip USB 2.0 Full-Speed OTG peripheral. The firmware configures the ESP32-S3 in composite device mode (`ARDUINO_USB_MODE=0`, `ARDUINO_USB_CDC_ON_BOOT=1` in `platformio.ini`), presenting two logical interfaces simultaneously to the macOS host:

1. **USB CDC (Communications Device Class) Serial Interface**:
   - Enumerates as `/dev/cu.usbmodemXXXX`.
   - Used for bidirectional framing: streams host CPU/RAM metrics, app shortcut profiles, and agent/CI telemetry downstream; streams action commands (`run_checks`, `open_pr`, `focus_agent`) upstream.
   - Operates at 115200 baud, 8-N-1.

2. **USB HID (Human Interface Device) Composite Interface**:
   - Enumerates natively as a standard USB Keyboard and USB Consumer Control device.
   - Requires no third-party host software or kext drivers; native macOS Quartz event taps treat the device as a physical external keyboard.
   - **Keyboard Subsystem**: Handles standard ASCII keys and functional non-printing keys (arrows, return, escape, tab, F11) combined with a 4-bit modifier mask (`MOD_CTRL`, `MOD_SHIFT`, `MOD_ALT`, `MOD_CMD`).
   - **Consumer Control Subsystem**: Transmits top-level multimedia HID usages, including `CONSUMER_CONTROL_MUTE`, `CONSUMER_CONTROL_VOLUME_INCREMENT`, `CONSUMER_CONTROL_VOLUME_DECREMENT`, and `CONSUMER_CONTROL_PLAY_PAUSE`.
   - **Dwell Timing**: Every keystroke applies a defensive `Keyboard.releaseAll()` call, asserts pressed modifiers and keycodes, holds for `HID_KEY_DWELL_MS = 20` milliseconds to guarantee the macOS WindowServer event queue registers the transition, and executes `Keyboard.releaseAll()`.

---

## 3. Display & Graphics Pipeline

### Hardware Interface:
- **Display Controller**: Sitronix ST7789V2 4-wire SPI LCD.
- **Resolution**: 240 × 280 pixels, IPS (In-Plane Switching) wide-angle viewing.
- **Color Depth**: RGB565 (16-bit color, 65,536 colors).
- **Physical Pins**:
  - `LCD_DC` (GPIO 4): Data / Command selection.
  - `LCD_CS` (GPIO 5): SPI Chip Select (Active Low).
  - `LCD_SCK` (GPIO 6): SPI Clock.
  - `LCD_MOSI` (GPIO 7): SPI Master Out Slave In.
  - `LCD_RST` (GPIO 8): Hardware Reset.
  - `LCD_BL` (GPIO 15): Backlight LED Control.

### Driver Stack (`Arduino_GFX_Library`):
```cpp
static Arduino_DataBus *bus = new Arduino_ESP32SPI(LCD_DC, LCD_CS, LCD_SCK, LCD_MOSI);
static Arduino_GFX *gfx = new Arduino_ST7789(bus, LCD_RST, 0 /* rotation */, true /* IPS */, LCD_WIDTH, LCD_HEIGHT, 0, 20, 0, 20);
```
*Note*: The physical panel is 240×280 pixels, offset within the ST7789's internal 240×320 memory space by `col_offset = 0`, `row_offset = 20`.

### LVGL 8.4 Integration:
- **Memory Buffer Allocation**: Internal DMA-capable SRAM is utilized for zero-copy SPI transfers:
  ```cpp
  size_t buf_pixels = LCD_WIDTH * 30; // 30-line rendering slice (240 x 30 = 7,200 px)
  buf1 = (lv_color_t *)heap_caps_malloc(buf_pixels * sizeof(lv_color_t), MALLOC_CAP_DMA);
  buf2 = (lv_color_t *)heap_caps_malloc(buf_pixels * sizeof(lv_color_t), MALLOC_CAP_DMA);
  lv_disp_draw_buf_init(&draw_buf, buf1, buf2, buf_pixels);
  ```
- **Hardware Timer Tick Generator**: LVGL requires a steady millisecond counter. Because `LV_TICK_CUSTOM = 0`, an `esp_timer` task is created running periodically every 2 ms:
  ```cpp
  const esp_timer_create_args_t tick_timer_args = {
      .callback = &lvgl_tick_cb,
      .arg = NULL,
      .dispatch_method = ESP_TIMER_TASK,
      .name = "lvgl_tick",
      .skip_unhandled_events = true,
  };
  ```
- **Cooperative Multitasking**: In the main `loop()`, `lv_timer_handler()` processes widget redraws and animations, followed by serial packet evaluation and a short 5ms yield.

---

## 4. Capacitive Touch Subsystem (CST816T)

The capacitive touch sensor is managed by the Hynitron CST816T controller communicating over I2C at 7-bit address `0x15`:
- **I2C Bus**: `IIC_SDA` (GPIO 11), `IIC_SCL` (GPIO 10), standard 100 kHz bus clock with internal pull-ups enabled.
- **Hardware Interrupt**: `TP_INT` (GPIO 14) triggers an ISR on `FALLING` edge.
- **Hardware Reset**: `TP_RST` (GPIO 13) driven through a defined reset sequence (HIGH 50ms -> LOW 20ms -> HIGH 100ms) on boot.
- **Sensor Configuration**:
  - Register `0xFA` (`REG_IRQ_CTL`): Written with `0x40` to select periodic touch notifications.
  - Register `0xFE` (`REG_DIS_AUTOSLEEP`): Written with `0xFF` to permanently disable the CST816T sleep mode, guaranteeing instant touch response.
- **Finger Gating Mechanism**:
  A known vulnerability of the CST816T is that Register `0x01` (`REG_GESTURE_ID`) latches the last detected swipe and does not clear on finger lift. The driver ignores Register `0x01` and evaluates Register `0x02` (`REG_FINGER_NUM`):
  ```cpp
  uint8_t fingers = dta[1];
  if (fingers == 0x00 || fingers == 0xFF) return false;
  fingers &= 0x0F;
  if (fingers == 0) return false;
  ```
  This guarantees that LVGL pointer states release cleanly (`LV_INDEV_STATE_REL`) as soon as the user's finger leaves the surface.

---

## 5. Audio Subsystem (`buzzer.cpp`)

The onboard buzzer on `BUZZER_PIN` (GPIO 42) is driven directly through **LEDC channel 0** at 10-bit resolution and 50% duty. The channel is claimed in `buzzer_init()` before anything else touches the pin — a later `pinMode()` on GPIO 42 would drop the LEDC matrix routing and silence every tone, which is why `mac_hid_init()` no longer configures it.

Playback is **non-blocking**. Every call queues a note sequence and returns; `buzzer_loop()` (pumped from the Arduino main loop) advances it. A blocking implementation would stall `lv_timer_handler()` for the ~600 ms of a chime and visibly freeze the carousel mid-swipe.

| Melody | Notes | Purpose |
|---|---|---|
| `buzzer_play_click()` | 1000 Hz, 20 ms | Touch confirmation on every button and switch |
| `buzzer_play_ci_pass()` | C5 523 / E5 659 / G5 784 / C6 1046 Hz | CI conclusion changed to `success` |
| `buzzer_play_ci_fail()` | F5 698 / D5 587 / B4 494 Hz | CI conclusion changed to a failure |

An 18 ms rest is inserted between notes so an arpeggio reads as four notes rather than one glissando, and a new melody pre-empts whatever was playing — a burst of CI transitions should sound like the latest result, not a queue backlog.

`buzzer_set_muted(true)` persists to NVS (`settings:chimes_muted`) and cuts an in-flight melody immediately. Because the buzzer is the device's only sound source, the mute covers the touch click as well as the chimes.

---

## 6. Dynamic Carousel Navigation Engine

The UI is constructed on an LVGL `lv_tileview` widget spanning 240×280 pixels. The four functional decks are assigned permanent identifiers:
- `DECK_SYSTEM` (0): System Deck
- `DECK_SMART` (1): Smart Deck
- `DECK_AGENT_CI` (2): Agent & CI Deck
- `DECK_SETTINGS` (3): Settings Deck

### Dynamic Re-Indexing Algorithm (`ui_reindex_carousel()`):
When any deck toggle switch is altered in the Settings Deck or received via a serial `deck_config` packet:
1. **Invariant Enforcement**: `deck_enabled[DECK_SETTINGS]` is forced to `true`.
2. **Offscreen Shelving**: All disabled deck tiles are assigned `LV_OBJ_FLAG_HIDDEN`, positioned offscreen at `(-1000, -1000)`, and their scroll direction flags set to `LV_DIR_NONE`.
3. **Contiguous Horizontal Re-Stacking**: Enabled decks are collected in order and repositioned contiguously across the X-axis:
   - Tile X position: `k * 240` (where `k` is the active index `0 <= k < active_count`).
   - Flag `LV_OBJ_FLAG_HIDDEN` is cleared.
4. **Direction Flag Reconfiguration**:
   - First active tile (`k == 0`): `LV_DIR_RIGHT`
   - Intermediate tiles (`0 < k < active_count - 1`): `LV_DIR_HOR`
   - Last active tile (`k == active_count - 1`): `LV_DIR_LEFT`
5. **Contextual Hint Update**: The navigation label at the bottom of each tile dynamically updates its text to show available swipe directions:
   - Example: `< System | Agent & CI >` or `< Swipe Right for System`.
6. **Zero-Jitter Viewport Preservation**: If the currently active tile was not disabled, the viewport remains pinned to that tile; if the active tile was disabled, the view immediately snaps to the invariant Settings Deck (`DECK_SETTINGS`).
7. **NVS Persistence**: Deck toggle states and brightness are written to ESP32 Non-Volatile Storage (`Preferences` namespace `"mac_ctrl"`, keys `"deck_sys"`, `"deck_smart"`, `"deck_agent"`, `"brightness"`).

---

## 7. Host Companion Daemon Architecture

The host software is a Python daemon (`mac_stats_daemon.py`) structured into modular subsystems:

```
mac_stats_daemon.py (Main Thread)
  │
  ├── FrontmostAppDetector (app_profiles.py)
  │     ├── /usr/bin/lsappinfo (<20ms query)
  │     ├── osascript (fallback query)
  │     └── 250ms Debounce State Machine
  │
  ├── AgentCIMonitor (agent_ci_monitor.py - Worker Thread)
  │     ├── Process Scanner: pgrep -fl "antigravity|claude|agy"
  │     ├── Workspace Scanner: .agents/*/progress.md mtime & error detection
  │     ├── Git Status: git status --porcelain -b
  │     ├── GitHub PR Checks: gh pr checks / gh run list
  │     └── Thread-Safe Atomic Cached Payload
  │
  └── StreamSession (transport-agnostic)
        ├── SerialTransport (pyserial)   -- /dev/cu.usbmodem*, preferred
        ├── UdpTransport (socket)        -- :8266, mDNS-discovered fallback
        ├── 1 Hz System Telemetry Loop
        ├── 5 Hz Agent/CI Telemetry Loop (with instant change trigger)
        └── Inbound Action Handler (run_checks, open_pr, focus_agent)
```

`StreamSession` holds all cadence state, so the USB and Wi-Fi paths run identical logic — the only difference between them is which transport object is passed in. `open_transport()` re-picks the link on every reconnect: the cable wins when present, and a Wi-Fi session yields back to USB within 2 s of the cable being plugged in. UDP sends never fail loudly, so Wi-Fi liveness comes from the device's own 5 s radio telemetry rather than from write errors; 20 s of silence tears the session down and re-runs discovery.

The daemon decouples slow shell commands (`gh pr checks` can take 1.5–3.0 seconds) into a background worker thread (`AgentCIMonitor`), guaranteeing that the main loop maintains its responsive 50ms loop interval for instant frontmost app switching.

---

## 8. Dual-Channel Packet Router (`packet_router.cpp`)

One decoder serves both transports. `packet_router_handle(json, len, channel)` is the only place the wire protocol is interpreted; `main.cpp` feeds it from `Serial` with `LINK_CHANNEL_USB` and from `net_telemetry` with `LINK_CHANNEL_NET`, and nothing downstream can tell them apart.

**Arbitration.** Each channel records the timestamp of its last *recognised* packet. USB is active while that timestamp is under 3 s old, then Wi-Fi, then nothing. Only recognised packets count: a stray datagram on :8266 must not hold the link out of standby or mute the cloud poller.

**Outbound.** `packet_router_emit()` sends over the active channel, preferring the UDP reply path when untethered and always mirroring to `Serial` so a plugged-in developer console sees every command. This is why Deck 2's buttons keep working across the LAN.

**mDNS.** `wifi_manager.cpp` starts the responder on each DHCP lease and tears it down on link loss, radio-off, and portal start — the responder binds to the station netif, so it cannot survive any of those.

---

## 9. Autonomous Cloud CI Monitor (`cloud_ci.cpp`)

When Wi-Fi is up and neither channel has carried a host packet for 15 s, the device polls the GitHub Actions API itself and takes over Deck 2 (header badge `LIVE` → `CLOUD`). A daemon packet takes the deck straight back.

**Thread model.** A TLS handshake blocks for hundreds of milliseconds, so the fetch runs on a dedicated FreeRTOS task (16 KB stack, priority 1) pinned to **core 0**; the Arduino loop and LVGL own core 1. The worker only ever writes into a mutex-guarded result slot, and `cloud_ci_loop()` drains it on the main loop — so every `ui_*` and `buzzer_*` call still happens on the Arduino task. The worker blocks on `ulTaskNotifyTake()` between polls and costs nothing while idle.

**Memory.** An ArduinoJson parse *filter* materialises only the six fields the deck renders; `exclude_pull_requests=true` keeps the body around 8 KB, and anything over 64 KB is refused rather than buffered.

**Trust.** Certificates are verified against three roots pinned in `src/github_ca.h` (DigiCert Global Root G2 and both USERTrust roots), covering GitHub's current chain and a rotation between them. `cloud_ci_set_insecure(true)` is the field escape hatch if GitHub moves outside that set before a firmware update lands; a TLS failure surfaces on the deck as an error rather than as silence.

**Backoff.** A failing poll backs off geometrically to a 15-minute ceiling — and never below the configured interval, so a broken endpoint is never polled *more* often than a healthy one.

---

## 10. Over-the-Air Updates (`ota_manager.cpp`)

Two paths, both gated on the same device-derived credential (`vitruvian-<last 3 MAC octets>`, overridable and persisted in NVS `ota:pass`):

- **ArduinoOTA** on port 3232 — `pio run -t upload --upload-port vitruvian-companion.local`.
- **HTTP `/update`** on port 80 — a browser upload form, no toolchain required, behind HTTP Basic auth as user `vitruvian`.

Port 80 is shared with the Wi-Fi provisioning portal, so the two are mutually exclusive: the Settings deck's `[Web Portal]` button calls `ota_manager_stop()` *before* `wifi_manager_start_portal()`, or the portal's bind would silently lose the race. `ota_manager_stop()` also refuses to run mid-flash — tearing the transport out from under a live upload leaves a half-written OTA partition and a bricked boot.
