# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Test suite for Direction 2: the autonomous cloud CI/CD monitor.

Covers:
1. The GitHub Actions request the poller puts on the wire: endpoint, query,
   headers, and the authenticated vs anonymous split.
2. Extraction of workflow_runs[0] from a realistic Actions payload, including
   the 7-char head_sha prefix the display has room for.
3. The conclusion-transition state machine that decides pass/fail/silence, and
   the mute that overrides it.
4. Buzzer melody note tables and the non-blocking sequencer.
5. Poll scheduling: activation window, interval clamping, failure backoff.
6. Firmware source invariants: TLS trust anchors, the FreeRTOS worker that
   keeps TLS off the LVGL task, and the NVS config keys.
"""

import json
import os
import re
import unittest

SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../src"))


def read_source(*parts) -> str:
    """Reads a firmware source file VERBATIM -- see tests/test_net_telemetry.py."""
    return open(os.path.join(*parts), encoding="utf-8").read()


# ---------------------------------------------------------------------------
# Wire model: the request cloud_ci.cpp builds
# ---------------------------------------------------------------------------
GITHUB_HOST = "api.github.com"
DEFAULT_REPO = "VitruvianSoftware/vitruvian-core"
USER_AGENT = "Vitruvian-ESP32-S3"


def build_poll_url(repo: str = DEFAULT_REPO) -> str:
    return (
        f"https://{GITHUB_HOST}/repos/{repo}/actions/runs"
        "?per_page=1&exclude_pull_requests=true"
    )


def build_poll_headers(token: str = "") -> dict:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


class TestPollRequest(unittest.TestCase):
    """The exact request the device sends to GitHub."""

    def test_endpoint_targets_the_latest_run_only(self):
        url = build_poll_url()
        self.assertTrue(url.startswith("https://api.github.com/repos/"))
        self.assertIn("/actions/runs?", url)
        self.assertIn("per_page=1", url)

    def test_pull_requests_are_excluded_from_the_payload(self):
        # The runs payload embeds every associated PR object; excluding them is
        # what keeps the body inside the device's heap budget.
        self.assertIn("exclude_pull_requests=true", build_poll_url())

    def test_custom_repo_is_substituted(self):
        self.assertIn(
            "/repos/octocat/hello-world/", build_poll_url("octocat/hello-world")
        )

    def test_anonymous_request_carries_no_authorization(self):
        self.assertNotIn("Authorization", build_poll_headers())

    def test_token_becomes_a_bearer_header(self):
        self.assertEqual(
            build_poll_headers("ghp_example")["Authorization"], "Bearer ghp_example"
        )

    def test_required_github_headers_are_present(self):
        headers = build_poll_headers()
        self.assertEqual(headers["User-Agent"], USER_AGENT)
        self.assertEqual(headers["Accept"], "application/vnd.github+json")

    def test_firmware_builds_the_same_request(self):
        src = read_source(SRC_DIR, "cloud_ci.cpp")
        self.assertIn(
            '"https://%s/repos/%s/actions/runs?per_page=1&exclude_pull_requests=true"',
            src,
        )
        self.assertIn(f'http.setUserAgent("{USER_AGENT}")', src)
        self.assertIn('http.addHeader("Accept", "application/vnd.github+json")', src)
        self.assertIn('snprintf(auth, sizeof(auth), "Bearer %s", cfg_token)', src)
        self.assertIn(f'GITHUB_HOST = "{GITHUB_HOST}"', src)


# ---------------------------------------------------------------------------
# Response model: the fields parse_latest_run() lifts out
# ---------------------------------------------------------------------------
SHA_DISPLAY_LEN = 7

ACTIONS_RESPONSE = {
    "total_count": 4821,
    "workflow_runs": [
        {
            "id": 33917860096,
            "name": "iot-esp32-s3",
            "node_id": "WFR_kwLOA",
            "head_branch": "feat/esp32-s3-untethered-and-cloud-monitor",
            "head_sha": "4e4fbf45c0a1b2c3d4e5f60718293a4b5c6d7e8f",
            "run_number": 1187,
            "event": "pull_request",
            "status": "completed",
            "conclusion": "success",
            "workflow_id": 88123,
            "url": "https://api.github.com/repos/VitruvianSoftware/vitruvian-core/actions/runs/33917860096",
        }
    ],
}


def parse_latest_run(body: str):
    """Mirrors cloud_ci.cpp's filtered ArduinoJson extraction."""
    doc = json.loads(body)
    runs = doc.get("workflow_runs") or []
    if not runs:
        return None
    run = runs[0]
    return {
        "workflow": run.get("name") or "Workflow",
        "status": run.get("status") or "unknown",
        # A run in flight has conclusion: null -- the C side coerces that to "".
        "conclusion": run.get("conclusion") or "",
        "branch": run.get("head_branch") or "-",
        "sha": (run.get("head_sha") or "-")[:SHA_DISPLAY_LEN],
        "run_number": run.get("run_number") or 0,
        "valid": True,
    }


class TestResponseParsing(unittest.TestCase):
    """Field extraction from an Actions runs payload."""

    def test_extracts_the_documented_fields(self):
        run = parse_latest_run(json.dumps(ACTIONS_RESPONSE))
        self.assertEqual(run["workflow"], "iot-esp32-s3")
        self.assertEqual(run["status"], "completed")
        self.assertEqual(run["conclusion"], "success")
        self.assertEqual(run["run_number"], 1187)

    def test_head_sha_is_truncated_to_seven_chars(self):
        run = parse_latest_run(json.dumps(ACTIONS_RESPONSE))
        self.assertEqual(run["sha"], "4e4fbf4")
        self.assertEqual(len(run["sha"]), SHA_DISPLAY_LEN)

    def test_firmware_sha_buffer_enforces_the_same_prefix(self):
        src = read_source(SRC_DIR, "cloud_ci.h")
        # strlcpy into char sha[8] truncates to 7 chars + NUL.
        self.assertIn(f"char sha[{SHA_DISPLAY_LEN + 1}]", src)

    def test_in_flight_run_has_an_empty_conclusion(self):
        payload = json.loads(json.dumps(ACTIONS_RESPONSE))
        payload["workflow_runs"][0]["status"] = "in_progress"
        payload["workflow_runs"][0]["conclusion"] = None
        run = parse_latest_run(json.dumps(payload))
        self.assertEqual(run["status"], "in_progress")
        self.assertEqual(run["conclusion"], "")

    def test_empty_run_list_yields_nothing(self):
        self.assertIsNone(parse_latest_run(json.dumps({"workflow_runs": []})))

    def test_branch_falls_back_when_absent(self):
        payload = {"workflow_runs": [{"name": "ci"}]}
        run = parse_latest_run(json.dumps(payload))
        self.assertEqual(run["branch"], "-")
        self.assertEqual(run["run_number"], 0)

    def test_firmware_filters_to_exactly_these_fields(self):
        src = read_source(SRC_DIR, "cloud_ci.cpp")
        for field in (
            "name",
            "status",
            "conclusion",
            "head_sha",
            "head_branch",
            "run_number",
        ):
            self.assertIn(f'run["{field}"] = true;', src)


# ---------------------------------------------------------------------------
# Chime state machine (cloud_ci.cpp: announce())
# ---------------------------------------------------------------------------
CHIME_NONE = "none"
CHIME_PASS = "pass"
CHIME_FAIL = "fail"

FAIL_CONCLUSIONS = ("failure", "timed_out", "startup_failure")


class ChimeModel:
    """Mirrors announce(): chime on a conclusion transition, never on the first."""

    def __init__(self, muted: bool = False):
        self.muted = muted
        self.primed = False
        self.last_conclusion = ""
        self.last_run_number = -1

    def observe(self, conclusion: str, run_number: int) -> str:
        same_run = run_number == self.last_run_number
        same_conclusion = conclusion == self.last_conclusion
        chime = CHIME_NONE

        if self.primed and conclusion and not (same_run and same_conclusion):
            if conclusion == "success":
                chime = CHIME_PASS
            elif conclusion in FAIL_CONCLUSIONS:
                chime = CHIME_FAIL

        self.last_conclusion = conclusion
        self.last_run_number = run_number
        self.primed = True
        return CHIME_NONE if self.muted else chime


class TestChimeTransitions(unittest.TestCase):
    """When the buzzer should and should not sound."""

    def setUp(self):
        self.model = ChimeModel()

    def test_first_poll_after_boot_is_silent(self):
        # Otherwise every power-on announces a build the user already knows about.
        self.assertEqual(self.model.observe("success", 100), CHIME_NONE)

    def test_in_progress_to_success_chimes_pass(self):
        self.model.observe("", 101)
        self.assertEqual(self.model.observe("success", 101), CHIME_PASS)

    def test_in_progress_to_failure_chimes_fail(self):
        self.model.observe("", 101)
        self.assertEqual(self.model.observe("failure", 101), CHIME_FAIL)

    def test_failure_to_success_chimes_pass(self):
        self.model.observe("failure", 101)
        self.assertEqual(self.model.observe("success", 102), CHIME_PASS)

    def test_success_to_failure_chimes_fail(self):
        self.model.observe("success", 101)
        self.assertEqual(self.model.observe("failure", 102), CHIME_FAIL)

    def test_repeated_poll_of_the_same_run_is_silent(self):
        self.model.observe("success", 101)
        self.model.observe("success", 101)
        for _ in range(10):
            self.assertEqual(self.model.observe("success", 101), CHIME_NONE)

    def test_a_new_run_with_the_same_conclusion_still_chimes(self):
        # Two green builds in a row are two events, not one.
        self.model.observe("success", 101)
        self.assertEqual(self.model.observe("success", 102), CHIME_PASS)

    def test_timed_out_and_startup_failure_sound_like_a_failure(self):
        for conclusion in ("timed_out", "startup_failure"):
            model = ChimeModel()
            model.observe("success", 1)
            self.assertEqual(model.observe(conclusion, 2), CHIME_FAIL, conclusion)

    def test_cancelled_and_skipped_are_shown_but_not_sounded(self):
        for conclusion in ("cancelled", "skipped", "neutral", "action_required"):
            model = ChimeModel()
            model.observe("success", 1)
            self.assertEqual(model.observe(conclusion, 2), CHIME_NONE, conclusion)

    def test_a_run_still_in_flight_never_chimes(self):
        self.model.observe("success", 101)
        self.assertEqual(self.model.observe("", 102), CHIME_NONE)

    def test_mute_silences_every_transition(self):
        model = ChimeModel(muted=True)
        model.observe("", 101)
        self.assertEqual(model.observe("success", 101), CHIME_NONE)
        self.assertEqual(model.observe("failure", 102), CHIME_NONE)

    def test_changing_repo_reprimes_so_the_first_result_is_silent(self):
        src = read_source(SRC_DIR, "cloud_ci.cpp")
        set_repo = src[src.index("void cloud_ci_set_repo(") :]
        set_repo = set_repo[: set_repo.index("\n}")]
        self.assertIn("primed = false;", set_repo)
        self.assertIn("last_run_number = -1;", set_repo)

    def test_firmware_maps_conclusions_to_the_same_melodies(self):
        src = read_source(SRC_DIR, "cloud_ci.cpp")
        announce = src[src.index("static void announce(") :]
        announce = announce[: announce.index("\n}")]
        self.assertIn('strcmp(result.conclusion, "success") == 0', announce)
        self.assertIn("buzzer_play_ci_pass();", announce)
        self.assertIn("buzzer_play_ci_fail();", announce)
        for conclusion in FAIL_CONCLUSIONS:
            self.assertIn(f'"{conclusion}"', announce)


# ---------------------------------------------------------------------------
# Buzzer melodies (buzzer.cpp)
# ---------------------------------------------------------------------------
CI_PASS_NOTES = [(523, 80), (659, 80), (784, 120), (1046, 200)]  # C5 E5 G5 C6
CI_FAIL_NOTES = [(698, 150), (587, 150), (494, 300)]  # F5 D5 B4
CLICK_NOTE = (1000, 20)


def parse_note_table(src: str, symbol: str):
    """Pulls the `{freq, dur}` pairs out of a static Note[] initialiser."""
    body = src[src.index(f"kNote_placeholder") :] if False else src
    start = body.index(f"static const Note {symbol}[]")
    end = body.index("};", start)
    return [
        (int(f), int(d)) for f, d in re.findall(r"\{(\d+),\s*(\d+)\}", body[start:end])
    ]


class TestBuzzerMelodies(unittest.TestCase):
    """Pitch progressions and the non-blocking sequencer."""

    def setUp(self):
        self.src = read_source(SRC_DIR, "buzzer.cpp")

    def test_pass_chime_is_an_ascending_c_major_arpeggio(self):
        self.assertEqual(parse_note_table(self.src, "kPass"), CI_PASS_NOTES)
        freqs = [f for f, _ in CI_PASS_NOTES]
        self.assertEqual(freqs, sorted(freqs))

    def test_fail_chime_descends(self):
        self.assertEqual(parse_note_table(self.src, "kFail"), CI_FAIL_NOTES)
        freqs = [f for f, _ in CI_FAIL_NOTES]
        self.assertEqual(freqs, sorted(freqs, reverse=True))

    def test_pass_and_fail_are_audibly_distinct(self):
        self.assertNotEqual(CI_PASS_NOTES[0][0], CI_FAIL_NOTES[0][0])

    def test_click_is_1khz_for_20ms(self):
        self.assertEqual(parse_note_table(self.src, "kClick"), [CLICK_NOTE])

    def test_note_buffer_fits_the_longest_melody_with_its_rests(self):
        header = read_source(SRC_DIR, "buzzer.h")
        capacity = int(re.search(r"#define BUZZER_MAX_NOTES (\d+)", header).group(1))
        needed = len(CI_PASS_NOTES) * 2 - 1  # notes interleaved with rests
        self.assertGreaterEqual(capacity, needed)

    def test_playback_is_non_blocking(self):
        # A blocking chime would stall lv_timer_handler() for ~600 ms and freeze
        # the carousel mid-swipe.
        self.assertNotIn("delay(", self.src)
        self.assertIn("void buzzer_loop()", self.src)
        self.assertIn("note_ends_at_ms", self.src)

    def test_pass_chime_total_duration_stays_under_a_second(self):
        gap = int(re.search(r"NOTE_GAP_MS = (\d+)", self.src).group(1))
        total = sum(d for _, d in CI_PASS_NOTES) + gap * (len(CI_PASS_NOTES) - 1)
        self.assertLess(total, 1000)

    def test_muting_cuts_an_in_flight_melody(self):
        set_muted = self.src[self.src.index("void buzzer_set_muted(") :]
        set_muted = set_muted[: set_muted.index("\n}")]
        self.assertIn("playing = false;", set_muted)
        self.assertIn("silence();", set_muted)

    def test_mute_is_persisted_under_the_documented_nvs_key(self):
        self.assertIn('NVS_SETTINGS_NS = "settings"', self.src)
        self.assertIn('NVS_MUTED_KEY = "chimes_muted"', self.src)

    def test_buzzer_owns_the_ledc_channel_the_backlight_does_not(self):
        ui = read_source(SRC_DIR, "ui.cpp")
        backlight_ch = int(re.search(r"BL_PWM_CH = (\d+)", ui).group(1))
        buzzer_ch = int(re.search(r"BUZZER_LEDC_CH = (\d+)", self.src).group(1))
        self.assertNotEqual(backlight_ch, buzzer_ch)

    def test_haptic_click_routes_through_the_buzzer_engine(self):
        mac_hid = read_source(SRC_DIR, "mac_hid.cpp")
        self.assertIn("buzzer_play_click();", mac_hid)
        # A raw tone() would grab a second LEDC channel behind the engine's back.
        self.assertNotIn("tone(BUZZER_PIN", mac_hid)


# ---------------------------------------------------------------------------
# Scheduling (cloud_ci.cpp)
# ---------------------------------------------------------------------------
INTERVAL_MIN_S = 15
INTERVAL_MAX_S = 3600
DEFAULT_INTERVAL_S = 60
BACKOFF_MAX_MS = 15 * 60 * 1000
CLOUD_TAKEOVER_IDLE_MS = 15000


def clamp_interval(seconds: int) -> int:
    return max(INTERVAL_MIN_S, min(INTERVAL_MAX_S, seconds))


def backoff_ms(interval_s: int, consecutive_failures: int) -> int:
    interval_ms = interval_s * 1000
    if consecutive_failures == 0:
        return interval_ms
    shift = min(consecutive_failures, 5)
    # The cap bounds the growth; it must never shorten a deliberately long
    # interval into a faster poll than the healthy path uses.
    return max(interval_ms, min(interval_ms << shift, BACKOFF_MAX_MS))


class TestPollScheduling(unittest.TestCase):
    """Activation, cadence, and what happens when GitHub is unreachable."""

    def test_default_interval_is_60s(self):
        self.assertEqual(DEFAULT_INTERVAL_S, 60)
        self.assertIn(
            "#define CLOUD_CI_DEFAULT_INTERVAL_S 60UL",
            read_source(SRC_DIR, "cloud_ci.cpp"),
        )

    def test_interval_is_clamped_at_both_ends(self):
        self.assertEqual(clamp_interval(1), INTERVAL_MIN_S)
        self.assertEqual(clamp_interval(99999), INTERVAL_MAX_S)
        self.assertEqual(clamp_interval(120), 120)

    def test_backoff_grows_then_caps(self):
        self.assertEqual(backoff_ms(60, 0), 60_000)
        self.assertEqual(backoff_ms(60, 1), 120_000)
        self.assertEqual(backoff_ms(60, 2), 240_000)
        self.assertEqual(backoff_ms(60, 9), BACKOFF_MAX_MS)

    def test_backoff_growth_is_capped_at_fifteen_minutes(self):
        for failures in range(0, 40):
            self.assertLessEqual(backoff_ms(60, failures), BACKOFF_MAX_MS)

    def test_failure_never_polls_faster_than_the_configured_interval(self):
        # A 1-hour interval with the 15-minute cap applied naively would make
        # a broken endpoint get polled FOUR TIMES more often than a healthy one.
        for failures in range(0, 40):
            self.assertGreaterEqual(backoff_ms(3600, failures), 3_600_000)

    def test_poller_only_activates_after_the_host_goes_quiet(self):
        main_cpp = read_source(SRC_DIR, "main.cpp")
        self.assertIn(
            f"#define CLOUD_TAKEOVER_IDLE_MS {CLOUD_TAKEOVER_IDLE_MS}UL", main_cpp
        )
        self.assertIn("packet_router_host_active(CLOUD_TAKEOVER_IDLE_MS)", main_cpp)
        self.assertIn("cloud_ci_loop(wifi_up, host_streaming)", main_cpp)

    def test_takeover_window_is_longer_than_the_link_badge_window(self):
        router_h = read_source(SRC_DIR, "packet_router.h")
        link_window = int(
            re.search(r"#define LINK_ACTIVE_WINDOW_MS (\d+)UL", router_h).group(1)
        )
        # The badge must fall back to standby before the poller steps in, or the
        # deck would flip to CLOUD while the header still claimed a live host.
        self.assertGreater(CLOUD_TAKEOVER_IDLE_MS, link_window)

    def test_a_hung_request_cannot_queue_a_backlog(self):
        src = read_source(SRC_DIR, "cloud_ci.cpp")
        loop_body = src[src.index("void cloud_ci_loop(") :]
        self.assertIn("if (poll_in_flight) {", loop_body)
        self.assertIn("next_poll_at_ms = millis() +", loop_body)

    def test_a_daemon_packet_takes_the_deck_back(self):
        ui = read_source(SRC_DIR, "ui.cpp")
        agent_ci = ui[ui.index("void ui_update_agent_ci(") :]
        agent_ci = agent_ci[: agent_ci.index("\n}")]
        self.assertIn("set_deck_source(false);", agent_ci)


class TestPollerHardening(unittest.TestCase):
    """TLS trust, thread isolation, and configuration persistence."""

    def setUp(self):
        self.src = read_source(SRC_DIR, "cloud_ci.cpp")

    def test_certificates_are_verified_by_default(self):
        # setInsecure() as the default would ship a Bearer token over an
        # unauthenticated TLS session.
        self.assertIn("client.setCACert(GITHUB_ROOT_CAS)", self.src)
        self.assertIn('cfg_insecure = cloud_prefs.getBool("insecure", false)', self.src)

    def test_trust_anchors_are_real_pem_certificates(self):
        ca = read_source(SRC_DIR, "github_ca.h")
        self.assertEqual(ca.count("-----BEGIN CERTIFICATE-----"), 3)
        self.assertEqual(
            ca.count("-----BEGIN CERTIFICATE-----"),
            ca.count("-----END CERTIFICATE-----"),
        )

    def test_tls_runs_off_the_lvgl_task(self):
        # A TLS handshake blocks for hundreds of ms; on the Arduino loop task
        # that is a visible carousel stutter.
        self.assertIn("xTaskCreatePinnedToCore(cloud_ci_task", self.src)
        self.assertIn("ulTaskNotifyTake(pdTRUE, portMAX_DELAY)", self.src)
        self.assertIn("#define CLOUD_CI_TASK_CORE 0", self.src)

    def test_results_cross_between_tasks_under_a_mutex(self):
        self.assertIn("xSemaphoreCreateMutex()", self.src)
        self.assertIn("xSemaphoreTake(result_mutex", self.src)
        self.assertIn("xSemaphoreGive(result_mutex)", self.src)

    def test_ui_and_buzzer_are_only_touched_from_the_main_loop(self):
        # do_poll() runs on the worker; everything it produces goes through
        # publish() and is consumed by drain_worker_result() on the main loop.
        do_poll = self.src[self.src.index("static void do_poll()") :]
        do_poll = do_poll[: do_poll.index("\nstatic void cloud_ci_task")]
        self.assertNotIn("buzzer_play", do_poll)
        self.assertNotIn("ui_", do_poll)

    def test_response_size_is_bounded(self):
        self.assertIn("#define CLOUD_CI_MAX_BODY 65536", self.src)
        self.assertIn("if (size > CLOUD_CI_MAX_BODY)", self.src)

    def test_auth_and_rate_limit_failures_are_reported_distinctly(self):
        self.assertIn("code == 401 || code == 403", self.src)
        self.assertIn("token/rate limit", self.src)

    def test_config_is_persisted_in_its_own_nvs_namespace(self):
        self.assertIn('NVS_CLOUD_NS = "cloud_ci"', self.src)
        for key in ('"repo"', '"token"', '"enabled"', '"interval"', '"insecure"'):
            self.assertIn(key, self.src)

    def test_default_repo_is_this_monorepo(self):
        self.assertIn(f'DEFAULT_REPO = "{DEFAULT_REPO}"', self.src)

    def test_repo_and_token_are_settable_over_the_wire(self):
        router = read_source(SRC_DIR, "packet_router.cpp")
        self.assertIn('strcmp(cmd, "cloud_config") == 0', router)
        self.assertIn("cloud_ci_set_repo(", router)
        self.assertIn("cloud_ci_set_token(", router)

    def test_token_never_reaches_the_serial_log(self):
        # The USB console is readable by anything on the bus, and the log is
        # what gets pasted into bug reports.
        for call in re.findall(r"Serial\.print[a-z]*\((.*?)\);", self.src, re.S):
            if "cfg_token" in call:
                # Only ever logged as a yes/no presence flag.
                self.assertIn('"yes" : "no"', call)

        router = read_source(SRC_DIR, "packet_router.cpp")
        for call in re.findall(r"Serial\.print[a-z]*\((.*?)\);", router, re.S):
            self.assertNotIn('doc["token"]', call)
            if "token" in call:
                self.assertIn('"yes" : "no"', call)


# ---------------------------------------------------------------------------
# Settings deck: the Audio Chimes card (ui.cpp)
# ---------------------------------------------------------------------------
SETTINGS_VIEWPORT_W = 240


def parse_card(src: str, symbol: str):
    """Reads back the (x, y, w, h) an lv_obj card was laid out with."""
    size = re.search(rf"lv_obj_set_size\({symbol}, (\d+), (\d+)\);", src)
    pos = re.search(rf"lv_obj_set_pos\({symbol}, (\d+), (\d+)\);", src)
    return (
        int(pos.group(1)),
        int(pos.group(2)),
        int(size.group(1)),
        int(size.group(2)),
    )


class TestAudioChimesToggle(unittest.TestCase):
    """The Settings deck switch that drives buzzer_set_muted()."""

    def setUp(self):
        self.ui = read_source(SRC_DIR, "ui.cpp")

    def test_switch_drives_the_buzzer_mute(self):
        cb = self.ui[self.ui.index("static void sw_chimes_toggle_cb(") :]
        cb = cb[: cb.index("\n}")]
        # Checked = audible, so the persisted flag is the inverse.
        self.assertIn("buzzer_set_muted(!checked);", cb)

    def test_initial_state_reflects_persisted_nvs_value(self):
        self.assertIn("if (!buzzer_is_muted()) {", self.ui)
        self.assertIn("lv_obj_add_state(sw_chimes, LV_STATE_CHECKED);", self.ui)

    def test_card_stays_inside_the_deck_width(self):
        x, y, w, h = parse_card(self.ui, "card_audio")
        self.assertLessEqual(x + w, SETTINGS_VIEWPORT_W)
        self.assertGreaterEqual(x, 0)

    def test_card_does_not_overlap_the_device_info_card(self):
        _, audio_y, _, audio_h = parse_card(self.ui, "card_audio")
        _, info_y, _, info_h = parse_card(self.ui, "card_info")
        self.assertGreaterEqual(audio_y, info_y + info_h)

    def test_bottom_hint_clears_the_new_card(self):
        _, audio_y, _, audio_h = parse_card(self.ui, "card_audio")
        hint_y = int(
            re.search(r"lv_obj_set_pos\(hint_back, 0, (\d+)\);", self.ui).group(1)
        )
        self.assertGreaterEqual(hint_y, audio_y + audio_h)

    def test_settings_deck_scrolls_vertically_to_reach_it(self):
        # The card stack is taller than the 280 px panel, so the tile must be
        # scrollable or the toggle is simply unreachable.
        self.assertIn("lv_obj_set_scroll_dir(t3, LV_DIR_VER);", self.ui)
        _, audio_y, _, audio_h = parse_card(self.ui, "card_audio")
        self.assertGreater(audio_y + audio_h, 280)


if __name__ == "__main__":
    unittest.main()
