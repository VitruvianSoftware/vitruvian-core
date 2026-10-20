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
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// The v1.4 HomeSpeaker surface, pinned against a temp copy of the app's own
// config file and a fake binary. Nothing here opens /Applications or speaks.

// homeSpeakerConfigFixture is the shape HomeSpeaker 1.5 writes, with one key
// the agent has never heard of: a rewrite that dropped it would be a bug the
// app would only notice as a missing setting.
const homeSpeakerConfigFixture = `{
  "default_target" : "lake_office",
  "enabled" : true,
  "quiet_hours_enabled" : false,
  "quiet_hours_end" : "06:00",
  "quiet_hours_start" : "00:00",
  "structure_id" : "5219a9d7",
  "structure_name" : "Home",
  "chat_monitor" : { "slack_enabled" : false },
  "targets" : {
    "all" : { "id" : "structure@5219a9d7", "name" : "Whole Home (All Speakers)", "room" : "All", "type" : "Structure" },
    "kitchen" : { "id" : "device@k", "name" : "Kitchen speaker", "room" : "Kitchen", "type" : "SpeakerDevice" },
    "lake_office" : { "id" : "device@l", "name" : "Lake Office display", "room" : "Lake Office", "type" : "GoogleDisplayDevice" },
    "lake_office_display" : { "id" : "device@l", "name" : "Lake Office display", "room" : "Lake Office", "type" : "GoogleDisplayDevice" }
  }
}`

type sayCall struct {
	name string
	args []string
}

// newTestHomeSpeaker mounts the three routes over a temp dir. The returned
// *sayCall records the last --say; the binary path is a real (empty) file so
// the "installed" check passes.
func newTestHomeSpeaker(t *testing.T, withConfig bool) (*homeSpeaker, *Store, *httptest.Server, *sayCall) {
	t.Helper()
	dir := t.TempDir()
	bin := filepath.Join(dir, "HomeSpeaker")
	if err := os.WriteFile(bin, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	last := &sayCall{}
	h := &homeSpeaker{
		configPath:  filepath.Join(dir, "speaker_broadcast.json"),
		historyPath: filepath.Join(dir, "speaker_history.json"),
		secretsPath: filepath.Join(dir, "secrets.json"),
		doorPath:    filepath.Join(dir, "speaker_door.json"),
		binary:      bin,
		run: func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error) {
			last.name, last.args = name, args
			return "sent to Lake Office display\n", "", nil
		},
		running: func(ctx context.Context) bool { return true },
	}
	if withConfig {
		if err := os.WriteFile(h.configPath, []byte(homeSpeakerConfigFixture), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	store := NewStore(t.TempDir())
	if _, err := store.EnsureToken(); err != nil {
		t.Fatal(err)
	}
	srv := &server{sampler: NewSampler(time.Second, "", "", nil, nil), store: store, speaker: h}
	mux := http.NewServeMux()
	srv.homeSpeakerRoutes(mux)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return h, store, ts, last
}

func getState(t *testing.T, ts *httptest.Server) homeSpeakerState {
	t.Helper()
	resp, err := http.Get(ts.URL + "/v1/homespeaker")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET /v1/homespeaker: %d", resp.StatusCode)
	}
	var st homeSpeakerState
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		t.Fatal(err)
	}
	return st
}

func postJSON(t *testing.T, ts *httptest.Server, path, token, body string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest(http.MethodPost, ts.URL+path, bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestHomeSpeakerStateReadsTheAppsOwnConfig(t *testing.T) {
	_, _, ts, _ := newTestHomeSpeaker(t, true)
	st := getState(t, ts)

	if !st.Available || !st.Installed || !st.AppRunning {
		t.Fatalf("available/installed/running = %v/%v/%v, want all true: %+v", st.Available, st.Installed, st.AppRunning, st)
	}
	if st.SignedIn {
		t.Error("no secrets file, but signed_in is true")
	}
	if !st.Enabled || st.DefaultTarget != "lake_office" {
		t.Errorf("enabled/default_target = %v/%q", st.Enabled, st.DefaultTarget)
	}
	// Absent in a 1.4-era file; the app's own default is summary.
	if st.SpeechLength != "summary" {
		t.Errorf("speech_length = %q, want the app's default summary", st.SpeechLength)
	}
	// Four entries in the file, three speakers: discovery wrote the Lake
	// Office display under two aliases, and offering it twice under one name
	// is a list the phone cannot act on sensibly.
	if len(st.Targets) != 3 {
		t.Fatalf("targets = %d, want 3 after dedup: %+v", len(st.Targets), st.Targets)
	}
	// Whole Home first, then by room; the selected one is marked.
	if st.Targets[0].Key != "all" || st.Targets[1].Key != "kitchen" || st.Targets[2].Key != "lake_office" {
		t.Errorf("order = %s %s %s", st.Targets[0].Key, st.Targets[1].Key, st.Targets[2].Key)
	}
	if !st.Targets[2].Selected || st.Targets[1].Selected {
		t.Errorf("selected flags wrong: %+v", st.Targets)
	}
	if st.Last != nil {
		t.Errorf("no history file, but last = %+v", st.Last)
	}
}

func TestHomeSpeakerDedupesOneDeviceUnderSeveralAliases(t *testing.T) {
	targets := map[string]any{
		"lake_office":         map[string]any{"id": "device@l"},
		"lake_office_display": map[string]any{"id": "device@l"},
		"kitchen":             map[string]any{"id": "device@k"},
		"all":                 map[string]any{"id": "structure@s"},
	}
	// The shortest alias wins when neither is the default.
	got := dedupeTargetKeys(targets, "kitchen")
	if len(got) != 3 || got[0] != "all" || got[1] != "kitchen" || got[2] != "lake_office" {
		t.Errorf("got %v, want [all kitchen lake_office]", got)
	}
	// ...but the default alias always wins, however long it is, or the phone
	// would show the speaker as unselected while the Mac uses it.
	got = dedupeTargetKeys(targets, "lake_office_display")
	if len(got) != 3 || got[2] != "lake_office_display" {
		t.Errorf("got %v, want the default alias kept", got)
	}
	// An entry with no id is kept rather than dropped.
	targets["mystery"] = map[string]any{"name": "no id"}
	if len(dedupeTargetKeys(targets, "")) != 4 {
		t.Error("an entry without an id vanished from the list")
	}
}

func TestHomeSpeakerStateWithoutASetupIsHonest(t *testing.T) {
	_, _, ts, _ := newTestHomeSpeaker(t, false)
	st := getState(t, ts)
	if st.Available {
		t.Fatal("no config file, but available")
	}
	if !strings.Contains(st.Reason, "not been set up") {
		t.Errorf("reason = %q", st.Reason)
	}
	if !st.Installed {
		t.Error("the binary exists; installed should still be true")
	}
}

func TestHomeSpeakerSignedInNeverLeaksTheToken(t *testing.T) {
	h, _, ts, _ := newTestHomeSpeaker(t, true)
	if err := os.WriteFile(h.secretsPath, []byte(`{"google":{"accessToken":"ya29.x","refreshToken":"1//SECRET-VALUE","clientId":"c","scopes":["s"]}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	resp, err := http.Get(ts.URL + "/v1/homespeaker")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var buf bytes.Buffer
	buf.ReadFrom(resp.Body)
	if strings.Contains(buf.String(), "SECRET-VALUE") {
		t.Fatal("the refresh token was written into the response")
	}
	var st homeSpeakerState
	json.Unmarshal(buf.Bytes(), &st)
	if !st.SignedIn {
		t.Error("a refresh token is present but signed_in is false")
	}

	// The key is camelCase because that is what the app writes. A snake_case
	// reading here reported "not signed in" on a Mac that was, which is the
	// exact mistake this fixture pins.
	if err := os.WriteFile(h.secretsPath, []byte(`{"google":{"refresh_token":"1//x"}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if getState(t, ts).SignedIn {
		t.Error("snake_case refresh_token is not what the app writes and must not count")
	}
}

func TestHomeSpeakerLastBroadcastUsesSwiftsEpoch(t *testing.T) {
	h, _, ts, _ := newTestHomeSpeaker(t, true)
	// Foundation's JSONEncoder writes a Date as seconds since 2001-01-01 by
	// default, so that is what the history file holds.
	want := time.Date(2026, 9, 19, 8, 14, 0, 0, time.UTC)
	stamp := want.Sub(time.Date(2001, 1, 1, 0, 0, 0, 0, time.UTC)).Seconds()
	hist := fmt.Sprintf(`[{"id":"x","timestamp":%.0f,"text":"Problem. Two hooks.","targetName":"Lake Office display","source":"claude"}]`, stamp)
	if err := os.WriteFile(h.historyPath, []byte(hist), 0o600); err != nil {
		t.Fatal(err)
	}
	st := getState(t, ts)
	if st.Last == nil {
		t.Fatal("history present, but last is nil")
	}
	if !st.Last.At.Equal(want) {
		t.Errorf("at = %v, want %v (a 1970 epoch would put it in 1995)", st.Last.At, want)
	}
	if st.Last.Text != "Problem. Two hooks." || st.Last.Target != "Lake Office display" {
		t.Errorf("last = %+v", st.Last)
	}
}

func TestHomeSpeakerUpdateRewritesOnlyWhatWasAskedAndKeepsUnknownKeys(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	tok := pairedToken(t, store)

	resp := postJSON(t, ts, "/v1/homespeaker", tok, `{"default_target":"kitchen","enabled":false,"speech_length":"full"}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
	var st homeSpeakerState
	json.NewDecoder(resp.Body).Decode(&st)
	if st.Enabled || st.DefaultTarget != "kitchen" || st.SpeechLength != "full" {
		t.Errorf("reply did not reflect the write: %+v", st)
	}

	// On disk: the three changed, everything else byte-for-byte in spirit.
	data, _ := os.ReadFile(h.configPath)
	var cfg map[string]any
	if err := json.Unmarshal(data, &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg["default_target"] != "kitchen" || cfg["enabled"] != false || cfg["speech_length"] != "full" {
		t.Errorf("file = %v", cfg)
	}
	if _, ok := cfg["chat_monitor"]; !ok {
		t.Error("chat_monitor, a key the agent does not know, was dropped by the rewrite")
	}
	if cfg["structure_id"] != "5219a9d7" || cfg["quiet_hours_start"] != "00:00" {
		t.Error("untouched keys changed")
	}
	// All four aliases survive: dedup is what the phone is SHOWN, never a
	// rewrite of the file. Dropping one here would lose it for the app too.
	if len(cfg["targets"].(map[string]any)) != 4 {
		t.Error("targets were rewritten")
	}
	if _, err := os.Stat(h.configPath + ".agent-tmp"); err == nil {
		t.Error("the temp file was left behind")
	}
}

func TestHomeSpeakerUpdateRefusesWhatTheAppWouldIgnore(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	tok := pairedToken(t, store)
	before, _ := os.ReadFile(h.configPath)

	for _, c := range []struct{ body, want string }{
		{`{"default_target":"garage"}`, "unknown speaker"},
		{`{"speech_length":"medium"}`, "speech_length must be one of"},
		{`{}`, "nothing to change"},
		{`{"enabled":"yes"}`, "cannot unmarshal"},
	} {
		resp := postJSON(t, ts, "/v1/homespeaker", tok, c.body)
		var buf bytes.Buffer
		buf.ReadFrom(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("%s: status %d, want 400", c.body, resp.StatusCode)
		}
		if !strings.Contains(buf.String(), c.want) {
			t.Errorf("%s: body %q, want %q", c.body, buf.String(), c.want)
		}
	}
	after, _ := os.ReadFile(h.configPath)
	if !bytes.Equal(before, after) {
		t.Error("a refused update still rewrote the file")
	}
}

func TestHomeSpeakerActsNeedPairing(t *testing.T) {
	_, _, ts, last := newTestHomeSpeaker(t, true)
	for _, path := range []string{"/v1/homespeaker", "/v1/homespeaker/say"} {
		resp := postJSON(t, ts, path, "", `{"enabled":false,"text":"hi"}`)
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("POST %s without a token: %d, want 401", path, resp.StatusCode)
		}
	}
	if last.name != "" {
		t.Error("an unpaired caller made the Mac speak")
	}
}

func TestHomeSpeakerSayRunsTheAppsOwnSay(t *testing.T) {
	h, store, ts, last := newTestHomeSpeaker(t, true)
	tok := pairedToken(t, store)

	resp := postJSON(t, ts, "/v1/homespeaker/say", tok, `{"text":"  dinner is ready  "}`)
	defer resp.Body.Close()
	var out map[string]any
	json.NewDecoder(resp.Body).Decode(&out)
	if out["ok"] != true {
		t.Fatalf("reply = %v", out)
	}
	if last.name != h.binary || len(last.args) != 2 || last.args[0] != "--say" || last.args[1] != "dinner is ready" {
		t.Errorf("ran %s %v, want <binary> [--say \"dinner is ready\"]", last.name, last.args)
	}
	if !strings.Contains(out["output"].(string), "sent to Lake Office display") {
		t.Errorf("output = %v", out["output"])
	}

	resp2 := postJSON(t, ts, "/v1/homespeaker/say", tok, `{"text":"   "}`)
	resp2.Body.Close()
	if resp2.StatusCode != http.StatusBadRequest {
		t.Errorf("blank text: %d, want 400", resp2.StatusCode)
	}
}

func TestHomeSpeakerUpdateWithoutASetupIsAConflictNotACrash(t *testing.T) {
	_, store, ts, _ := newTestHomeSpeaker(t, false)
	tok := pairedToken(t, store)
	resp := postJSON(t, ts, "/v1/homespeaker", tok, `{"enabled":true}`)
	resp.Body.Close()
	if resp.StatusCode != http.StatusConflict {
		t.Errorf("status %d, want 409", resp.StatusCode)
	}
}

func TestHomeSpeakerIsAKnownToolResolvedByBundleNotPath(t *testing.T) {
	found := false
	for _, n := range knownTools {
		found = found || n == "homespeaker"
	}
	if !found {
		t.Fatal("homespeaker is not in knownTools, so the gallery can never say it is installed")
	}
	tools := toolPresence([]string{"homespeaker"})
	got := tools.Tools["homespeaker"]
	if got.Path != homeSpeakerBinary {
		t.Errorf("path = %q, want the app bundle's binary", got.Path)
	}
	_, statErr := os.Stat(homeSpeakerBinary)
	if got.Available != (statErr == nil) {
		t.Errorf("available = %v, but stat says %v", got.Available, statErr == nil)
	}
}

// Pause media while announcing (HomeSpeaker 1.8): reported with the app's own
// defaults when the file predates it, and settable from the phone.
func TestHomeSpeakerPauseMediaDefaultsAndRoundTrip(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	st := getState(t, ts)
	if st.PauseMedia || st.PauseMediaExtraSeconds != 1 {
		t.Errorf("a file without the keys = pause_media %v, extra %v; want the app's defaults false, 1", st.PauseMedia, st.PauseMediaExtraSeconds)
	}

	tok := pairedToken(t, store)
	resp := postJSON(t, ts, "/v1/homespeaker", tok, `{"pause_media":true,"pause_media_extra_seconds":3}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
	json.NewDecoder(resp.Body).Decode(&st)
	if !st.PauseMedia || st.PauseMediaExtraSeconds != 3 {
		t.Errorf("reply = %v/%v, want true/3", st.PauseMedia, st.PauseMediaExtraSeconds)
	}
	var cfg map[string]any
	data, _ := os.ReadFile(h.configPath)
	json.Unmarshal(data, &cfg)
	if cfg["pause_media"] != true || cfg["pause_media_extra_seconds"] != 3.0 {
		t.Errorf("file = %v / %v", cfg["pause_media"], cfg["pause_media_extra_seconds"])
	}
	if _, ok := cfg["chat_monitor"]; !ok {
		t.Error("an unrelated key was dropped")
	}
}

func TestHomeSpeakerPauseMediaMarginIsRefusedOutsideTheAppsRange(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	tok := pairedToken(t, store)
	before, _ := os.ReadFile(h.configPath)
	for _, body := range []string{`{"pause_media_extra_seconds":11}`, `{"pause_media_extra_seconds":-1}`, `{"pause_media":true,"pause_media_extra_seconds":99}`} {
		resp := postJSON(t, ts, "/v1/homespeaker", tok, body)
		var buf bytes.Buffer
		buf.ReadFrom(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusBadRequest || !strings.Contains(buf.String(), "between 0 and 10") {
			t.Errorf("%s: %d %q, want 400 naming the range", body, resp.StatusCode, buf.String())
		}
	}
	after, _ := os.ReadFile(h.configPath)
	if !bytes.Equal(before, after) {
		t.Error("a refused margin still rewrote the file -- including the valid pause_media beside it")
	}
}

// --- v1.5: volume ---------------------------------------------------------

// fakeVolumeApp answers like HomeSpeaker's --volume / --set-volume / --mute:
// one JSON line, and for a refusal JSON plus a non-zero exit.
func fakeVolumeApp(h *homeSpeaker, calls *[][]string) {
	level, muted := 40, false
	h.run = func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error) {
		*calls = append(*calls, args)
		switch args[0] {
		case "--set-volume":
			fmt.Sscan(args[1], &level)
		case "--mute":
			muted = true
		case "--unmute":
			muted = false
		}
		return fmt.Sprintf(`{"available":true,"muted":%v,"online":true,"percent":%d,"speaker":"Lake Office display"}`+"\n", muted, level), "", nil
	}
}

func TestHomeSpeakerVolumeIsReadWithoutPairingAndChangedWithIt(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	var calls [][]string
	fakeVolumeApp(h, &calls)

	resp, err := http.Get(ts.URL + "/v1/homespeaker/volume")
	if err != nil {
		t.Fatal(err)
	}
	var v homeSpeakerVolume
	json.NewDecoder(resp.Body).Decode(&v)
	resp.Body.Close()
	if !v.Available || v.Percent != 40 || v.Speaker != "Lake Office display" {
		t.Fatalf("GET = %+v", v)
	}

	if r := postJSON(t, ts, "/v1/homespeaker/volume", "", `{"percent":55}`); r.StatusCode != http.StatusUnauthorized {
		t.Errorf("unpaired set: %d, want 401", r.StatusCode)
	}

	tok := pairedToken(t, store)
	r := postJSON(t, ts, "/v1/homespeaker/volume", tok, `{"percent":55}`)
	json.NewDecoder(r.Body).Decode(&v)
	r.Body.Close()
	if v.Percent != 55 {
		t.Errorf("after set, percent = %d, want the level HomeSpeaker read back (55)", v.Percent)
	}
	r = postJSON(t, ts, "/v1/homespeaker/volume", tok, `{"muted":true}`)
	json.NewDecoder(r.Body).Decode(&v)
	r.Body.Close()
	if !v.Muted {
		t.Error("mute did not come back muted")
	}
	want := [][]string{{"--volume"}, {"--set-volume", "55"}, {"--mute"}}
	if fmt.Sprint(calls) != fmt.Sprint(want) {
		t.Errorf("ran %v, want %v", calls, want)
	}
}

func TestHomeSpeakerVolumeRefusesAmbiguousOrOutOfRangeRequests(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	var calls [][]string
	fakeVolumeApp(h, &calls)
	tok := pairedToken(t, store)
	for _, body := range []string{`{}`, `{"percent":50,"muted":true}`, `{"percent":101}`, `{"percent":-1}`} {
		r := postJSON(t, ts, "/v1/homespeaker/volume", tok, body)
		r.Body.Close()
		if r.StatusCode != http.StatusBadRequest {
			t.Errorf("%s: %d, want 400", body, r.StatusCode)
		}
	}
	if len(calls) != 0 {
		t.Errorf("a refused request still ran HomeSpeaker: %v", calls)
	}
}

// A refusal from the app is JSON on stdout with exit 1 -- still an answer to
// relay, not an agent error. An old app with no --volume prints nothing.
func TestHomeSpeakerVolumeRelaysTheAppsOwnRefusalAndExplainsAnOldApp(t *testing.T) {
	h, _, ts, _ := newTestHomeSpeaker(t, true)
	h.run = func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error) {
		return `{"available":false,"reason":"Pick a single speaker to see or change its volume.","speaker":"Whole Home"}` + "\n", "", fmt.Errorf("exit status 1")
	}
	var v homeSpeakerVolume
	resp, _ := http.Get(ts.URL + "/v1/homespeaker/volume")
	json.NewDecoder(resp.Body).Decode(&v)
	resp.Body.Close()
	if v.Available || !strings.Contains(v.Reason, "single speaker") {
		t.Errorf("got %+v, want the app's own reason relayed", v)
	}

	h.run = func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error) {
		return "", "", fmt.Errorf("exit status 1")
	}
	resp, _ = http.Get(ts.URL + "/v1/homespeaker/volume")
	json.NewDecoder(resp.Body).Decode(&v)
	resp.Body.Close()
	if v.Available || !strings.Contains(v.Reason, "exit status 1") {
		t.Errorf("got %+v, want the failure named", v)
	}
}

func TestHomeSpeakerAnnounceVolumeDefaultsRoundTripAndRange(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	st := getState(t, ts)
	if st.AnnounceVolumeEnabled || st.AnnounceVolume != 60 {
		t.Errorf("defaults = %v/%d, want the app's false/60", st.AnnounceVolumeEnabled, st.AnnounceVolume)
	}
	tok := pairedToken(t, store)
	r := postJSON(t, ts, "/v1/homespeaker", tok, `{"announce_volume_enabled":true,"announce_volume":45}`)
	json.NewDecoder(r.Body).Decode(&st)
	r.Body.Close()
	if !st.AnnounceVolumeEnabled || st.AnnounceVolume != 45 {
		t.Errorf("after set = %v/%d", st.AnnounceVolumeEnabled, st.AnnounceVolume)
	}
	before, _ := os.ReadFile(h.configPath)
	r = postJSON(t, ts, "/v1/homespeaker", tok, `{"announce_volume":101}`)
	r.Body.Close()
	after, _ := os.ReadFile(h.configPath)
	if r.StatusCode != http.StatusBadRequest || !bytes.Equal(before, after) {
		t.Errorf("101: %d, file changed %v; want 400 and untouched", r.StatusCode, !bytes.Equal(before, after))
	}
}

// --- v1.8: where announcements are spoken ---------------------------------

// A file that predates local speech reads as today's behaviour: home
// speakers only, and the Mac's default voice (local-speech.md).
func TestHomeSpeakerOutputsDefaultWhenAbsent(t *testing.T) {
	_, _, ts, _ := newTestHomeSpeaker(t, true)
	st := getState(t, ts)
	if !st.SpeakHome || st.SpeakLocal {
		t.Errorf("speak_home/speak_local = %v/%v, want the defaults true/false", st.SpeakHome, st.SpeakLocal)
	}
	if st.LocalVoice != "com.apple.ttsbundle.siri_Aaron_en-US_premium" || st.LocalVoiceName != "Aaron" {
		t.Errorf("local_voice = %q (%q), want Siri's Aaron", st.LocalVoice, st.LocalVoiceName)
	}
}

// The phone switches one output at a time; the write keeps every other key,
// including the voice it may not set and keys it has never heard of.
func TestHomeSpeakerOutputsRoundTripKeepsUnknownKeys(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	cfg, err := h.readConfig()
	if err != nil {
		t.Fatal(err)
	}
	cfg["local_voice"] = "com.apple.voice.premium.en-US.Zoe"
	if err := h.writeConfig(cfg); err != nil {
		t.Fatal(err)
	}
	tok := pairedToken(t, store)

	resp := postJSON(t, ts, "/v1/homespeaker", tok, `{"speak_local":true}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
	var st homeSpeakerState
	json.NewDecoder(resp.Body).Decode(&st)
	if !st.SpeakHome || !st.SpeakLocal || st.LocalVoiceName != "Zoe" {
		t.Errorf("reply = home %v local %v voice %q, want true/true/Zoe", st.SpeakHome, st.SpeakLocal, st.LocalVoiceName)
	}

	data, _ := os.ReadFile(h.configPath)
	var got map[string]any
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got["speak_local"] != true {
		t.Errorf("speak_local on disk = %v", got["speak_local"])
	}
	// Only what was asked is written: speak_home stays absent (and so on).
	if _, ok := got["speak_home"]; ok {
		t.Error("speak_home was written although the phone did not send it")
	}
	if got["local_voice"] != "com.apple.voice.premium.en-US.Zoe" {
		t.Errorf("local_voice changed to %v", got["local_voice"])
	}
	if _, ok := got["chat_monitor"]; !ok {
		t.Error("chat_monitor, a key the agent does not know, was dropped by the rewrite")
	}
	if got["structure_id"] != "5219a9d7" || len(got["targets"].(map[string]any)) != 4 {
		t.Error("untouched keys changed")
	}
}

// Both off is the user's choice and is kept, not refused or corrected.
func TestHomeSpeakerOutputsBothSet(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	tok := pairedToken(t, store)
	for _, c := range []struct {
		body        string
		home, local bool
	}{
		{`{"speak_home":false,"speak_local":true}`, false, true},
		{`{"speak_home":false,"speak_local":false}`, false, false},
		{`{"speak_home":true,"speak_local":true}`, true, true},
	} {
		resp := postJSON(t, ts, "/v1/homespeaker", tok, c.body)
		var st homeSpeakerState
		json.NewDecoder(resp.Body).Decode(&st)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK || st.SpeakHome != c.home || st.SpeakLocal != c.local {
			t.Errorf("%s: %d home %v local %v", c.body, resp.StatusCode, st.SpeakHome, st.SpeakLocal)
		}
		cfg, _ := h.readConfig()
		if cfg["speak_home"] != c.home || cfg["speak_local"] != c.local {
			t.Errorf("%s: file = %v/%v", c.body, cfg["speak_home"], cfg["speak_local"])
		}
	}
}

func TestHomeSpeakerVoiceName(t *testing.T) {
	for id, want := range map[string]string{
		"com.apple.siri.natural.Aaron":                 "Aaron",
		"com.apple.ttsbundle.siri_Aaron_en-US_premium": "Aaron",
		"com.apple.voice.premium.en-US.Zoe":            "Zoe",
		"com.apple.voice.compact.en-US":                "com.apple.voice.compact.en-US",
		"Aaron":                                        "Aaron",
		"com.apple.":                                   "com.apple.",
	} {
		if got := voiceName(id); got != want {
			t.Errorf("voiceName(%q) = %q, want %q", id, got, want)
		}
	}
}

// --- sources and recent broadcasts (HomeSpeaker 1.23) ---------------------

// A config written before the source keys existed reads as the app's own
// defaults: both coding agents spoken, every chat app off. Every field is
// present so the phone can tell this agent from an older one.
func TestHomeSpeakerSourcesDefaultWhenAbsent(t *testing.T) {
	_, _, ts, _ := newTestHomeSpeaker(t, true)
	resp, err := http.Get(ts.URL + "/v1/homespeaker")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var raw map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{
		"announce_claude_code": true,
		"announce_antigravity": true,
		"announce_opencode":    true,
		"slack_enabled":        false,
		"google_chat_enabled":  false,
		"beeper_enabled":       false,
	}
	for key, v := range want {
		got, ok := raw[key]
		if !ok {
			t.Errorf("%s missing from the reply; the phone would read this agent as an old one", key)
			continue
		}
		if got != v {
			t.Errorf("%s = %v, want %v", key, got, v)
		}
	}
	if r, ok := raw["recent"].([]any); !ok || len(r) != 0 {
		t.Errorf("recent = %#v, want [] (not null) with no history", raw["recent"])
	}
}

// No chat_monitor at all (a fresh config) still reads, and a toggle creates it.
func TestHomeSpeakerChatToggleCreatesChatMonitorWhenAbsent(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	cfg, _ := h.readConfig()
	delete(cfg, "chat_monitor")
	if err := h.writeConfig(cfg); err != nil {
		t.Fatal(err)
	}
	if st := getState(t, ts); st.SlackEnabled == nil || *st.SlackEnabled {
		t.Fatalf("slack_enabled without chat_monitor = %v, want false", st.SlackEnabled)
	}
	tok := pairedToken(t, store)
	resp := postJSON(t, ts, "/v1/homespeaker", tok, `{"beeper_enabled":true}`)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
	got, _ := h.readConfig()
	monitor, _ := got["chat_monitor"].(map[string]any)
	if monitor["beeper_enabled"] != true {
		t.Errorf("chat_monitor = %v, want beeper_enabled true", got["chat_monitor"])
	}
}

// Each switch writes its own key, in its own place, and nothing else: the
// coding agents at the top level, the chat apps inside chat_monitor next to
// every setting the app keeps there.
func TestHomeSpeakerSourceTogglesWriteTheirKeysAndKeepChatMonitor(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	cfg, err := h.readConfig()
	if err != nil {
		t.Fatal(err)
	}
	cfg["chat_monitor"] = map[string]any{
		"slack_enabled":         false,
		"poll_interval_seconds": 15.0,
		"slack_Mode":            "mentions",
		"gchat_command":         "gws chat",
		"beeper_base_url":       "http://localhost:23373",
		"beeper_token":          "keep-me",
	}
	if err := h.writeConfig(cfg); err != nil {
		t.Fatal(err)
	}
	tok := pairedToken(t, store)

	cases := []struct {
		body     string
		topLevel bool
		key      string
		want     bool
		read     func(homeSpeakerState) *bool
	}{
		{`{"announce_claude_code":false}`, true, "announce_claude_code", false, func(s homeSpeakerState) *bool { return s.AnnounceClaudeCode }},
		{`{"announce_antigravity":false}`, true, "announce_antigravity", false, func(s homeSpeakerState) *bool { return s.AnnounceAntigravity }},
		{`{"announce_opencode":false}`, true, "announce_opencode", false, func(s homeSpeakerState) *bool { return s.AnnounceOpenCode }},
		{`{"slack_enabled":true}`, false, "slack_enabled", true, func(s homeSpeakerState) *bool { return s.SlackEnabled }},
		{`{"google_chat_enabled":true}`, false, "google_chat_enabled", true, func(s homeSpeakerState) *bool { return s.GoogleChatEnabled }},
		{`{"beeper_enabled":true}`, false, "beeper_enabled", true, func(s homeSpeakerState) *bool { return s.BeeperEnabled }},
	}
	for _, c := range cases {
		resp := postJSON(t, ts, "/v1/homespeaker", tok, c.body)
		var st homeSpeakerState
		json.NewDecoder(resp.Body).Decode(&st)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("%s: status %d", c.body, resp.StatusCode)
		}
		if v := c.read(st); v == nil || *v != c.want {
			got := "absent"
			if v != nil {
				got = fmt.Sprint(*v)
			}
			t.Errorf("%s: reply %s = %s, want %v", c.body, c.key, got, c.want)
		}
		got, _ := h.readConfig()
		monitor, _ := got["chat_monitor"].(map[string]any)
		if c.topLevel {
			if got[c.key] != c.want {
				t.Errorf("%s: on disk %s = %v", c.body, c.key, got[c.key])
			}
			if _, ok := monitor[c.key]; ok {
				t.Errorf("%s: also written inside chat_monitor", c.key)
			}
		} else {
			if monitor[c.key] != c.want {
				t.Errorf("%s: on disk chat_monitor.%s = %v", c.body, c.key, monitor[c.key])
			}
			if _, ok := got[c.key]; ok {
				t.Errorf("%s: also written at the top level, where HomeSpeaker never reads it", c.key)
			}
		}
	}

	got, _ := h.readConfig()
	monitor := got["chat_monitor"].(map[string]any)
	for key, want := range map[string]any{
		"poll_interval_seconds": 15.0,
		"slack_Mode":            "mentions",
		"gchat_command":         "gws chat",
		"beeper_base_url":       "http://localhost:23373",
		"beeper_token":          "keep-me",
	} {
		if monitor[key] != want {
			t.Errorf("chat_monitor.%s = %v after the toggles, want %v", key, monitor[key], want)
		}
	}
	if got["enabled"] != true || got["structure_id"] != "5219a9d7" {
		t.Error("untouched top-level keys changed")
	}
}

// The source fields count as "something to change"; nothing at all is refused.
func TestHomeSpeakerUpdateNeedsARecognisedField(t *testing.T) {
	_, store, ts, _ := newTestHomeSpeaker(t, true)
	tok := pairedToken(t, store)
	for body, want := range map[string]int{
		`{}`:                             http.StatusBadRequest,
		`{"announce_claude_code":true}`:  http.StatusOK,
		`{"google_chat_enabled":false}`:  http.StatusOK,
		`{"announce_antigravity":false}`: http.StatusOK,
		`{"announce_opencode":false}`:    http.StatusOK,
	} {
		resp := postJSON(t, ts, "/v1/homespeaker", tok, body)
		resp.Body.Close()
		if resp.StatusCode != want {
			t.Errorf("%s: %d, want %d", body, resp.StatusCode, want)
		}
	}
}

// Recent is the newest five, newest first, and last is still recent[0] for
// phones that only read last.
func TestHomeSpeakerRecentBroadcasts(t *testing.T) {
	h, _, ts, _ := newTestHomeSpeaker(t, true)
	if st := getState(t, ts); len(st.Recent) != 0 || st.Last != nil {
		t.Fatalf("no history: recent %v last %v", st.Recent, st.Last)
	}
	base := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC).Sub(swiftReferenceEpoch).Seconds()
	var items []string
	for i := 0; i < 7; i++ {
		// The app writes newest first: item 0 is the latest.
		items = append(items, fmt.Sprintf(`{"id":"%d","timestamp":%.0f,"text":"line %d","targetName":"Kitchen speaker","source":"Claude Code"}`, i, base-float64(i*60), i))
	}
	if err := os.WriteFile(h.historyPath, []byte("["+strings.Join(items, ",")+"]"), 0o600); err != nil {
		t.Fatal(err)
	}
	st := getState(t, ts)
	if len(st.Recent) != recentBroadcasts {
		t.Fatalf("recent has %d, want %d", len(st.Recent), recentBroadcasts)
	}
	for i, r := range st.Recent {
		if r.Text != fmt.Sprintf("line %d", i) {
			t.Errorf("recent[%d] = %q, want newest first", i, r.Text)
		}
	}
	if st.Last == nil || st.Last.Text != "line 0" || !st.Last.At.Equal(st.Recent[0].At) {
		t.Errorf("last = %+v, want recent[0]", st.Last)
	}
	if st.Recent[0].Source != "Claude Code" || st.Recent[0].Target != "Kitchen speaker" {
		t.Errorf("recent[0] = %+v", st.Recent[0])
	}
}

// A replay is a --say of the history's text, run without the coding-agent
// markers so HomeSpeaker does not hold it to an agent's switch.
func TestHomeSpeakerSayRunsAsAPerson(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	var sayArgs []string
	h.say = func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error) {
		sayArgs = args
		return "sent\n", "", nil
	}
	tok := pairedToken(t, store)
	resp := postJSON(t, ts, "/v1/homespeaker/say", tok, `{"text":"line 0"}`)
	resp.Body.Close()
	if len(sayArgs) != 2 || sayArgs[0] != "--say" || sayArgs[1] != "line 0" {
		t.Errorf("say ran %v, want [--say \"line 0\"] through the person runner", sayArgs)
	}
	if newHomeSpeaker().say == nil {
		t.Error("production --say does not use the person runner")
	}

	env := personEnv([]string{"PATH=/usr/bin", "CLAUDECODE=1", "ANTIGRAVITY_AGENT=1", "OPENCODE=1", "AI_AGENT=claude-code", "CLAUDECODE_X=keep", "HOME=/Users/j"})
	if strings.Join(env, " ") != "PATH=/usr/bin CLAUDECODE_X=keep HOME=/Users/j" {
		t.Errorf("personEnv = %v", env)
	}
}

// --- extension door & Gemini TTS / announcement style parity --------------

func TestHomeSpeakerDoorRoutesToExtensionWhenChosen(t *testing.T) {
	h, store, ts, last := newTestHomeSpeaker(t, true)
	tok := pairedToken(t, store)

	// Without speaker_door.json, active_door defaults to "app".
	st := getState(t, ts)
	if st.ActiveDoor != "app" {
		t.Fatalf("active_door without door file = %q, want app", st.ActiveDoor)
	}

	// Set up an extension layout under a temp root:
	//   <root>/Tools/dev.vitruvian.homespeaker/bin/tool
	//   <root>/ToolData/dev.vitruvian.homespeaker/{settings.json,history.json,secrets.json,running.lock}
	root := t.TempDir()
	extBin := filepath.Join(root, "Tools", "dev.vitruvian.homespeaker", "bin", "tool")
	dataFolder := filepath.Join(root, "ToolData", "dev.vitruvian.homespeaker")
	if err := os.MkdirAll(filepath.Dir(extBin), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dataFolder, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(extBin, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	extSettings := filepath.Join(dataFolder, "settings.json")
	if err := os.WriteFile(extSettings, []byte(homeSpeakerConfigFixture), 0o600); err != nil {
		t.Fatal(err)
	}
	extSecrets := filepath.Join(dataFolder, "secrets.json")
	if err := os.WriteFile(extSecrets, []byte(`{"google":{"refreshToken":"1//ext-token"},"geminiAPIKey":"AIza-SECRET-GEMINI"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	extHistory := filepath.Join(dataFolder, "history.json")
	base := time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC).Sub(swiftReferenceEpoch).Seconds()
	if err := os.WriteFile(extHistory, []byte(fmt.Sprintf(`[{"id":"1","timestamp":%.0f,"text":"extension spoke","targetName":"Kitchen speaker","source":"Extension"}]`, base)), 0o600); err != nil {
		t.Fatal(err)
	}

	// Acquire an exclusive flock on running.lock to simulate a live extension daemon.
	lockPath := filepath.Join(dataFolder, "running.lock")
	lockFile, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer lockFile.Close()
	if err := syscall.Flock(int(lockFile.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatalf("flock in test setup: %v", err)
	}

	// Write speaker_door.json choosing the extension (and omitting data_folder
	// first to verify deriveExtensionDataFolder resolves .../ToolData/<id>).
	doorJSON := fmt.Sprintf(`{"version":1,"chosen":"extension","extension":{"program":%q,"version":"1.19.0","door":1}}`, extBin)
	if err := os.WriteFile(h.doorPath, []byte(doorJSON), 0o600); err != nil {
		t.Fatal(err)
	}

	// Make h.running return false for the standalone app so AppRunning must come
	// from the extension's running.lock flock.
	h.running = func(ctx context.Context) bool { return false }

	st = getState(t, ts)
	if st.ActiveDoor != "extension" {
		t.Fatalf("active_door = %q, want extension", st.ActiveDoor)
	}
	if !st.Available || !st.Installed || !st.AppRunning {
		t.Fatalf("extension available/installed/running = %v/%v/%v, want all true", st.Available, st.Installed, st.AppRunning)
	}
	if !st.SignedIn || !st.HasGeminiKey {
		t.Errorf("signed_in/has_gemini_key = %v/%v, want true/true from extension secrets.json", st.SignedIn, st.HasGeminiKey)
	}
	if len(st.Recent) != 1 || st.Recent[0].Text != "extension spoke" {
		t.Errorf("recent = %+v, want extension history.json", st.Recent)
	}

	// Unlock running.lock and verify AppRunning becomes false (and the probe
	// does not leave running.lock locked).
	_ = syscall.Flock(int(lockFile.Fd()), syscall.LOCK_UN)
	st = getState(t, ts)
	if st.AppRunning {
		t.Error("after unlocking running.lock, app_running = true, want false")
	}

	// POST /v1/homespeaker writes to extension settings.json, leaving the app's
	// speaker_broadcast.json untouched.
	appBefore, _ := os.ReadFile(h.configPath)
	resp := postJSON(t, ts, "/v1/homespeaker", tok, `{"default_target":"kitchen"}`)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("POST /v1/homespeaker: %d", resp.StatusCode)
	}
	appAfter, _ := os.ReadFile(h.configPath)
	if !bytes.Equal(appBefore, appAfter) {
		t.Error("extension update modified the standalone app's speaker_broadcast.json")
	}
	extData, _ := os.ReadFile(extSettings)
	var extCfg map[string]any
	_ = json.Unmarshal(extData, &extCfg)
	if extCfg["default_target"] != "kitchen" {
		t.Errorf("extension settings.json default_target = %v, want kitchen", extCfg["default_target"])
	}

	// POST /v1/homespeaker/say invokes the extension's bin/tool --say.
	respSay := postJSON(t, ts, "/v1/homespeaker/say", tok, `{"text":"hello extension"}`)
	respSay.Body.Close()
	if last.name != extBin || len(last.args) != 2 || last.args[0] != "--say" || last.args[1] != "hello extension" {
		t.Errorf("say ran %s %v, want %s [--say \"hello extension\"]", last.name, last.args, extBin)
	}
}

func TestHomeSpeakerDoorFallbacksAndUnchosenExtension(t *testing.T) {
	h, _, ts, _ := newTestHomeSpeaker(t, true)
	root := t.TempDir()
	extBin := filepath.Join(root, "bin", "tool")
	dataFolder := filepath.Join(root, "data")
	_ = os.MkdirAll(filepath.Dir(extBin), 0o755)
	_ = os.MkdirAll(dataFolder, 0o755)
	_ = os.WriteFile(extBin, []byte("#!/bin/sh\n"), 0o755)
	_ = os.WriteFile(filepath.Join(dataFolder, "settings.json"), []byte(homeSpeakerConfigFixture), 0o600)

	// 1. chosen == "app" keeps the standalone app even when extension is present.
	doorJSON := fmt.Sprintf(`{"version":1,"chosen":"app","extension":{"program":%q,"data_folder":%q,"door":1}}`, extBin, dataFolder)
	_ = os.WriteFile(h.doorPath, []byte(doorJSON), 0o600)
	if st := getState(t, ts); st.ActiveDoor != "app" {
		t.Errorf("chosen=app: active_door = %q, want app", st.ActiveDoor)
	}

	// 2. chosen == "" with standalone app installed keeps "app"; removing standalone app switches to "extension".
	doorJSON = fmt.Sprintf(`{"version":1,"chosen":"","extension":{"program":%q,"data_folder":%q,"door":1}}`, extBin, dataFolder)
	_ = os.WriteFile(h.doorPath, []byte(doorJSON), 0o600)
	if st := getState(t, ts); st.ActiveDoor != "app" {
		t.Errorf("chosen=\"\" with app present: active_door = %q, want app", st.ActiveDoor)
	}
	_ = os.Remove(h.binary)
	if st := getState(t, ts); st.ActiveDoor != "extension" {
		t.Errorf("chosen=\"\" without app binary: active_door = %q, want extension", st.ActiveDoor)
	}

	// 3. Extension inside /.Trash/ is ignored and falls back to "app".
	trashBin := filepath.Join(root, ".Trash", "tool")
	_ = os.MkdirAll(filepath.Dir(trashBin), 0o755)
	_ = os.WriteFile(trashBin, []byte("#!/bin/sh\n"), 0o755)
	doorJSON = fmt.Sprintf(`{"version":1,"chosen":"extension","extension":{"program":%q,"data_folder":%q,"door":1}}`, trashBin, dataFolder)
	_ = os.WriteFile(h.doorPath, []byte(doorJSON), 0o600)
	if st := getState(t, ts); st.ActiveDoor != "app" {
		t.Errorf("extension in .Trash: active_door = %q, want app", st.ActiveDoor)
	}
}

func TestHomeSpeakerGeminiTTSAndStyleDefaultsRoundTripAndValidation(t *testing.T) {
	h, store, ts, _ := newTestHomeSpeaker(t, true)
	tok := pairedToken(t, store)

	// Defaults when absent in config and secrets.
	st := getState(t, ts)
	if st.LocalEngine != "apple" || st.GeminiVoice != "Kore" || st.HasGeminiKey {
		t.Errorf("defaults: local_engine=%q gemini_voice=%q has_gemini_key=%v, want apple/Kore/false", st.LocalEngine, st.GeminiVoice, st.HasGeminiKey)
	}
	if st.AnnouncementStyle != "verbatim" || st.StyleModel != "apple" {
		t.Errorf("defaults: announcement_style=%q style_model=%q, want verbatim/apple", st.AnnouncementStyle, st.StyleModel)
	}

	// Saving geminiAPIKey in secrets.json flips has_gemini_key to true and never leaks the key.
	if err := os.WriteFile(h.secretsPath, []byte(`{"geminiAPIKey":"AIza-DO-NOT-LEAK"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	rawResp, err := http.Get(ts.URL + "/v1/homespeaker")
	if err != nil {
		t.Fatal(err)
	}
	var rawBuf bytes.Buffer
	rawBuf.ReadFrom(rawResp.Body)
	rawResp.Body.Close()
	if strings.Contains(rawBuf.String(), "AIza-DO-NOT-LEAK") {
		t.Fatal("geminiAPIKey leaked into GET /v1/homespeaker response")
	}
	_ = json.Unmarshal(rawBuf.Bytes(), &st)
	if !st.HasGeminiKey {
		t.Error("has_gemini_key = false with geminiAPIKey present in secrets.json")
	}

	// Round-trip update of local_engine, gemini_voice, announcement_style, style_model.
	resp := postJSON(t, ts, "/v1/homespeaker", tok, `{"local_engine":"gemini","gemini_voice":"Puck","announcement_style":"briefing","style_model":"gemini"}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
	_ = json.NewDecoder(resp.Body).Decode(&st)
	if st.LocalEngine != "gemini" || st.GeminiVoice != "Puck" || st.AnnouncementStyle != "briefing" || st.StyleModel != "gemini" {
		t.Errorf("after update: %+v", st)
	}

	// Refuses invalid enum values with 400 and leaves config untouched.
	before, _ := os.ReadFile(h.configPath)
	for _, c := range []struct{ body, want string }{
		{`{"local_engine":"elevenlabs"}`, "local_engine must be one of"},
		{`{"gemini_voice":"UnknownVoice"}`, "gemini_voice must be one of"},
		{`{"announcement_style":"poetic"}`, "announcement_style must be one of"},
		{`{"style_model":"claude"}`, "style_model must be one of"},
	} {
		r := postJSON(t, ts, "/v1/homespeaker", tok, c.body)
		var buf bytes.Buffer
		buf.ReadFrom(r.Body)
		r.Body.Close()
		if r.StatusCode != http.StatusBadRequest || !strings.Contains(buf.String(), c.want) {
			t.Errorf("%s: status %d body %q, want 400 containing %q", c.body, r.StatusCode, buf.String(), c.want)
		}
	}
	after, _ := os.ReadFile(h.configPath)
	if !bytes.Equal(before, after) {
		t.Error("a refused enum update still modified the config file")
	}
}
