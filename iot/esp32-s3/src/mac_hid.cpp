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

void mac_hid_init() {
    Keyboard.begin();
    ConsumerControl.begin();
    USB.begin();

    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(BUZZER_PIN, LOW);
}

void haptic_click() {
    // Subtle, short 2.5kHz tick
    tone(BUZZER_PIN, 2400, 15);
}

void trigger_mission_control() {
    haptic_click();
    Keyboard.press(KEY_LEFT_CTRL);
    Keyboard.press(KEY_UP_ARROW);
    delay(40);
    Keyboard.releaseAll();
}

void trigger_show_desktop() {
    haptic_click();
    // F11 (Standard macOS Mission Control Show Desktop shortcut)
    Keyboard.press(KEY_F11);
    delay(40);
    Keyboard.releaseAll();
}

void trigger_space_left() {
    haptic_click();
    // Ctrl + Left Arrow (Move left a space)
    Keyboard.press(KEY_LEFT_CTRL);
    Keyboard.press(KEY_LEFT_ARROW);
    delay(40);
    Keyboard.releaseAll();
}

void trigger_space_right() {
    haptic_click();
    // Ctrl + Right Arrow (Move right a space)
    Keyboard.press(KEY_LEFT_CTRL);
    Keyboard.press(KEY_RIGHT_ARROW);
    delay(40);
    Keyboard.releaseAll();
}

void trigger_mute() {
    haptic_click();
    ConsumerControl.press(CONSUMER_CONTROL_MUTE);
    delay(40);
    ConsumerControl.release();
}

void trigger_spotlight() {
    haptic_click();
    // Cmd + Space (Spotlight Search)
    Keyboard.press(KEY_LEFT_GUI);
    Keyboard.press(' ');
    delay(40);
    Keyboard.releaseAll();
}

void trigger_vol_up() {
    haptic_click();
    ConsumerControl.press(CONSUMER_CONTROL_VOLUME_INCREMENT);
    delay(40);
    ConsumerControl.release();
}

void trigger_vol_down() {
    haptic_click();
    ConsumerControl.press(CONSUMER_CONTROL_VOLUME_DECREMENT);
    delay(40);
    ConsumerControl.release();
}
