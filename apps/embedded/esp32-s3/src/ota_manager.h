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

#pragma once
#include <stdbool.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Wireless firmware updates, two ways:
//   1. ArduinoOTA on port 3232 -- `pio run -t upload --upload-port
//      vitruvian-companion.local` from the workstation.
//   2. An HTTP `/update` form on port 80 -- drag a .bin onto the page from any
//      browser on the LAN, no toolchain required.
//
// Both are HTTP-Basic / OTA-password gated with the same device-derived
// credential (see ota_manager_password); the device is only reachable from the
// local subnet in the first place.
//
// Port 80 is shared with the Wi-Fi provisioning portal, so the two are
// mutually exclusive: ota_manager_stop() must run before the portal comes up.
// ---------------------------------------------------------------------------

#define OTA_HTTP_USER "vitruvian"
#define OTA_PASSWORD_MAX 33

// Fired from ota_manager_loop() (main-loop context, LVGL-safe) on every
// progress step, and once with percent = -1 on failure.
typedef void (*ota_progress_cb_t)(int percent, const char* detail);

void ota_manager_init(ota_progress_cb_t cb);

// Idempotent; safe to drive straight off the Wi-Fi link state each loop.
bool ota_manager_start();
void ota_manager_stop();
bool ota_manager_is_running();

void ota_manager_loop();

// True from the first byte of an upload until the reboot, so callers can hold
// off anything that would compete for flash or CPU.
bool ota_manager_is_updating();
int ota_manager_progress_percent();

// Device-derived default ("vitruvian-<last 3 MAC octets>"), overridable and
// persisted in NVS namespace "ota", key "pass".
const char* ota_manager_password();
void ota_manager_set_password(const char* password);
