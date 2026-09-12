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

#include "buzzer.h"

#include <Arduino.h>
#include <Preferences.h>

#include "pin_config.h"

// LEDC channel 0. Channel 7 is the display backlight (ui.cpp), and the
// Arduino tone() helper would grab a channel of its own -- owning the buzzer
// here keeps the two PWM users explicit and non-overlapping.
static const int BUZZER_LEDC_CH = 0;
static const int BUZZER_LEDC_RES = 10;
// 50% duty on a piezo is the loudest point; anything else just clips.
static const uint32_t BUZZER_DUTY = (1u << BUZZER_LEDC_RES) / 2;

// Silence between consecutive notes so an arpeggio reads as four notes rather
// than one glissando.
static const uint16_t NOTE_GAP_MS = 18;

static const char* NVS_SETTINGS_NS = "settings";
static const char* NVS_MUTED_KEY = "chimes_muted";

struct Note {
    uint16_t freq_hz;  // 0 = rest
    uint16_t dur_ms;
};

static Note sequence[BUZZER_MAX_NOTES];
static uint8_t seq_len = 0;
static uint8_t seq_pos = 0;
static unsigned long note_ends_at_ms = 0;
static bool playing = false;

static bool muted = false;
static bool initialised = false;

static Preferences buzzer_prefs;

static void silence() {
    if (!initialised) return;
    ledcWriteTone(BUZZER_LEDC_CH, 0);
    ledcWrite(BUZZER_LEDC_CH, 0);
}

static void start_note(const Note& note) {
    if (note.freq_hz == 0) {
        silence();
    } else {
        ledcWriteTone(BUZZER_LEDC_CH, note.freq_hz);
        ledcWrite(BUZZER_LEDC_CH, BUZZER_DUTY);
    }
    note_ends_at_ms = millis() + note.dur_ms;
}

// Loads `notes` into the sequencer, interleaving rests, and starts note 0.
// A new melody pre-empts whatever was playing: a burst of CI transitions
// should sound like the latest result, not a queue backlog.
static void play_sequence(const Note* notes, uint8_t count, bool with_gaps) {
    if (!initialised || muted || count == 0) return;

    seq_len = 0;
    for (uint8_t i = 0; i < count && seq_len < BUZZER_MAX_NOTES; i++) {
        sequence[seq_len++] = notes[i];
        bool more = (i + 1 < count);
        if (with_gaps && more && seq_len < BUZZER_MAX_NOTES) {
            sequence[seq_len].freq_hz = 0;
            sequence[seq_len].dur_ms = NOTE_GAP_MS;
            seq_len++;
        }
    }

    seq_pos = 0;
    playing = true;
    start_note(sequence[0]);
}

void buzzer_init() {
    if (buzzer_prefs.begin(NVS_SETTINGS_NS, true /* read-only */)) {
        muted = buzzer_prefs.getBool(NVS_MUTED_KEY, false);
        buzzer_prefs.end();
    }

    // A frequency is required up front; ledcWriteTone() re-programs it per note.
    ledcSetup(BUZZER_LEDC_CH, 1000, BUZZER_LEDC_RES);
    ledcAttachPin(BUZZER_PIN, BUZZER_LEDC_CH);
    initialised = true;
    silence();
}

void buzzer_loop() {
    if (!playing) return;
    if ((long)(millis() - note_ends_at_ms) < 0) return;

    seq_pos++;
    if (seq_pos >= seq_len) {
        playing = false;
        silence();
        return;
    }
    start_note(sequence[seq_pos]);
}

void buzzer_play_ci_pass() {
    static const Note kPass[] = {
        {523, 80},   // C5
        {659, 80},   // E5
        {784, 120},  // G5
        {1046, 200}, // C6
    };
    play_sequence(kPass, sizeof(kPass) / sizeof(kPass[0]), true);
}

void buzzer_play_ci_fail() {
    static const Note kFail[] = {
        {698, 150}, // F5
        {587, 150}, // D5
        {494, 300}, // B4
    };
    play_sequence(kFail, sizeof(kFail) / sizeof(kFail[0]), true);
}

void buzzer_play_click() {
    static const Note kClick[] = {{1000, 20}};
    play_sequence(kClick, 1, false);
}

void buzzer_set_muted(bool value) {
    if (value == muted) return;
    muted = value;
    if (buzzer_prefs.begin(NVS_SETTINGS_NS, false)) {
        buzzer_prefs.putBool(NVS_MUTED_KEY, muted);
        buzzer_prefs.end();
    }
    if (muted) {
        // Cut an in-flight chime rather than letting it ring on past the tap.
        playing = false;
        seq_len = 0;
        silence();
    }
}

bool buzzer_is_muted() {
    return muted;
}

bool buzzer_is_playing() {
    return playing;
}
