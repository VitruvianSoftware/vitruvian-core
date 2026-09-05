# mac-controller Architecture & Subsystems

This document describes the architectural design of the ESP32-S3 Mac Controller, detailing the composite USB OTG stack, graphics rendering pipeline, capacitive touch driver, haptic feedback mechanism, dynamic carousel navigation engine, and host companion architecture.

---

## 1. System Architecture Overview

The system operates across two asynchronous physical domains communicating over a single USB Type-C physical link:

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
                            │ USB-C Cable (OTG Full Speed)
                            │   - USB CDC Serial (115200 8-N-1)
                            │   - USB HID Keyboard & Consumer Control
┌───────────────────────────┼────────────────────────────┐
│                           ▼                            │
│  ┌──────────────────────────────────────────────────┐  │
│  │           ESP32-S3 Native USB OTG Core           │  │
│  └────────────┬─────────────────────────┬───────────┘  │
│               │ Inbound JSON Packets    │ HID Key Press│
│               ▼                         ▲              │
│  ┌──────────────────────────┐   ┌───────┴───────────┐  │
│  │ Packet Dispatcher        │   │ mac_hid Subsystem │  │
│  │ (ArduinoJson 7)          │   │ (TinyUSB HID)     │  │
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

## 5. Audio Haptic Feedback Subsystem

Tactile confirmation is provided by an onboard active buzzer connected to `BUZZER_PIN` (GPIO 42):
- **Click Profile**: `tone(BUZZER_PIN, 2400, 15)`.
- **Frequency**: 2.4 kHz (resonant frequency of the onboard transducer).
- **Duration**: 15 ms non-blocking tone.
- **Trigger Points**: Triggered on every valid touch button click across all four decks and on toggle switch state changes in Settings.

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
  └── Serial Transport Engine (pyserial)
        ├── Auto-detection: /dev/cu.usbmodem*
        ├── 1 Hz System Telemetry Loop
        ├── 5 Hz Agent/CI Telemetry Loop (with instant change trigger)
        └── Inbound Action Handler (run_checks, open_pr, focus_agent)
```

The daemon decouples slow shell commands (`gh pr checks` can take 1.5–3.0 seconds) into a background worker thread (`AgentCIMonitor`), guaranteeing that the main loop maintains its responsive 50ms loop interval for instant frontmost app switching.
