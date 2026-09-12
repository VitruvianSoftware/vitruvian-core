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
#include <SensorQMI8658.hpp>
#include <Wire.h>
#include "pin_config.h"

static SensorQMI8658 qmi;
static uint8_t dev_addr = 0;    // 0 while absent/unprobed
static bool present = false;
static uint8_t chip_who = 0;

// Debounce state machine (see qmi8658_get_orientation)
static uint8_t stable_orientation = 0;
static bool candidate_tracking = false;
static uint8_t candidate_orientation = 0;
static unsigned long candidate_since_ms = 0;

// Safe bus ping: tests if an I2C device ACKs its address, releasing the bus with STOP.
static bool ping_addr(uint8_t addr) {
    Wire.beginTransmission(addr);
    return (Wire.endTransmission(true) == 0);
}

bool qmi8658_init() {
    // 1. Safe ping check before running full driver initialization
    //    so non-responsive addresses never hang the I2C bus.
    if (ping_addr(QMI8658_ADDR_PRIMARY)) {
        dev_addr = QMI8658_ADDR_PRIMARY;
    } else if (ping_addr(QMI8658_ADDR_FALLBACK)) {
        dev_addr = QMI8658_ADDR_FALLBACK;
    } else {
        Serial.println("[IMU] QMI8658 not found (0x6B/0x6A) - auto-rotate unavailable");
        present = false;
        return false;
    }

    // 2. Initialize using SensorLib
    if (!qmi.begin(Wire, dev_addr, IIC_SDA, IIC_SCL)) {
        Serial.printf("[IMU] QMI8658 @ 0x%02X begin() failed\n", dev_addr);
        present = false;
        return false;
    }

    chip_who = qmi.whoAmI();
    qmi.configAccelerometer(SensorQMI8658::ACC_RANGE_4G, SensorQMI8658::ACC_ODR_125Hz, SensorQMI8658::LPF_MODE_0);
    qmi.enableAccelerometer();

    present = true;
    Serial.printf("[IMU] QMI8658 detected @ 0x%02X (WHO_AM_I=0x%02X, +-4g, 125Hz, accel on)\n", dev_addr, chip_who);
    return true;
}

bool qmi8658_is_present() {
    return present;
}

uint8_t qmi8658_get_dev_addr() {
    return dev_addr;
}

uint8_t qmi8658_get_who_am_i() {
    return chip_who;
}

bool qmi8658_read_accel(int16_t *ax, int16_t *ay, int16_t *az) {
    if (!present || !ax || !ay || !az) return false;

    int16_t raw[3] = {0};
    if (!qmi.getAccelRaw(raw)) {
        return false;
    }

    *ax = raw[0];
    *ay = raw[1];
    *az = raw[2];
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
//   0  portrait, USB down        (+X reads +1g)
//   1  landscape, USB left (90° CW, +Y reads +1g)
//   2  inverted portrait, USB up (-X reads -1g)
//   3  landscape, USB right (270° CW, -Y reads -1g)
//  -1  hold current orientation  (flat on desk, or ambiguous tilt)
static int classify_sample(int16_t ax, int16_t ay, int16_t az) {
    if (is_flat_sample(ax, ay, az)) return -1;

    int32_t aax = ax < 0 ? -(int32_t)ax : ax;
    int32_t aay = ay < 0 ? -(int32_t)ay : ay;

    if (aax >= QMI8658_ORIENT_TRIGGER_LSB && aax > aay) {
        return ax > 0 ? 0 : 2;
    } else if (aay >= QMI8658_ORIENT_TRIGGER_LSB && aay > aax) {
        return ay > 0 ? 1 : 3;
    }

    return -1;
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
