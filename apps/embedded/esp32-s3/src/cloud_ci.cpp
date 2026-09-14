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

#include "cloud_ci.h"

#include <Arduino.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

#include "buzzer.h"
#include "github_ca.h"

static const char* NVS_CLOUD_NS = "cloud_ci";
static const char* GITHUB_HOST = "api.github.com";

// Default target: this monorepo. Overridable over the wire (cloud_config) and
// persisted, so a re-flash does not lose a user's repo.
static const char* DEFAULT_REPO = "VitruvianSoftware/vitruvian-core";

#define CLOUD_CI_INTERVAL_MIN_S 15UL
#define CLOUD_CI_INTERVAL_MAX_S 3600UL
#define CLOUD_CI_DEFAULT_INTERVAL_S 60UL

// A failed poll backs off geometrically to this ceiling: an unreachable API or
// a spent rate-limit budget must not turn into a request every minute forever.
#define CLOUD_CI_BACKOFF_MAX_MS (15UL * 60UL * 1000UL)

// HTTPS + a ~20 KB response body needs real stack; the Arduino loop task's own
// 8 KB would overflow during the mbedTLS handshake.
#define CLOUD_CI_TASK_STACK 16384
#define CLOUD_CI_TASK_PRIO 1
// Core 0: the Arduino loop (LVGL) owns core 1 on the S3's dual-core Xtensa.
#define CLOUD_CI_TASK_CORE 0

// Hard cap on the body we will buffer. per_page=1 with pull requests excluded
// is ~8 KB; anything an order of magnitude larger is a wrong endpoint, and
// buffering it would exhaust the heap.
#define CLOUD_CI_MAX_BODY 65536

static Preferences cloud_prefs;

static char cfg_repo[CLOUD_CI_REPO_MAX] = "";
static char cfg_token[CLOUD_CI_TOKEN_MAX] = "";
static bool cfg_enabled = true;
static bool cfg_insecure = false;
static uint32_t cfg_interval_s = CLOUD_CI_DEFAULT_INTERVAL_S;

static CloudCIState state = CLOUD_CI_STATE_IDLE;
static CloudCIResult published;   // main-loop-owned copy
static char published_error[64] = "";
static bool driving = false;
static bool update_pending = false;

// --- worker <-> main-loop handoff -----------------------------------------
static SemaphoreHandle_t result_mutex = NULL;
static TaskHandle_t worker_task = NULL;
static volatile bool poll_in_flight = false;
static bool shared_ready = false;      // guarded by result_mutex
static bool shared_ok = false;         // guarded by result_mutex
static CloudCIResult shared_result;    // guarded by result_mutex
static char shared_error[64] = "";     // guarded by result_mutex

// --- scheduling ------------------------------------------------------------
static unsigned long next_poll_at_ms = 0;
static bool poll_requested = false;
static uint32_t consecutive_failures = 0;
static bool primed = false;            // first result must not chime
static char last_conclusion[16] = "";
static int last_run_number = -1;

// ---------------------------------------------------------------------------
// Config persistence
// ---------------------------------------------------------------------------
static void load_config() {
    if (!cloud_prefs.begin(NVS_CLOUD_NS, true /* read-only */)) {
        strlcpy(cfg_repo, DEFAULT_REPO, sizeof(cfg_repo));
        return;
    }
    String repo = cloud_prefs.getString("repo", DEFAULT_REPO);
    String token = cloud_prefs.getString("token", "");
    cfg_enabled = cloud_prefs.getBool("enabled", true);
    cfg_insecure = cloud_prefs.getBool("insecure", false);
    cfg_interval_s = cloud_prefs.getUInt("interval", CLOUD_CI_DEFAULT_INTERVAL_S);
    cloud_prefs.end();

    strlcpy(cfg_repo, repo.c_str(), sizeof(cfg_repo));
    strlcpy(cfg_token, token.c_str(), sizeof(cfg_token));
    if (cfg_interval_s < CLOUD_CI_INTERVAL_MIN_S) cfg_interval_s = CLOUD_CI_INTERVAL_MIN_S;
    if (cfg_interval_s > CLOUD_CI_INTERVAL_MAX_S) cfg_interval_s = CLOUD_CI_INTERVAL_MAX_S;
}

static void save_string(const char* key, const char* value) {
    if (cloud_prefs.begin(NVS_CLOUD_NS, false)) {
        cloud_prefs.putString(key, value);
        cloud_prefs.end();
    }
}

static void save_bool(const char* key, bool value) {
    if (cloud_prefs.begin(NVS_CLOUD_NS, false)) {
        cloud_prefs.putBool(key, value);
        cloud_prefs.end();
    }
}

// ---------------------------------------------------------------------------
// Worker task: the only place that touches the network
// ---------------------------------------------------------------------------
static void publish(bool ok, const CloudCIResult* result, const char* error) {
    if (xSemaphoreTake(result_mutex, portMAX_DELAY) != pdTRUE) return;
    shared_ok = ok;
    if (result) {
        shared_result = *result;
    } else {
        memset(&shared_result, 0, sizeof(shared_result));
    }
    strlcpy(shared_error, error ? error : "", sizeof(shared_error));
    shared_ready = true;
    xSemaphoreGive(result_mutex);
}

// Extracts workflow_runs[0] from `body` using a parse filter, so only the six
// fields we render are ever materialised into the document.
static bool parse_latest_run(const String& body, CloudCIResult* out, char* err, size_t err_len) {
    JsonDocument filter;
    JsonObject run = filter["workflow_runs"][0].to<JsonObject>();
    run["name"] = true;
    run["status"] = true;
    run["conclusion"] = true;
    run["head_sha"] = true;
    run["head_branch"] = true;
    run["run_number"] = true;

    JsonDocument doc;
    DeserializationError jerr =
        deserializeJson(doc, body, DeserializationOption::Filter(filter));
    if (jerr) {
        snprintf(err, err_len, "Bad JSON: %s", jerr.c_str());
        return false;
    }

    JsonArray runs = doc["workflow_runs"].as<JsonArray>();
    if (runs.isNull() || runs.size() == 0) {
        snprintf(err, err_len, "No workflow runs");
        return false;
    }

    JsonObject latest = runs[0];
    memset(out, 0, sizeof(*out));
    strlcpy(out->workflow, latest["name"] | "Workflow", sizeof(out->workflow));
    strlcpy(out->status, latest["status"] | "unknown", sizeof(out->status));
    strlcpy(out->conclusion, latest["conclusion"] | "", sizeof(out->conclusion));
    strlcpy(out->branch, latest["head_branch"] | "-", sizeof(out->branch));
    // sizeof(out->sha) is 8, so strlcpy already truncates to the 7-char prefix.
    strlcpy(out->sha, latest["head_sha"] | "-", sizeof(out->sha));
    out->run_number = latest["run_number"] | 0;
    out->valid = true;
    return true;
}

static void do_poll() {
    char err[64] = "";

    WiFiClientSecure client;
    if (cfg_insecure) {
        client.setInsecure();
    } else {
        client.setCACert(GITHUB_ROOT_CAS);
    }
    client.setHandshakeTimeout(12);
    client.setTimeout(10);

    char url[CLOUD_CI_REPO_MAX + 96];
    snprintf(url, sizeof(url),
             "https://%s/repos/%s/actions/runs?per_page=1&exclude_pull_requests=true",
             GITHUB_HOST, cfg_repo);

    HTTPClient http;
    http.setUserAgent("Vitruvian-ESP32-S3");
    http.setConnectTimeout(10000);
    http.setTimeout(12000);
    http.setReuse(false);

    if (!http.begin(client, url)) {
        publish(false, NULL, "HTTP begin failed");
        return;
    }

    http.addHeader("Accept", "application/vnd.github+json");
    http.addHeader("X-GitHub-Api-Version", "2022-11-28");
    if (cfg_token[0] != '\0') {
        char auth[CLOUD_CI_TOKEN_MAX + 8];
        snprintf(auth, sizeof(auth), "Bearer %s", cfg_token);
        http.addHeader("Authorization", auth);
    }

    int code = http.GET();
    if (code <= 0) {
        // Negative codes are the client's own errors (connect refused, TLS
        // failure, timeout) rather than an HTTP status.
        snprintf(err, sizeof(err), "Net error %d", code);
        http.end();
        publish(false, NULL, err);
        return;
    }
    if (code == 401 || code == 403) {
        snprintf(err, sizeof(err), "HTTP %d (token/rate limit)", code);
        http.end();
        publish(false, NULL, err);
        return;
    }
    if (code != 200) {
        snprintf(err, sizeof(err), "HTTP %d", code);
        http.end();
        publish(false, NULL, err);
        return;
    }

    int size = http.getSize();
    if (size > CLOUD_CI_MAX_BODY) {
        snprintf(err, sizeof(err), "Body too large (%d B)", size);
        http.end();
        publish(false, NULL, err);
        return;
    }

    String body = http.getString();
    http.end();

    if (body.length() == 0) {
        publish(false, NULL, "Empty response");
        return;
    }

    CloudCIResult result;
    if (!parse_latest_run(body, &result, err, sizeof(err))) {
        publish(false, NULL, err);
        return;
    }
    publish(true, &result, "");
}

static void cloud_ci_task(void* arg) {
    (void)arg;
    for (;;) {
        // Blocks until cloud_ci_loop() notifies; costs no CPU while idle.
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        do_poll();
        poll_in_flight = false;
    }
}

// ---------------------------------------------------------------------------
// Main-loop side
// ---------------------------------------------------------------------------
void cloud_ci_init() {
    load_config();
    if (cfg_repo[0] == '\0') {
        strlcpy(cfg_repo, DEFAULT_REPO, sizeof(cfg_repo));
    }
    memset(&published, 0, sizeof(published));
    memset(&shared_result, 0, sizeof(shared_result));

    result_mutex = xSemaphoreCreateMutex();
    if (!result_mutex) {
        Serial.println("[CLOUD] Mutex alloc failed; poller disabled");
        return;
    }
    if (xTaskCreatePinnedToCore(cloud_ci_task, "cloud_ci", CLOUD_CI_TASK_STACK, NULL,
                                CLOUD_CI_TASK_PRIO, &worker_task,
                                CLOUD_CI_TASK_CORE) != pdPASS) {
        worker_task = NULL;
        Serial.println("[CLOUD] Worker task alloc failed; poller disabled");
        return;
    }
    Serial.printf("[CLOUD] Poller ready: repo=%s interval=%us token=%s\n", cfg_repo,
                  (unsigned)cfg_interval_s, cfg_token[0] ? "yes" : "no");
}

// Chimes on a conclusion transition only. A re-run that lands on the same
// conclusion still chimes (the run number changed); a poll that returns the
// identical run is silent.
static void announce(const CloudCIResult& result) {
    bool same_run = (result.run_number == last_run_number);
    bool same_conclusion = (strcmp(result.conclusion, last_conclusion) == 0);

    bool should_chime = primed && result.conclusion[0] != '\0' &&
                        !(same_run && same_conclusion);

    if (should_chime) {
        if (strcmp(result.conclusion, "success") == 0) {
            buzzer_play_ci_pass();
        } else if (strcmp(result.conclusion, "failure") == 0 ||
                   strcmp(result.conclusion, "timed_out") == 0 ||
                   strcmp(result.conclusion, "startup_failure") == 0) {
            buzzer_play_ci_fail();
        }
        // cancelled / skipped / neutral / action_required: shown, not sounded.
    }

    strlcpy(last_conclusion, result.conclusion, sizeof(last_conclusion));
    last_run_number = result.run_number;
    primed = true;
}

static void drain_worker_result() {
    if (!result_mutex) return;
    if (xSemaphoreTake(result_mutex, 0) != pdTRUE) return;

    bool ready = shared_ready;
    bool ok = shared_ok;
    CloudCIResult result = shared_result;
    char error[64];
    strlcpy(error, shared_error, sizeof(error));
    shared_ready = false;
    xSemaphoreGive(result_mutex);

    if (!ready) return;

    if (ok) {
        consecutive_failures = 0;
        published = result;
        published_error[0] = '\0';
        state = CLOUD_CI_STATE_OK;
        Serial.printf("[CLOUD] #%d %s %s/%s (%s)\n", result.run_number, result.workflow,
                      result.status, result.conclusion[0] ? result.conclusion : "-",
                      result.sha);
        announce(result);
    } else {
        consecutive_failures++;
        published.valid = false;
        strlcpy(published_error, error, sizeof(published_error));
        state = CLOUD_CI_STATE_ERROR;
        Serial.printf("[CLOUD] Poll failed (%u in a row): %s\n",
                      (unsigned)consecutive_failures, published_error);
    }
    update_pending = true;

    // Geometric backoff on failure, capped, so a dead endpoint costs one
    // request every 15 minutes rather than one a minute. The cap is a ceiling
    // on the GROWTH, never a floor: a configured interval longer than the cap
    // must not make failures poll more often than success does.
    unsigned long interval_ms = (unsigned long)cfg_interval_s * 1000UL;
    unsigned long delay_ms = interval_ms;
    if (consecutive_failures > 0) {
        unsigned long backoff =
            interval_ms << (consecutive_failures > 5 ? 5 : consecutive_failures);
        if (backoff > CLOUD_CI_BACKOFF_MAX_MS) backoff = CLOUD_CI_BACKOFF_MAX_MS;
        delay_ms = backoff > interval_ms ? backoff : interval_ms;
    }
    next_poll_at_ms = millis() + delay_ms;
}

void cloud_ci_loop(bool wifi_connected, bool host_streaming) {
    // Always drain first: a result that landed just as the Mac woke up still
    // belongs on the deck rather than being thrown away.
    drain_worker_result();

    bool should_run = cfg_enabled && wifi_connected && !host_streaming &&
                      cfg_repo[0] != '\0' && worker_task != NULL;

    if (!should_run) {
        if (driving) {
            driving = false;
            if (!poll_in_flight) state = CLOUD_CI_STATE_IDLE;
            Serial.println("[CLOUD] Standing down (host stream or Wi-Fi took over)");
        }
        return;
    }

    if (!driving) {
        driving = true;
        // Poll immediately on takeover so the deck is never blank for a minute.
        next_poll_at_ms = millis();
        Serial.printf("[CLOUD] Taking over the deck: polling %s\n", cfg_repo);
    }

    if (poll_in_flight) {
        state = CLOUD_CI_STATE_POLLING;
        return;
    }

    bool due = poll_requested || (long)(millis() - next_poll_at_ms) >= 0;
    if (!due) return;

    poll_requested = false;
    poll_in_flight = true;
    state = CLOUD_CI_STATE_POLLING;
    // Reschedule up front so a hung request cannot queue a backlog of polls.
    next_poll_at_ms = millis() + (unsigned long)cfg_interval_s * 1000UL;
    xTaskNotifyGive(worker_task);
}

void cloud_ci_request_poll() {
    poll_requested = true;
}

bool cloud_ci_take_update() {
    bool pending = update_pending;
    update_pending = false;
    return pending;
}

CloudCIState cloud_ci_get_state() {
    return state;
}

const CloudCIResult* cloud_ci_get_result() {
    return &published;
}

const char* cloud_ci_get_error() {
    return published_error;
}

bool cloud_ci_is_driving() {
    return driving;
}

void cloud_ci_set_repo(const char* owner_repo) {
    if (!owner_repo || owner_repo[0] == '\0') return;
    if (strcmp(owner_repo, cfg_repo) == 0) return;
    strlcpy(cfg_repo, owner_repo, sizeof(cfg_repo));
    save_string("repo", cfg_repo);
    // A new repo invalidates the transition history: the first result for it
    // primes silently instead of chiming about a build the user never watched.
    primed = false;
    last_conclusion[0] = '\0';
    last_run_number = -1;
    poll_requested = true;
}

const char* cloud_ci_get_repo() {
    return cfg_repo;
}

void cloud_ci_set_token(const char* token) {
    strlcpy(cfg_token, token ? token : "", sizeof(cfg_token));
    save_string("token", cfg_token);
    poll_requested = true;
}

bool cloud_ci_has_token() {
    return cfg_token[0] != '\0';
}

void cloud_ci_set_enabled(bool enabled) {
    if (enabled == cfg_enabled) return;
    cfg_enabled = enabled;
    save_bool("enabled", cfg_enabled);
}

bool cloud_ci_is_enabled() {
    return cfg_enabled;
}

void cloud_ci_set_interval_seconds(uint32_t seconds) {
    if (seconds < CLOUD_CI_INTERVAL_MIN_S) seconds = CLOUD_CI_INTERVAL_MIN_S;
    if (seconds > CLOUD_CI_INTERVAL_MAX_S) seconds = CLOUD_CI_INTERVAL_MAX_S;
    cfg_interval_s = seconds;
    if (cloud_prefs.begin(NVS_CLOUD_NS, false)) {
        cloud_prefs.putUInt("interval", cfg_interval_s);
        cloud_prefs.end();
    }
}

uint32_t cloud_ci_get_interval_seconds() {
    return cfg_interval_s;
}

void cloud_ci_set_insecure(bool insecure) {
    if (insecure == cfg_insecure) return;
    cfg_insecure = insecure;
    save_bool("insecure", cfg_insecure);
}

bool cloud_ci_is_insecure() {
    return cfg_insecure;
}
