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

#include "ota_manager.h"

#include <ArduinoOTA.h>
#include <Preferences.h>
#include <Update.h>
#include <WebServer.h>
#include <WiFi.h>
#include <Wire.h>

#include "qmi8658.h"
#include "ui.h"
#include "version.h"

static const char* NVS_OTA_NS = "ota";

static WebServer* ota_server = NULL;
static Preferences ota_prefs;
static ota_progress_cb_t progress_cb = NULL;

static bool running = false;
static bool updating = false;
static int progress_percent = 0;
static char ota_password[OTA_PASSWORD_MAX] = "";

// Reported from ota_manager_loop() rather than from the upload callbacks, so
// the LVGL-touching consumer only ever runs on the Arduino loop task.
static volatile int pending_percent = -2;  // -2 = nothing to report
static char pending_detail[48] = "";

static void note_progress(int percent, const char* detail) {
    pending_percent = percent;
    strlcpy(pending_detail, detail ? detail : "", sizeof(pending_detail));
}

static void ensure_password() {
    if (ota_prefs.begin(NVS_OTA_NS, true /* read-only */)) {
        String stored = ota_prefs.getString("pass", "");
        ota_prefs.end();
        if (stored.length() > 0) {
            strlcpy(ota_password, stored.c_str(), sizeof(ota_password));
            return;
        }
    }
    // Device-derived default: unique per unit, printable, and recoverable from
    // the MAC shown on the Settings deck.
    uint8_t mac[6];
    WiFi.macAddress(mac);
    snprintf(ota_password, sizeof(ota_password), "vitruvian-%02X%02X%02X", mac[3], mac[4],
             mac[5]);
}

// ---------------------------------------------------------------------------
// HTTP `/update` endpoint
// ---------------------------------------------------------------------------
static const char UPDATE_HTML[] PROGMEM = R"HTML(<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vitruvian Companion OTA</title>
<style>
body{font-family:-apple-system,Helvetica,Arial,sans-serif;background:#000;color:#fff;
margin:0 auto;padding:24px;max-width:420px}
h1{font-size:20px;margin:16px 0 4px}
p.sub{color:#8e8e93;font-size:13px;margin:0 0 20px}
.card{background:#1c1c1e;border:1px solid #2c2c2e;border-radius:12px;padding:16px}
input[type=file]{width:100%;box-sizing:border-box;color:#fff;font-size:14px;margin:8px 0}
button{width:100%;background:#0a84ff;color:#fff;border:0;border-radius:8px;
padding:14px;font-size:15px;font-weight:600;margin-top:12px}
button:disabled{opacity:.5}
#bar{height:8px;background:#2c2c2e;border-radius:4px;margin-top:16px;overflow:hidden}
#fill{height:100%;width:0;background:#30d158;transition:width .2s}
#msg{color:#8e8e93;font-size:13px;margin-top:12px;text-align:center}
</style></head><body>
<h1>Vitruvian Companion</h1>
<p class="sub">Over-the-air firmware update &mdash; upload <code>firmware.bin</code>.</p>
<div class="card">
<form id="f" method="POST" action="/update" enctype="multipart/form-data">
<input type="file" id="bin" name="update" accept=".bin" required>
<button type="submit" id="go">Flash Firmware</button>
</form>
<div id="bar"><div id="fill"></div></div>
<div id="msg">Firmware )HTML" FIRMWARE_VERSION R"HTML(</div>
</div>
<script>
document.getElementById('f').addEventListener('submit',function(e){
e.preventDefault();
var f=document.getElementById('bin').files[0];if(!f)return;
document.getElementById('go').disabled=true;
var d=new FormData();d.append('update',f);
var x=new XMLHttpRequest();x.open('POST','/update',true);
x.upload.onprogress=function(ev){if(ev.lengthComputable){
var p=Math.round(ev.loaded/ev.total*100);
document.getElementById('fill').style.width=p+'%';
document.getElementById('msg').textContent='Uploading '+p+'%';}};
x.onload=function(){document.getElementById('msg').textContent=
x.status==200?'Update complete - rebooting...':'Update failed: '+x.responseText;};
x.onerror=function(){document.getElementById('msg').textContent='Upload error';};
x.send(d);});
</script></body></html>)HTML";

static bool require_auth() {
    if (ota_server->authenticate(OTA_HTTP_USER, ota_password)) return true;
    ota_server->requestAuthentication();
    return false;
}

static void handle_diag() {
    String out = "{\n";

    // I2C bus scan
    out += "  \"i2c_scan\": [";
    bool first = true;
    for (uint8_t addr = 1; addr < 128; addr++) {
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() == 0) {
            if (!first) out += ", ";
            first = false;
            char hex_buf[10];
            snprintf(hex_buf, sizeof(hex_buf), "\"0x%02X\"", addr);
            out += hex_buf;
        }
    }
    out += "],\n";

    int16_t ax = 0, ay = 0, az = 0;
    bool read_ok = qmi8658_read_accel(&ax, &ay, &az);
    char addr_str[10], who_str[10];
    snprintf(addr_str, sizeof(addr_str), "0x%02X", qmi8658_get_dev_addr());
    snprintf(who_str, sizeof(who_str), "0x%02X", qmi8658_get_who_am_i());

    out += "  \"qmi8658\": {\n";
    out += "    \"present\": " + String(qmi8658_is_present() ? "true" : "false") + ",\n";
    out += "    \"addr\": \"" + String(addr_str) + "\",\n";
    out += "    \"who_am_i\": \"" + String(who_str) + "\",\n";
    out += "    \"read_ok\": " + String(read_ok ? "true" : "false") + ",\n";
    out += "    \"ax\": " + String(ax) + ",\n";
    out += "    \"ay\": " + String(ay) + ",\n";
    out += "    \"az\": " + String(az) + ",\n";
    out += "    \"orientation\": " + String(qmi8658_get_orientation()) + ",\n";
    out += "    \"is_flat\": " + String(qmi8658_is_flat() ? "true" : "false") + "\n";
    out += "  },\n";

    out += "  \"auto_rotate_enabled\": " + String(ui_get_auto_rotate_enabled() ? "true" : "false") + ",\n";
    out += "  \"current_rotation\": " + String(display_get_current_rotation()) + "\n";
    out += "}\n";

    ota_server->sendHeader("Connection", "close");
    ota_server->send(200, "application/json", out);
}

static void handle_update_page() {
    if (!require_auth()) return;
    ota_server->send_P(200, "text/html", UPDATE_HTML);
}

static void handle_update_done() {
    if (!require_auth()) return;
    bool ok = !Update.hasError();
    ota_server->sendHeader("Connection", "close");
    ota_server->send(ok ? 200 : 500, "text/plain", ok ? "OK" : Update.errorString());
    if (ok) {
        note_progress(100, "Rebooting");
        // Let the response drain before the reset drops the socket.
        delay(500);
        ESP.restart();
    } else {
        updating = false;
        note_progress(-1, Update.errorString());
    }
}

static void handle_update_upload() {
    if (!ota_server->authenticate(OTA_HTTP_USER, ota_password)) return;

    HTTPUpload& upload = ota_server->upload();
    switch (upload.status) {
        case UPLOAD_FILE_START:
            updating = true;
            progress_percent = 0;
            Serial.printf("[OTA] Web update start: %s\n", upload.filename.c_str());
            note_progress(0, "Web update");
            // UPDATE_SIZE_UNKNOWN: a multipart body carries no length, so the
            // Update library sizes against the free OTA partition instead.
            if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
                Update.printError(Serial);
                updating = false;
                note_progress(-1, Update.errorString());
            }
            break;

        case UPLOAD_FILE_WRITE:
            if (!updating) break;
            if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
                Update.printError(Serial);
                Update.abort();
                updating = false;
                note_progress(-1, Update.errorString());
                break;
            }
            // No Content-Length to divide by, so report bytes-so-far against
            // the partition the Update library reserved.
            if (Update.size() > 0) {
                progress_percent = (int)((Update.progress() * 100) / Update.size());
                note_progress(progress_percent, "Web update");
            }
            break;

        case UPLOAD_FILE_END:
            if (!updating) break;
            if (Update.end(true /* evenIfRemaining */)) {
                progress_percent = 100;
                Serial.printf("[OTA] Web update complete (%u bytes)\n",
                              (unsigned)upload.totalSize);
            } else {
                Update.printError(Serial);
                updating = false;
                note_progress(-1, Update.errorString());
            }
            break;

        case UPLOAD_FILE_ABORTED:
            Update.abort();
            updating = false;
            note_progress(-1, "Upload aborted");
            break;

        default:
            break;
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
void ota_manager_init(ota_progress_cb_t cb) {
    progress_cb = cb;
    ensure_password();
}

bool ota_manager_start() {
    if (running) return true;
    if (WiFi.status() != WL_CONNECTED) return false;

    ArduinoOTA.setHostname(MDNS_HOSTNAME);
    ArduinoOTA.setPassword(ota_password);
    ArduinoOTA.onStart([]() {
        updating = true;
        progress_percent = 0;
        Serial.println("[OTA] ArduinoOTA update start");
        note_progress(0, "OTA update");
    });
    ArduinoOTA.onProgress([](unsigned int done, unsigned int total) {
        if (total == 0) return;
        progress_percent = (int)((done * 100) / total);
        note_progress(progress_percent, "OTA update");
    });
    ArduinoOTA.onEnd([]() {
        progress_percent = 100;
        Serial.println("[OTA] ArduinoOTA update complete; rebooting");
        note_progress(100, "Rebooting");
    });
    ArduinoOTA.onError([](ota_error_t error) {
        updating = false;
        Serial.printf("[OTA] Error %u\n", (unsigned)error);
        note_progress(-1, "OTA failed");
    });
    ArduinoOTA.begin();

    ota_server = new WebServer(80);
    ota_server->on("/", HTTP_GET, handle_update_page);
    ota_server->on("/update", HTTP_GET, handle_update_page);
    ota_server->on("/update", HTTP_POST, handle_update_done, handle_update_upload);
    ota_server->on("/diag", HTTP_GET, handle_diag);
    ota_server->begin();

    running = true;
    Serial.printf("[OTA] Ready: http://%s/update (user %s) and %s.local:3232\n",
                  WiFi.localIP().toString().c_str(), OTA_HTTP_USER, MDNS_HOSTNAME);
    return true;
}

void ota_manager_stop() {
    if (!running) return;
    // Never tear the transport out from under a live flash: a half-written
    // OTA partition is a bricked boot.
    if (updating) return;

    ArduinoOTA.end();
    if (ota_server) {
        ota_server->stop();
        delete ota_server;
        ota_server = NULL;
    }
    running = false;
    Serial.println("[OTA] Stopped");
}

bool ota_manager_is_running() {
    return running;
}

void ota_manager_loop() {
    if (running) {
        ArduinoOTA.handle();
        if (ota_server) ota_server->handleClient();
    }

    int percent = pending_percent;
    if (percent != -2) {
        pending_percent = -2;
        if (progress_cb) progress_cb(percent, pending_detail);
    }
}

bool ota_manager_is_updating() {
    return updating;
}

int ota_manager_progress_percent() {
    return progress_percent;
}

const char* ota_manager_password() {
    return ota_password;
}

void ota_manager_set_password(const char* password) {
    if (!password || strlen(password) == 0) return;
    strlcpy(ota_password, password, sizeof(ota_password));
    if (ota_prefs.begin(NVS_OTA_NS, false)) {
        ota_prefs.putString("pass", ota_password);
        ota_prefs.end();
    }
    if (running && !updating) {
        // Re-arm both listeners so the new credential takes effect now.
        running = false;
        ArduinoOTA.end();
        if (ota_server) {
            ota_server->stop();
            delete ota_server;
            ota_server = NULL;
        }
        ota_manager_start();
    }
}
