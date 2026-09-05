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

#include "mac_hid.h"
#include "pin_config.h"
#include "USB.h"
#include "USBHIDKeyboard.h"
#include "USBHIDConsumerControl.h"

static USBHIDKeyboard Keyboard;
static USBHIDConsumerControl ConsumerControl;

#define HID_KEY_DWELL_MS 20

void mac_hid_init() {
    Keyboard.begin();
    ConsumerControl.begin();
    USB.begin();

    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(BUZZER_PIN, LOW);
}

void haptic_click() {
    // Subtle, short 2.4kHz tick (15ms duration)
    tone(BUZZER_PIN, 2400, 15);
}

void mac_hid_execute_action(uint8_t mod, uint8_t key, uint16_t cons) {
    // 1. Tactile feedback pulse on every action
    haptic_click();

    // 2. Consumer Multimedia Action
    if (cons != 0) {
        ConsumerControl.press(cons);
        delay(HID_KEY_DWELL_MS);
        ConsumerControl.release();
        return;
    }

    // 3. Keyboard Key Action (with modifier bitmask decoding)
    if (mod != 0 || key != 0) {
        // Defensive reset: Clear any leftover modifier state from prior interruptions
        Keyboard.releaseAll();

        // Decode modifier bitmask and press modifiers
        if (mod & MOD_CTRL)  Keyboard.press(KEY_LEFT_CTRL);
        if (mod & MOD_SHIFT) Keyboard.press(KEY_LEFT_SHIFT);
        if (mod & MOD_ALT)   Keyboard.press(KEY_LEFT_ALT);
        if (mod & MOD_CMD)   Keyboard.press(KEY_LEFT_GUI);

        // Press primary keycode if specified
        if (key != 0) {
            Keyboard.press(key);
        }

        // Dwell time ensures macOS Quartz event tap / WindowServer registers the keydown
        delay(HID_KEY_DWELL_MS);

        // Complete release to avoid stuck keys
        Keyboard.releaseAll();
    }
}

void trigger_mission_control() {
    mac_hid_execute_action(MOD_CTRL, KEY_UP_ARROW, 0);
}

void trigger_show_desktop() {
    mac_hid_execute_action(MOD_NONE, KEY_F11, 0);
}

void trigger_space_left() {
    mac_hid_execute_action(MOD_CTRL, KEY_LEFT_ARROW, 0);
}

void trigger_space_right() {
    mac_hid_execute_action(MOD_CTRL, KEY_RIGHT_ARROW, 0);
}

void trigger_mute() {
    mac_hid_execute_action(MOD_NONE, 0, CONSUMER_CONTROL_MUTE);
}

void trigger_spotlight() {
    mac_hid_execute_action(MOD_CMD, ' ', 0);
}

void trigger_vol_up() {
    mac_hid_execute_action(MOD_NONE, 0, CONSUMER_CONTROL_VOLUME_INCREMENT);
}

void trigger_vol_down() {
    mac_hid_execute_action(MOD_NONE, 0, CONSUMER_CONTROL_VOLUME_DECREMENT);
}
