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

#pragma once
#include <stdbool.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Piezo buzzer melody engine (GPIO 42, LEDC PWM channel 0).
//
// Every playback call is NON-BLOCKING: it queues a note sequence and returns
// immediately. buzzer_loop() must be pumped from the Arduino main loop to
// advance the sequence -- a blocking implementation would stall lv_timer_handler()
// for the ~500 ms of a chime and visibly freeze the carousel mid-swipe.
// ---------------------------------------------------------------------------

// Longest sequence any melody below enqueues (4 tones + 4 inter-note gaps).
#define BUZZER_MAX_NOTES 8

void buzzer_init();
void buzzer_loop();

// CI conclusion chimes. Ascending major arpeggio on pass, descending minor
// figure on fail -- distinguishable from across a room without looking.
void buzzer_play_ci_pass();   // C5 -> E5 -> G5 -> C6
void buzzer_play_ci_fail();   // F5 -> D5 -> B4

// Short UI tick played on every touch action.
void buzzer_play_click();     // 1000 Hz, 20 ms

// Mute toggle, persisted to NVS (namespace "settings", key "chimes_muted").
// Muting silences an in-flight melody immediately.
void buzzer_set_muted(bool muted);
bool buzzer_is_muted();

// True while a queued sequence is still playing.
bool buzzer_is_playing();
