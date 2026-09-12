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
// Autonomous GitHub Actions poller.
//
// Turns the companion into a standalone build beacon: when it is on Wi-Fi and
// no Mac daemon is streaming (USB or LAN), it queries the Actions REST API
// itself, drives the Agent & CI deck, and chimes on every conclusion change.
//
// The HTTPS fetch runs on its own FreeRTOS task -- a TLS handshake blocks for
// hundreds of milliseconds, which would stall lv_timer_handler() and stutter
// the carousel. The worker only ever publishes into a mutex-guarded result
// slot; cloud_ci_loop() drains it in main-loop context, so every UI and buzzer
// call still happens on the Arduino loop task.
// ---------------------------------------------------------------------------

// "owner/repo", NUL-terminated. GitHub caps owner at 39 and repo at 100.
#define CLOUD_CI_REPO_MAX 144
#define CLOUD_CI_TOKEN_MAX 128

enum CloudCIState {
    CLOUD_CI_STATE_IDLE = 0,  // poller not running (tethered, off, or no Wi-Fi)
    CLOUD_CI_STATE_POLLING,   // request in flight
    CLOUD_CI_STATE_OK,        // last poll returned a run
    CLOUD_CI_STATE_ERROR      // last poll failed; `error` says why
};

struct CloudCIResult {
    char workflow[48];    // workflow_runs[0].name
    char status[16];      // queued | in_progress | completed
    char conclusion[16];  // success | failure | cancelled | "" while running
    char branch[48];      // workflow_runs[0].head_branch
    char sha[8];          // 7-char head_sha prefix
    int run_number;
    bool valid;
};

void cloud_ci_init();

// Pump from the Arduino main loop. `host_streaming` is the packet router's
// verdict on whether a Mac daemon is feeding us; while true the poller idles
// so the two sources never fight over the Agent & CI deck.
void cloud_ci_loop(bool wifi_connected, bool host_streaming);

// Runs a poll at the next loop tick (used by the deck's Refresh button).
void cloud_ci_request_poll();

// True exactly once per newly published poll result -- the main loop uses it
// to refresh the Agent & CI deck without re-rendering on every tick.
bool cloud_ci_take_update();

CloudCIState cloud_ci_get_state();
const CloudCIResult* cloud_ci_get_result();
const char* cloud_ci_get_error();

// True when the poller -- not a Mac daemon -- currently owns the deck.
bool cloud_ci_is_driving();

// NVS-backed config (namespace "cloud_ci").
void cloud_ci_set_repo(const char* owner_repo);
const char* cloud_ci_get_repo();
void cloud_ci_set_token(const char* token);
bool cloud_ci_has_token();
void cloud_ci_set_enabled(bool enabled);
bool cloud_ci_is_enabled();

// Poll cadence, clamped to [15, 3600] s. GitHub allows 60 unauthenticated
// requests/hour per IP, so the 60 s default needs a token to be sustainable.
void cloud_ci_set_interval_seconds(uint32_t seconds);
uint32_t cloud_ci_get_interval_seconds();

// Field escape hatch: skip certificate verification if GitHub rotates to a CA
// outside src/github_ca.h before a firmware update reaches the device.
void cloud_ci_set_insecure(bool insecure);
bool cloud_ci_is_insecure();
