#pragma once
#include <lvgl.h>

void ui_init();
void ui_update_stats(int cpu, int ram, const char* time_str, bool linked);
void set_backlight_brightness(uint8_t percent);
uint8_t get_backlight_brightness();
