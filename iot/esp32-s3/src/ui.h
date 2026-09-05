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
#include <lvgl.h>
#include <stdint.h>
#include "mac_hid.h"

// Dynamic button configuration structure
struct DynamicButtonConfig {
    char label[32];      // Button label (supports '\n' for 2-line layout, max 31 chars + null)
    uint32_t color;      // 24-bit RGB accent/border color (e.g. 0x007ACC)
    uint8_t mod;         // Modifier bitmask (MOD_CTRL, MOD_SHIFT, MOD_ALT, MOD_CMD)
    uint8_t key;         // ASCII char or HID key code (e.g. 'P', 112, etc.)
    uint16_t cons;       // USB Consumer Control code (0 if hotkey)
};

// ===========================================================================
// Milestone 3: Agent & CI Deck Data Contracts
// ===========================================================================
enum AgentState {
    AGENT_STATE_IDLE = 0,
    AGENT_STATE_RUNNING,
    AGENT_STATE_REVIEW,
    AGENT_STATE_ERROR
};

enum CIStatus {
    CI_STATUS_UNKNOWN = 0,
    CI_STATUS_PASSING,
    CI_STATUS_FAILING,
    CI_STATUS_PENDING,
    CI_STATUS_NONE
};

typedef CIStatus CIState;
#define CI_STATE_UNKNOWN CI_STATUS_UNKNOWN
#define CI_STATE_PASSING CI_STATUS_PASSING
#define CI_STATE_FAILING CI_STATUS_FAILING
#define CI_STATE_PENDING CI_STATUS_PENDING
#define CI_STATE_NONE    CI_STATUS_NONE

struct AgentCIConfig {
    // Agent subsystem
    char agent_name[32];      // e.g. "Antigravity", "Claude Code" (31 chars + null)
    AgentState agent_state;   // AGENT_STATE_* enum
    char agent_task[64];      // Current task description (63 chars + null)
    int active_agents;        // Count of active agents/subagents

    // CI/CD subsystem
    char repo[32];            // Repository name (e.g. "vitruvian-core")
    char branch[48];          // Git branch name (47 chars + null)
    CIStatus ci_status;       // CI_STATUS_* enum
    int pr_number;            // GitHub PR number (0 if none)
    int checks_passed;        // Number of passed checks
    int checks_total;         // Total number of checks
    bool is_dirty;            // True if uncommitted modified/untracked files exist
    int dirty_files;          // Count of uncommitted files
};

// UI Initialization and Update Functions
void ui_init();
void ui_update_stats(int cpu, int ram, const char* time_str, bool linked);
void ui_update_smart_deck(const char* app_name, uint32_t app_color, const DynamicButtonConfig btns[6]);
void ui_update_agent_ci(const AgentCIConfig* config);
void set_backlight_brightness(uint8_t percent);
uint8_t get_backlight_brightness();

// ===========================================================================
// Milestone 4: Deck Visibility Toggles & Carousel Re-Indexing
// ===========================================================================
enum DeckId {
    DECK_SYSTEM = 0,
    DECK_SMART = 1,
    DECK_AGENT_CI = 2,
    DECK_SETTINGS = 3,
    DECK_COUNT = 4
};

struct DeckVisibilityConfig {
    bool system_enabled;
    bool smart_enabled;
    bool agent_ci_enabled;
};

extern bool deck_enabled[DECK_COUNT];

void ui_set_deck_enabled(uint8_t deck_id, bool enabled);
bool ui_is_deck_enabled(uint8_t deck_id);
void ui_set_deck_visible(DeckId deck, bool visible);
bool ui_get_deck_visible(DeckId deck);
int  ui_get_active_deck_count();
DeckId ui_get_active_deck_at_col(int col);
DeckVisibilityConfig ui_get_deck_visibility();
void ui_set_deck_visibility(const DeckVisibilityConfig* config);
void ui_reindex_carousel();
void ui_update_navigation_hints();
void ui_load_deck_preferences();
void ui_save_deck_preferences();

