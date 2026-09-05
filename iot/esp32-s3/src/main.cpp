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
#include <ArduinoJson.h>
#include "Arduino_GFX_Library.h"
#include "pin_config.h"
#include "mac_hid.h"
#include "touch_cst816t.h"
#include "ui.h"

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

static unsigned long last_stats_ms = 0;
static unsigned long last_diag_ms = 0;
static bool link_active = false;

static uint32_t parse_color_hex(const char* str, uint32_t default_color = 0x0A84FF) {
    if (!str || strlen(str) == 0) return default_color;
    if (str[0] == '#') {
        return (uint32_t)strtoul(str + 1, NULL, 16);
    } else if (strncmp(str, "0x", 2) == 0 || strncmp(str, "0X", 2) == 0) {
        return (uint32_t)strtoul(str + 2, NULL, 16);
    }
    return (uint32_t)strtoul(str, NULL, 16);
}

static uint32_t extract_color(JsonVariant v, uint32_t default_color = 0x0A84FF) {
    if (v.is<uint32_t>()) {
        return v.as<uint32_t>();
    } else if (v.is<const char*>()) {
        return parse_color_hex(v.as<const char*>(), default_color);
    }
    return default_color;
}

void setup() {
    Serial.begin(115200);

    // 1. Initialize USB HID Stack
    mac_hid_init();

    // 2. Initialize Touch Driver
    touch_init();

    // 3. Initialize Display
    gfx->begin();

    // 4. Initialize LVGL
    lv_init();
    lvgl_tick_timer_init();   // must be running before any lv_timer_handler() call

    size_t buf_pixels = LCD_WIDTH * 30; // 30 lines buffer in DMA
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

    // 5. Build UI (TileView: System Deck + Smart Deck + Settings Deck)
    ui_init();
}

void loop() {
    // LVGL tick and task processing
    lv_timer_handler();

    // Periodic I2C Diagnostics every 2.5 seconds
    if (millis() - last_diag_ms > 2500) {
        last_diag_ms = millis();
        Wire.beginTransmission(CST816T_DEVICE_ADDRESS);
        byte err = Wire.endTransmission();
        Serial.printf("[DIAG] I2C 0x15 Ping: %s (code %d)\n", (err == 0 ? "ACK/OK" : "NO-ACK"), err);
    }

    // Read incoming JSON packets from Mac companion over USB CDC
    while (Serial.available()) {
        String line = Serial.readStringUntil('\n');
        line.trim();
        if (line.length() > 0 && line.startsWith("{") && line.endsWith("}")) {
            JsonDocument doc;
            DeserializationError err = deserializeJson(doc, line);
            if (err) {
                Serial.printf("[JSON] Deserialization error: %s\n", err.c_str());
                continue;
            }

            const char* type = doc["type"] | "";

            // 1. Stats Packet (or legacy packet containing "cpu")
            if (strcmp(type, "stats") == 0 || (strlen(type) == 0 && !doc["cpu"].isNull())) {
                int cpu = doc["cpu"] | -1;
                int ram = doc["ram"] | -1;
                const char* time_str = doc["time"] | "";
                ui_update_stats(cpu, ram, time_str, true);
                last_stats_ms = millis();
                link_active = true;
            }
            // 2. App Shortcut Profile Packet
            else if (strcmp(type, "app") == 0) {
                const char* app_name = doc["app"] | doc["name"] | "Default";
                uint32_t app_color = extract_color(doc["color"], 0x0A84FF);

                DynamicButtonConfig btns[6];
                JsonArray btn_arr = doc["buttons"].as<JsonArray>();
                int count = 0;

                for (JsonObject b : btn_arr) {
                    if (count >= 6) break;
                    const char* lbl = b["label"] | "";
                    strncpy(btns[count].label, lbl, sizeof(btns[count].label) - 1);
                    btns[count].label[sizeof(btns[count].label) - 1] = '\0';

                    btns[count].mod   = b["mod"] | 0;
                    btns[count].key   = b["key"] | 0;
                    btns[count].cons  = b["cons"] | 0;
                    btns[count].color = extract_color(b["color"], app_color);
                    count++;
                }

                // Fill remaining slots with safe defaults
                for (int i = count; i < 6; i++) {
                    snprintf(btns[i].label, sizeof(btns[i].label), "-");
                    btns[i].mod   = 0;
                    btns[i].key   = 0;
                    btns[i].cons  = 0;
                    btns[i].color = 0x2C2C2E;
                }

                ui_update_smart_deck(app_name, app_color, btns);
                last_stats_ms = millis();
                link_active = true;
                Serial.printf("[SMART] Applied profile for '%s' (%d buttons)\n", app_name, count);
            }
            // 3. Agent & CI/CD Status Packet (Milestone 3)
            else if (strcmp(type, "agent_ci") == 0) {
                AgentCIConfig config;
                memset(&config, 0, sizeof(config));

                // A. Parse Agent Sub-Object
                JsonObject agent = doc["agent"];
                if (!agent.isNull()) {
                    const char* a_name = agent["name"] | "Agent";
                    strncpy(config.agent_name, a_name, sizeof(config.agent_name) - 1);
                    config.agent_name[sizeof(config.agent_name) - 1] = '\0';

                    const char* a_state = agent["state"] | "idle";
                    if (strcasecmp(a_state, "running") == 0) {
                        config.agent_state = AGENT_STATE_RUNNING;
                    } else if (strcasecmp(a_state, "review") == 0) {
                        config.agent_state = AGENT_STATE_REVIEW;
                    } else if (strcasecmp(a_state, "error") == 0) {
                        config.agent_state = AGENT_STATE_ERROR;
                    } else {
                        config.agent_state = AGENT_STATE_IDLE;
                    }

                    const char* a_task = agent["task"] | agent["detail"] | "Idle";
                    strncpy(config.agent_task, a_task, sizeof(config.agent_task) - 1);
                    config.agent_task[sizeof(config.agent_task) - 1] = '\0';

                    config.active_agents = agent["active_agents"] | (config.agent_state == AGENT_STATE_RUNNING ? 1 : 0);
                } else {
                    strncpy(config.agent_name, "Agent", sizeof(config.agent_name) - 1);
                    config.agent_state = AGENT_STATE_IDLE;
                    strncpy(config.agent_task, "No data", sizeof(config.agent_task) - 1);
                }

                // B. Parse CI Sub-Object
                JsonObject ci = doc["ci"];
                if (!ci.isNull()) {
                    const char* c_repo = ci["repo"] | "repo";
                    strncpy(config.repo, c_repo, sizeof(config.repo) - 1);
                    config.repo[sizeof(config.repo) - 1] = '\0';

                    const char* c_branch = ci["branch"] | "main";
                    strncpy(config.branch, c_branch, sizeof(config.branch) - 1);
                    config.branch[sizeof(config.branch) - 1] = '\0';

                    const char* c_status = ci["status"] | ci["state"] | "unknown";
                    if (strcasecmp(c_status, "passing") == 0 || strcasecmp(c_status, "success") == 0) {
                        config.ci_status = CI_STATUS_PASSING;
                    } else if (strcasecmp(c_status, "failing") == 0 || strcasecmp(c_status, "failure") == 0) {
                        config.ci_status = CI_STATUS_FAILING;
                    } else if (strcasecmp(c_status, "pending") == 0 || strcasecmp(c_status, "in_progress") == 0) {
                        config.ci_status = CI_STATUS_PENDING;
                    } else if (strcasecmp(c_status, "none") == 0) {
                        config.ci_status = CI_STATUS_NONE;
                    } else {
                        config.ci_status = CI_STATUS_UNKNOWN;
                    }

                    config.pr_number = ci["pr"] | 0;
                    config.checks_passed = ci["passed"] | 0;
                    config.checks_total = ci["total"] | 0;
                    config.is_dirty = ci["dirty"] | false;
                    config.dirty_files = ci["dirty_files"] | 0;
                } else {
                    strncpy(config.repo, "-", sizeof(config.repo) - 1);
                    strncpy(config.branch, "-", sizeof(config.branch) - 1);
                    config.ci_status = CI_STATUS_UNKNOWN;
                }

                // C. Update LVGL Tile 2
                ui_update_agent_ci(&config);

                // D. Reset Link Watchdog Timer
                last_stats_ms = millis();
                link_active = true;

                Serial.printf("[AGENT_CI] Received: Agent=%s, CI=%s (%d/%d checks)\n",
                              config.agent_name, config.branch,
                              config.checks_passed, config.checks_total);
            }
            // 4. Deck Visibility Configuration Packet (Milestone 4)
            else if (strcmp(type, "deck_config") == 0) {
                if (!doc["system"].isNull()) {
                    ui_set_deck_enabled(DECK_SYSTEM, doc["system"].as<bool>());
                }
                if (!doc["smart"].isNull()) {
                    ui_set_deck_enabled(DECK_SMART, doc["smart"].as<bool>());
                }
                if (!doc["agent"].isNull()) {
                    ui_set_deck_enabled(DECK_AGENT_CI, doc["agent"].as<bool>());
                }
                ui_reindex_carousel();
                ui_save_deck_preferences();
                last_stats_ms = millis();
                link_active = true;
                Serial.printf("[DECK_CONFIG] Applied: sys=%d, smart=%d, agent=%d\n",
                              ui_is_deck_enabled(DECK_SYSTEM),
                              ui_is_deck_enabled(DECK_SMART),
                              ui_is_deck_enabled(DECK_AGENT_CI));
            }
        }
    }

    // Check link timeout (4 seconds without packet -> standby mode)
    if (link_active && (millis() - last_stats_ms > 4000)) {
        link_active = false;
        ui_update_stats(-1, -1, NULL, false);
    }

    delay(5);
}
