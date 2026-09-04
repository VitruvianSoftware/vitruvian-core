#include "ui.h"
#include "mac_hid.h"
#include "pin_config.h"
#include <Arduino.h>

static uint8_t current_brightness = 80;
static const int BL_PWM_CH = 7;
static const int BL_PWM_FREQ = 5000;
static const int BL_PWM_RES = 8;

void set_backlight_brightness(uint8_t percent) {
    if (percent > 100) percent = 100;
    if (percent < 5) percent = 5;
    current_brightness = percent;
    uint32_t duty = (255 * percent) / 100;
    ledcWrite(BL_PWM_CH, duty);
}

uint8_t get_backlight_brightness() {
    return current_brightness;
}

// UI Elements that get updated dynamically
static lv_obj_t *label_time = NULL;
static lv_obj_t *label_link = NULL;
static lv_obj_t *bar_cpu = NULL;
static lv_obj_t *label_cpu = NULL;
static lv_obj_t *bar_ram = NULL;
static lv_obj_t *label_ram = NULL;
static lv_obj_t *label_brightness = NULL;

static void btn_action_cb(lv_event_t * e) {
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_CLICKED) {
        int id = (int)(intptr_t)lv_event_get_user_data(e);
        switch (id) {
            case 1: trigger_mission_control(); break;
            case 2: trigger_show_desktop(); break;
            case 3: trigger_space_left(); break;
            case 4: trigger_space_right(); break;
            case 5: trigger_mute(); break;
            case 6: trigger_spotlight(); break;
        }
    }
}

static void slider_brightness_cb(lv_event_t * e) {
    lv_obj_t * slider = lv_event_get_target(e);
    int val = lv_slider_get_value(slider);
    set_backlight_brightness((uint8_t)val);
    if (label_brightness) {
        lv_label_set_text_fmt(label_brightness, "Brightness: %d%%", val);
    }
}

void ui_init() {
    // 1. Backlight PWM Setup
    ledcSetup(BL_PWM_CH, BL_PWM_FREQ, BL_PWM_RES);
    ledcAttachPin(LCD_BL, BL_PWM_CH);
    set_backlight_brightness(current_brightness);

    // 2. Base Dark Style
    lv_obj_t *scr = lv_scr_act();
    lv_obj_set_style_bg_color(scr, lv_color_hex(0x000000), 0);

    // 3. TileView Root (240x280)
    lv_obj_t *tv = lv_tileview_create(scr);
    lv_obj_set_size(tv, 240, 280);
    lv_obj_set_style_bg_color(tv, lv_color_hex(0x000000), 0);
    lv_obj_set_scrollbar_mode(tv, LV_SCROLLBAR_MODE_OFF);

    // Tile 0: Mac Controls & Status (Swipe right allowed)
    lv_obj_t *t0 = lv_tileview_add_tile(tv, 0, 0, LV_DIR_RIGHT);
    lv_obj_clear_flag(t0, LV_OBJ_FLAG_SCROLLABLE);

    // Tile 1: Settings (Swipe left allowed)
    lv_obj_t *t1 = lv_tileview_add_tile(tv, 1, 0, LV_DIR_LEFT);
    lv_obj_clear_flag(t1, LV_OBJ_FLAG_SCROLLABLE);

    // ==========================================
    // TILE 0: MAC CONTROLS & STATUS
    // ==========================================

    // Header Card (Status & Time & Stats)
    lv_obj_t *header = lv_obj_create(t0);
    lv_obj_set_size(header, 226, 68);
    lv_obj_set_pos(header, 7, 5);
    lv_obj_set_style_bg_color(header, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(header, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(header, 1, 0);
    lv_obj_set_style_radius(header, 10, 0);
    lv_obj_set_style_pad_all(header, 6, 0);
    lv_obj_clear_flag(header, LV_OBJ_FLAG_SCROLLABLE);

    // Time Label
    label_time = lv_label_create(header);
    lv_label_set_text(label_time, "Mac Desk");
    lv_obj_set_style_text_color(label_time, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(label_time, &lv_font_montserrat_14, 0);
    lv_obj_align(label_time, LV_ALIGN_TOP_LEFT, 2, 0);

    // Link Status Label
    label_link = lv_label_create(header);
    lv_label_set_text(label_link, "● Ready");
    lv_obj_set_style_text_color(label_link, lv_color_hex(0x30D158), 0); // iOS Green
    lv_obj_set_style_text_font(label_link, &lv_font_montserrat_12, 0);
    lv_obj_align(label_link, LV_ALIGN_TOP_RIGHT, -2, 0);

    // CPU Bar & Label
    label_cpu = lv_label_create(header);
    lv_label_set_text(label_cpu, "CPU: --%");
    lv_obj_set_style_text_color(label_cpu, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_text_font(label_cpu, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_cpu, 2, 24);

    bar_cpu = lv_bar_create(header);
    lv_obj_set_size(bar_cpu, 100, 8);
    lv_obj_set_pos(bar_cpu, 2, 40);
    lv_bar_set_range(bar_cpu, 0, 100);
    lv_bar_set_value(bar_cpu, 0, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(bar_cpu, lv_color_hex(0x3A3A3C), 0);
    lv_obj_set_style_bg_color(bar_cpu, lv_color_hex(0x0A84FF), LV_PART_INDICATOR);

    // RAM Bar & Label
    label_ram = lv_label_create(header);
    lv_label_set_text(label_ram, "RAM: --%");
    lv_obj_set_style_text_color(label_ram, lv_color_hex(0xBF5AF2), 0);
    lv_obj_set_style_text_font(label_ram, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_ram, 112, 24);

    bar_ram = lv_bar_create(header);
    lv_obj_set_size(bar_ram, 100, 8);
    lv_obj_set_pos(bar_ram, 112, 40);
    lv_bar_set_range(bar_ram, 0, 100);
    lv_bar_set_value(bar_ram, 0, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(bar_ram, lv_color_hex(0x3A3A3C), 0);
    lv_obj_set_style_bg_color(bar_ram, lv_color_hex(0xBF5AF2), LV_PART_INDICATOR);

    // Grid of 6 Shortcuts
    struct BtnConfig {
        const char *title;
        int id;
        int x;
        int y;
        uint32_t color;
    } buttons[] = {
        {"Mission\nControl", 1, 7,   78,  0x0A84FF},
        {"Show\nDesktop",    2, 122, 78,  0x5E5CE6},
        {"Space\nLeft",      3, 7,   136, 0x30D158},
        {"Space\nRight",     4, 122, 136, 0x30D158},
        {"Mute\nAudio",      5, 7,   194, 0xFF453A},
        {"Spotlight\nSearch",6, 122, 194, 0xFF9F0A}
    };

    for (int i = 0; i < 6; i++) {
        lv_obj_t *btn = lv_btn_create(t0);
        lv_obj_set_size(btn, 111, 52);
        lv_obj_set_pos(btn, buttons[i].x, buttons[i].y);
        lv_obj_set_style_bg_color(btn, lv_color_hex(0x1C1C1E), 0);
        lv_obj_set_style_bg_color(btn, lv_color_hex(buttons[i].color), LV_STATE_PRESSED);
        lv_obj_set_style_border_color(btn, lv_color_hex(0x2C2C2E), 0);
        lv_obj_set_style_border_width(btn, 1, 0);
        lv_obj_set_style_radius(btn, 10, 0);
        lv_obj_set_style_shadow_width(btn, 0, 0);

        lv_obj_t *lbl = lv_label_create(btn);
        lv_label_set_text(lbl, buttons[i].title);
        lv_obj_set_style_text_color(lbl, lv_color_hex(0xFFFFFF), 0);
        lv_obj_set_style_text_font(lbl, &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_align(lbl, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_center(lbl);

        lv_obj_add_event_cb(btn, btn_action_cb, LV_EVENT_CLICKED, (void*)(intptr_t)buttons[i].id);
    }

    // Bottom Navigation Hint
    lv_obj_t *hint_nav = lv_label_create(t0);
    lv_label_set_text(hint_nav, "Swipe Left for Settings >");
    lv_obj_set_style_text_color(hint_nav, lv_color_hex(0x636366), 0);
    lv_obj_set_style_text_font(hint_nav, &lv_font_montserrat_10, 0);
    lv_obj_align(hint_nav, LV_ALIGN_BOTTOM_MID, 0, -4);

    // ==========================================
    // TILE 1: SETTINGS
    // ==========================================

    // Title
    lv_obj_t *title_settings = lv_label_create(t1);
    lv_label_set_text(title_settings, "< Settings");
    lv_obj_set_style_text_color(title_settings, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(title_settings, &lv_font_montserrat_16, 0);
    lv_obj_set_pos(title_settings, 12, 10);

    // Brightness Card
    lv_obj_t *card_bright = lv_obj_create(t1);
    lv_obj_set_size(card_bright, 224, 76);
    lv_obj_set_pos(card_bright, 8, 38);
    lv_obj_set_style_bg_color(card_bright, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_bright, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_bright, 1, 0);
    lv_obj_set_style_radius(card_bright, 10, 0);
    lv_obj_set_style_pad_all(card_bright, 8, 0);
    lv_obj_clear_flag(card_bright, LV_OBJ_FLAG_SCROLLABLE);

    label_brightness = lv_label_create(card_bright);
    lv_label_set_text_fmt(label_brightness, "Brightness: %d%%", current_brightness);
    lv_obj_set_style_text_color(label_brightness, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(label_brightness, &lv_font_montserrat_12, 0);
    lv_obj_align(label_brightness, LV_ALIGN_TOP_LEFT, 4, 0);

    lv_obj_t *slider = lv_slider_create(card_bright);
    lv_obj_set_size(slider, 196, 12);
    lv_obj_align(slider, LV_ALIGN_BOTTOM_MID, 0, -6);
    lv_slider_set_range(slider, 10, 100);
    lv_slider_set_value(slider, current_brightness, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0x3A3A3C), 0);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0x0A84FF), LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0xFFFFFF), LV_PART_KNOB);
    lv_obj_add_event_cb(slider, slider_brightness_cb, LV_EVENT_VALUE_CHANGED, NULL);

    // System Info Card
    lv_obj_t *card_info = lv_obj_create(t1);
    lv_obj_set_size(card_info, 224, 134);
    lv_obj_set_pos(card_info, 8, 120);
    lv_obj_set_style_bg_color(card_info, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_info, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_info, 1, 0);
    lv_obj_set_style_radius(card_info, 10, 0);
    lv_obj_set_style_pad_all(card_info, 8, 0);
    lv_obj_clear_flag(card_info, LV_OBJ_FLAG_SCROLLABLE);

    const char *info_text = 
        "Device: Waveshare 1.69\"\n"
        "SoC: ESP32-S3 @ 240MHz\n"
        "Flash: 16MB | PSRAM: 8MB\n"
        "Screen: 240x280 IPS ST7789\n"
        "Touch: CST816T I2C\n"
        "USB: Native CDC + HID";

    lv_obj_t *info_lbl = lv_label_create(card_info);
    lv_label_set_text(info_lbl, info_text);
    lv_obj_set_style_text_color(info_lbl, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(info_lbl, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_line_space(info_lbl, 4, 0);
    lv_obj_align(info_lbl, LV_ALIGN_TOP_LEFT, 4, 2);

    // Settings Bottom Hint
    lv_obj_t *hint_back = lv_label_create(t1);
    lv_label_set_text(hint_back, "< Swipe Right for Controls");
    lv_obj_set_style_text_color(hint_back, lv_color_hex(0x636366), 0);
    lv_obj_set_style_text_font(hint_back, &lv_font_montserrat_10, 0);
    lv_obj_align(hint_back, LV_ALIGN_BOTTOM_MID, 0, -4);
}

void ui_update_stats(int cpu, int ram, const char* time_str, bool linked) {
    if (bar_cpu && cpu >= 0 && cpu <= 100) {
        lv_bar_set_value(bar_cpu, cpu, LV_ANIM_ON);
        if (label_cpu) lv_label_set_text_fmt(label_cpu, "CPU: %d%%", cpu);
    }

    if (bar_ram && ram >= 0 && ram <= 100) {
        lv_bar_set_value(bar_ram, ram, LV_ANIM_ON);
        if (label_ram) lv_label_set_text_fmt(label_ram, "RAM: %d%%", ram);
    }

    if (label_time && time_str != NULL && strlen(time_str) > 0) {
        lv_label_set_text(label_time, time_str);
    }

    if (label_link) {
        if (linked) {
            lv_label_set_text(label_link, "● Linked");
            lv_obj_set_style_text_color(label_link, lv_color_hex(0x30D158), 0);
        } else {
            lv_label_set_text(label_link, "● Standby");
            lv_obj_set_style_text_color(label_link, lv_color_hex(0xFF9F0A), 0);
        }
    }
}
