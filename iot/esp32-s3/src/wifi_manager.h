/*
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#pragma once
#include <stdint.h>

// Wi-Fi subsystem states surfaced to the UI and wire telemetry.
enum WifiMgrState {
    WIFI_MGR_OFF = 0,     // Radio disabled by the user toggle
    WIFI_MGR_IDLE,        // Radio on, no credentials stored
    WIFI_MGR_CONNECTING,  // Station association in progress
    WIFI_MGR_CONNECTED,   // Associated with an IP lease
    WIFI_MGR_PORTAL       // SoftAP provisioning portal active
};

// WPA2 wire limits: SSID is 1..32 octets, passphrase is 8..63 ASCII (or empty
// for open networks). Buffers include the NUL terminator.
#define WIFI_SSID_MAX_LEN 32
#define WIFI_PASS_MAX_LEN 64

// Fired from wifi_manager_loop() (main-loop context, LVGL-safe) whenever the
// state changes. `detail` carries the IP when connected, or the SoftAP SSID
// while the portal is up; `ssid` is the station network name.
typedef void (*wifi_status_cb_t)(WifiMgrState state, const char* detail, const char* ssid);

void wifi_manager_init();
void wifi_manager_loop();
void wifi_manager_set_status_callback(wifi_status_cb_t cb);

// Radio enable toggle, persisted to NVS namespace "wifi_config" key "enabled".
bool wifi_manager_is_enabled();
void wifi_manager_set_enabled(bool enabled);

// Stores credentials to NVS (keys "ssid"/"pass"), enables the radio, and
// starts a station connection attempt. Returns false on invalid input.
bool wifi_manager_set_credentials(const char* ssid, const char* pass);
bool wifi_manager_has_credentials();

// SoftAP provisioning portal (embedded web server at 192.168.4.1).
void wifi_manager_start_portal();
void wifi_manager_stop_portal();
uint32_t wifi_manager_portal_seconds_left();

WifiMgrState wifi_manager_get_state();
const char* wifi_manager_get_ip();      // "" unless connected
const char* wifi_manager_get_ssid();    // stored station SSID ("" if none)
const char* wifi_manager_get_ap_name(); // SoftAP SSID (valid while portal up)
const char* wifi_manager_get_mac();     // station MAC, formatted
const char* wifi_manager_state_str();   // "off"|"offline"|"connecting"|"connected"|"portal"

// mDNS responder ("vitruvian-companion.local" advertising _vitruvian._tcp on
// NET_TELEMETRY_PORT). Started automatically on every DHCP lease and torn down
// when the link drops; exposed for tests and for callers that need the name.
bool wifi_manager_mdns_is_up();
const char* wifi_manager_mdns_hostname();  // "vitruvian-companion.local"
