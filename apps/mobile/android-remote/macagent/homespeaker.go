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
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// HomeSpeaker (apps/desktop/home-speaker) from the phone: is it on, which
// speaker does it talk to, how much does it say, and say this now.
//
// The agent never imports HomeSpeaker's code -- the inter-app boundary (#82)
// forbids it, and it would be the wrong design anyway. The two apps already
// share one contract: the config file at ~/.gemini/speaker_broadcast.json,
// which HomeSpeaker, its Claude Code hook and the `speaker-broadcast` CLI all
// read. The agent reads and rewrites that file, and HomeSpeaker watches it. To
// SAY something it runs the app binary's own `--say`, so the announcement goes
// through HomeSpeaker's sign-in, target resolution and speech cleaning rather
// than a second copy of them here.

// homeSpeaker is where the app keeps its state, and how to run it. Fields
// rather than constants so a test can point them at a temp dir and a fake
// binary; newHomeSpeaker fills in the real ones.
type homeSpeaker struct {
	configPath  string
	historyPath string
	secretsPath string
	// binary is the app's executable inside its bundle, used for --say.
	binary string
	// run executes the binary. runToolWithin in production.
	run func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error)
	// running answers "is the menu bar app up". `pgrep -x HomeSpeaker` in
	// production; the hook and --say work without it, but the phone should
	// know the difference between "off" and "not even open".
	running func(ctx context.Context) bool
}

const homeSpeakerBinary = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"

func newHomeSpeaker() *homeSpeaker {
	home, _ := os.UserHomeDir()
	return &homeSpeaker{
		configPath:  filepath.Join(home, ".gemini", "speaker_broadcast.json"),
		historyPath: filepath.Join(home, ".gemini", "speaker_history.json"),
		secretsPath: filepath.Join(home, "Library", "Application Support", "HomeSpeaker", "secrets.json"),
		binary:      homeSpeakerBinary,
		run:         runToolWithin,
		running: func(ctx context.Context) bool {
			return exec.CommandContext(ctx, "pgrep", "-x", "HomeSpeaker").Run() == nil
		},
	}
}

// speechLengths are the values HomeSpeaker's `speech_length` accepts
// (SpeechLength in its Models.swift). Anything else is refused here rather
// than written and silently ignored by the app.
var speechLengths = []string{"headline", "summary", "full"}

// homeSpeakerState is GET /v1/homespeaker.
type homeSpeakerState struct {
	Available bool   `json:"available"`
	Reason    string `json:"reason,omitempty"`
	// Installed says the app bundle is present; AppRunning that the menu
	// bar process is up. Both false with a config file present means the
	// CLI or an old install wrote it.
	Installed  bool `json:"installed"`
	AppRunning bool `json:"app_running"`
	SignedIn   bool `json:"signed_in"`

	Enabled       bool                `json:"enabled"`
	DefaultTarget string              `json:"default_target"`
	SpeechLength  string              `json:"speech_length"`
	StructureName string              `json:"structure_name"`
	QuietHours    homeSpeakerQuiet    `json:"quiet_hours"`
	Targets       []homeSpeakerTarget `json:"targets"`
	Last          *homeSpeakerLast    `json:"last,omitempty"`
}

type homeSpeakerQuiet struct {
	Enabled bool   `json:"enabled"`
	Start   string `json:"start"`
	End     string `json:"end"`
}

type homeSpeakerTarget struct {
	Key      string `json:"key"`
	Name     string `json:"name"`
	Room     string `json:"room"`
	Type     string `json:"type"`
	Selected bool   `json:"selected"`
}

type homeSpeakerLast struct {
	Text   string    `json:"text"`
	Target string    `json:"target"`
	Source string    `json:"source"`
	At     time.Time `json:"at"`
}

// readConfig is the file as a generic map, so a rewrite keeps every key the
// app or the CLI put there that this agent has never heard of.
func (h *homeSpeaker) readConfig() (map[string]any, error) {
	data, err := os.ReadFile(h.configPath)
	if err != nil {
		return nil, err
	}
	var cfg map[string]any
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("%s: %w", filepath.Base(h.configPath), err)
	}
	return cfg, nil
}

// writeConfig replaces the file atomically. HomeSpeaker watches the directory
// for exactly this rename, and its own saves are atomic too, so neither side
// ever reads the other's half-written file.
func (h *homeSpeaker) writeConfig(cfg map[string]any) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	tmp := h.configPath + ".agent-tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, h.configPath)
}

func (h *homeSpeaker) state(ctx context.Context) homeSpeakerState {
	st := homeSpeakerState{}
	if _, err := os.Stat(h.binary); err == nil {
		st.Installed = true
	}
	cfg, err := h.readConfig()
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			st.Reason = "HomeSpeaker has not been set up on this Mac (no " + h.configPath + ")"
		} else {
			st.Reason = err.Error()
		}
		return st
	}
	st.Available = true
	st.AppRunning = h.running(ctx)
	st.SignedIn = h.signedIn()
	st.Enabled, _ = cfg["enabled"].(bool)
	st.DefaultTarget, _ = cfg["default_target"].(string)
	st.SpeechLength, _ = cfg["speech_length"].(string)
	if st.SpeechLength == "" {
		// The app's own default when the key is absent (SpeakerConfig.effectiveSpeechLength).
		st.SpeechLength = "summary"
	}
	st.StructureName, _ = cfg["structure_name"].(string)
	st.QuietHours.Enabled, _ = cfg["quiet_hours_enabled"].(bool)
	st.QuietHours.Start, _ = cfg["quiet_hours_start"].(string)
	st.QuietHours.End, _ = cfg["quiet_hours_end"].(string)
	if targets, ok := cfg["targets"].(map[string]any); ok {
		for _, key := range dedupeTargetKeys(targets, st.DefaultTarget) {
			t, _ := targets[key].(map[string]any)
			name, _ := t["name"].(string)
			room, _ := t["room"].(string)
			typ, _ := t["type"].(string)
			st.Targets = append(st.Targets, homeSpeakerTarget{
				Key: key, Name: name, Room: room, Type: typ, Selected: key == st.DefaultTarget,
			})
		}
		// A map has no order and the phone draws a list; "Whole Home" first
		// because it is the one that is not a room, then by room.
		sort.Slice(st.Targets, func(i, j int) bool {
			a, b := st.Targets[i], st.Targets[j]
			if (a.Type == "Structure") != (b.Type == "Structure") {
				return a.Type == "Structure"
			}
			if a.Room != b.Room {
				return a.Room < b.Room
			}
			return a.Name < b.Name
		})
	}
	st.Last = h.lastBroadcast()
	return st
}

// dedupeTargetKeys is the same rule HomeSpeaker's own picker uses
// (SpeakerConfig.uniqueTargets): discovery writes one device under more than
// one alias -- `lake_office` and `lake_office_display` are the same speaker --
// and a list that shows both offers the same speaker twice under one name.
//
// One alias per device id: the default target always wins, otherwise the
// shortest key. Ported rather than shared because the agent may not import the
// app's code, so the pair is kept honest by a test using a real duplicate.
func dedupeTargetKeys(targets map[string]any, defaultTarget string) []string {
	keys := make([]string, 0, len(targets))
	for k := range targets {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	byDevice := map[string]string{}
	for _, key := range keys {
		t, _ := targets[key].(map[string]any)
		id, _ := t["id"].(string)
		if id == "" {
			// No id to group by: keep it, or it would vanish from the list.
			byDevice[key] = key
			continue
		}
		existing, seen := byDevice[id]
		switch {
		case key == defaultTarget:
			byDevice[id] = key
		case !seen:
			byDevice[id] = key
		case existing != defaultTarget && len(key) < len(existing):
			byDevice[id] = key
		}
	}
	chosen := make([]string, 0, len(byDevice))
	for _, key := range byDevice {
		chosen = append(chosen, key)
	}
	sort.Strings(chosen)
	return chosen
}

// signedIn is "there is a Google Home refresh token", and nothing about it:
// the value is never read into a response or a log.
func (h *homeSpeaker) signedIn() bool {
	data, err := os.ReadFile(h.secretsPath)
	if err != nil {
		return false
	}
	// camelCase: the app's SecretStore uses Foundation's default key
	// encoding, not the snake_case its config file uses.
	var secrets struct {
		Google *struct {
			RefreshToken string `json:"refreshToken"`
		} `json:"google"`
	}
	if json.Unmarshal(data, &secrets) != nil || secrets.Google == nil {
		return false
	}
	return secrets.Google.RefreshToken != ""
}

// swiftReferenceEpoch is what Foundation's JSONEncoder writes a Date as by
// default: seconds since 2001-01-01, not since 1970. HomeSpeaker's history
// file uses that default.
var swiftReferenceEpoch = time.Date(2001, 1, 1, 0, 0, 0, 0, time.UTC)

func (h *homeSpeaker) lastBroadcast() *homeSpeakerLast {
	data, err := os.ReadFile(h.historyPath)
	if err != nil {
		return nil
	}
	var items []struct {
		Timestamp  float64 `json:"timestamp"`
		Text       string  `json:"text"`
		TargetName string  `json:"targetName"`
		Source     string  `json:"source"`
	}
	if json.Unmarshal(data, &items) != nil || len(items) == 0 {
		return nil
	}
	// The app inserts newest first.
	it := items[0]
	return &homeSpeakerLast{
		Text:   it.Text,
		Target: it.TargetName,
		Source: it.Source,
		At:     swiftReferenceEpoch.Add(time.Duration(it.Timestamp * float64(time.Second))),
	}
}

// homeSpeakerUpdate is POST /v1/homespeaker. Every field is a pointer so an
// omitted one is "leave it alone" and never a zero value written by accident.
type homeSpeakerUpdate struct {
	Enabled           *bool   `json:"enabled"`
	DefaultTarget     *string `json:"default_target"`
	SpeechLength      *string `json:"speech_length"`
	QuietHoursEnabled *bool   `json:"quiet_hours_enabled"`
}

func (u homeSpeakerUpdate) empty() bool {
	return u.Enabled == nil && u.DefaultTarget == nil && u.SpeechLength == nil && u.QuietHoursEnabled == nil
}

// apply validates against the file as it is now and rewrites it. It returns
// what changed, for the act log.
func (h *homeSpeaker) apply(u homeSpeakerUpdate) (string, error) {
	cfg, err := h.readConfig()
	if err != nil {
		return "", err
	}
	var changed []string
	if u.Enabled != nil {
		cfg["enabled"] = *u.Enabled
		changed = append(changed, fmt.Sprintf("enabled=%v", *u.Enabled))
	}
	if u.DefaultTarget != nil {
		targets, _ := cfg["targets"].(map[string]any)
		if _, ok := targets[*u.DefaultTarget]; !ok {
			return "", &badRequest{fmt.Sprintf("unknown speaker %q; GET /v1/homespeaker lists the keys", *u.DefaultTarget)}
		}
		cfg["default_target"] = *u.DefaultTarget
		changed = append(changed, "default_target="+*u.DefaultTarget)
	}
	if u.SpeechLength != nil {
		ok := false
		for _, v := range speechLengths {
			ok = ok || v == *u.SpeechLength
		}
		if !ok {
			return "", &badRequest{fmt.Sprintf("speech_length must be one of %s", strings.Join(speechLengths, ", "))}
		}
		cfg["speech_length"] = *u.SpeechLength
		changed = append(changed, "speech_length="+*u.SpeechLength)
	}
	if u.QuietHoursEnabled != nil {
		cfg["quiet_hours_enabled"] = *u.QuietHoursEnabled
		changed = append(changed, fmt.Sprintf("quiet_hours_enabled=%v", *u.QuietHoursEnabled))
	}
	if err := h.writeConfig(cfg); err != nil {
		return "", err
	}
	return strings.Join(changed, " "), nil
}

// badRequest is a validation failure the handler turns into a 400; every
// other error from apply is the file system and a 500.
type badRequest struct{ msg string }

func (b *badRequest) Error() string { return b.msg }

// --- handlers -------------------------------------------------------------

// getHomeSpeaker is GET /v1/homespeaker: READ. Which speaker the Mac talks to
// is on its menu bar for anyone at the keyboard.
func (srv *server) getHomeSpeaker(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, srv.speaker.state(r.Context()))
}

// setHomeSpeaker is POST /v1/homespeaker: ACT. Answers with the state it
// ended in, read back from the file, so the phone renders what the Mac now
// believes rather than what it just asked for.
func (srv *server) setHomeSpeaker(w http.ResponseWriter, r *http.Request) {
	var body homeSpeakerUpdate
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if body.empty() {
		writeError(w, http.StatusBadRequest, "nothing to change: give enabled, default_target, speech_length or quiet_hours_enabled")
		return
	}
	changed, err := srv.speaker.apply(body)
	if err != nil {
		var bad *badRequest
		switch {
		case errors.As(err, &bad):
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, os.ErrNotExist):
			writeError(w, http.StatusConflict, "HomeSpeaker has not been set up on this Mac")
		default:
			writeError(w, http.StatusInternalServerError, err.Error())
		}
		return
	}
	logAct("homespeaker", changed)
	writeJSON(w, srv.speaker.state(r.Context()))
}

// homeSpeakerSay is POST /v1/homespeaker/say: ACT. The text is spoken in the
// house, which is at least as much of an act as the clipboard.
func (srv *server) homeSpeakerSay(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Text string `json:"text"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	text := strings.TrimSpace(body.Text)
	if text == "" {
		writeError(w, http.StatusBadRequest, "text is required")
		return
	}
	if _, err := os.Stat(srv.speaker.binary); err != nil {
		writeError(w, http.StatusConflict, "HomeSpeaker is not installed at "+srv.speaker.binary)
		return
	}
	logAct("homespeaker", "say "+text)
	// --say is deliberate speech: it overrides quiet hours but still honours
	// the master switch, and exits 1 with a reason on stderr when refused.
	stdout, stderr, err := srv.speaker.run(r.Context(), 30*time.Second, srv.speaker.binary, "--say", text)
	out := strings.TrimSpace(strings.TrimSpace(stdout) + "\n" + strings.TrimSpace(stderr))
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "output": strings.TrimSpace(out + "\n" + err.Error())})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "output": out})
}
