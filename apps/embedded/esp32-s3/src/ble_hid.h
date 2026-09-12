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

// BLE HID subsystem states surfaced to the UI and wire telemetry.
enum BleHidState {
    BLE_HID_OFF = 0,      // Radio disabled by the user toggle
    BLE_HID_STANDBY,      // Enabled, not advertising, not connected
    BLE_HID_ADVERTISING,  // Discoverable pairing window open
    BLE_HID_CONNECTED     // Central (Mac) connected; HID reports flow over BLE
};

// [Pair BLE] opens a discoverable window this long; a bonded device instead
// gets an open-ended reconnect advertisement.
#define BLE_PAIR_WINDOW_SECONDS 60

// Fired from ble_hid_loop() (main-loop context, LVGL-safe) on state changes
// and once per second while the pairing countdown runs. `host` is the peer
// address when connected/bonded, else "".
typedef void (*ble_status_cb_t)(BleHidState state, const char* host, uint32_t seconds_left);

void ble_hid_init();
void ble_hid_loop();
void ble_hid_set_status_callback(ble_status_cb_t cb);

// Radio enable toggle, persisted to NVS namespace "ble_config" key "enabled".
bool ble_hid_is_enabled();
void ble_hid_set_enabled(bool enabled);

// One-touch pairing: enables the radio if needed and advertises for
// BLE_PAIR_WINDOW_SECONDS.
void ble_hid_start_advertising();
void ble_hid_stop_advertising();

bool ble_hid_is_connected();
bool ble_hid_is_advertising();
uint32_t ble_hid_advertising_seconds_left();

BleHidState ble_hid_get_state();
const char* ble_hid_get_host();     // connected/bonded peer address ("" if none)
const char* ble_hid_state_str();    // "off"|"standby"|"advertising"|"connected"

// Sends a keystroke/consumer action using the same (mod, key, cons) semantics
// as the USB path in mac_hid.cpp. No-op unless connected.
void ble_hid_send(uint8_t mod, uint8_t key, uint16_t cons);
