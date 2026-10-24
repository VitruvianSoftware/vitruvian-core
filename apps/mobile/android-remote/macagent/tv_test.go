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

package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

type recordedTVCall struct {
	name string
	args []string
}

type tvTestHarness struct {
	tv           *tvController
	store        *Store
	ts           *httptest.Server
	token        string
	calls        []recordedTVCall
	adbPath      string
	statusOut    string
	statusStderr string
	statusErr    error
	connectOut   string
}

func newTestTV(t *testing.T) *tvTestHarness {
	t.Helper()
	dir := t.TempDir()
	store := NewStore(t.TempDir())
	tok, err := store.EnsureToken()
	if err != nil {
		t.Fatal(err)
	}
	h := &tvTestHarness{
		store:      store,
		token:      tok,
		adbPath:    "/opt/homebrew/bin/adb",
		connectOut: "connected to 192.168.86.31:5555\n",
		statusOut: "  mWakefulness=Awake\n" +
			"  mCurrentFocus=Window{123 u0 com.spocky.projengmenu/com.spocky.projengmenu.ui.home.MainActivity}\n" +
			"MemTotal:        3014656 kB\n" +
			"MemAvailable:    1048576 kB\n",
	}
	h.tv = &tvController{
		configPath:       filepath.Join(dir, "tv.json"),
		legacyConfigPath: filepath.Join(dir, "storage.json"),
		findAdb:          func() string { return h.adbPath },
		run: func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error) {
			h.calls = append(h.calls, recordedTVCall{name: name, args: append([]string(nil), args...)})
			if len(args) > 0 && args[0] == "connect" {
				return h.connectOut, "", nil
			}
			if len(args) >= 4 && args[2] == "shell" && strings.Contains(args[3], "MemAvailable") {
				if h.statusErr != nil {
					stderr := h.statusStderr
					if stderr == "" {
						stderr = "device offline"
					}
					return "", stderr, h.statusErr
				}
				return h.statusOut, "", nil
			}
			if len(args) >= 4 && args[2] == "shell" && strings.Contains(args[3], "dumpsys power | grep mWakefulness=") {
				return h.statusOut, "", nil
			}
			return "ok\n", "", nil
		},
	}
	srv := &server{
		sampler: NewSampler(time.Second, "", "", nil, nil),
		store:   store,
		tv:      h.tv,
		phone:   newPhoneBridge(),
	}
	mux := http.NewServeMux()
	srv.tvRoutes(mux)
	h.ts = httptest.NewServer(mux)
	t.Cleanup(h.ts.Close)
	return h
}

func getTVState(t *testing.T, ts *httptest.Server) tvState {
	t.Helper()
	resp, err := http.Get(ts.URL + "/v1/tv")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET /v1/tv: %d", resp.StatusCode)
	}
	var st tvState
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		t.Fatal(err)
	}
	return st
}

func TestTVStateWhenAdbIsMissing(t *testing.T) {
	h := newTestTV(t)
	h.adbPath = ""

	st := getTVState(t, h.ts)
	if st.Available {
		t.Fatalf("expected available=false when adb is missing, got %+v", st)
	}
	if !strings.Contains(st.Reason, "adb") {
		t.Errorf("reason = %q, want mention of adb", st.Reason)
	}
	if st.Address != defaultTVAddress {
		t.Errorf("address = %q, want %q", st.Address, defaultTVAddress)
	}
}

func TestTVStateParsesForegroundAppsAndMemory(t *testing.T) {
	h := newTestTV(t)

	st := getTVState(t, h.ts)
	if !st.Available || !st.Connected || !st.Awake || st.Dreaming {
		t.Fatalf("unexpected state flags: %+v", st)
	}
	if st.Foreground != "Projectivy Home" {
		t.Errorf("foreground = %q, want Projectivy Home", st.Foreground)
	}
	if st.MemAvailableMB != 1024 {
		t.Errorf("mem_available_mb = %d, want 1024", st.MemAvailableMB)
	}

	cases := []struct {
		name         string
		out          string
		wantAwake    bool
		wantDreaming bool
		wantFG       string
	}{
		{
			name:         "SmartTube",
			out:          "mWakefulness=Awake\nmCurrentFocus=Window{1 u0 com.liskovsoft.smarttubetv.beta}\nMemAvailable: 524288 kB\n",
			wantAwake:    true,
			wantDreaming: false,
			wantFG:       "SmartTube 4K",
		},
		{
			name:         "AerialViews dreaming",
			out:          "mWakefulness=Dreaming\nmCurrentFocus=Window{1 u0 com.fourchars.lmp}\n",
			wantAwake:    false,
			wantDreaming: true,
			wantFG:       "AerialViews 4K",
		},
		{
			name:         "Disney+",
			out:          "mWakefulness=Awake\nmCurrentFocus=Window{1 u0 com.disney.disneyplus}\n",
			wantAwake:    true,
			wantDreaming: false,
			wantFG:       "Disney+",
		},
		{
			name:         "Netflix",
			out:          "mWakefulness=Awake\nmCurrentFocus=Window{1 u0 com.netflix.ninja}\n",
			wantAwake:    true,
			wantDreaming: false,
			wantFG:       "Netflix",
		},
		{
			name:         "Standby",
			out:          "mWakefulness=Asleep\n",
			wantAwake:    false,
			wantDreaming: false,
			wantFG:       "Standby",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h.statusOut = tc.out
			got := getTVState(t, h.ts)
			if got.Awake != tc.wantAwake || got.Dreaming != tc.wantDreaming || got.Foreground != tc.wantFG {
				t.Errorf("got awake=%v dreaming=%v fg=%q, want %v/%v/%q",
					got.Awake, got.Dreaming, got.Foreground, tc.wantAwake, tc.wantDreaming, tc.wantFG)
			}
		})
	}
}

func TestTVStateWhenDisconnected(t *testing.T) {
	h := newTestTV(t)
	h.connectOut = "failed to connect to 192.168.86.31:5555"
	h.statusErr = errors.New("exit status 1")

	st := getTVState(t, h.ts)
	if !st.Available || st.Connected {
		t.Fatalf("expected available=true connected=false, got %+v", st)
	}
	if st.Foreground != "Standby" {
		t.Errorf("foreground = %q, want Standby", st.Foreground)
	}
	if st.Reason == "" {
		t.Error("expected non-empty reason when disconnected")
	}

	h.statusStderr = "adb: device unauthorized.\nThis adb server's $ADB_VENDOR_KEYS is not set"
	st = getTVState(t, h.ts)
	if !strings.Contains(st.Reason, "TV unauthorized") {
		t.Errorf("reason = %q, want clean TV unauthorized message", st.Reason)
	}
}

func TestTVAddressFallbackAndSetAddress(t *testing.T) {
	h := newTestTV(t)

	// Legacy storage.json fallback when tv.json does not exist yet.
	if err := os.WriteFile(h.tv.legacyConfigPath, []byte(`{"tvAddress":"192.168.86.99:5555"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := getTVState(t, h.ts).Address; got != "192.168.86.99:5555" {
		t.Fatalf("legacy address = %q, want 192.168.86.99:5555", got)
	}

	// Unauthenticated POST is rejected.
	unauth := postJSON(t, h.ts, "/v1/tv", "", `{"action":"set_address","address":"192.168.86.42:5555"}`)
	unauth.Body.Close()
	if unauth.StatusCode != http.StatusUnauthorized {
		t.Fatalf("unauthenticated POST /v1/tv = %d, want 401", unauth.StatusCode)
	}

	// Valid set_address persists to tv.json and overrides legacy storage.json.
	resp := postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"set_address","address":"192.168.86.42:5555"}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("set_address status = %d, want 200", resp.StatusCode)
	}
	var st tvState
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		t.Fatal(err)
	}
	if st.Address != "192.168.86.42:5555" {
		t.Errorf("st.Address = %q, want 192.168.86.42:5555", st.Address)
	}

	// Invalid addresses are rejected with 400.
	for _, bad := range []string{"", "192.168.86.42", "bad host:5555", "192.168.86.42:99999"} {
		r := postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"set_address","address":"`+bad+`"}`)
		r.Body.Close()
		if r.StatusCode != http.StatusBadRequest {
			t.Errorf("set_address(%q) = %d, want 400", bad, r.StatusCode)
		}
	}
}

func TestTVActionsDispatchExpectedAdbCommands(t *testing.T) {
	h := newTestTV(t)

	// 1. toggle_power when Awake -> KEYCODE_SLEEP
	h.calls = nil
	resp := postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"toggle_power"}`)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("toggle_power(awake) = %d", resp.StatusCode)
	}
	if !hasArgs(h.calls, "shell", "input", "keyevent", "KEYCODE_SLEEP") {
		t.Errorf("expected KEYCODE_SLEEP when awake, calls: %+v", h.calls)
	}

	// 2. toggle_power when Asleep -> KEYCODE_WAKEUP
	h.statusOut = "mWakefulness=Asleep\n"
	h.calls = nil
	resp = postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"toggle_power"}`)
	resp.Body.Close()
	if !hasArgs(h.calls, "shell", "input", "keyevent", "KEYCODE_WAKEUP") {
		t.Errorf("expected KEYCODE_WAKEUP when asleep, calls: %+v", h.calls)
	}

	// 3. start_aerial
	h.calls = nil
	resp = postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"start_aerial"}`)
	resp.Body.Close()
	if !hasArgSubstring(h.calls, "com.android.systemui/.Somnambulator") {
		t.Errorf("expected Somnambulator on start_aerial, calls: %+v", h.calls)
	}

	// 4. launch_app
	h.calls = nil
	resp = postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"launch_app","target":"smarttube"}`)
	resp.Body.Close()
	if !hasArgSubstring(h.calls, "monkey -p com.liskovsoft.smarttubetv.beta -c android.intent.category.LAUNCHER 1") {
		t.Errorf("expected smarttube monkey launch, calls: %+v", h.calls)
	}

	// 5. hdmi
	h.calls = nil
	resp = postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"hdmi","target":"2"}`)
	resp.Body.Close()
	if !hasArgSubstring(h.calls, "ExternalTvInputService%2FHW2") {
		t.Errorf("expected HDMI 2 URI, calls: %+v", h.calls)
	}

	// 6. key
	h.calls = nil
	resp = postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"key","target":"volume_up"}`)
	resp.Body.Close()
	if !hasArgs(h.calls, "shell", "input", "keyevent", "24") {
		t.Errorf("expected keyevent 24 for volume_up, calls: %+v", h.calls)
	}

	// 7. cast_url
	h.calls = nil
	resp = postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"cast_url","url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s"}`)
	resp.Body.Close()
	if !hasArgSubstring(h.calls, `'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s' com.liskovsoft.smarttubetv.beta`) {
		t.Errorf("expected quoted URL cast to SmartTube, calls: %+v", h.calls)
	}

	// Reject non-http(s) or whitespace URLs.
	for _, badURL := range []string{"", "javascript:alert(1)", "https://example.com/a b"} {
		badResp := postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"cast_url","url":"`+badURL+`"}`)
		badResp.Body.Close()
		if badResp.StatusCode != http.StatusBadRequest {
			t.Errorf("cast_url(%q) = %d, want 400", badURL, badResp.StatusCode)
		}
	}

	// 8. trim_caches
	h.calls = nil
	resp = postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"trim_caches"}`)
	resp.Body.Close()
	if !hasArgs(h.calls, "shell", "pm", "trim-caches", "999999999999999999") {
		t.Errorf("expected pm trim-caches, calls: %+v", h.calls)
	}

	// 9. reconnect
	h.calls = nil
	resp = postJSON(t, h.ts, "/v1/tv", h.token, `{"action":"reconnect"}`)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("reconnect = %d, want 200", resp.StatusCode)
	}
	if !hasArgs(h.calls, "disconnect", defaultTVAddress) {
		t.Errorf("expected adb disconnect %s on reconnect, calls: %+v", defaultTVAddress, h.calls)
	}
	if !hasArgs(h.calls, "connect", defaultTVAddress) {
		t.Errorf("expected adb connect %s on reconnect, calls: %+v", defaultTVAddress, h.calls)
	}
}

func hasArgs(calls []recordedTVCall, suffix ...string) bool {
	for _, c := range calls {
		if len(c.args) >= len(suffix) && slices.Equal(c.args[len(c.args)-len(suffix):], suffix) {
			return true
		}
	}
	return false
}

func hasArgSubstring(calls []recordedTVCall, sub string) bool {
	for _, c := range calls {
		for _, a := range c.args {
			if strings.Contains(a, sub) {
				return true
			}
		}
	}
	return false
}
