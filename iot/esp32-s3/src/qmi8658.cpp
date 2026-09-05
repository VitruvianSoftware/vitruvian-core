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

#include "qmi8658.h"
#include <Wire.h>

// Register map (QMI8658 datasheet rev A)
#define REG_WHO_AM_I 0x00  // reads 0x05
#define REG_CTRL1    0x02  // 0x60: address auto-increment for burst reads
#define REG_CTRL2    0x03  // 0x10: accelerometer +-4g full scale, 50Hz ODR
#define REG_CTRL7    0x08  // 0x01: aEN=1, accelerometer enabled
#define REG_AX_L     0x35  // AX_L AX_H AY_L AY_H AZ_L AZ_H, int16 LE

#define CTRL1_AUTO_INC 0x60
#define CTRL2_4G_50HZ  0x10
#define CTRL7_ACC_EN   0x01

static uint8_t dev_addr = 0;    // 0 while absent/unprobed
static bool present = false;

// Debounce state machine (see qmi8658_get_orientation)
static uint8_t stable_orientation = 0;
static bool candidate_tracking = false;
static uint8_t candidate_orientation = 0;
static unsigned long candidate_since_ms = 0;

static uint8_t i2c_write_reg(uint8_t addr, uint8_t reg, uint8_t val) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    Wire.write(val);
    return Wire.endTransmission(true);
}

static uint8_t i2c_read_regs(uint8_t addr, uint8_t reg, uint8_t *data, size_t len) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    if (Wire.endTransmission(true) != 0) return 1;
    if (Wire.requestFrom(addr, (uint8_t)len, (uint8_t)true) != len) return 2;
    for (size_t i = 0; i < len; i++) {
        data[i] = Wire.read();
    }
    return 0;
}

static bool probe_addr(uint8_t addr) {
    uint8_t who = 0;
    if (i2c_read_regs(addr, REG_WHO_AM_I, &who, 1) != 0) return false;
    return who == QMI8658_WHO_AM_I_VALUE;
}

bool qmi8658_init() {
    // touch_init() has already brought the shared bus up; just probe.
    if (probe_addr(QMI8658_ADDR_PRIMARY)) {
        dev_addr = QMI8658_ADDR_PRIMARY;
    } else if (probe_addr(QMI8658_ADDR_FALLBACK)) {
        dev_addr = QMI8658_ADDR_FALLBACK;
    } else {
        Serial.println("[IMU] QMI8658 not found (0x6B/0x6A) - auto-rotate unavailable");
        present = false;
        return false;
    }

    uint8_t err = 0;
    err |= i2c_write_reg(dev_addr, REG_CTRL1, CTRL1_AUTO_INC);
    err |= i2c_write_reg(dev_addr, REG_CTRL2, CTRL2_4G_50HZ);
    err |= i2c_write_reg(dev_addr, REG_CTRL7, CTRL7_ACC_EN);
    if (err != 0) {
        Serial.printf("[IMU] QMI8658 @ 0x%02X config write failed\n", dev_addr);
        present = false;
        return false;
    }

    present = true;
    Serial.printf("[IMU] QMI8658 detected @ 0x%02X (+-4g, 50Hz, accel on)\n", dev_addr);
    return true;
}

bool qmi8658_is_present() {
    return present;
}

bool qmi8658_read_accel(int16_t *ax, int16_t *ay, int16_t *az) {
    if (!present || !ax || !ay || !az) return false;

    uint8_t raw[6] = {0};
    if (i2c_read_regs(dev_addr, REG_AX_L, raw, 6) != 0) return false;

    *ax = (int16_t)((uint16_t)raw[0] | ((uint16_t)raw[1] << 8));
    *ay = (int16_t)((uint16_t)raw[2] | ((uint16_t)raw[3] << 8));
    *az = (int16_t)((uint16_t)raw[4] | ((uint16_t)raw[5] << 8));
    return true;
}

static bool is_flat_sample(int16_t ax, int16_t ay, int16_t az) {
    int32_t aax = ax < 0 ? -(int32_t)ax : ax;
    int32_t aay = ay < 0 ? -(int32_t)ay : ay;
    int32_t aaz = az < 0 ? -(int32_t)az : az;
    return aaz > QMI8658_FLAT_AZ_LSB &&
           aax < QMI8658_FLAT_XY_LSB &&
           aay < QMI8658_FLAT_XY_LSB;
}

// Classify one accelerometer sample:
//   0  portrait, USB down       (+Y reads +1g: chip +Y points at the top edge)
//   2  inverted portrait, USB up
//  -1  hold current orientation (flat on desk, or gravity not clearly on Y)
static int classify_sample(int16_t ax, int16_t ay, int16_t az) {
    if (is_flat_sample(ax, ay, az)) return -1;

    int32_t aax = ax < 0 ? -(int32_t)ax : ax;
    int32_t aay = ay < 0 ? -(int32_t)ay : ay;
    // Y must both clear the trigger threshold and dominate X, so a sideways
    // (landscape-ish) tilt never flips the portrait UI.
    if (aay < QMI8658_ORIENT_TRIGGER_LSB || aay <= aax) return -1;

    return ay > 0 ? 0 : 2;
}

uint8_t qmi8658_get_orientation() {
    int16_t ax = 0, ay = 0, az = 0;
    if (!qmi8658_read_accel(&ax, &ay, &az)) {
        return stable_orientation;
    }

    int candidate = classify_sample(ax, ay, az);
    if (candidate < 0 || (uint8_t)candidate == stable_orientation) {
        // Flat/indeterminate samples and confirmations of the current state
        // both restart the debounce from scratch.
        candidate_tracking = false;
        return stable_orientation;
    }

    unsigned long now = millis();
    if (!candidate_tracking || candidate_orientation != (uint8_t)candidate) {
        candidate_tracking = true;
        candidate_orientation = (uint8_t)candidate;
        candidate_since_ms = now;
        return stable_orientation;
    }

    if (now - candidate_since_ms >= QMI8658_DEBOUNCE_MS) {
        stable_orientation = candidate_orientation;
        candidate_tracking = false;
    }
    return stable_orientation;
}

bool qmi8658_is_flat() {
    int16_t ax = 0, ay = 0, az = 0;
    if (!qmi8658_read_accel(&ax, &ay, &az)) return false;
    return is_flat_sample(ax, ay, az);
}
