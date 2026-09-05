// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include <Arduino.h>
#include <esp_timer.h>
#include <lvgl.h>
#include "Arduino_GFX_Library.h"
#include "pin_config.h"
#include "ble_hid.h"
#include "buzzer.h"
#include "cloud_ci.h"
#include "mac_hid.h"
#include "net_telemetry.h"
#include "ota_manager.h"
#include "packet_router.h"
#include "qmi8658.h"
#include "touch_cst816t.h"
#include "ui.h"
#include "wifi_manager.h"

// GFX Driver
static Arduino_DataBus *bus = new Arduino_ESP32SPI(LCD_DC, LCD_CS, LCD_SCK, LCD_MOSI);
static Arduino_GFX *gfx = new Arduino_ST7789(bus, LCD_RST, 0 /* rotation */, true /* IPS */, LCD_WIDTH, LCD_HEIGHT, 0, 20, 0, 20);

// LVGL Buffers
static lv_disp_draw_buf_t draw_buf;
static lv_color_t *buf1 = NULL;
static lv_color_t *buf2 = NULL;

static void disp_flush_cb(lv_disp_drv_t *disp, const lv_area_t *area, lv_color_t *color_p) {
    uint32_t w = (area->x2 - area->x1 + 1);
    uint32_t h = (area->y2 - area->y1 + 1);
    gfx->draw16bitRGBBitmap(area->x1, area->y1, (uint16_t *)&color_p->full, w, h);
    lv_disp_flush_ready(disp);
}

// ---------------------------------------------------------------------------
// Milestone 7: IMU auto-rotate. The display driver lives here, so this is
// where a rotation actually lands on the hardware. ui.cpp calls it to restore
// portrait when the toggle goes off; loop() calls it with the debounced IMU
// orientation while auto-rotate is enabled.
// ---------------------------------------------------------------------------
static uint8_t current_rotation = 0;

uint8_t display_get_current_rotation() {
    return current_rotation;
}

void display_apply_rotation(uint8_t rotation) {
    if (rotation > 3) return;
    if (rotation == current_rotation) return;
    uint8_t prev_rotation = current_rotation;
    current_rotation = rotation;

    bool prev_is_landscape = (prev_rotation == 1 || prev_rotation == 3);
    bool new_is_landscape = (rotation == 1 || rotation == 3);

    gfx->setRotation(rotation);
    touch_set_rotation(rotation);

    if (prev_is_landscape != new_is_landscape) {
        uint16_t new_w = new_is_landscape ? LCD_HEIGHT : LCD_WIDTH;
        uint16_t new_h = new_is_landscape ? LCD_WIDTH : LCD_HEIGHT;

        lv_disp_t *disp = lv_disp_get_default();
        if (disp && disp->driver) {
            disp->driver->hor_res = new_w;
            disp->driver->ver_res = new_h;
            lv_disp_drv_update(disp, disp->driver);
        }
        ui_reflow_layout(new_is_landscape);
    }

    // Rotation swaps the panel's scan direction underneath LVGL's clean
    // buffers; force a full repaint through the new transform.
    lv_obj_invalidate(lv_scr_act());
    lv_refr_now(NULL);
    Serial.printf("[DISPLAY] Rotated to orientation %d (%s)\n", rotation,
                  new_is_landscape ? "Landscape" : "Portrait");
}

static unsigned long last_touch_print = 0;

static void touchpad_read_cb(lv_indev_drv_t *indev_driver, lv_indev_data_t *data) {
    uint16_t touchX = 0;
    uint16_t touchY = 0;
    bool touched = touch_read(&touchX, &touchY);

    if (touched) {
        data->state = LV_INDEV_STATE_PR;
        data->point.x = touchX;
        data->point.y = touchY;

        if (millis() - last_touch_print > 150) {
            Serial.printf("TOUCH_EVENT: x=%d, y=%d\n", touchX, touchY);
            last_touch_print = millis();
        }
    } else {
        data->state = LV_INDEV_STATE_REL;
    }
}

// ---------------------------------------------------------------------------
// LVGL tick source.
//
// lv_conf.h sets LV_TICK_CUSTOM 0, so LVGL's millisecond counter only advances
// when lv_tick_inc() is called. Without it lv_tick_get() stays pinned at 0 and
// no lv_timer ever becomes due -- meaning neither the display refresh timer nor
// the input-device (touch) read timer ever runs. Matches the tick timer used by
// the Waveshare reference example (examples/arduino/11_LVGL_Arduino).
// ---------------------------------------------------------------------------
#define LVGL_TICK_PERIOD_MS 2

static void lvgl_tick_cb(void *arg) {
    lv_tick_inc(LVGL_TICK_PERIOD_MS);
}

static void lvgl_tick_timer_init() {
    const esp_timer_create_args_t tick_timer_args = {
        .callback = &lvgl_tick_cb,
        .arg = NULL,
        .dispatch_method = ESP_TIMER_TASK,
        .name = "lvgl_tick",
        .skip_unhandled_events = true,
    };
    esp_timer_handle_t tick_timer = NULL;
    ESP_ERROR_CHECK(esp_timer_create(&tick_timer_args, &tick_timer));
    ESP_ERROR_CHECK(esp_timer_start_periodic(tick_timer, LVGL_TICK_PERIOD_MS * 1000));
}

static unsigned long last_diag_ms = 0;
static unsigned long last_radio_telemetry_ms = 0;

// Rendered link state, so the Tile 0 badge is only rewritten on a transition
// rather than on every 5 ms loop tick.
static LinkChannel rendered_channel = (LinkChannel)-1;
static char rendered_ip[16] = "";

// The cloud poller only takes the deck once BOTH host channels have been
// quiet this long (design spec 4.1); the 3 s link-badge window is deliberately
// shorter, so the badge drops to standby well before the poller steps in.
#define CLOUD_TAKEOVER_IDLE_MS 15000UL

// ---------------------------------------------------------------------------
// Inbound packets. Both channels funnel into the same router, so a stats or
// app packet behaves identically whether it arrived over the cable or the LAN.
// ---------------------------------------------------------------------------
static void on_net_packet(const char* json, size_t len) {
    packet_router_handle(json, len, LINK_CHANNEL_NET);
}

static void ingest_usb_serial() {
    while (Serial.available()) {
        String line = Serial.readStringUntil('\n');
        line.trim();
        if (line.length() == 0) continue;
        packet_router_handle(line.c_str(), line.length(), LINK_CHANNEL_USB);
    }
}

// Both callbacks fire from the managers' loop functions (main-loop context),
// so touching LVGL here is safe.
static void on_wifi_status_change(WifiMgrState state, const char* detail, const char* ssid) {
    ui_update_wifi_status(wifi_manager_state_str(), detail, ssid);
    packet_router_send_wifi_status();
}

static void on_ble_status_change(BleHidState state, const char* host, uint32_t seconds_left) {
    ui_update_ble_status(ble_hid_state_str(), host, seconds_left);
    // The advertising countdown re-fires this every second; only put state
    // transitions on the wire.
    static BleHidState last_wire_state = (BleHidState)-1;
    if (state != last_wire_state) {
        last_wire_state = state;
        packet_router_send_ble_status();
    }
}

// Fired from ota_manager_loop() in main-loop context.
static void on_ota_progress(int percent, const char* detail) {
    ui_show_ota_progress(percent, detail);
}

void setup() {
    Serial.begin(115200);

    // 1. Claim the buzzer's LEDC channel before anything can drive GPIO 42.
    buzzer_init();

    // 2. Initialize USB HID Stack
    mac_hid_init();

    // 3. Initialize Touch Driver
    touch_init();

    // 3b. Probe the QMI8658 IMU (shares the touch I2C bus, so this must run
    //     after touch_init's Wire.begin). Absence is fine: auto-rotate simply
    //     reports "IMU not detected" and the panel stays in portrait.
    qmi8658_init();

    // 4. Initialize Wireless Radios (before ui_init so the Settings Deck
    //    toggles reflect the NVS-persisted enable flags)
    wifi_manager_init();
    ble_hid_init();
    wifi_manager_set_status_callback(on_wifi_status_change);
    ble_hid_set_status_callback(on_ble_status_change);

    // 5. Untethered services. The UDP listener and OTA endpoints only bind
    //    once a lease lands (driven from loop()); this just wires them up.
    net_telemetry_init(on_net_packet);
    ota_manager_init(on_ota_progress);
    cloud_ci_init();

    // 6. Initialize Display
    gfx->begin();

    // 7. Initialize LVGL
    lv_init();
    lvgl_tick_timer_init();   // must be running before any lv_timer_handler() call

    size_t buf_pixels = LCD_HEIGHT * 30; // 30 lines buffer in DMA for either orientation
    buf1 = (lv_color_t *)heap_caps_malloc(buf_pixels * sizeof(lv_color_t), MALLOC_CAP_DMA);
    buf2 = (lv_color_t *)heap_caps_malloc(buf_pixels * sizeof(lv_color_t), MALLOC_CAP_DMA);
    lv_disp_draw_buf_init(&draw_buf, buf1, buf2, buf_pixels);

    static lv_disp_drv_t disp_drv;
    lv_disp_drv_init(&disp_drv);
    disp_drv.hor_res = LCD_WIDTH;
    disp_drv.ver_res = LCD_HEIGHT;
    disp_drv.flush_cb = disp_flush_cb;
    disp_drv.draw_buf = &draw_buf;
    lv_disp_drv_register(&disp_drv);

    static lv_indev_drv_t indev_drv;
    lv_indev_drv_init(&indev_drv);
    indev_drv.type = LV_INDEV_TYPE_POINTER;
    indev_drv.read_cb = touchpad_read_cb;
    lv_indev_drv_register(&indev_drv);

    // 8. Build UI (TileView: System Deck + Smart Deck + Settings Deck)
    ui_init();
    ui_set_hw_ids(wifi_manager_get_mac());
}

void loop() {
    // LVGL tick and task processing
    lv_timer_handler();

    // Advance any queued buzzer melody (non-blocking; see buzzer.cpp).
    buzzer_loop();

    // Periodic I2C Diagnostics every 2.5 seconds
    if (millis() - last_diag_ms > 2500) {
        last_diag_ms = millis();
        Wire.beginTransmission(CST816T_DEVICE_ADDRESS);
        byte err = Wire.endTransmission();
        Serial.printf("[DIAG] I2C 0x15 Ping: %s (code %d)\n", (err == 0 ? "ACK/OK" : "NO-ACK"), err);
    }

    // IMU auto-rotate: feed the debounced orientation classifier every 100ms
    // while the Settings toggle is on. The 300ms debounce and flat-on-desk
    // suppression live inside qmi8658_get_orientation(); the applier below
    // no-ops unless the stable orientation actually changed.
    static unsigned long last_orient_poll_ms = 0;
    if (millis() - last_orient_poll_ms > 100) {
        last_orient_poll_ms = millis();
        if (ui_get_auto_rotate_enabled() && qmi8658_is_present()) {
            display_apply_rotation(qmi8658_get_orientation());
        }
    }

    // Channel 1: USB CDC from the tethered Mac companion.
    ingest_usb_serial();

    // Wireless radio state machines (portal HTTP serving, station reconnect,
    // BLE advertising windows) + their UI/telemetry notifications. Runs before
    // the transports below so they see this tick's link state.
    wifi_manager_loop();
    ble_hid_loop();

    // Bring the untethered services up and down with the station link. Both
    // calls are idempotent, so this is a plain level-triggered follower rather
    // than a state machine of its own.
    bool wifi_up = (wifi_manager_get_state() == WIFI_MGR_CONNECTED);
    if (wifi_up) {
        net_telemetry_start();
        ota_manager_start();
    } else {
        ota_manager_stop();
        net_telemetry_stop();
    }

    // Channel 2: UDP telemetry from an untethered Mac companion.
    net_telemetry_loop();
    ota_manager_loop();

    // Autonomous cloud beacon: only takes the Agent & CI deck once neither
    // channel has carried a host packet for CLOUD_TAKEOVER_IDLE_MS.
    bool host_streaming = packet_router_host_active(CLOUD_TAKEOVER_IDLE_MS);
    static bool was_driving = false;
    cloud_ci_loop(wifi_up, host_streaming);
    bool driving = cloud_ci_is_driving();
    if (driving && (cloud_ci_take_update() || !was_driving)) {
        ui_update_cloud_ci(cloud_ci_get_result(), cloud_ci_get_state(), cloud_ci_get_repo(),
                           cloud_ci_get_error());
    }
    was_driving = driving;

    // Periodic radio telemetry for the companion daemon (5s cadence, over
    // whichever channel the host is actually reachable on).
    if ((mac_hid_usb_ready() || net_telemetry_has_client()) &&
        millis() - last_radio_telemetry_ms > 5000) {
        last_radio_telemetry_ms = millis();
        packet_router_send_wifi_status();
        packet_router_send_ble_status();
    }

    // Tile 0 link badge: USB while the cable is streaming, Wi-Fi while the LAN
    // is, otherwise the station IP (reachable but idle) or Standby.
    LinkChannel channel = packet_router_active_channel();
    const char* ip = wifi_up ? wifi_manager_get_ip() : "";
    if (channel != rendered_channel || strcmp(ip, rendered_ip) != 0) {
        rendered_channel = channel;
        strlcpy(rendered_ip, ip, sizeof(rendered_ip));
        ui_update_link_status(channel, ip);
    }

    delay(5);
}
