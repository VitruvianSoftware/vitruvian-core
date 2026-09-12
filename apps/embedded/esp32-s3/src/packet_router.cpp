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

#include "packet_router.h"

#include <Arduino.h>
#include <ArduinoJson.h>

#include "ble_hid.h"
#include "cloud_ci.h"
#include "mac_hid.h"
#include "net_telemetry.h"
#include "ui.h"
#include "wifi_manager.h"

static unsigned long last_usb_rx_ms = 0;
static unsigned long last_net_rx_ms = 0;

// ---------------------------------------------------------------------------
// Colour coercion: the wire accepts 0xRRGGBB integers as well as "#RRGGBB" /
// "0xRRGGBB" / "RRGGBB" strings, because both shapes occur in hand-written
// app profiles.
// ---------------------------------------------------------------------------
static uint32_t parse_color_hex(const char* str, uint32_t default_color) {
    if (!str || strlen(str) == 0) return default_color;
    if (str[0] == '#') {
        return (uint32_t)strtoul(str + 1, NULL, 16);
    }
    if (strncmp(str, "0x", 2) == 0 || strncmp(str, "0X", 2) == 0) {
        return (uint32_t)strtoul(str + 2, NULL, 16);
    }
    return (uint32_t)strtoul(str, NULL, 16);
}

static uint32_t extract_color(JsonVariant v, uint32_t default_color) {
    if (v.is<uint32_t>()) {
        return v.as<uint32_t>();
    }
    if (v.is<const char*>()) {
        return parse_color_hex(v.as<const char*>(), default_color);
    }
    return default_color;
}

// ---------------------------------------------------------------------------
// Wi-Fi / radio status telemetry (device -> host)
// ---------------------------------------------------------------------------
void packet_router_send_wifi_status() {
    JsonDocument doc;
    doc["type"] = "wifi_status";
    doc["state"] = wifi_manager_state_str();
    doc["enabled"] = wifi_manager_is_enabled();
    doc["ssid"] = wifi_manager_get_ssid();
    doc["ip"] = wifi_manager_get_ip();

    char line[192];
    serializeJson(doc, line, sizeof(line));
    packet_router_emit(line);
}

void packet_router_send_ble_status() {
    JsonDocument doc;
    doc["type"] = "ble_status";
    doc["state"] = ble_hid_state_str();
    doc["enabled"] = ble_hid_is_enabled();
    doc["host"] = ble_hid_get_host();
    doc["adv_seconds"] = ble_hid_advertising_seconds_left();

    char line[192];
    serializeJson(doc, line, sizeof(line));
    packet_router_emit(line);
}

// ---------------------------------------------------------------------------
// Per-packet handlers
// ---------------------------------------------------------------------------
static void handle_app_profile(JsonDocument& doc) {
    const char* app_name = doc["app"] | doc["name"] | "Default";
    uint32_t app_color = extract_color(doc["color"], 0x0A84FF);

    DynamicButtonConfig btns[6];
    JsonArray btn_arr = doc["buttons"].as<JsonArray>();
    int count = 0;

    for (JsonObject b : btn_arr) {
        if (count >= 6) break;
        const char* lbl = b["label"] | "";
        strlcpy(btns[count].label, lbl, sizeof(btns[count].label));
        btns[count].mod = b["mod"] | 0;
        btns[count].key = b["key"] | 0;
        btns[count].cons = b["cons"] | 0;
        btns[count].color = extract_color(b["color"], app_color);
        count++;
    }

    for (int i = count; i < 6; i++) {
        snprintf(btns[i].label, sizeof(btns[i].label), "-");
        btns[i].mod = 0;
        btns[i].key = 0;
        btns[i].cons = 0;
        btns[i].color = 0x2C2C2E;
    }

    ui_update_smart_deck(app_name, app_color, btns);
    Serial.printf("[SMART] Applied profile for '%s' (%d buttons)\n", app_name, count);
}

static void handle_agent_ci(JsonDocument& doc) {
    AgentCIConfig config;
    memset(&config, 0, sizeof(config));

    JsonObject agent = doc["agent"];
    if (!agent.isNull()) {
        strlcpy(config.agent_name, agent["name"] | "Agent", sizeof(config.agent_name));

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

        strlcpy(config.agent_task, agent["task"] | agent["detail"] | "Idle",
                sizeof(config.agent_task));
        config.active_agents =
            agent["active_agents"] | (config.agent_state == AGENT_STATE_RUNNING ? 1 : 0);
    } else {
        strlcpy(config.agent_name, "Agent", sizeof(config.agent_name));
        config.agent_state = AGENT_STATE_IDLE;
        strlcpy(config.agent_task, "No data", sizeof(config.agent_task));
    }

    JsonObject ci = doc["ci"];
    if (!ci.isNull()) {
        strlcpy(config.repo, ci["repo"] | "repo", sizeof(config.repo));
        strlcpy(config.branch, ci["branch"] | "main", sizeof(config.branch));

        const char* c_status = ci["status"] | ci["state"] | "unknown";
        if (strcasecmp(c_status, "passing") == 0 || strcasecmp(c_status, "success") == 0) {
            config.ci_status = CI_STATUS_PASSING;
        } else if (strcasecmp(c_status, "failing") == 0 || strcasecmp(c_status, "failure") == 0) {
            config.ci_status = CI_STATUS_FAILING;
        } else if (strcasecmp(c_status, "pending") == 0 ||
                   strcasecmp(c_status, "in_progress") == 0) {
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
        strlcpy(config.repo, "-", sizeof(config.repo));
        strlcpy(config.branch, "-", sizeof(config.branch));
        config.ci_status = CI_STATUS_UNKNOWN;
    }

    ui_update_agent_ci(&config);
    Serial.printf("[AGENT_CI] Received: Agent=%s, CI=%s (%d/%d checks)\n",
                  config.agent_name, config.branch, config.checks_passed,
                  config.checks_total);
}

static void handle_deck_config(JsonDocument& doc) {
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
    Serial.printf("[DECK_CONFIG] Applied: sys=%d, smart=%d, agent=%d\n",
                  ui_is_deck_enabled(DECK_SYSTEM), ui_is_deck_enabled(DECK_SMART),
                  ui_is_deck_enabled(DECK_AGENT_CI));
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------
bool packet_router_handle(const char* json, size_t len, LinkChannel channel) {
    if (!json || len == 0) return false;
    if (json[0] != '{' || json[len - 1] != '}') return false;

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, json, len);
    if (err) {
        Serial.printf("[JSON] Deserialization error: %s\n", err.c_str());
        return false;
    }

    const char* type = doc["type"] | "";
    const char* cmd = doc["cmd"] | "";
    bool matched = true;

    if (strcmp(cmd, "wifi_set") == 0) {
        const char* ssid = doc["ssid"] | "";
        const char* pass = doc["pass"] | "";
        if (wifi_manager_set_credentials(ssid, pass)) {
            Serial.printf("[WIFI] Companion provisioned SSID '%s'\n", ssid);
            packet_router_send_wifi_status();
        } else {
            Serial.println("[WIFI] Rejected wifi_set: invalid ssid/pass length");
        }
    } else if (strcmp(cmd, "wifi_status") == 0 || strcmp(cmd, "radio_status") == 0) {
        packet_router_send_wifi_status();
    } else if (strcmp(cmd, "cloud_config") == 0 || strcmp(type, "cloud_config") == 0) {
        // Repo/token provisioning for the autonomous poller (docs/protocol.md 2.7).
        if (!doc["repo"].isNull()) {
            cloud_ci_set_repo(doc["repo"] | "");
        }
        if (!doc["token"].isNull()) {
            cloud_ci_set_token(doc["token"] | "");
        }
        if (!doc["enabled"].isNull()) {
            cloud_ci_set_enabled(doc["enabled"].as<bool>());
        }
        Serial.printf("[CLOUD] Config applied: repo=%s token=%s enabled=%d\n",
                      cloud_ci_get_repo(), cloud_ci_has_token() ? "yes" : "no",
                      cloud_ci_is_enabled());
    } else if (strcmp(type, "wifi_sync_error") == 0) {
        const char* detail = doc["error"] | "Mac Wi-Fi error";
        Serial.printf("[WIFI] Sync error received: %s\n", detail);
        ui_show_wifi_error(detail);
    } else if (strcmp(type, "stats") == 0 || (strlen(type) == 0 && !doc["cpu"].isNull())) {
        ui_update_stats(doc["cpu"] | -1, doc["ram"] | -1, doc["time"] | "");
    } else if (strcmp(type, "app") == 0) {
        handle_app_profile(doc);
    } else if (strcmp(type, "agent_ci") == 0) {
        handle_agent_ci(doc);
    } else if (strcmp(type, "deck_config") == 0) {
        handle_deck_config(doc);
    } else {
        matched = false;
    }

    // Only a recognised packet counts as host liveness: a stray datagram on
    // :8266 must not hold the link out of standby (or mute the cloud poller).
    if (matched) {
        if (channel == LINK_CHANNEL_USB) {
            last_usb_rx_ms = millis();
        } else if (channel == LINK_CHANNEL_NET) {
            last_net_rx_ms = millis();
        }
    }
    return matched;
}

// millis() is 0 at boot and wraps after ~49 days; a zero timestamp means
// "never seen", and the subtraction is unsigned so the wrap is harmless.
static bool within_window(unsigned long stamp, unsigned long window_ms) {
    return stamp != 0 && (millis() - stamp) < window_ms;
}

LinkChannel packet_router_active_channel() {
    if (within_window(last_usb_rx_ms, LINK_ACTIVE_WINDOW_MS)) return LINK_CHANNEL_USB;
    if (within_window(last_net_rx_ms, LINK_ACTIVE_WINDOW_MS)) return LINK_CHANNEL_NET;
    return LINK_CHANNEL_NONE;
}

unsigned long packet_router_last_usb_rx_ms() {
    return last_usb_rx_ms;
}

unsigned long packet_router_last_net_rx_ms() {
    return last_net_rx_ms;
}

bool packet_router_host_active(unsigned long within_ms) {
    return within_window(last_usb_rx_ms, within_ms) || within_window(last_net_rx_ms, within_ms);
}

LinkChannel packet_router_emit(const char* json) {
    if (!json) return LINK_CHANNEL_NONE;

    // Untethered: answer the host that is actually streaming to us. Serial is
    // still written so a plugged-in developer console sees every command.
    if (packet_router_active_channel() == LINK_CHANNEL_NET || !mac_hid_usb_ready()) {
        if (net_telemetry_send_line(json)) {
            Serial.println(json);
            return LINK_CHANNEL_NET;
        }
    }

    Serial.println(json);
    return mac_hid_usb_ready() ? LINK_CHANNEL_USB : LINK_CHANNEL_NONE;
}
