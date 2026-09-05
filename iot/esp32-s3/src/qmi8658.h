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

// QMI8658 6-axis IMU on the shared touch I2C bus (SDA=11, SCL=10).
// Only the accelerometer is used, as the input to the portrait/inverted
// auto-rotate classifier. qmi8658_init() must run AFTER touch_init(), which
// owns Wire.begin() for the shared bus.

// Probe order: primary address first, then the SA0-strapped fallback.
#define QMI8658_ADDR_PRIMARY   0x6B
#define QMI8658_ADDR_FALLBACK  0x6A
#define QMI8658_WHO_AM_I_VALUE 0x05

// +-4g full scale -> 1g ~ 8192 LSB. All thresholds below are in raw LSB.
#define QMI8658_LSB_PER_G          8192
// Flat-table suppression: |Az| beyond 0.8g with the in-plane axes quiet means
// the device is lying on the desk, where Ax/Ay are all noise -- hold the
// current orientation instead of chasing it.
#define QMI8658_FLAT_AZ_LSB        6553  // 0.8g
#define QMI8658_FLAT_XY_LSB        2867  // 0.35g in-plane deadband while flat
// A candidate orientation only counts when gravity clearly projects onto the
// panel's long axis (X axis on this board, where +X points towards the USB connector).
#define QMI8658_ORIENT_TRIGGER_LSB 4096  // 0.5g
// Candidate must persist this long before the stable orientation flips.
#define QMI8658_DEBOUNCE_MS        300

// Probe (0x6B then 0x6A, WHO_AM_I == 0x05) and configure: CTRL1 auto-increment,
// CTRL2 +-4g @ 50Hz, CTRL7 accelerometer enable. Returns false when no IMU
// answers; every other call then degrades to a safe no-op.
bool qmi8658_init();
bool qmi8658_is_present();

// One burst read of AX/AY/AZ (registers 0x35..0x3A, LSB first). Raw signed
// 16-bit counts at +-4g. False on I2C failure (outputs untouched).
bool qmi8658_read_accel(int16_t *ax, int16_t *ay, int16_t *az);

// Debounced screen orientation: 0 = portrait (USB down), 2 = inverted portrait
// (USB up). Call periodically (~100ms); each call feeds one sample into the
// flat-suppression + 300ms debounce state machine and returns the stable
// orientation.
uint8_t qmi8658_get_orientation();

// Fresh sample: true when the device is lying flat on the desk (|Az| > 0.8g
// with Ax/Ay inside the deadband).
bool qmi8658_is_flat();

// Diagnostics
uint8_t qmi8658_get_dev_addr();
uint8_t qmi8658_get_who_am_i();
