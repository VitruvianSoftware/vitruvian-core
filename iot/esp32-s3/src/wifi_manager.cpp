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

#include "wifi_manager.h"
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>

// All state transitions and callback dispatch happen in wifi_manager_loop()
// (main-loop context) so the callback may safely touch LVGL. The Arduino WiFi
// event task is never given a handler that reaches into the UI.

static const char* NVS_WIFI_NS = "wifi_config";

#define STA_CONNECT_TIMEOUT_MS 15000UL
#define STA_RETRY_BACKOFF_MS   30000UL
// Base portal window; every HTTP request re-arms it so the user is never cut
// off mid-passphrase. The UI countdown tracks the live remaining time.
#define PORTAL_TIMEOUT_MS      180000UL

static Preferences wifi_prefs;
static wifi_status_cb_t status_cb = NULL;

static bool radio_enabled = false;
static char sta_ssid[WIFI_SSID_MAX_LEN + 1] = "";
static char sta_pass[WIFI_PASS_MAX_LEN + 1] = "";
static char last_ip[16] = "";
static char mac_str[18] = "";
static char ap_name[24] = "";

static WifiMgrState cur_state = WIFI_MGR_OFF;
static WifiMgrState reported_state = (WifiMgrState)-1;
static unsigned long connect_started_ms = 0;
static unsigned long next_retry_ms = 0;
static unsigned long portal_deadline_ms = 0;
static bool portal_creds_saved = false;
static unsigned long portal_shutdown_at_ms = 0;

static WebServer* portal_server = NULL;
static DNSServer* portal_dns = NULL;

// ---------------------------------------------------------------------------
// NVS persistence (namespace "wifi_config": enabled, ssid, pass, ip)
// ---------------------------------------------------------------------------
static void load_config() {
    if (wifi_prefs.begin(NVS_WIFI_NS, true /* read-only */)) {
        radio_enabled = wifi_prefs.getBool("enabled", false);
        String s = wifi_prefs.getString("ssid", "");
        String p = wifi_prefs.getString("pass", "");
        String ip = wifi_prefs.getString("ip", "");
        strlcpy(sta_ssid, s.c_str(), sizeof(sta_ssid));
        strlcpy(sta_pass, p.c_str(), sizeof(sta_pass));
        strlcpy(last_ip, ip.c_str(), sizeof(last_ip));
        wifi_prefs.end();
    }
}

static void save_enabled() {
    if (wifi_prefs.begin(NVS_WIFI_NS, false)) {
        wifi_prefs.putBool("enabled", radio_enabled);
        wifi_prefs.end();
    }
}

static void save_credentials() {
    if (wifi_prefs.begin(NVS_WIFI_NS, false)) {
        wifi_prefs.putBool("enabled", radio_enabled);
        wifi_prefs.putString("ssid", sta_ssid);
        wifi_prefs.putString("pass", sta_pass);
        wifi_prefs.end();
    }
}

static void save_last_ip() {
    if (wifi_prefs.begin(NVS_WIFI_NS, false)) {
        wifi_prefs.putString("ip", last_ip);
        wifi_prefs.end();
    }
}

// ---------------------------------------------------------------------------
// Station connection lifecycle
// ---------------------------------------------------------------------------
static void begin_station_connect() {
    if (!radio_enabled || sta_ssid[0] == '\0') return;
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(sta_ssid, sta_pass[0] != '\0' ? sta_pass : NULL);
    connect_started_ms = millis();
    cur_state = WIFI_MGR_CONNECTING;
    Serial.printf("[WIFI] Connecting to '%s'...\n", sta_ssid);
}

static void radio_off() {
    WiFi.disconnect(true /* wifioff */);
    WiFi.mode(WIFI_OFF);
}

// ---------------------------------------------------------------------------
// SoftAP provisioning portal
// ---------------------------------------------------------------------------
static const char PORTAL_HTML[] PROGMEM = R"HTML(<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vitruvian Setup</title>
<style>
body{font-family:-apple-system,Helvetica,Arial,sans-serif;background:#000;color:#fff;
margin:0;padding:24px;max-width:420px;margin:0 auto}
h1{font-size:20px;margin:16px 0 4px}
p.sub{color:#8e8e93;font-size:13px;margin:0 0 20px}
.card{background:#1c1c1e;border:1px solid #2c2c2e;border-radius:12px;padding:16px;margin-bottom:14px}
label{display:block;color:#8e8e93;font-size:12px;margin:10px 0 4px}
select,input{width:100%;box-sizing:border-box;background:#2c2c2e;color:#fff;border:0;
border-radius:8px;padding:12px;font-size:15px}
button{width:100%;background:#0a84ff;color:#fff;border:0;border-radius:8px;
padding:14px;font-size:15px;font-weight:600;margin-top:16px}
button:active{opacity:.7}
#msg{color:#30d158;font-size:13px;margin-top:12px;text-align:center}
a.rescan{color:#0a84ff;font-size:12px;text-decoration:none}
</style></head><body>
<h1>Vitruvian Companion</h1>
<p class="sub">Wi-Fi Setup Portal &mdash; select your network and enter its passphrase.</p>
<div class="card">
<label>Network <a class="rescan" href="#" onclick="scan();return false">(rescan)</a></label>
<select id="ssid"><option>Scanning...</option></select>
<label>Or enter SSID manually</label>
<input id="ssid_manual" placeholder="Hidden network name">
<label>Passphrase</label>
<input id="pass" type="password" placeholder="WPA2 passphrase (blank if open)">
<button onclick="save()">Save &amp; Connect</button>
<div id="msg"></div>
</div>
<script>
function scan(){fetch('/scan').then(r=>r.json()).then(l=>{
var s=document.getElementById('ssid');s.innerHTML='';
l.forEach(n=>{var o=document.createElement('option');
o.value=n.ssid;o.textContent=n.ssid+' ('+n.rssi+' dBm)'+(n.open?' [open]':'');
s.appendChild(o);});
if(!l.length){s.innerHTML='<option value="">No networks found</option>';}
}).catch(()=>{});}
function save(){
var ssid=document.getElementById('ssid_manual').value||document.getElementById('ssid').value;
var pass=document.getElementById('pass').value;
if(!ssid){document.getElementById('msg').textContent='Pick a network first.';return;}
var b='ssid='+encodeURIComponent(ssid)+'&pass='+encodeURIComponent(pass);
fetch('/save',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:b})
.then(r=>r.text()).then(t=>{document.getElementById('msg').textContent=t;});}
scan();
</script></body></html>)HTML";

static void portal_touch_deadline() {
    portal_deadline_ms = millis() + PORTAL_TIMEOUT_MS;
}

static void portal_handle_root() {
    portal_touch_deadline();
    portal_server->send_P(200, "text/html", PORTAL_HTML);
}

static void portal_handle_scan() {
    portal_touch_deadline();
    // Synchronous scan; the portal is a dedicated mode so blocking ~2s is fine.
    int n = WiFi.scanNetworks();
    String json = "[";
    for (int i = 0; i < n && i < 20; i++) {
        if (i > 0) json += ",";
        String ssid = WiFi.SSID(i);
        ssid.replace("\\", "\\\\");
        ssid.replace("\"", "\\\"");
        json += "{\"ssid\":\"" + ssid + "\",\"rssi\":" + String(WiFi.RSSI(i)) +
                ",\"open\":" + (WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "true" : "false") + "}";
    }
    json += "]";
    WiFi.scanDelete();
    portal_server->send(200, "application/json", json);
}

static void portal_handle_save() {
    portal_touch_deadline();
    String ssid = portal_server->arg("ssid");
    String pass = portal_server->arg("pass");
    if (ssid.length() == 0 || ssid.length() > WIFI_SSID_MAX_LEN ||
        pass.length() > WIFI_PASS_MAX_LEN - 1) {
        portal_server->send(400, "text/plain", "Invalid SSID or passphrase length.");
        return;
    }
    strlcpy(sta_ssid, ssid.c_str(), sizeof(sta_ssid));
    strlcpy(sta_pass, pass.c_str(), sizeof(sta_pass));
    radio_enabled = true;
    save_credentials();
    portal_creds_saved = true;
    // Let the HTTP response flush before tearing the AP down.
    portal_shutdown_at_ms = millis() + 1500;
    portal_server->send(200, "text/plain",
                        "Saved. The companion is now joining '" + ssid + "' - you can close this page.");
    Serial.printf("[WIFI] Portal saved credentials for '%s'\n", sta_ssid);
}

static void portal_handle_not_found() {
    // Captive-portal redirect: any unknown host/path lands on the setup page.
    portal_touch_deadline();
    portal_server->sendHeader("Location", "http://192.168.4.1/", true);
    portal_server->send(302, "text/plain", "");
}

void wifi_manager_start_portal() {
    if (cur_state == WIFI_MGR_PORTAL) {
        portal_touch_deadline();
        return;
    }

    uint8_t mac[6];
    WiFi.macAddress(mac);
    snprintf(ap_name, sizeof(ap_name), "Vitruvian-Setup-%02X%02X", mac[4], mac[5]);

    // AP+STA so /scan can enumerate nearby networks while the AP is serving.
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP(ap_name);

    portal_server = new WebServer(80);
    portal_dns = new DNSServer();
    portal_dns->start(53, "*", WiFi.softAPIP());
    portal_server->on("/", portal_handle_root);
    portal_server->on("/scan", portal_handle_scan);
    portal_server->on("/save", HTTP_POST, portal_handle_save);
    portal_server->onNotFound(portal_handle_not_found);
    portal_server->begin();

    portal_creds_saved = false;
    portal_shutdown_at_ms = 0;
    portal_touch_deadline();
    cur_state = WIFI_MGR_PORTAL;
    Serial.printf("[WIFI] Portal up: AP '%s' @ %s\n", ap_name, WiFi.softAPIP().toString().c_str());
}

void wifi_manager_stop_portal() {
    if (portal_server) {
        portal_server->stop();
        delete portal_server;
        portal_server = NULL;
    }
    if (portal_dns) {
        portal_dns->stop();
        delete portal_dns;
        portal_dns = NULL;
    }
    WiFi.softAPdisconnect(true);

    if (radio_enabled && sta_ssid[0] != '\0') {
        begin_station_connect();
    } else if (radio_enabled) {
        WiFi.mode(WIFI_STA);
        cur_state = WIFI_MGR_IDLE;
    } else {
        radio_off();
        cur_state = WIFI_MGR_OFF;
    }
    Serial.println("[WIFI] Portal stopped");
}

uint32_t wifi_manager_portal_seconds_left() {
    if (cur_state != WIFI_MGR_PORTAL) return 0;
    unsigned long now = millis();
    if (now >= portal_deadline_ms) return 0;
    return (portal_deadline_ms - now) / 1000;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
void wifi_manager_init() {
    load_config();

    // Formatting the MAC needs the netif; a brief STA bring-up is harmless.
    WiFi.mode(WIFI_STA);
    strlcpy(mac_str, WiFi.macAddress().c_str(), sizeof(mac_str));

    if (radio_enabled && sta_ssid[0] != '\0') {
        begin_station_connect();
    } else if (radio_enabled) {
        cur_state = WIFI_MGR_IDLE;
    } else {
        radio_off();
        cur_state = WIFI_MGR_OFF;
    }
}

void wifi_manager_set_status_callback(wifi_status_cb_t cb) {
    status_cb = cb;
    reported_state = (WifiMgrState)-1; // force a refresh on next loop
}

bool wifi_manager_is_enabled() {
    return radio_enabled;
}

void wifi_manager_set_enabled(bool enabled) {
    if (enabled == radio_enabled && cur_state != WIFI_MGR_PORTAL) return;
    radio_enabled = enabled;
    save_enabled();

    if (cur_state == WIFI_MGR_PORTAL) {
        wifi_manager_stop_portal();
        return;
    }
    if (enabled) {
        if (sta_ssid[0] != '\0') {
            begin_station_connect();
        } else {
            WiFi.mode(WIFI_STA);
            cur_state = WIFI_MGR_IDLE;
        }
    } else {
        radio_off();
        cur_state = WIFI_MGR_OFF;
    }
}

bool wifi_manager_set_credentials(const char* ssid, const char* pass) {
    if (!ssid || strlen(ssid) == 0 || strlen(ssid) > WIFI_SSID_MAX_LEN) return false;
    if (pass && strlen(pass) > WIFI_PASS_MAX_LEN - 1) return false;

    strlcpy(sta_ssid, ssid, sizeof(sta_ssid));
    strlcpy(sta_pass, pass ? pass : "", sizeof(sta_pass));
    radio_enabled = true;
    save_credentials();

    if (cur_state == WIFI_MGR_PORTAL) {
        wifi_manager_stop_portal(); // falls through into a station connect
    } else {
        begin_station_connect();
    }
    return true;
}

bool wifi_manager_has_credentials() {
    return sta_ssid[0] != '\0';
}

WifiMgrState wifi_manager_get_state() {
    return cur_state;
}

const char* wifi_manager_get_ip() {
    return (cur_state == WIFI_MGR_CONNECTED) ? last_ip : "";
}

const char* wifi_manager_get_ssid() {
    return sta_ssid;
}

const char* wifi_manager_get_ap_name() {
    return ap_name;
}

const char* wifi_manager_get_mac() {
    return mac_str;
}

const char* wifi_manager_state_str() {
    switch (cur_state) {
        case WIFI_MGR_CONNECTED:  return "connected";
        case WIFI_MGR_CONNECTING: return "connecting";
        case WIFI_MGR_PORTAL:     return "portal";
        case WIFI_MGR_IDLE:       return "offline";
        case WIFI_MGR_OFF:
        default:                  return "off";
    }
}

void wifi_manager_loop() {
    unsigned long now = millis();

    switch (cur_state) {
        case WIFI_MGR_PORTAL:
            if (portal_dns) portal_dns->processNextRequest();
            if (portal_server) portal_server->handleClient();
            if (portal_creds_saved && portal_shutdown_at_ms && now >= portal_shutdown_at_ms) {
                wifi_manager_stop_portal();
            } else if (!portal_creds_saved && now >= portal_deadline_ms) {
                Serial.println("[WIFI] Portal timed out");
                wifi_manager_stop_portal();
            }
            break;

        case WIFI_MGR_CONNECTING:
            if (WiFi.status() == WL_CONNECTED) {
                strlcpy(last_ip, WiFi.localIP().toString().c_str(), sizeof(last_ip));
                save_last_ip();
                cur_state = WIFI_MGR_CONNECTED;
                Serial.printf("[WIFI] Connected: %s (%s)\n", last_ip, sta_ssid);
            } else if (now - connect_started_ms > STA_CONNECT_TIMEOUT_MS) {
                Serial.printf("[WIFI] Connect to '%s' timed out; retrying in %lus\n",
                              sta_ssid, STA_RETRY_BACKOFF_MS / 1000);
                WiFi.disconnect();
                next_retry_ms = now + STA_RETRY_BACKOFF_MS;
                cur_state = WIFI_MGR_IDLE;
            }
            break;

        case WIFI_MGR_CONNECTED:
            if (WiFi.status() != WL_CONNECTED) {
                Serial.println("[WIFI] Link lost; auto-reconnecting");
                // setAutoReconnect keeps trying underneath; reflect it in state.
                connect_started_ms = now;
                cur_state = WIFI_MGR_CONNECTING;
            }
            break;

        case WIFI_MGR_IDLE:
            if (radio_enabled && sta_ssid[0] != '\0' && next_retry_ms && now >= next_retry_ms) {
                next_retry_ms = 0;
                begin_station_connect();
            }
            break;

        case WIFI_MGR_OFF:
        default:
            break;
    }

    // Single, main-loop-context notification point for the UI + telemetry.
    if (cur_state != reported_state && status_cb) {
        reported_state = cur_state;
        const char* detail = "";
        if (cur_state == WIFI_MGR_CONNECTED) detail = last_ip;
        else if (cur_state == WIFI_MGR_PORTAL) detail = ap_name;
        status_cb(cur_state, detail, sta_ssid);
    }
}
