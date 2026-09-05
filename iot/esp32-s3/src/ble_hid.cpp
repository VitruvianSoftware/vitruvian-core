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

#include "ble_hid.h"
#include "mac_hid.h" // MOD_* modifier bitmask definitions (shared wire protocol)
#include <Arduino.h>
#include <Preferences.h>
#include <NimBLEDevice.h>
#include <NimBLEHIDDevice.h>

static const char* NVS_BLE_NS = "ble_config";
static const char* BLE_DEVICE_NAME = "Vitruvian Companion";

#define BLE_KEY_DWELL_MS 20
#define KEYBOARD_REPORT_ID 1
#define CONSUMER_REPORT_ID 2

static Preferences ble_prefs;
static ble_status_cb_t status_cb = NULL;

static bool radio_enabled = false;
static bool stack_up = false;
static bool connected = false;
static bool pending_disconnect_readvertise = false;
static char paired_mac[18] = "";
static char peer_addr[18] = "";
static unsigned long adv_deadline_ms = 0; // 0 = not in a pairing window
static bool advertising = false;

static BleHidState reported_state = (BleHidState)-1;
static uint32_t reported_seconds = 0;

static NimBLEServer* ble_server = NULL;
static NimBLEHIDDevice* hid_device = NULL;
static NimBLECharacteristic* input_keyboard = NULL;
static NimBLECharacteristic* input_consumer = NULL;

// Keyboard (report 1) + consumer control (report 2) — same key semantics as
// the USB path so DynamicButtonConfig actions are transport-agnostic.
static const uint8_t HID_REPORT_MAP[] = {
    // --- Keyboard ---
    0x05, 0x01,        // Usage Page (Generic Desktop)
    0x09, 0x06,        // Usage (Keyboard)
    0xA1, 0x01,        // Collection (Application)
    0x85, KEYBOARD_REPORT_ID,
    0x05, 0x07,        //   Usage Page (Key Codes)
    0x19, 0xE0,        //   Usage Min (224: Left Ctrl)
    0x29, 0xE7,        //   Usage Max (231: Right GUI)
    0x15, 0x00,        //   Logical Min (0)
    0x25, 0x01,        //   Logical Max (1)
    0x75, 0x01,        //   Report Size (1)
    0x95, 0x08,        //   Report Count (8)
    0x81, 0x02,        //   Input (Data, Var, Abs) — modifier byte
    0x95, 0x01,        //   Report Count (1)
    0x75, 0x08,        //   Report Size (8)
    0x81, 0x01,        //   Input (Const) — reserved byte
    0x95, 0x06,        //   Report Count (6)
    0x75, 0x08,        //   Report Size (8)
    0x15, 0x00,        //   Logical Min (0)
    0x25, 0x65,        //   Logical Max (101)
    0x05, 0x07,        //   Usage Page (Key Codes)
    0x19, 0x00,        //   Usage Min (0)
    0x29, 0x65,        //   Usage Max (101)
    0x81, 0x00,        //   Input (Data, Array) — 6-key rollover
    0xC0,              // End Collection
    // --- Consumer Control ---
    0x05, 0x0C,        // Usage Page (Consumer)
    0x09, 0x01,        // Usage (Consumer Control)
    0xA1, 0x01,        // Collection (Application)
    0x85, CONSUMER_REPORT_ID,
    0x15, 0x00,        //   Logical Min (0)
    0x26, 0xFF, 0x03,  //   Logical Max (0x3FF)
    0x19, 0x00,        //   Usage Min (0)
    0x2A, 0xFF, 0x03,  //   Usage Max (0x3FF)
    0x75, 0x10,        //   Report Size (16)
    0x95, 0x01,        //   Report Count (1)
    0x81, 0x00,        //   Input (Data, Array)
    0xC0               // End Collection
};

// ASCII → HID usage table, mirroring arduino-esp32's USBHIDKeyboard _asciimap
// so `key` bytes route identically over USB and BLE. High bit = needs SHIFT.
#define SHIFT 0x80
static const uint8_t ascii_to_hid[128] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,             // NUL..BEL
    0x2a, 0x2b, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00,             // BS TAB LF ..
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,             // DLE..ETB
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,             // CAN..US
    0x2c, 0x1e|SHIFT, 0x34|SHIFT, 0x20|SHIFT,                   // ' ' ! " #
    0x21|SHIFT, 0x22|SHIFT, 0x24|SHIFT, 0x34,                   // $ % & '
    0x26|SHIFT, 0x27|SHIFT, 0x25|SHIFT, 0x2e|SHIFT,             // ( ) * +
    0x36, 0x2d, 0x37, 0x38,                                     // , - . /
    0x27, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24,             // 0..7
    0x25, 0x26, 0x33|SHIFT, 0x33,                               // 8 9 : ;
    0x36|SHIFT, 0x2e, 0x37|SHIFT, 0x38|SHIFT,                   // < = > ?
    0x1f|SHIFT, 0x04|SHIFT, 0x05|SHIFT, 0x06|SHIFT,             // @ A B C
    0x07|SHIFT, 0x08|SHIFT, 0x09|SHIFT, 0x0a|SHIFT,             // D E F G
    0x0b|SHIFT, 0x0c|SHIFT, 0x0d|SHIFT, 0x0e|SHIFT,             // H I J K
    0x0f|SHIFT, 0x10|SHIFT, 0x11|SHIFT, 0x12|SHIFT,             // L M N O
    0x13|SHIFT, 0x14|SHIFT, 0x15|SHIFT, 0x16|SHIFT,             // P Q R S
    0x17|SHIFT, 0x18|SHIFT, 0x19|SHIFT, 0x1a|SHIFT,             // T U V W
    0x1b|SHIFT, 0x1c|SHIFT, 0x1d|SHIFT, 0x2f,                   // X Y Z [
    0x31, 0x30, 0x23|SHIFT, 0x2d|SHIFT,                         // \ ] ^ _
    0x35, 0x04, 0x05, 0x06,                                     // ` a b c
    0x07, 0x08, 0x09, 0x0a,                                     // d e f g
    0x0b, 0x0c, 0x0d, 0x0e,                                     // h i j k
    0x0f, 0x10, 0x11, 0x12,                                     // l m n o
    0x13, 0x14, 0x15, 0x16,                                     // p q r s
    0x17, 0x18, 0x19, 0x1a,                                     // t u v w
    0x1b, 0x1c, 0x1d, 0x2f|SHIFT,                               // x y z {
    0x31|SHIFT, 0x30|SHIFT, 0x35|SHIFT, 0x00                    // | } ~ DEL
};

// ---------------------------------------------------------------------------
// NVS persistence (namespace "ble_config": enabled, paired_mac)
// ---------------------------------------------------------------------------
static void load_config() {
    if (ble_prefs.begin(NVS_BLE_NS, true /* read-only */)) {
        radio_enabled = ble_prefs.getBool("enabled", false);
        String mac = ble_prefs.getString("paired_mac", "");
        strlcpy(paired_mac, mac.c_str(), sizeof(paired_mac));
        ble_prefs.end();
    }
}

static void save_config() {
    if (ble_prefs.begin(NVS_BLE_NS, false)) {
        ble_prefs.putBool("enabled", radio_enabled);
        ble_prefs.putString("paired_mac", paired_mac);
        ble_prefs.end();
    }
}

// ---------------------------------------------------------------------------
// NimBLE server callbacks. These run on the NimBLE host task, so they only
// flip flags; UI notification happens from ble_hid_loop().
// ---------------------------------------------------------------------------
class CompanionServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* server, ble_gap_conn_desc* desc) override {
        connected = true;
        advertising = false;
        adv_deadline_ms = 0;
        strlcpy(peer_addr, NimBLEAddress(desc->peer_ota_addr).toString().c_str(),
                sizeof(peer_addr));
    }
    void onDisconnect(NimBLEServer* server) override {
        connected = false;
        peer_addr[0] = '\0';
        // Re-advertise from the loop (bonded reconnect path).
        pending_disconnect_readvertise = true;
    }
    void onAuthenticationComplete(ble_gap_conn_desc* desc) override {
        if (desc->sec_state.bonded) {
            strlcpy(paired_mac, NimBLEAddress(desc->peer_ota_addr).toString().c_str(),
                    sizeof(paired_mac));
            save_config();
        }
    }
};

static void start_advertising_internal(bool pairing_window) {
    if (!stack_up || connected) return;
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    if (!adv->isAdvertising()) {
        adv->start(0 /* managed by ble_hid_loop */);
    }
    advertising = true;
    adv_deadline_ms = pairing_window ? millis() + BLE_PAIR_WINDOW_SECONDS * 1000UL : 0;
}

static void stack_start() {
    if (stack_up) return;

    NimBLEDevice::init(BLE_DEVICE_NAME);
    // Just-works bonding with secure connections; the Mac initiates pairing.
    NimBLEDevice::setSecurityAuth(true /* bond */, false /* mitm */, true /* sc */);

    ble_server = NimBLEDevice::createServer();
    ble_server->setCallbacks(new CompanionServerCallbacks());
    ble_server->advertiseOnDisconnect(false);

    hid_device = new NimBLEHIDDevice(ble_server);
    input_keyboard = hid_device->inputReport(KEYBOARD_REPORT_ID);
    input_consumer = hid_device->inputReport(CONSUMER_REPORT_ID);
    hid_device->manufacturer()->setValue("VitruvianSoftware");
    hid_device->pnp(0x02 /* USB SIG */, 0xE502, 0xA111, 0x0210);
    hid_device->hidInfo(0x00, 0x01);
    hid_device->reportMap((uint8_t*)HID_REPORT_MAP, sizeof(HID_REPORT_MAP));
    hid_device->startServices();

    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->setAppearance(0x03C1 /* HID Keyboard */);
    adv->addServiceUUID(hid_device->hidService()->getUUID());
    adv->setScanResponse(true);

    stack_up = true;
    Serial.printf("[BLE] Stack up as '%s'\n", BLE_DEVICE_NAME);

    // A previously bonded Mac reconnects on its own schedule — advertise
    // open-endedly so the companion is always reachable when enabled.
    if (paired_mac[0] != '\0') {
        start_advertising_internal(false);
    }
}

static void stack_stop() {
    if (!stack_up) return;
    NimBLEDevice::deinit(true);
    ble_server = NULL;
    hid_device = NULL;
    input_keyboard = NULL;
    input_consumer = NULL;
    stack_up = false;
    connected = false;
    advertising = false;
    adv_deadline_ms = 0;
    peer_addr[0] = '\0';
    Serial.println("[BLE] Stack down");
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
void ble_hid_init() {
    load_config();
    if (radio_enabled) {
        stack_start();
    }
}

void ble_hid_set_status_callback(ble_status_cb_t cb) {
    status_cb = cb;
    reported_state = (BleHidState)-1;
}

bool ble_hid_is_enabled() {
    return radio_enabled;
}

void ble_hid_set_enabled(bool enabled) {
    if (enabled == radio_enabled) return;
    radio_enabled = enabled;
    save_config();
    if (enabled) {
        stack_start();
    } else {
        stack_stop();
    }
}

void ble_hid_start_advertising() {
    if (!radio_enabled) {
        radio_enabled = true;
        save_config();
        stack_start();
    }
    start_advertising_internal(true /* 60s pairing window */);
    Serial.printf("[BLE] Advertising for %ds\n", BLE_PAIR_WINDOW_SECONDS);
}

void ble_hid_stop_advertising() {
    if (stack_up) {
        NimBLEDevice::getAdvertising()->stop();
    }
    advertising = false;
    adv_deadline_ms = 0;
}

bool ble_hid_is_connected() {
    return connected;
}

bool ble_hid_is_advertising() {
    return advertising;
}

uint32_t ble_hid_advertising_seconds_left() {
    if (!advertising || adv_deadline_ms == 0) return 0;
    unsigned long now = millis();
    if (now >= adv_deadline_ms) return 0;
    return (adv_deadline_ms - now) / 1000;
}

BleHidState ble_hid_get_state() {
    if (!radio_enabled) return BLE_HID_OFF;
    if (connected) return BLE_HID_CONNECTED;
    if (advertising) return BLE_HID_ADVERTISING;
    return BLE_HID_STANDBY;
}

const char* ble_hid_get_host() {
    if (connected && peer_addr[0] != '\0') return peer_addr;
    return paired_mac;
}

const char* ble_hid_state_str() {
    switch (ble_hid_get_state()) {
        case BLE_HID_CONNECTED:   return "connected";
        case BLE_HID_ADVERTISING: return "advertising";
        case BLE_HID_STANDBY:     return "standby";
        case BLE_HID_OFF:
        default:                  return "off";
    }
}

void ble_hid_send(uint8_t mod, uint8_t key, uint16_t cons) {
    if (!connected) return;

    // Consumer multimedia action
    if (cons != 0 && input_consumer) {
        uint8_t report[2] = {(uint8_t)(cons & 0xFF), (uint8_t)(cons >> 8)};
        input_consumer->setValue(report, sizeof(report));
        input_consumer->notify();
        delay(BLE_KEY_DWELL_MS);
        uint8_t release[2] = {0, 0};
        input_consumer->setValue(release, sizeof(release));
        input_consumer->notify();
        return;
    }

    if ((mod == 0 && key == 0) || !input_keyboard) return;

    // Keyboard action: [modifiers, reserved, key1..key6]
    uint8_t report[8] = {0};
    if (mod & MOD_CTRL)  report[0] |= 0x01; // Left Ctrl
    if (mod & MOD_SHIFT) report[0] |= 0x02; // Left Shift
    if (mod & MOD_ALT)   report[0] |= 0x04; // Left Alt/Option
    if (mod & MOD_CMD)   report[0] |= 0x08; // Left GUI/Command

    // Same decode as USBHIDKeyboard::press(): >=136 raw usage, >=128 modifier,
    // else ASCII via the map (high bit = implied SHIFT).
    if (key >= 136) {
        report[2] = key - 136;
    } else if (key >= 128) {
        report[0] |= (1 << (key - 128));
    } else if (key != 0) {
        uint8_t usage = ascii_to_hid[key & 0x7F];
        if (usage & SHIFT) {
            report[0] |= 0x02;
            usage &= 0x7F;
        }
        report[2] = usage;
    }

    input_keyboard->setValue(report, sizeof(report));
    input_keyboard->notify();
    delay(BLE_KEY_DWELL_MS);

    uint8_t release[8] = {0};
    input_keyboard->setValue(release, sizeof(release));
    input_keyboard->notify();
}

void ble_hid_loop() {
    unsigned long now = millis();

    if (pending_disconnect_readvertise) {
        pending_disconnect_readvertise = false;
        if (radio_enabled && stack_up) {
            start_advertising_internal(false);
        }
    }

    // Close an expired pairing window (bonded reconnect adverts have no deadline).
    if (advertising && adv_deadline_ms != 0 && now >= adv_deadline_ms) {
        Serial.println("[BLE] Pairing window expired");
        if (paired_mac[0] != '\0') {
            adv_deadline_ms = 0; // fall back to open-ended reconnect advertising
        } else {
            ble_hid_stop_advertising();
        }
    }

    // Notify on state change, and once per second during the countdown.
    BleHidState state = ble_hid_get_state();
    uint32_t seconds = ble_hid_advertising_seconds_left();
    if (status_cb && (state != reported_state ||
                      (state == BLE_HID_ADVERTISING && seconds != reported_seconds))) {
        reported_state = state;
        reported_seconds = seconds;
        status_cb(state, ble_hid_get_host(), seconds);
    }
}
