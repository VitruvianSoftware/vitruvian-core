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

#include "power_manager.h"
#include <Arduino.h>
#include <esp_sleep.h>
#include "pin_config.h"
#include "buzzer.h"
#include "packet_router.h"
#include "ui.h"

// Hardware voltage divider on Waveshare ESP32-S3-Touch-LCD-1.69:
// R3 = 200k, R7 = 100k -> Ratio = (200 + 100) / 100 = 3.0
static const float VOLTAGE_DIVIDER_RATIO = 3.0f;

// Battery voltage and state
static uint16_t battery_mv = 4000;
static uint8_t battery_percent = 80;
static bool is_charging = false;
static float filtered_mv = 0.0f;

// Button state tracking (SYS_OUT_PIN, active LOW)
static bool last_btn_state = HIGH;
static unsigned long btn_press_start = 0;
static bool long_press_handled = false;
static bool boot_press_ignored = false;
static unsigned long last_sample_time = 0;

// Convert LiPo millivolts to percentage (0 - 100%)
// Standard single-cell 3.7V LiPo / Li-ion discharge profile:
//   >= 4200 mV : 100%
//   4050 - 4200 mV : 85% - 100%
//   3850 - 4050 mV : 60% - 85%
//   3700 - 3850 mV : 35% - 60%
//   3500 - 3700 mV : 10% - 35%
//   3200 - 3500 mV : 0% - 10%
//   <= 3200 mV : 0%
static uint8_t calculate_battery_percent(uint16_t mv) {
    if (mv >= 4200) return 100;
    if (mv <= 3200) return 0;
    if (mv >= 4050) {
        return 85 + (uint8_t)(((uint32_t)(mv - 4050) * 15) / 150);
    } else if (mv >= 3850) {
        return 60 + (uint8_t)(((uint32_t)(mv - 3850) * 25) / 200);
    } else if (mv >= 3700) {
        return 35 + (uint8_t)(((uint32_t)(mv - 3700) * 25) / 150);
    } else if (mv >= 3500) {
        return 10 + (uint8_t)(((uint32_t)(mv - 3500) * 25) / 200);
    } else {
        return (uint8_t)(((uint32_t)(mv - 3200) * 10) / 300);
    }
}

void power_manager_init() {
    // 1. Immediately latch the battery power circuit!
    // Drive BOTH V2.x (GPIO 41) and V1.0 (GPIO 35) HIGH so power is held on any hardware revision.
    pinMode(SYS_EN_PIN, OUTPUT);
    digitalWrite(SYS_EN_PIN, HIGH);
    pinMode(SYS_EN_LEGACY_PIN, OUTPUT);
    digitalWrite(SYS_EN_LEGACY_PIN, HIGH);

    // 2. Configure power button sense (Key2, active LOW) on both revisions
    pinMode(SYS_OUT_PIN, INPUT_PULLUP);
    pinMode(SYS_OUT_LEGACY_PIN, INPUT_PULLUP);

    // 3. Configure battery ADC input
    analogSetPinAttenuation(BAT_ADC_PIN, ADC_11db);

    // Initial battery reading
    uint32_t raw_adc_mv = analogReadMilliVolts(BAT_ADC_PIN);
    filtered_mv = (float)raw_adc_mv * VOLTAGE_DIVIDER_RATIO;
    battery_mv = (uint16_t)filtered_mv;
    battery_percent = calculate_battery_percent(battery_mv);

    // If button is held during boot (which happens when powering on the device from cold battery),
    // mark boot press as already handled so releasing the power button does NOT trigger sleep or shutdown!
    bool initial_btn_raw = (digitalRead(SYS_OUT_PIN) == LOW || digitalRead(SYS_OUT_LEGACY_PIN) == LOW);
    if (initial_btn_raw) {
        last_btn_state = LOW;
        boot_press_ignored = true;
    } else {
        last_btn_state = HIGH;
        boot_press_ignored = false;
    }

    Serial.printf("[POWER] Power latch engaged on GPIO %d & %d. Initial battery: %u mV (%u%%)\n",
                  SYS_EN_PIN, SYS_EN_LEGACY_PIN, battery_mv, battery_percent);
}

void power_manager_power_off() {
    Serial.println("[POWER] Shutting down: unlatching GPIO 41 and GPIO 35");
    buzzer_play_ci_fail();
    delay(400);

    // Turn off display completely
    set_backlight_brightness(0);

    // Drive SYS_EN LOW on both revisions to cut hardware battery power
    digitalWrite(SYS_EN_PIN, LOW);
    digitalWrite(SYS_EN_LEGACY_PIN, LOW);
    delay(500);

    // If still powered (e.g. connected to USB-C 5V VBUS), enter deep sleep
    esp_deep_sleep_start();
}

void power_manager_loop() {
    unsigned long now = millis();

    // -----------------------------------------------------------------------
    // 1. Power Button Handling (Active LOW, dual-revision support)
    // -----------------------------------------------------------------------
    bool btn_raw = (digitalRead(SYS_OUT_PIN) == LOW || digitalRead(SYS_OUT_LEGACY_PIN) == LOW);
    bool btn_state = btn_raw ? LOW : HIGH;

    // Button pressed (transition HIGH -> LOW)
    if (btn_state == LOW && last_btn_state == HIGH) {
        btn_press_start = now;
        long_press_handled = false;
    }
    // Button held LOW
    else if (btn_state == LOW && last_btn_state == LOW) {
        if (!boot_press_ignored && !long_press_handled && (now - btn_press_start >= 2500)) {
            long_press_handled = true;
            Serial.println("[POWER] Power button long-press detected (>2.5s) -> Powering off");
            power_manager_power_off();
        }
    }
    // Button released (transition LOW -> HIGH)
    else if (btn_state == HIGH && last_btn_state == LOW) {
        if (boot_press_ignored) {
            boot_press_ignored = false;
            Serial.println("[POWER] Initial boot power-on button released; normal button handling active");
        } else {
            unsigned long press_duration = now - btn_press_start;
            if (!long_press_handled && press_duration >= 50 && press_duration < 1200) {
                Serial.printf("[POWER] Power button short-click (%lu ms) -> Toggle Display Sleep\n", press_duration);
                ui_toggle_display_sleep();
            }
        }
    }
    last_btn_state = btn_state;

    // -----------------------------------------------------------------------
    // 2. Battery Voltage Sampling & Filtering (1 Hz)
    // -----------------------------------------------------------------------
    if (now - last_sample_time >= 1000) {
        last_sample_time = now;

        uint32_t raw_adc_mv = analogReadMilliVolts(BAT_ADC_PIN);
        float current_bat_mv = (float)raw_adc_mv * VOLTAGE_DIVIDER_RATIO;

        // Exponential moving average to remove transient noise
        if (filtered_mv < 100.0f) {
            filtered_mv = current_bat_mv;
        } else {
            filtered_mv = (0.2f * current_bat_mv) + (0.8f * filtered_mv);
        }

        battery_mv = (uint16_t)filtered_mv;
        battery_percent = calculate_battery_percent(battery_mv);

        // ETA6098 charges to ~4.20V. In USB operation or while charging, voltage is elevated
        is_charging = (battery_mv >= 4230 || packet_router_active_channel() == LINK_CHANNEL_USB);

        ui_update_battery(battery_percent, battery_mv, is_charging);
    }
}

uint16_t power_manager_get_battery_mv() {
    return battery_mv;
}

uint8_t power_manager_get_battery_percent() {
    return battery_percent;
}

bool power_manager_is_charging() {
    return is_charging;
}
