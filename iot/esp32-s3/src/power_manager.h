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

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initializes the hardware power latch (drives SYS_EN_PIN 41 HIGH),
// configures the power button (SYS_OUT_PIN 40), and sets up the battery ADC.
// MUST be called as step 0 in setup() to hold battery power when untethered.
void power_manager_init();

// Periodic service routine, called from the Arduino loop().
// Handles button debounce, short press (sleep/wake), long press (power-off),
// and filtered battery ADC sampling.
void power_manager_loop();

// Battery telemetry getters
uint16_t power_manager_get_battery_mv();
uint8_t power_manager_get_battery_percent();
bool power_manager_is_charging();

// Cleanly cuts power to the board by driving SYS_EN_PIN LOW.
void power_manager_power_off();

#ifdef __cplusplus
}
#endif
