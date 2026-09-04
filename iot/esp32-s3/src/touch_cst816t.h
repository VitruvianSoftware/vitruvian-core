#pragma once
#include <Arduino.h>

bool touch_init();
bool touch_read(uint16_t *x, uint16_t *y);
uint8_t touch_get_chip_id();
