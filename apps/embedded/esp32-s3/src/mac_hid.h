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
#include <Arduino.h>
#include "USBHIDKeyboard.h"
#include "USBHIDConsumerControl.h"

// Modifier bitmask definitions (Canonical wire protocol & firmware)
#define MOD_NONE  0x00
#define MOD_CTRL  0x01  // Bit 0: Control
#define MOD_SHIFT 0x02  // Bit 1: Shift
#define MOD_ALT   0x04  // Bit 2: Alt / Option
#define MOD_CMD   0x08  // Bit 3: GUI / Command (Apple ⌘)

// Unified HID Execution Engine: routes to USB HID while the cable is mounted,
// falling back to BLE HID when a Mac is connected wirelessly (see ble_hid.h).
void mac_hid_init();
void mac_hid_execute_action(uint8_t mod, uint8_t key, uint16_t cons);
bool mac_hid_usb_ready();
void haptic_click();

// Legacy System Deck Macro Triggers (Tile 0 backward compatibility)
void trigger_mission_control();
void trigger_show_desktop();
void trigger_space_left();
void trigger_space_right();
void trigger_mute();
void trigger_display_sleep();
void trigger_vol_up();
void trigger_vol_down();
