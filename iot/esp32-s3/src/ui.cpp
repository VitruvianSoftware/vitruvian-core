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

#include "ui.h"
#include "mac_hid.h"
#include "wifi_manager.h"
#include "ble_hid.h"
#include "pin_config.h"
#include <Arduino.h>
#include <Preferences.h>

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

// ---------------------------------------------------------------------------
// Tile 0: System Deck Objects & State
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Tile 1: Smart Deck Objects & State
// ---------------------------------------------------------------------------
static lv_obj_t *header_smart = NULL;
static lv_obj_t *label_smart_app = NULL;
static lv_obj_t *dot_smart_accent = NULL;
static lv_obj_t *bar_smart_accent = NULL;
static lv_obj_t *smart_btn_objs[6] = {NULL};
static lv_obj_t *smart_btn_labels[6] = {NULL};
static DynamicButtonConfig smart_buttons[6];

static void smart_btn_action_cb(lv_event_t * e) {
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_CLICKED) {
        int id = (int)(intptr_t)lv_event_get_user_data(e);
        if (id >= 0 && id < 6) {
            const DynamicButtonConfig &btn = smart_buttons[id];
            if (btn.key != 0 || btn.cons != 0 || btn.mod != 0) {
                mac_hid_execute_action(btn.mod, btn.key, btn.cons);
            }
        }
    }
}

static Preferences prefs;
static const char* NVS_NAMESPACE = "mac_ctrl";

static void slider_brightness_cb(lv_event_t * e) {
    lv_obj_t * slider = lv_event_get_target(e);
    int val = lv_slider_get_value(slider);
    set_backlight_brightness((uint8_t)val);
    if (label_brightness) {
        lv_label_set_text_fmt(label_brightness, "Brightness: %d%%", val);
    }
    if (prefs.begin(NVS_NAMESPACE, false)) {
        prefs.putUChar("brightness", (uint8_t)val);
        prefs.end();
    }
}

// ---------------------------------------------------------------------------
// Tile 2: Agent & CI Deck Objects & State
// ---------------------------------------------------------------------------
static lv_obj_t *label_agent_name = NULL;
static lv_obj_t *badge_agent_container = NULL;
static lv_obj_t *badge_agent_label = NULL;
static lv_obj_t *label_agent_task = NULL;
static lv_obj_t *label_agent_meta = NULL;

static lv_obj_t *label_branch_name = NULL;
static lv_obj_t *badge_ci_container = NULL;
static lv_obj_t *badge_ci_label = NULL;
static lv_obj_t *label_ci_details = NULL;
static lv_obj_t *bar_ci_progress = NULL;

static void agent_ci_btn_action_cb(lv_event_t * e) {
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_CLICKED) {
        int action_id = (int)(intptr_t)lv_event_get_user_data(e);
        haptic_click(); // GPIO 42 buzzer feedback
        if (action_id == 201) {
            Serial.println("{\"cmd\":\"run_checks\",\"action\":\"run_checks\"}");
        } else if (action_id == 202) {
            Serial.println("{\"cmd\":\"open_pr\",\"action\":\"open_pr\"}");
        }
    }
}

// ---------------------------------------------------------------------------
// Milestone 4: Carousel State Globals & Preferences Persistence
// ---------------------------------------------------------------------------
static lv_obj_t *tile_view = NULL;
static lv_obj_t *deck_tiles[DECK_COUNT] = {NULL};
static lv_obj_t *deck_hint_labels[DECK_COUNT] = {NULL};
bool deck_enabled[DECK_COUNT] = {true, true, true, true};

static lv_obj_t *sw_deck_system = NULL;
static lv_obj_t *sw_deck_smart = NULL;
static lv_obj_t *sw_deck_agent_ci = NULL;

// ---------------------------------------------------------------------------
// Milestone 5: Wireless Connectivity Card Objects & State
// ---------------------------------------------------------------------------
static lv_obj_t *sw_wifi = NULL;
static lv_obj_t *label_wifi_status = NULL;
static lv_obj_t *sw_ble = NULL;
static lv_obj_t *label_ble_status = NULL;
static lv_obj_t *label_hw_net = NULL;
static char hw_wifi_mac[18] = "--";
static char hw_last_ip[16] = "--";

// Settings connectivity action IDs (wire protocol: docs/protocol.md)
#define ACTION_WIFI_SYNC   301
#define ACTION_WIFI_PORTAL 302
#define ACTION_BLE_PAIR    303

static unsigned long wifi_sync_pending_until_ms = 0;

static void connectivity_btn_action_cb(lv_event_t * e) {
    if (lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    int action_id = (int)(intptr_t)lv_event_get_user_data(e);
    haptic_click();

    switch (action_id) {
        case ACTION_WIFI_SYNC:
            // Least-friction default: ask the tethered Mac companion to beam
            // its current network credentials over USB CDC.
            wifi_sync_pending_until_ms = millis() + 10000;
            if (!wifi_manager_is_enabled()) {
                wifi_manager_set_enabled(true);
                if (sw_wifi) lv_obj_add_state(sw_wifi, LV_STATE_CHECKED);
            }
            Serial.println("{\"cmd\":\"wifi_sync\"}");
            if (label_wifi_status) {
                lv_label_set_text(label_wifi_status, "Syncing with Mac...");
                lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0xFF9F0A), 0);
            }
            break;
        case ACTION_WIFI_PORTAL:
            if (sw_wifi) lv_obj_add_state(sw_wifi, LV_STATE_CHECKED);
            wifi_manager_start_portal();
            break;
        case ACTION_BLE_PAIR:
            ble_hid_start_advertising();
            if (sw_ble) lv_obj_add_state(sw_ble, LV_STATE_CHECKED);
            break;
        default:
            break;
    }
}

static void sw_wifi_toggle_cb(lv_event_t * e) {
    if (lv_event_get_code(e) != LV_EVENT_VALUE_CHANGED) return;
    bool checked = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    haptic_click();
    wifi_manager_set_enabled(checked);
    Serial.printf("[SETTINGS] Wi-Fi radio %s\n", checked ? "ENABLED" : "DISABLED");
}

static void sw_ble_toggle_cb(lv_event_t * e) {
    if (lv_event_get_code(e) != LV_EVENT_VALUE_CHANGED) return;
    bool checked = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    haptic_click();
    ble_hid_set_enabled(checked);
    Serial.printf("[SETTINGS] Bluetooth radio %s\n", checked ? "ENABLED" : "DISABLED");
}

// Shared factory for the compact accent-bordered buttons on the
// connectivity cards (same visual language as the deck action buttons).
static lv_obj_t* create_conn_button(lv_obj_t *parent, const char *text, uint32_t accent,
                                    int x, int y, int w, int h, int action_id) {
    lv_obj_t *btn = lv_btn_create(parent);
    lv_obj_set_size(btn, w, h);
    lv_obj_set_pos(btn, x, y);
    lv_obj_set_style_bg_color(btn, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_bg_color(btn, lv_color_hex(accent), LV_STATE_PRESSED);
    lv_obj_set_style_border_color(btn, lv_color_hex(accent), 0);
    lv_obj_set_style_border_width(btn, 1, 0);
    lv_obj_set_style_radius(btn, 8, 0);
    lv_obj_set_style_shadow_width(btn, 0, 0);
    lv_obj_add_event_cb(btn, connectivity_btn_action_cb, LV_EVENT_CLICKED,
                        (void*)(intptr_t)action_id);

    lv_obj_t *lbl = lv_label_create(btn);
    lv_label_set_text(lbl, text);
    lv_obj_set_style_text_color(lbl, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(lbl, &lv_font_montserrat_10, 0);
    lv_obj_set_style_text_align(lbl, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(lbl);
    return btn;
}

void ui_load_deck_preferences() {
    if (prefs.begin(NVS_NAMESPACE, true /* read-only */)) {
        deck_enabled[DECK_SYSTEM]   = prefs.getBool("deck_sys", true);
        deck_enabled[DECK_SMART]    = prefs.getBool("deck_smart", true);
        deck_enabled[DECK_AGENT_CI] = prefs.getBool("deck_agent", true);
        deck_enabled[DECK_SETTINGS] = true; // Invariant: Settings Deck is always enabled
        
        uint8_t saved_brightness = prefs.getUChar("brightness", 80);
        set_backlight_brightness(saved_brightness);
        prefs.end();
        
        Serial.printf("[PREFS] Loaded: sys=%d, smart=%d, agent=%d, bright=%d\n",
                      deck_enabled[DECK_SYSTEM], deck_enabled[DECK_SMART],
                      deck_enabled[DECK_AGENT_CI], saved_brightness);
    } else {
        deck_enabled[DECK_SYSTEM]   = true;
        deck_enabled[DECK_SMART]    = true;
        deck_enabled[DECK_AGENT_CI] = true;
        deck_enabled[DECK_SETTINGS] = true;
    }
}

void ui_save_deck_preferences() {
    if (prefs.begin(NVS_NAMESPACE, false /* read-write */)) {
        prefs.putBool("deck_sys", deck_enabled[DECK_SYSTEM]);
        prefs.putBool("deck_smart", deck_enabled[DECK_SMART]);
        prefs.putBool("deck_agent", deck_enabled[DECK_AGENT_CI]);
        prefs.putUChar("brightness", get_backlight_brightness());
        prefs.end();
        Serial.println("[PREFS] Saved deck preferences to NVS");
    }
}

static const char* get_deck_short_name(uint8_t id) {
    switch (id) {
        case DECK_SYSTEM:   return "System";
        case DECK_SMART:    return "Smart";
        case DECK_AGENT_CI: return "Agent & CI";
        case DECK_SETTINGS: return "Settings";
        default:            return "";
    }
}

void ui_update_navigation_hints() {
    uint8_t active_decks[DECK_COUNT];
    int active_count = 0;
    for (int d = 0; d < DECK_COUNT; d++) {
        if (deck_enabled[d]) {
            active_decks[active_count++] = (uint8_t)d;
        }
    }

    for (int k = 0; k < active_count; k++) {
        uint8_t d = active_decks[k];
        lv_obj_t *lbl_hint = deck_hint_labels[d];
        if (!lbl_hint) continue;

        if (active_count == 1) {
            lv_label_set_text(lbl_hint, "No other active decks");
        } else if (k == 0) {
            const char *next_name = get_deck_short_name(active_decks[1]);
            lv_label_set_text_fmt(lbl_hint, "Swipe Left for %s >", next_name);
        } else if (k == active_count - 1) {
            const char *prev_name = get_deck_short_name(active_decks[k - 1]);
            lv_label_set_text_fmt(lbl_hint, "< Swipe Right for %s", prev_name);
        } else {
            const char *prev_name = get_deck_short_name(active_decks[k - 1]);
            const char *next_name = get_deck_short_name(active_decks[k + 1]);
            lv_label_set_text_fmt(lbl_hint, "< %s | %s >", prev_name, next_name);
        }
    }
}

void ui_reindex_carousel() {
    if (!tile_view) return;

    // Invariant: Settings Deck is permanently pinned to enabled
    deck_enabled[DECK_SETTINGS] = true;

    // 1. Collect all active decks in stable order
    uint8_t active_decks[DECK_COUNT];
    int active_count = 0;
    for (int d = 0; d < DECK_COUNT; d++) {
        if (deck_enabled[d]) {
            active_decks[active_count++] = (uint8_t)d;
        }
    }

    // 2. Hide and shelf disabled decks offscreen
    for (int d = 0; d < DECK_COUNT; d++) {
        if (!deck_enabled[d] && deck_tiles[d]) {
            lv_obj_add_flag(deck_tiles[d], LV_OBJ_FLAG_HIDDEN);
            lv_obj_set_pos(deck_tiles[d], -1000, -1000);
            lv_tileview_tile_t *tile = (lv_tileview_tile_t *)deck_tiles[d];
            tile->dir = LV_DIR_NONE;
        }
    }

    // 3. Contiguously position active decks and configure direction flags
    const lv_coord_t deck_width = 240;
    for (int k = 0; k < active_count; k++) {
        uint8_t d = active_decks[k];
        lv_obj_t *tile_obj = deck_tiles[d];
        if (!tile_obj) continue;

        lv_obj_clear_flag(tile_obj, LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_pos(tile_obj, k * deck_width, 0);

        lv_dir_t dir;
        if (active_count == 1) {
            dir = LV_DIR_NONE;
        } else if (k == 0) {
            dir = LV_DIR_RIGHT;
        } else if (k == active_count - 1) {
            dir = LV_DIR_LEFT;
        } else {
            dir = LV_DIR_HOR;
        }

        lv_tileview_tile_t *tile = (lv_tileview_tile_t *)tile_obj;
        tile->dir = dir;
    }

    // 4. Update Navigation Hints
    ui_update_navigation_hints();

    // 5. Zero-jitter Viewport Maintenance
    lv_obj_t *act_tile = lv_tileview_get_tile_act(tile_view);
    bool act_is_visible = false;
    for (int k = 0; k < active_count; k++) {
        if (deck_tiles[active_decks[k]] == act_tile) {
            act_is_visible = true;
            break;
        }
    }

    if (act_is_visible && act_tile) {
        lv_obj_set_tile(tile_view, act_tile, LV_ANIM_OFF);
    } else {
        lv_obj_set_tile(tile_view, deck_tiles[DECK_SETTINGS], LV_ANIM_OFF);
    }

    lv_obj_update_layout(tile_view);
}

void ui_set_deck_enabled(uint8_t deck_id, bool enabled) {
    if (deck_id >= DECK_SETTINGS) return; // Settings Deck is immutable invariant
    deck_enabled[deck_id] = enabled;

    lv_obj_t *sw = NULL;
    if (deck_id == DECK_SYSTEM) sw = sw_deck_system;
    else if (deck_id == DECK_SMART) sw = sw_deck_smart;
    else if (deck_id == DECK_AGENT_CI) sw = sw_deck_agent_ci;

    if (sw) {
        if (enabled) {
            lv_obj_add_state(sw, LV_STATE_CHECKED);
        } else {
            lv_obj_clear_state(sw, LV_STATE_CHECKED);
        }
    }
}

bool ui_is_deck_enabled(uint8_t deck_id) {
    if (deck_id == DECK_SETTINGS) return true;
    if (deck_id < DECK_COUNT) {
        return deck_enabled[deck_id];
    }
    return false;
}

void ui_set_deck_visible(DeckId deck, bool visible) {
    ui_set_deck_enabled((uint8_t)deck, visible);
    ui_reindex_carousel();
}

bool ui_get_deck_visible(DeckId deck) {
    return ui_is_deck_enabled((uint8_t)deck);
}

int ui_get_active_deck_count() {
    int count = 0;
    for (int d = 0; d < DECK_COUNT; d++) {
        if (deck_enabled[d]) count++;
    }
    return count;
}

DeckId ui_get_active_deck_at_col(int col) {
    int cur_col = 0;
    for (int d = 0; d < DECK_COUNT; d++) {
        if (deck_enabled[d]) {
            if (cur_col == col) return (DeckId)d;
            cur_col++;
        }
    }
    return DECK_SETTINGS;
}

DeckVisibilityConfig ui_get_deck_visibility() {
    DeckVisibilityConfig cfg;
    cfg.system_enabled = deck_enabled[DECK_SYSTEM];
    cfg.smart_enabled = deck_enabled[DECK_SMART];
    cfg.agent_ci_enabled = deck_enabled[DECK_AGENT_CI];
    return cfg;
}

void ui_set_deck_visibility(const DeckVisibilityConfig* config) {
    if (!config) return;
    ui_set_deck_enabled(DECK_SYSTEM, config->system_enabled);
    ui_set_deck_enabled(DECK_SMART, config->smart_enabled);
    ui_set_deck_enabled(DECK_AGENT_CI, config->agent_ci_enabled);
    ui_reindex_carousel();
}

static void style_deck_switch(lv_obj_t *sw, uint32_t accent_color) {
    lv_obj_set_size(sw, 40, 20);

    // Track when OFF
    lv_obj_set_style_bg_color(sw, lv_color_hex(0x3A3A3C), LV_PART_MAIN);
    lv_obj_set_style_border_width(sw, 0, LV_PART_MAIN);
    lv_obj_set_style_radius(sw, LV_RADIUS_CIRCLE, LV_PART_MAIN);
    lv_obj_set_style_pad_all(sw, 2, LV_PART_MAIN);

    // Track when ON
    lv_obj_set_style_bg_color(sw, lv_color_hex(accent_color), LV_PART_INDICATOR | LV_STATE_CHECKED);
    lv_obj_set_style_radius(sw, LV_RADIUS_CIRCLE, LV_PART_INDICATOR | LV_STATE_CHECKED);

    // Knob
    lv_obj_set_style_bg_color(sw, lv_color_hex(0xFFFFFF), LV_PART_KNOB);
    lv_obj_set_style_radius(sw, LV_RADIUS_CIRCLE, LV_PART_KNOB);
    lv_obj_set_style_shadow_width(sw, 0, LV_PART_KNOB);
}

static void sw_deck_toggle_cb(lv_event_t * e) {
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_VALUE_CHANGED) {
        lv_obj_t * sw = lv_event_get_target(e);
        uint8_t deck_id = (uint8_t)(intptr_t)lv_event_get_user_data(e);
        bool is_checked = lv_obj_has_state(sw, LV_STATE_CHECKED);

        haptic_click();

        ui_set_deck_enabled(deck_id, is_checked);
        ui_reindex_carousel();
        ui_save_deck_preferences();

        Serial.printf("[SETTINGS] Deck %d (%s) set to %s\n",
                      (int)deck_id, get_deck_short_name(deck_id),
                      is_checked ? "ENABLED" : "DISABLED");
    }
}

static void deck_row_click_cb(lv_event_t * e) {
    lv_obj_t * sw = (lv_obj_t *)lv_event_get_user_data(e);
    if (sw) {
        if (lv_obj_has_state(sw, LV_STATE_CHECKED)) {
            lv_obj_clear_state(sw, LV_STATE_CHECKED);
        } else {
            lv_obj_add_state(sw, LV_STATE_CHECKED);
        }
        lv_event_send(sw, LV_EVENT_VALUE_CHANGED, NULL);
    }
}

void ui_init() {
    // 1. Backlight PWM Setup & Load Preferences
    ui_load_deck_preferences();
    ledcSetup(BL_PWM_CH, BL_PWM_FREQ, BL_PWM_RES);
    ledcAttachPin(LCD_BL, BL_PWM_CH);
    set_backlight_brightness(current_brightness);

    // 2. Base Dark Style
    lv_obj_t *scr = lv_scr_act();
    lv_obj_set_style_bg_color(scr, lv_color_hex(0x000000), 0);

    // 3. TileView Root (240x280)
    tile_view = lv_tileview_create(scr);
    lv_obj_t *tv = tile_view;
    lv_obj_set_size(tv, 240, 280);
    lv_obj_set_style_bg_color(tv, lv_color_hex(0x000000), 0);
    lv_obj_set_scrollbar_mode(tv, LV_SCROLLBAR_MODE_OFF);

    // Tile 0: System Deck (Mac Controls & Status) -> swipe right towards Smart Deck
    lv_obj_t *t0 = lv_tileview_add_tile(tv, 0, 0, LV_DIR_RIGHT);
    lv_obj_clear_flag(t0, LV_OBJ_FLAG_SCROLLABLE);
    deck_tiles[DECK_SYSTEM] = t0;

    // Tile 1: Smart Deck (Dynamic Contextual Shortcuts) -> swipe horizontal (left & right)
    lv_obj_t *t1 = lv_tileview_add_tile(tv, 1, 0, LV_DIR_HOR);
    lv_obj_clear_flag(t1, LV_OBJ_FLAG_SCROLLABLE);
    deck_tiles[DECK_SMART] = t1;

    // Tile 2: Agent & CI Deck (Live Workflow Telemetry) -> swipe horizontal (left & right)
    lv_obj_t *t2 = lv_tileview_add_tile(tv, 2, 0, LV_DIR_HOR);
    lv_obj_clear_flag(t2, LV_OBJ_FLAG_SCROLLABLE);
    deck_tiles[DECK_AGENT_CI] = t2;

    // Tile 3: Settings Deck -> swipe left towards Agent & CI Deck.
    // Vertically scrollable card stack (Milestone 5): horizontal swipes still
    // chain up to the tileview, vertical drags scroll the settings content.
    lv_obj_t *t3 = lv_tileview_add_tile(tv, 3, 0, LV_DIR_LEFT);
    lv_obj_add_flag(t3, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scroll_dir(t3, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(t3, LV_SCROLLBAR_MODE_AUTO);
    deck_tiles[DECK_SETTINGS] = t3;

    // ==========================================
    // TILE 0: MAC CONTROLS & STATUS (SYSTEM DECK)
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
    deck_hint_labels[DECK_SYSTEM] = hint_nav;
    lv_label_set_text(hint_nav, "Swipe Left for Smart >");
    lv_obj_set_style_text_color(hint_nav, lv_color_hex(0x636366), 0);
    lv_obj_set_style_text_font(hint_nav, &lv_font_montserrat_10, 0);
    lv_obj_align(hint_nav, LV_ALIGN_BOTTOM_MID, 0, -4);

    // ==========================================
    // TILE 1: SMART DECK (DYNAMIC SHORTCUTS)
    // ==========================================
    header_smart = lv_obj_create(t1);
    lv_obj_set_size(header_smart, 226, 68);
    lv_obj_set_pos(header_smart, 7, 5);
    lv_obj_set_style_bg_color(header_smart, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(header_smart, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_border_width(header_smart, 1, 0);
    lv_obj_set_style_radius(header_smart, 10, 0);
    lv_obj_set_style_pad_all(header_smart, 6, 0);
    lv_obj_clear_flag(header_smart, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *lbl_cat = lv_label_create(header_smart);
    lv_label_set_text(lbl_cat, "SMART DECK");
    lv_obj_set_style_text_color(lbl_cat, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(lbl_cat, &lv_font_montserrat_10, 0);
    lv_obj_align(lbl_cat, LV_ALIGN_TOP_LEFT, 2, 0);

    dot_smart_accent = lv_obj_create(header_smart);
    lv_obj_set_size(dot_smart_accent, 12, 12);
    lv_obj_set_style_radius(dot_smart_accent, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(dot_smart_accent, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_border_width(dot_smart_accent, 0, 0);
    lv_obj_align(dot_smart_accent, LV_ALIGN_TOP_RIGHT, -2, 0);

    label_smart_app = lv_label_create(header_smart);
    lv_label_set_text(label_smart_app, "Default");
    lv_obj_set_style_text_color(label_smart_app, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(label_smart_app, &lv_font_montserrat_16, 0);
    lv_obj_set_pos(label_smart_app, 2, 14);

    lv_obj_t *lbl_sub = lv_label_create(header_smart);
    lv_label_set_text(lbl_sub, "6 Active Shortcuts");
    lv_obj_set_style_text_color(lbl_sub, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(lbl_sub, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(lbl_sub, 2, 38);

    bar_smart_accent = lv_obj_create(header_smart);
    lv_obj_set_size(bar_smart_accent, 214, 2);
    lv_obj_set_pos(bar_smart_accent, 0, 52);
    lv_obj_set_style_bg_color(bar_smart_accent, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_border_width(bar_smart_accent, 0, 0);
    lv_obj_set_style_radius(bar_smart_accent, 1, 0);

    // Create 6 dynamic buttons on Tile 1
    const int btn_coords[6][2] = {
        {7, 78},   {122, 78},
        {7, 136},  {122, 136},
        {7, 194},  {122, 194}
    };

    for (int i = 0; i < 6; i++) {
        smart_btn_objs[i] = lv_btn_create(t1);
        lv_obj_set_size(smart_btn_objs[i], 111, 52);
        lv_obj_set_pos(smart_btn_objs[i], btn_coords[i][0], btn_coords[i][1]);
        lv_obj_set_style_bg_color(smart_btn_objs[i], lv_color_hex(0x1C1C1E), 0);
        lv_obj_set_style_bg_color(smart_btn_objs[i], lv_color_hex(0x0A84FF), LV_STATE_PRESSED);
        lv_obj_set_style_border_color(smart_btn_objs[i], lv_color_hex(0x0A84FF), 0);
        lv_obj_set_style_border_width(smart_btn_objs[i], 1, 0);
        lv_obj_set_style_radius(smart_btn_objs[i], 10, 0);
        lv_obj_set_style_shadow_width(smart_btn_objs[i], 0, 0);

        smart_btn_labels[i] = lv_label_create(smart_btn_objs[i]);
        lv_label_set_text(smart_btn_labels[i], "-");
        lv_obj_set_style_text_color(smart_btn_labels[i], lv_color_hex(0xFFFFFF), 0);
        lv_obj_set_style_text_font(smart_btn_labels[i], &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_align(smart_btn_labels[i], LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_width(smart_btn_labels[i], 100);
        lv_label_set_long_mode(smart_btn_labels[i], LV_LABEL_LONG_WRAP);
        lv_obj_center(smart_btn_labels[i]);

        lv_obj_add_event_cb(smart_btn_objs[i], smart_btn_action_cb, LV_EVENT_CLICKED, (void*)(intptr_t)i);
    }

    // Navigation Hint on Smart Deck
    lv_obj_t *hint_smart = lv_label_create(t1);
    deck_hint_labels[DECK_SMART] = hint_smart;
    lv_label_set_text(hint_smart, "< System | Agent & CI >");
    lv_obj_set_style_text_color(hint_smart, lv_color_hex(0x636366), 0);
    lv_obj_set_style_text_font(hint_smart, &lv_font_montserrat_10, 0);
    lv_obj_align(hint_smart, LV_ALIGN_BOTTOM_MID, 0, -4);

    // Initial default profile for Smart Deck
    static const DynamicButtonConfig default_smart_buttons[6] = {
        {"Mission\nControl", 0x0A84FF, MOD_CTRL, KEY_UP_ARROW,    0},
        {"Show\nDesktop",    0x5E5CE6, 0,        KEY_F11,         0},
        {"Space\nLeft",      0x30D158, MOD_CTRL, KEY_LEFT_ARROW,  0},
        {"Space\nRight",     0x30D158, MOD_CTRL, KEY_RIGHT_ARROW, 0},
        {"Mute\nAudio",      0xFF453A, 0,        0,               CONSUMER_CONTROL_MUTE},
        {"Spotlight\nSearch",0xFF9F0A, MOD_CMD,  ' ',             0}
    };
    ui_update_smart_deck("Default", 0x0A84FF, default_smart_buttons);

    // ==========================================
    // TILE 2: AGENT & CI/CD PIPELINE DECK
    // ==========================================

    // 1. Header Card (226 x 34)
    lv_obj_t *header_aci = lv_obj_create(t2);
    lv_obj_set_size(header_aci, 226, 34);
    lv_obj_set_pos(header_aci, 7, 5);
    lv_obj_set_style_bg_color(header_aci, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(header_aci, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_border_width(header_aci, 1, 0);
    lv_obj_set_style_radius(header_aci, 10, 0);
    lv_obj_set_style_pad_all(header_aci, 4, 0);
    lv_obj_clear_flag(header_aci, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *lbl_aci_title = lv_label_create(header_aci);
    lv_label_set_text(lbl_aci_title, "AGENT & CI DECK");
    lv_obj_set_style_text_color(lbl_aci_title, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(lbl_aci_title, &lv_font_montserrat_10, 0);
    lv_obj_align(lbl_aci_title, LV_ALIGN_LEFT_MID, 4, 0);

    lv_obj_t *dot_aci = lv_obj_create(header_aci);
    lv_obj_set_size(dot_aci, 8, 8);
    lv_obj_set_style_radius(dot_aci, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(dot_aci, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_border_width(dot_aci, 0, 0);
    lv_obj_align(dot_aci, LV_ALIGN_RIGHT_MID, -36, 0);

    lv_obj_t *lbl_aci_status = lv_label_create(header_aci);
    lv_label_set_text(lbl_aci_status, "LIVE");
    lv_obj_set_style_text_color(lbl_aci_status, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_text_font(lbl_aci_status, &lv_font_montserrat_10, 0);
    lv_obj_align(lbl_aci_status, LV_ALIGN_RIGHT_MID, -4, 0);

    // 2. Agent Card (226 x 78)
    lv_obj_t *card_agent = lv_obj_create(t2);
    lv_obj_set_size(card_agent, 226, 78);
    lv_obj_set_pos(card_agent, 7, 43);
    lv_obj_set_style_bg_color(card_agent, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_agent, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_agent, 1, 0);
    lv_obj_set_style_radius(card_agent, 10, 0);
    lv_obj_set_style_pad_all(card_agent, 6, 0);
    lv_obj_clear_flag(card_agent, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *lbl_ag_pfx = lv_label_create(card_agent);
    lv_label_set_text(lbl_ag_pfx, "AGENT:");
    lv_obj_set_style_text_color(lbl_ag_pfx, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(lbl_ag_pfx, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(lbl_ag_pfx, 2, 2);

    label_agent_name = lv_label_create(card_agent);
    lv_label_set_text(label_agent_name, "Ready");
    lv_obj_set_style_text_color(label_agent_name, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(label_agent_name, &lv_font_montserrat_12, 0);
    lv_obj_set_pos(label_agent_name, 50, 0);
    lv_obj_set_width(label_agent_name, 110);
    lv_label_set_long_mode(label_agent_name, LV_LABEL_LONG_DOT);

    badge_agent_container = lv_obj_create(card_agent);
    lv_obj_set_size(badge_agent_container, 62, 18);
    lv_obj_align(badge_agent_container, LV_ALIGN_TOP_RIGHT, 0, 0);
    lv_obj_set_style_bg_color(badge_agent_container, lv_color_hex(0x3A3A3C), 0);
    lv_obj_set_style_border_width(badge_agent_container, 0, 0);
    lv_obj_set_style_radius(badge_agent_container, 4, 0);
    lv_obj_clear_flag(badge_agent_container, LV_OBJ_FLAG_SCROLLABLE);

    badge_agent_label = lv_label_create(badge_agent_container);
    lv_label_set_text(badge_agent_label, "IDLE");
    lv_obj_set_style_text_color(badge_agent_label, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(badge_agent_label, &lv_font_montserrat_10, 0);
    lv_obj_center(badge_agent_label);

    label_agent_task = lv_label_create(card_agent);
    lv_label_set_text(label_agent_task, "Task: Ready");
    lv_obj_set_style_text_color(label_agent_task, lv_color_hex(0xE5E5EA), 0);
    lv_obj_set_style_text_font(label_agent_task, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_agent_task, 2, 24);
    lv_obj_set_width(label_agent_task, 214);
    lv_label_set_long_mode(label_agent_task, LV_LABEL_LONG_DOT);

    label_agent_meta = lv_label_create(card_agent);
    lv_label_set_text(label_agent_meta, "Active Subagents: 0");
    lv_obj_set_style_text_color(label_agent_meta, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(label_agent_meta, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_agent_meta, 2, 44);

    // 3. CI/CD Card (226 x 80)
    lv_obj_t *card_ci = lv_obj_create(t2);
    lv_obj_set_size(card_ci, 226, 80);
    lv_obj_set_pos(card_ci, 7, 125);
    lv_obj_set_style_bg_color(card_ci, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_ci, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_ci, 1, 0);
    lv_obj_set_style_radius(card_ci, 10, 0);
    lv_obj_set_style_pad_all(card_ci, 6, 0);
    lv_obj_clear_flag(card_ci, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *lbl_br_pfx = lv_label_create(card_ci);
    lv_label_set_text(lbl_br_pfx, "BRANCH:");
    lv_obj_set_style_text_color(lbl_br_pfx, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(lbl_br_pfx, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(lbl_br_pfx, 2, 2);

    label_branch_name = lv_label_create(card_ci);
    lv_label_set_text(label_branch_name, "main");
    lv_obj_set_style_text_color(label_branch_name, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(label_branch_name, &lv_font_montserrat_12, 0);
    lv_obj_set_pos(label_branch_name, 56, 0);

    badge_ci_container = lv_obj_create(card_ci);
    lv_obj_set_size(badge_ci_container, 62, 18);
    lv_obj_align(badge_ci_container, LV_ALIGN_TOP_RIGHT, 0, 0);
    lv_obj_set_style_bg_color(badge_ci_container, lv_color_hex(0x3A3A3C), 0);
    lv_obj_set_style_border_width(badge_ci_container, 0, 0);
    lv_obj_set_style_radius(badge_ci_container, 4, 0);
    lv_obj_clear_flag(badge_ci_container, LV_OBJ_FLAG_SCROLLABLE);

    badge_ci_label = lv_label_create(badge_ci_container);
    lv_label_set_text(badge_ci_label, "NO PR");
    lv_obj_set_style_text_color(badge_ci_label, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(badge_ci_label, &lv_font_montserrat_10, 0);
    lv_obj_center(badge_ci_label);

    label_ci_details = lv_label_create(card_ci);
    lv_label_set_text(label_ci_details, "No Checks Active");
    lv_obj_set_style_text_color(label_ci_details, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(label_ci_details, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_ci_details, 2, 24);

    bar_ci_progress = lv_bar_create(card_ci);
    lv_obj_set_size(bar_ci_progress, 214, 8);
    lv_obj_set_pos(bar_ci_progress, 0, 48);
    lv_bar_set_range(bar_ci_progress, 0, 100);
    lv_bar_set_value(bar_ci_progress, 0, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(bar_ci_progress, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_bg_color(bar_ci_progress, lv_color_hex(0x30D158), LV_PART_INDICATOR);
    lv_obj_set_style_radius(bar_ci_progress, 4, 0);

    // 4. Action Buttons (2 buttons side by side, 110x42)
    lv_obj_t *btn_run_check = lv_btn_create(t2);
    lv_obj_set_size(btn_run_check, 110, 42);
    lv_obj_set_pos(btn_run_check, 7, 210);
    lv_obj_set_style_bg_color(btn_run_check, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_bg_color(btn_run_check, lv_color_hex(0x30D158), LV_STATE_PRESSED);
    lv_obj_set_style_border_color(btn_run_check, lv_color_hex(0x30D158), 0);
    lv_obj_set_style_border_width(btn_run_check, 1, 0);
    lv_obj_set_style_radius(btn_run_check, 8, 0);
    lv_obj_set_style_shadow_width(btn_run_check, 0, 0);
    lv_obj_add_event_cb(btn_run_check, agent_ci_btn_action_cb, LV_EVENT_CLICKED, (void*)(intptr_t)201);

    lv_obj_t *lbl_run_check = lv_label_create(btn_run_check);
    lv_label_set_text(lbl_run_check, "Run Checks\n(gh pr)");
    lv_obj_set_style_text_color(lbl_run_check, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(lbl_run_check, &lv_font_montserrat_10, 0);
    lv_obj_set_style_text_align(lbl_run_check, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(lbl_run_check);

    lv_obj_t *btn_open_pr = lv_btn_create(t2);
    lv_obj_set_size(btn_open_pr, 110, 42);
    lv_obj_set_pos(btn_open_pr, 123, 210);
    lv_obj_set_style_bg_color(btn_open_pr, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_bg_color(btn_open_pr, lv_color_hex(0x0A84FF), LV_STATE_PRESSED);
    lv_obj_set_style_border_color(btn_open_pr, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_border_width(btn_open_pr, 1, 0);
    lv_obj_set_style_radius(btn_open_pr, 8, 0);
    lv_obj_set_style_shadow_width(btn_open_pr, 0, 0);
    lv_obj_add_event_cb(btn_open_pr, agent_ci_btn_action_cb, LV_EVENT_CLICKED, (void*)(intptr_t)202);

    lv_obj_t *lbl_open_pr = lv_label_create(btn_open_pr);
    lv_label_set_text(lbl_open_pr, "Open PR\n(Browser)");
    lv_obj_set_style_text_color(lbl_open_pr, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(lbl_open_pr, &lv_font_montserrat_10, 0);
    lv_obj_set_style_text_align(lbl_open_pr, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(lbl_open_pr);

    // Navigation Hint on Agent & CI Deck
    lv_obj_t *hint_aci_nav = lv_label_create(t2);
    deck_hint_labels[DECK_AGENT_CI] = hint_aci_nav;
    lv_label_set_text(hint_aci_nav, "< Smart | Settings >");
    lv_obj_set_style_text_color(hint_aci_nav, lv_color_hex(0x636366), 0);
    lv_obj_set_style_text_font(hint_aci_nav, &lv_font_montserrat_10, 0);
    lv_obj_align(hint_aci_nav, LV_ALIGN_BOTTOM_MID, 0, -4);

    // ==========================================
    // TILE 3: SETTINGS DECK
    // ==========================================

    // Title
    lv_obj_t *title_settings = lv_label_create(t3);
    lv_label_set_text(title_settings, "< Settings");
    lv_obj_set_style_text_color(title_settings, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(title_settings, &lv_font_montserrat_14, 0);
    lv_obj_set_pos(title_settings, 12, 6);

    // Card 1: Brightness Card (8, 26, 224, 46)
    lv_obj_t *card_bright = lv_obj_create(t3);
    lv_obj_set_size(card_bright, 224, 46);
    lv_obj_set_pos(card_bright, 8, 26);
    lv_obj_set_style_bg_color(card_bright, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_bright, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_bright, 1, 0);
    lv_obj_set_style_radius(card_bright, 8, 0);
    lv_obj_set_style_pad_all(card_bright, 4, 0);
    lv_obj_clear_flag(card_bright, LV_OBJ_FLAG_SCROLLABLE);

    label_brightness = lv_label_create(card_bright);
    lv_label_set_text_fmt(label_brightness, "Brightness: %d%%", current_brightness);
    lv_obj_set_style_text_color(label_brightness, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(label_brightness, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_brightness, 4, 2);

    lv_obj_t *slider = lv_slider_create(card_bright);
    lv_obj_set_size(slider, 196, 10);
    lv_obj_set_pos(slider, 14, 28);
    lv_slider_set_range(slider, 10, 100);
    lv_slider_set_value(slider, current_brightness, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0x3A3A3C), 0);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0x0A84FF), LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0xFFFFFF), LV_PART_KNOB);
    lv_obj_add_event_cb(slider, slider_brightness_cb, LV_EVENT_VALUE_CHANGED, NULL);

    // Card 2: Active Decks Card (8, 76, 224, 104)
    lv_obj_t *card_decks = lv_obj_create(t3);
    lv_obj_set_size(card_decks, 224, 104);
    lv_obj_set_pos(card_decks, 8, 76);
    lv_obj_set_style_bg_color(card_decks, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_decks, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_decks, 1, 0);
    lv_obj_set_style_radius(card_decks, 8, 0);
    lv_obj_set_style_pad_all(card_decks, 4, 0);
    lv_obj_clear_flag(card_decks, LV_OBJ_FLAG_SCROLLABLE);

    // Header: "ACTIVE DECKS"
    lv_obj_t *hdr_decks = lv_label_create(card_decks);
    lv_label_set_text(hdr_decks, "ACTIVE DECKS");
    lv_obj_set_style_text_color(hdr_decks, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(hdr_decks, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(hdr_decks, 4, 2);

    // Row 1: System Deck
    lv_obj_t *row_sys = lv_obj_create(card_decks);
    lv_obj_set_size(row_sys, 165, 26);
    lv_obj_set_pos(row_sys, 4, 16);
    lv_obj_set_style_bg_opa(row_sys, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(row_sys, 0, 0);
    lv_obj_set_style_pad_all(row_sys, 0, 0);
    lv_obj_clear_flag(row_sys, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(row_sys, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *dot_sys = lv_obj_create(row_sys);
    lv_obj_set_size(dot_sys, 8, 8);
    lv_obj_set_pos(dot_sys, 0, 9);
    lv_obj_set_style_radius(dot_sys, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(dot_sys, lv_color_hex(0x0A84FF), 0);
    lv_obj_set_style_border_width(dot_sys, 0, 0);
    lv_obj_set_style_pad_all(dot_sys, 0, 0);
    lv_obj_clear_flag(dot_sys, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *lbl_sys = lv_label_create(row_sys);
    lv_label_set_text(lbl_sys, "System Deck");
    lv_obj_set_style_text_color(lbl_sys, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(lbl_sys, &lv_font_montserrat_12, 0);
    lv_obj_set_pos(lbl_sys, 14, 5);

    sw_deck_system = lv_switch_create(card_decks);
    style_deck_switch(sw_deck_system, 0x0A84FF);
    lv_obj_set_pos(sw_deck_system, 172, 19);
    if (deck_enabled[DECK_SYSTEM]) {
        lv_obj_add_state(sw_deck_system, LV_STATE_CHECKED);
    } else {
        lv_obj_clear_state(sw_deck_system, LV_STATE_CHECKED);
    }
    lv_obj_add_event_cb(sw_deck_system, sw_deck_toggle_cb, LV_EVENT_VALUE_CHANGED, (void*)(intptr_t)DECK_SYSTEM);
    lv_obj_add_event_cb(row_sys, deck_row_click_cb, LV_EVENT_CLICKED, sw_deck_system);

    // Row 2: Smart Deck
    lv_obj_t *row_smart = lv_obj_create(card_decks);
    lv_obj_set_size(row_smart, 165, 26);
    lv_obj_set_pos(row_smart, 4, 44);
    lv_obj_set_style_bg_opa(row_smart, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(row_smart, 0, 0);
    lv_obj_set_style_pad_all(row_smart, 0, 0);
    lv_obj_clear_flag(row_smart, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(row_smart, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *dot_smart = lv_obj_create(row_smart);
    lv_obj_set_size(dot_smart, 8, 8);
    lv_obj_set_pos(dot_smart, 0, 9);
    lv_obj_set_style_radius(dot_smart, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(dot_smart, lv_color_hex(0xBF5AF2), 0);
    lv_obj_set_style_border_width(dot_smart, 0, 0);
    lv_obj_set_style_pad_all(dot_smart, 0, 0);
    lv_obj_clear_flag(dot_smart, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *lbl_smart = lv_label_create(row_smart);
    lv_label_set_text(lbl_smart, "Smart Deck");
    lv_obj_set_style_text_color(lbl_smart, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(lbl_smart, &lv_font_montserrat_12, 0);
    lv_obj_set_pos(lbl_smart, 14, 5);

    sw_deck_smart = lv_switch_create(card_decks);
    style_deck_switch(sw_deck_smart, 0xBF5AF2);
    lv_obj_set_pos(sw_deck_smart, 172, 47);
    if (deck_enabled[DECK_SMART]) {
        lv_obj_add_state(sw_deck_smart, LV_STATE_CHECKED);
    } else {
        lv_obj_clear_state(sw_deck_smart, LV_STATE_CHECKED);
    }
    lv_obj_add_event_cb(sw_deck_smart, sw_deck_toggle_cb, LV_EVENT_VALUE_CHANGED, (void*)(intptr_t)DECK_SMART);
    lv_obj_add_event_cb(row_smart, deck_row_click_cb, LV_EVENT_CLICKED, sw_deck_smart);

    // Row 3: Agent & CI Deck
    lv_obj_t *row_agent_ci = lv_obj_create(card_decks);
    lv_obj_set_size(row_agent_ci, 165, 26);
    lv_obj_set_pos(row_agent_ci, 4, 72);
    lv_obj_set_style_bg_opa(row_agent_ci, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(row_agent_ci, 0, 0);
    lv_obj_set_style_pad_all(row_agent_ci, 0, 0);
    lv_obj_clear_flag(row_agent_ci, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(row_agent_ci, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *dot_row_aci = lv_obj_create(row_agent_ci);
    lv_obj_set_size(dot_row_aci, 8, 8);
    lv_obj_set_pos(dot_row_aci, 0, 9);
    lv_obj_set_style_radius(dot_row_aci, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(dot_row_aci, lv_color_hex(0x30D158), 0);
    lv_obj_set_style_border_width(dot_row_aci, 0, 0);
    lv_obj_set_style_pad_all(dot_row_aci, 0, 0);
    lv_obj_clear_flag(dot_row_aci, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *lbl_aci = lv_label_create(row_agent_ci);
    lv_label_set_text(lbl_aci, "Agent & CI Deck");
    lv_obj_set_style_text_color(lbl_aci, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(lbl_aci, &lv_font_montserrat_12, 0);
    lv_obj_set_pos(lbl_aci, 14, 5);

    sw_deck_agent_ci = lv_switch_create(card_decks);
    style_deck_switch(sw_deck_agent_ci, 0x30D158);
    lv_obj_set_pos(sw_deck_agent_ci, 172, 75);
    if (deck_enabled[DECK_AGENT_CI]) {
        lv_obj_add_state(sw_deck_agent_ci, LV_STATE_CHECKED);
    } else {
        lv_obj_clear_state(sw_deck_agent_ci, LV_STATE_CHECKED);
    }
    lv_obj_add_event_cb(sw_deck_agent_ci, sw_deck_toggle_cb, LV_EVENT_VALUE_CHANGED, (void*)(intptr_t)DECK_AGENT_CI);
    lv_obj_add_event_cb(row_agent_ci, deck_row_click_cb, LV_EVENT_CLICKED, sw_deck_agent_ci);

    // Card 3: Wi-Fi Connectivity (8, 184, 224, 100)
    lv_obj_t *card_wifi = lv_obj_create(t3);
    lv_obj_set_size(card_wifi, 224, 100);
    lv_obj_set_pos(card_wifi, 8, 184);
    lv_obj_set_style_bg_color(card_wifi, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_wifi, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_wifi, 1, 0);
    lv_obj_set_style_radius(card_wifi, 8, 0);
    lv_obj_set_style_pad_all(card_wifi, 4, 0);
    lv_obj_clear_flag(card_wifi, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *hdr_wifi = lv_label_create(card_wifi);
    lv_label_set_text(hdr_wifi, "WI-FI CONNECTIVITY");
    lv_obj_set_style_text_color(hdr_wifi, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(hdr_wifi, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(hdr_wifi, 4, 2);

    sw_wifi = lv_switch_create(card_wifi);
    style_deck_switch(sw_wifi, 0x0A84FF);
    lv_obj_set_pos(sw_wifi, 172, 0);
    if (wifi_manager_is_enabled()) {
        lv_obj_add_state(sw_wifi, LV_STATE_CHECKED);
    }
    lv_obj_add_event_cb(sw_wifi, sw_wifi_toggle_cb, LV_EVENT_VALUE_CHANGED, NULL);

    label_wifi_status = lv_label_create(card_wifi);
    lv_label_set_text(label_wifi_status, "Offline");
    lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(label_wifi_status, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_wifi_status, 4, 22);
    lv_obj_set_width(label_wifi_status, 206);
    lv_label_set_long_mode(label_wifi_status, LV_LABEL_LONG_DOT);

    // Multiple options, least friction first: companion sync is the primary
    // (default) path, the standalone web portal is the fallback.
    create_conn_button(card_wifi, "Sync from\nMac", 0x0A84FF, 2, 40, 102, 44, ACTION_WIFI_SYNC);
    create_conn_button(card_wifi, "Web\nPortal", 0x5E5CE6, 110, 40, 102, 44, ACTION_WIFI_PORTAL);

    // Card 4: Bluetooth (BLE HID) (8, 288, 224, 92)
    lv_obj_t *card_ble = lv_obj_create(t3);
    lv_obj_set_size(card_ble, 224, 92);
    lv_obj_set_pos(card_ble, 8, 288);
    lv_obj_set_style_bg_color(card_ble, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_ble, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_ble, 1, 0);
    lv_obj_set_style_radius(card_ble, 8, 0);
    lv_obj_set_style_pad_all(card_ble, 4, 0);
    lv_obj_clear_flag(card_ble, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *hdr_ble = lv_label_create(card_ble);
    lv_label_set_text(hdr_ble, "BLUETOOTH (BLE HID)");
    lv_obj_set_style_text_color(hdr_ble, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(hdr_ble, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(hdr_ble, 4, 2);

    sw_ble = lv_switch_create(card_ble);
    style_deck_switch(sw_ble, 0x30D158);
    lv_obj_set_pos(sw_ble, 172, 0);
    if (ble_hid_is_enabled()) {
        lv_obj_add_state(sw_ble, LV_STATE_CHECKED);
    }
    lv_obj_add_event_cb(sw_ble, sw_ble_toggle_cb, LV_EVENT_VALUE_CHANGED, NULL);

    label_ble_status = lv_label_create(card_ble);
    lv_label_set_text(label_ble_status, ble_hid_is_enabled() ? "Standby" : "Bluetooth Off");
    lv_obj_set_style_text_color(label_ble_status, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(label_ble_status, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_ble_status, 4, 22);
    lv_obj_set_width(label_ble_status, 206);
    lv_label_set_long_mode(label_ble_status, LV_LABEL_LONG_DOT);

    create_conn_button(card_ble, "Pair New Device (BLE)", 0x30D158, 2, 40, 210, 40, ACTION_BLE_PAIR);

    // Card 5: Device & System Info (8, 384, 224, 88)
    lv_obj_t *card_info = lv_obj_create(t3);
    lv_obj_set_size(card_info, 224, 88);
    lv_obj_set_pos(card_info, 8, 384);
    lv_obj_set_style_bg_color(card_info, lv_color_hex(0x1C1C1E), 0);
    lv_obj_set_style_border_color(card_info, lv_color_hex(0x2C2C2E), 0);
    lv_obj_set_style_border_width(card_info, 1, 0);
    lv_obj_set_style_radius(card_info, 8, 0);
    lv_obj_set_style_pad_all(card_info, 4, 0);
    lv_obj_clear_flag(card_info, LV_OBJ_FLAG_SCROLLABLE);

    const char *info_text =
        "ESP32-S3 @ 240MHz (16MB/8MB)\n"
        "Wi-Fi 2.4GHz 802.11n | BT5 LE HID\n"
        "USB CDC + USB/BLE HID Hotkeys\n"
        "Firmware: vitruvian-core v1.1";

    lv_obj_t *info_lbl = lv_label_create(card_info);
    lv_label_set_text(info_lbl, info_text);
    lv_obj_set_style_text_color(info_lbl, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(info_lbl, &lv_font_montserrat_10, 0);
    lv_obj_set_style_text_line_space(info_lbl, 3, 0);
    lv_obj_set_pos(info_lbl, 4, 2);

    label_hw_net = lv_label_create(card_info);
    lv_label_set_text_fmt(label_hw_net, "IP: %s | MAC: %s", hw_last_ip, hw_wifi_mac);
    lv_obj_set_style_text_color(label_hw_net, lv_color_hex(0x8E8E93), 0);
    lv_obj_set_style_text_font(label_hw_net, &lv_font_montserrat_10, 0);
    lv_obj_set_pos(label_hw_net, 4, 62);
    lv_obj_set_width(label_hw_net, 206);
    lv_label_set_long_mode(label_hw_net, LV_LABEL_LONG_DOT);

    // Settings Bottom Hint (end of the scrollable card stack)
    lv_obj_t *hint_back = lv_label_create(t3);
    deck_hint_labels[DECK_SETTINGS] = hint_back;
    lv_label_set_text(hint_back, "< Swipe Right for Agent & CI");
    lv_obj_set_style_text_color(hint_back, lv_color_hex(0x636366), 0);
    lv_obj_set_style_text_font(hint_back, &lv_font_montserrat_10, 0);
    lv_obj_set_style_text_align(hint_back, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_width(hint_back, 240);
    lv_obj_set_pos(hint_back, 0, 478);

    // Initial Re-indexing and Viewport Configuration
    ui_reindex_carousel();
    if (deck_enabled[DECK_SYSTEM]) {
        lv_obj_set_tile(tv, t0, LV_ANIM_OFF);
    } else {
        lv_obj_set_tile(tv, t3, LV_ANIM_OFF);
    }
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
            if (hw_last_ip[0] != '\0' && strcmp(hw_last_ip, "--") != 0) {
                lv_label_set_text_fmt(label_link, "● %s", hw_last_ip);
            } else {
                lv_label_set_text(label_link, "● Linked");
            }
            lv_obj_set_style_text_color(label_link, lv_color_hex(0x30D158), 0);
        } else {
            if (hw_last_ip[0] != '\0' && strcmp(hw_last_ip, "--") != 0) {
                lv_label_set_text_fmt(label_link, "📶 %s", hw_last_ip);
                lv_obj_set_style_text_color(label_link, lv_color_hex(0x30D158), 0);
            } else {
                lv_label_set_text(label_link, "● Standby");
                lv_obj_set_style_text_color(label_link, lv_color_hex(0xFF9F0A), 0);
            }
        }
    }
}

void ui_update_smart_deck(const char* app_name, uint32_t app_color, const DynamicButtonConfig btns[6]) {
    // 1. Update App Name
    if (label_smart_app && app_name && strlen(app_name) > 0) {
        lv_label_set_text(label_smart_app, app_name);
    }

    // 2. Update Header Accent Color Elements
    if (dot_smart_accent) {
        lv_obj_set_style_bg_color(dot_smart_accent, lv_color_hex(app_color), 0);
    }
    if (header_smart) {
        lv_obj_set_style_border_color(header_smart, lv_color_hex(app_color), 0);
    }
    if (bar_smart_accent) {
        lv_obj_set_style_bg_color(bar_smart_accent, lv_color_hex(app_color), 0);
    }

    // 3. Update the 6 Buttons
    for (int i = 0; i < 6; i++) {
        smart_buttons[i] = btns[i];

        // Update Label
        if (smart_btn_labels[i]) {
            lv_label_set_text(smart_btn_labels[i], smart_buttons[i].label);
        }

        // Update Button Styling
        if (smart_btn_objs[i]) {
            // Unpressed state: dark gray fill with colored accent border
            lv_obj_set_style_bg_color(smart_btn_objs[i], lv_color_hex(0x1C1C1E), 0);
            lv_obj_set_style_border_color(smart_btn_objs[i], lv_color_hex(smart_buttons[i].color), 0);

            // Pressed state: solid fill with button accent color
            lv_obj_set_style_bg_color(smart_btn_objs[i], lv_color_hex(smart_buttons[i].color), LV_STATE_PRESSED);

            // Invalidate to guarantee immediate repaint on next tick
            lv_obj_invalidate(smart_btn_objs[i]);
        }
    }
}

void ui_update_agent_ci(const AgentCIConfig* config) {
    if (!config) return;

    // 1. Update Agent Name
    if (label_agent_name && config->agent_name[0] != '\0') {
        lv_label_set_text(label_agent_name, config->agent_name);
    }

    // 2. Update Agent Badge (Color & Text)
    if (badge_agent_container && badge_agent_label) {
        switch (config->agent_state) {
            case AGENT_STATE_RUNNING:
                lv_obj_set_style_bg_color(badge_agent_container, lv_color_hex(0x0A84FF), 0);
                lv_label_set_text(badge_agent_label, "RUNNING");
                lv_obj_set_style_text_color(badge_agent_label, lv_color_hex(0xFFFFFF), 0);
                break;
            case AGENT_STATE_IDLE:
                lv_obj_set_style_bg_color(badge_agent_container, lv_color_hex(0x3A3A3C), 0);
                lv_label_set_text(badge_agent_label, "IDLE");
                lv_obj_set_style_text_color(badge_agent_label, lv_color_hex(0x8E8E93), 0);
                break;
            case AGENT_STATE_REVIEW:
                lv_obj_set_style_bg_color(badge_agent_container, lv_color_hex(0xFF9F0A), 0);
                lv_label_set_text(badge_agent_label, "REVIEW");
                lv_obj_set_style_text_color(badge_agent_label, lv_color_hex(0x000000), 0);
                break;
            case AGENT_STATE_ERROR:
                lv_obj_set_style_bg_color(badge_agent_container, lv_color_hex(0xFF453A), 0);
                lv_label_set_text(badge_agent_label, "ERROR");
                lv_obj_set_style_text_color(badge_agent_label, lv_color_hex(0xFFFFFF), 0);
                break;
        }
    }

    // 3. Update Agent Task Label
    if (label_agent_task) {
        if (config->agent_task[0] != '\0') {
            lv_label_set_text_fmt(label_agent_task, "Task: %s", config->agent_task);
        } else {
            lv_label_set_text(label_agent_task, "Task: Ready");
        }
    }

    // 4. Update Agent Meta Label (Subagents count)
    if (label_agent_meta) {
        lv_label_set_text_fmt(label_agent_meta, "Active Subagents: %d", config->active_agents);
    }

    // 5. Update Git Branch & Dirty Indicator
    if (label_branch_name) {
        if (config->is_dirty) {
            lv_label_set_text_fmt(label_branch_name, "%s (*%d)", config->branch, config->dirty_files);
            lv_obj_set_style_text_color(label_branch_name, lv_color_hex(0xFF9F0A), 0);
        } else {
            lv_label_set_text(label_branch_name, config->branch);
            lv_obj_set_style_text_color(label_branch_name, lv_color_hex(0xFFFFFF), 0);
        }
    }

    // 6. Update CI Badge & Colors
    uint32_t ci_color = 0x3A3A3C;
    if (badge_ci_container && badge_ci_label) {
        switch (config->ci_status) {
            case CI_STATUS_PASSING:
                ci_color = 0x30D158; // iOS Green
                lv_obj_set_style_bg_color(badge_ci_container, lv_color_hex(ci_color), 0);
                lv_label_set_text(badge_ci_label, "PASSING");
                lv_obj_set_style_text_color(badge_ci_label, lv_color_hex(0xFFFFFF), 0);
                break;
            case CI_STATUS_FAILING:
                ci_color = 0xFF453A; // iOS Red
                lv_obj_set_style_bg_color(badge_ci_container, lv_color_hex(ci_color), 0);
                lv_label_set_text(badge_ci_label, "FAILING");
                lv_obj_set_style_text_color(badge_ci_label, lv_color_hex(0xFFFFFF), 0);
                break;
            case CI_STATUS_PENDING:
                ci_color = 0xFFD60A; // iOS Yellow
                lv_obj_set_style_bg_color(badge_ci_container, lv_color_hex(ci_color), 0);
                lv_label_set_text(badge_ci_label, "PENDING");
                lv_obj_set_style_text_color(badge_ci_label, lv_color_hex(0x000000), 0);
                break;
            case CI_STATUS_NONE:
            case CI_STATUS_UNKNOWN:
            default:
                ci_color = 0x48484A; // Muted Gray
                lv_obj_set_style_bg_color(badge_ci_container, lv_color_hex(0x3A3A3C), 0);
                lv_label_set_text(badge_ci_label, "NO PR");
                lv_obj_set_style_text_color(badge_ci_label, lv_color_hex(0x8E8E93), 0);
                break;
        }
    }

    // 7. Update CI Details (PR Check Numbers)
    if (label_ci_details) {
        if (config->pr_number > 0) {
            lv_label_set_text_fmt(label_ci_details, "PR #%d: %d / %d Checks", 
                                  config->pr_number, config->checks_passed, config->checks_total);
        } else if (config->checks_total > 0) {
            lv_label_set_text_fmt(label_ci_details, "Checks: %d / %d Passed", 
                                  config->checks_passed, config->checks_total);
        } else {
            lv_label_set_text(label_ci_details, "No Checks Active");
        }
    }

    // 8. Update Progress Bar
    if (bar_ci_progress) {
        int total = config->checks_total > 0 ? config->checks_total : 100;
        int passed = config->checks_passed;
        lv_bar_set_range(bar_ci_progress, 0, total);
        lv_bar_set_value(bar_ci_progress, passed, LV_ANIM_ON);
        lv_obj_set_style_bg_color(bar_ci_progress, lv_color_hex(ci_color), LV_PART_INDICATOR);
    }
}

// ===========================================================================
// Milestone 5: Wireless Connectivity Status Updaters
// ===========================================================================
void ui_set_hw_ids(const char* wifi_mac) {
    if (wifi_mac && wifi_mac[0] != '\0') {
        strlcpy(hw_wifi_mac, wifi_mac, sizeof(hw_wifi_mac));
    }
    if (label_hw_net) {
        lv_label_set_text_fmt(label_hw_net, "IP: %s | MAC: %s", hw_last_ip, hw_wifi_mac);
    }
}

void ui_update_wifi_status(const char* state, const char* ip, const char* ssid) {
    if (!state) return;
    bool radio_on = (strcmp(state, "off") != 0);

    // Keep the toggle in sync with the manager (no VALUE_CHANGED re-fire).
    if (sw_wifi) {
        if (radio_on) lv_obj_add_state(sw_wifi, LV_STATE_CHECKED);
        else lv_obj_clear_state(sw_wifi, LV_STATE_CHECKED);
    }

    if (label_wifi_status) {
        if (strcmp(state, "connected") == 0) {
            wifi_sync_pending_until_ms = 0;
            lv_label_set_text_fmt(label_wifi_status, "Connected: %s (%s)",
                                  ip ? ip : "?", ssid ? ssid : "?");
            lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0x30D158), 0);
        } else if (strcmp(state, "connecting") == 0) {
            lv_label_set_text_fmt(label_wifi_status, "Connecting to %s...",
                                  (ssid && ssid[0]) ? ssid : "network");
            lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0xFF9F0A), 0);
        } else if (strcmp(state, "portal") == 0) {
            wifi_sync_pending_until_ms = 0;
            // `ip` carries the SoftAP SSID while the portal is up.
            lv_label_set_text_fmt(label_wifi_status, "AP: %s @ 192.168.4.1",
                                  (ip && ip[0]) ? ip : "Vitruvian-Setup");
            lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0x0A84FF), 0);
        } else if (wifi_sync_pending_until_ms > 0 && millis() < wifi_sync_pending_until_ms) {
            // Retain sync status while waiting for host response
            lv_label_set_text(label_wifi_status, "Syncing with Mac...");
            lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0xFF9F0A), 0);
        } else if (strcmp(state, "offline") == 0) {
            wifi_sync_pending_until_ms = 0;
            if (ssid && ssid[0]) {
                lv_label_set_text_fmt(label_wifi_status, "Offline (saved: %s)", ssid);
            } else {
                lv_label_set_text(label_wifi_status, "Offline - no network saved");
            }
            lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0x8E8E93), 0);
        } else {
            wifi_sync_pending_until_ms = 0;
            lv_label_set_text(label_wifi_status, "Wi-Fi Off");
            lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0x8E8E93), 0);
        }
    }

    // Mirror the IP into the Device & System Info card.
    if (strcmp(state, "connected") == 0 && ip && ip[0]) {
        strlcpy(hw_last_ip, ip, sizeof(hw_last_ip));
    } else {
        strlcpy(hw_last_ip, "--", sizeof(hw_last_ip));
    }
    if (label_hw_net) {
        lv_label_set_text_fmt(label_hw_net, "IP: %s | MAC: %s", hw_last_ip, hw_wifi_mac);
    }
}

void ui_show_wifi_error(const char* error_msg) {
    wifi_sync_pending_until_ms = 0;
    if (label_wifi_status) {
        lv_label_set_text_fmt(label_wifi_status, "Sync Failed: %s", error_msg ? error_msg : "Error");
        lv_obj_set_style_text_color(label_wifi_status, lv_color_hex(0xFF453A), 0);
    }
}

void ui_update_ble_status(const char* state, const char* host, uint32_t seconds_left) {
    if (!state) return;
    bool radio_on = (strcmp(state, "off") != 0);

    if (sw_ble) {
        if (radio_on) lv_obj_add_state(sw_ble, LV_STATE_CHECKED);
        else lv_obj_clear_state(sw_ble, LV_STATE_CHECKED);
    }

    if (!label_ble_status) return;
    if (strcmp(state, "connected") == 0 || strcmp(state, "paired") == 0) {
        lv_label_set_text_fmt(label_ble_status, "Paired: %s",
                              (host && host[0]) ? host : "Mac");
        lv_obj_set_style_text_color(label_ble_status, lv_color_hex(0x30D158), 0);
    } else if (strcmp(state, "advertising") == 0) {
        if (seconds_left > 0) {
            lv_label_set_text_fmt(label_ble_status, "Advertising (%us)...",
                                  (unsigned)seconds_left);
        } else {
            lv_label_set_text(label_ble_status, "Advertising (reconnect)...");
        }
        lv_obj_set_style_text_color(label_ble_status, lv_color_hex(0x0A84FF), 0);
    } else if (strcmp(state, "standby") == 0) {
        lv_label_set_text(label_ble_status, "Standby");
        lv_obj_set_style_text_color(label_ble_status, lv_color_hex(0x8E8E93), 0);
    } else {
        lv_label_set_text(label_ble_status, "Bluetooth Off");
        lv_obj_set_style_text_color(label_ble_status, lv_color_hex(0x8E8E93), 0);
    }
}

