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
