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
	"regexp"
	"sort"
	"strings"
	"syscall"
	"time"
	"unicode"
)

// HomeSpeaker (apps/desktop/home-speaker) from the phone: is it on, which
// speaker does it talk to, how much does it say, and say this now.
//
// The agent never imports HomeSpeaker's code -- the inter-app boundary (#82)
// forbids it, and it would be the wrong design anyway. The two apps already
// share one contract: the config file at ~/.gemini/speaker_broadcast.json (or
// the Vitruvian extension's ToolData/dev.vitruvian.homespeaker/settings.json
// when ~/.gemini/speaker_door.json selects the extension door), which
// HomeSpeaker, its Claude Code hook and the `speaker-broadcast` CLI all read.
// The agent reads and rewrites that file, and HomeSpeaker watches it. To SAY
// something it runs the active door's binary with `--say`, so the announcement
// goes through HomeSpeaker's sign-in, target resolution and speech cleaning
// rather than a second copy of them here.

// homeSpeaker is where the app keeps its state, and how to run it. Fields
// rather than constants so a test can point them at a temp dir and a fake
// binary; newHomeSpeaker fills in the real ones.
type homeSpeaker struct {
	configPath  string
	historyPath string
	secretsPath string
	doorPath    string
	// binary is the app's executable inside its bundle, used for --say.
	binary string
	// run executes the binary. runToolWithin in production.
	run func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error)
	// say executes the binary for --say. Nil falls back to run; production
	// sets runAsPersonWithin, which hides the coding-agent markers in the
	// agent's own environment so a sentence typed on the phone is never
	// taken for a Claude Code or Antigravity reply (see personEnv).
	say func(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error)
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
		doorPath:    filepath.Join(home, ".gemini", "speaker_door.json"),
		binary:      homeSpeakerBinary,
		run:         runToolWithin,
		say:         runAsPersonWithin,
		running: func(ctx context.Context) bool {
			return exec.CommandContext(ctx, "pgrep", "-x", "HomeSpeaker").Run() == nil
		},
	}
}

// homeSpeakerProfile is the resolved file and binary layout for whichever
// distribution (standalone .app or Vitruvian extension) is active on this Mac.
type homeSpeakerProfile struct {
	activeDoor  string
	configPath  string
	historyPath string
	secretsPath string
	binary      string
	lockPath    string
}

func isInTrash(path string) bool {
	return strings.Contains(path, "/.Trash/") || strings.Contains(path, "/.Trashes/")
}

// deriveExtensionDataFolder mirrors HomeSpeakerProfile.extensionFolders in
// apps/desktop/home-speaker/Sources/HomeSpeakerCore/Profile.swift:
// .../Tools/<id>/bin/tool -> .../ToolData/<id>.
func deriveExtensionDataFolder(program string) string {
	if filepath.Base(program) != "tool" {
		return ""
	}
	binDir := filepath.Dir(program)
	if filepath.Base(binDir) != "bin" {
		return ""
	}
	extDir := filepath.Dir(binDir)
	extID := filepath.Base(extDir)
	toolsDir := filepath.Dir(extDir)
	if filepath.Base(toolsDir) != "Tools" || extID == "" || extID == "." {
		return ""
	}
	rootDir := filepath.Dir(toolsDir)
	return filepath.Join(rootDir, "ToolData", extID)
}

// activeProfile reads ~/.gemini/speaker_door.json (DoorFile in
// apps/desktop/home-speaker/Sources/HomeSpeakerCore/Door.swift) and resolves
// whether the Vitruvian extension or the standalone .app is the active door.
func (h *homeSpeaker) activeProfile() homeSpeakerProfile {
	appProfile := homeSpeakerProfile{
		activeDoor:  "app",
		configPath:  h.configPath,
		historyPath: h.historyPath,
		secretsPath: h.secretsPath,
		binary:      h.binary,
	}
	if h.doorPath == "" {
		return appProfile
	}
	data, err := os.ReadFile(h.doorPath)
	if err != nil {
		return appProfile
	}
	var door struct {
		Chosen    string `json:"chosen"`
		Extension *struct {
			Program    string `json:"program"`
			DataFolder string `json:"data_folder"`
			Version    string `json:"version"`
			Door       int    `json:"door"`
		} `json:"extension"`
	}
	if json.Unmarshal(data, &door) != nil || door.Extension == nil {
		return appProfile
	}
	prog := strings.TrimSpace(door.Extension.Program)
	if prog == "" || isInTrash(prog) {
		return appProfile
	}
	if _, err := os.Stat(prog); err != nil {
		return appProfile
	}
	dataFolder := strings.TrimSpace(door.Extension.DataFolder)
	if dataFolder == "" {
		dataFolder = deriveExtensionDataFolder(prog)
	}
	if dataFolder == "" {
		return appProfile
	}
	useExtension := false
	switch door.Chosen {
	case "extension":
		useExtension = true
	case "":
		_, appErr := os.Stat(h.binary)
		appInstalled := appErr == nil && !isInTrash(h.binary)
		useExtension = !appInstalled
	}
	if !useExtension {
		return appProfile
	}
	return homeSpeakerProfile{
		activeDoor:  "extension",
		configPath:  filepath.Join(dataFolder, "settings.json"),
		historyPath: filepath.Join(dataFolder, "history.json"),
		secretsPath: filepath.Join(dataFolder, "secrets.json"),
		binary:      prog,
		lockPath:    filepath.Join(dataFolder, "running.lock"),
	}
}

// isLockHeld checks whether the extension holds an exclusive flock on
// running.lock (LiveLock in apps/desktop/home-speaker). If the probe acquires
// the lock, it unlocks immediately and reports false.
func isLockHeld(path string) bool {
	if path == "" {
		return false
	}
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	for {
		err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if !errors.Is(err, syscall.EINTR) {
			break
		}
	}
	if err == nil {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		return false
	}
	return errors.Is(err, syscall.EWOULDBLOCK) || errors.Is(err, syscall.EAGAIN)
}

func (h *homeSpeaker) isRunning(ctx context.Context, p homeSpeakerProfile) bool {
	if p.activeDoor == "extension" {
		if isLockHeld(p.lockPath) {
			return true
		}
		return exec.CommandContext(ctx, "pgrep", "-f", p.binary).Run() == nil
	}
	if h.running != nil {
		return h.running(ctx)
	}
	return false
}

// speechLengths, localEngines, geminiVoices, announcementStyles and styleModels
// are the values HomeSpeaker accepts (Models.swift in apps/desktop/home-speaker).
// Anything else is refused here rather than written and silently ignored by the app.
var (
	speechLengths       = []string{"headline", "summary", "full"}
	localEngines        = []string{"apple", "gemini"}
	geminiVoices        = []string{"Kore", "Puck", "Aoede", "Charon", "Zephyr", "Fenrir", "Leda", "Orus"}
	announcementStyles  = []string{"verbatim", "plain", "briefing", "casual"}
	styleModels         = []string{"apple", "gemini"}
	beeperAnnounceModes = []string{"direct_and_mentions", "all"}
	beeperNetworkKeyRe  = regexp.MustCompile("^[a-z0-9_-]{1,64}$")
)

// homeSpeakerState is GET /v1/homespeaker.
type homeSpeakerState struct {
	Available bool   `json:"available"`
	Reason    string `json:"reason,omitempty"`
	// Installed says the app bundle or active extension binary is present;
	// AppRunning that the menu bar process or extension daemon is up. Both
	// false with a config file present means the CLI or an old install wrote it.
	Installed  bool   `json:"installed"`
	AppRunning bool   `json:"app_running"`
	SignedIn   bool   `json:"signed_in"`
	ActiveDoor string `json:"active_door"`

	Enabled       bool   `json:"enabled"`
	DefaultTarget string `json:"default_target"`
	SpeechLength  string `json:"speech_length"`
	// PauseMedia: HomeSpeaker pauses what the Mac is playing while it
	// announces (1.8+). PauseMediaExtraSeconds is how long after the
	// estimated end of the announcement it waits to resume.
	PauseMedia             bool    `json:"pause_media"`
	PauseMediaExtraSeconds float64 `json:"pause_media_extra_seconds"`
	// AnnounceVolume*: HomeSpeaker sets the speaker to AnnounceVolume for each
	// announcement and puts it back after (1.9+).
	AnnounceVolumeEnabled bool `json:"announce_volume_enabled"`
	AnnounceVolume        int  `json:"announce_volume"`
	// SpeakHome / SpeakLocal: where an announcement is spoken -- the Google
	// Home target, this Mac, both or neither (HomeSpeaker's local speech,
	// apps/desktop/home-speaker/docs/local-speech.md). LocalVoice is the
	// Mac's AVSpeechSynthesisVoice identifier, chosen on the Mac;
	// LocalVoiceName is the same voice for people ("Aaron").
	SpeakHome      bool   `json:"speak_home"`
	SpeakLocal     bool   `json:"speak_local"`
	LocalVoice     string `json:"local_voice"`
	LocalVoiceName string `json:"local_voice_name"`
	// LocalEngine / GeminiVoice / HasGeminiKey (HomeSpeaker 1.15+): whether
	// "This Mac" uses Apple's on-device voice ("apple") or Gemini TTS
	// ("gemini"), which prebuilt Gemini voice is selected, and whether a
	// Gemini API key is saved in secrets.json.
	LocalEngine  string `json:"local_engine"`
	GeminiVoice  string `json:"gemini_voice"`
	HasGeminiKey bool   `json:"has_gemini_key"`
	// AnnouncementStyle / StyleModel (HomeSpeaker 1.17+): how announcements
	// are rewritten before speaking ("verbatim", "plain", "briefing",
	// "casual") and which model performs the rewrite ("apple", "gemini").
	AnnouncementStyle string `json:"announcement_style"`
	StyleModel        string `json:"style_model"`

	StructureName string              `json:"structure_name"`
	QuietHours    homeSpeakerQuiet    `json:"quiet_hours"`
	Targets       []homeSpeakerTarget `json:"targets"`
	Last          *homeSpeakerLast    `json:"last,omitempty"`

	// Sources (HomeSpeaker 1.23+, apps/desktop/home-speaker BroadcastSource):
	// which senders are spoken, each under the master switch (Enabled).
	// Pointers so the field is always present from this agent and absent from
	// an older one -- the phone then hides the switches instead of guessing,
	// the same rule as speak_home / speak_local.
	//
	// AnnounceClaudeCode / AnnounceAntigravity / AnnounceOpenCode are top-level
	// keys and default to true when absent: a config written before they existed
	// still speaks for all coding agents, as it did. The chat apps live under
	// chat_monitor and default to false: nothing is read until someone turns it on.
	AnnounceClaudeCode  *bool `json:"announce_claude_code"`
	AnnounceAntigravity *bool `json:"announce_antigravity"`
	AnnounceOpenCode    *bool `json:"announce_opencode"`
	SlackEnabled        *bool `json:"slack_enabled"`
	GoogleChatEnabled   *bool `json:"google_chat_enabled"`
	BeeperEnabled       *bool `json:"beeper_enabled"`
	// BeeperAnnounce / BeeperNetworks / MuteOwnMessages (HomeSpeaker 1.19+):
	// which Beeper messages are spoken ("direct_and_mentions" or "all"),
	// the discovered Beeper networks merged with beeper_muted_networks,
	// and whether messages sent by the user's own account are skipped.
	BeeperAnnounce  string                     `json:"beeper_announce"`
	BeeperNetworks  []homeSpeakerBeeperNetwork `json:"beeper_networks"`
	MuteOwnMessages *bool                      `json:"mute_own_messages"`
	// Recent is the newest few broadcasts, newest first, so the phone can
	// list and replay them. Last stays for phones that predate it; it is
	// always Recent[0] when both are present.
	Recent []homeSpeakerLast `json:"recent"`
}

type homeSpeakerBeeperNetwork struct {
	Key   string `json:"key"`
	Name  string `json:"name"`
	State string `json:"state"`
}

type homeSpeakerBeeperNetworkUpdate struct {
	Key     string `json:"key"`
	Reading bool   `json:"reading"`
}

// recentBroadcasts is how many history entries GET /v1/homespeaker returns.
const recentBroadcasts = 5

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
	p := h.activeProfile()
	data, err := os.ReadFile(p.configPath)
	if err != nil {
		return nil, err
	}
	var cfg map[string]any
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("%s: %w", filepath.Base(p.configPath), err)
	}
	return cfg, nil
}

// writeConfig replaces the file atomically. HomeSpeaker watches the directory
// for exactly this rename, and its own saves are atomic too, so neither side
// ever reads the other's half-written file.
func (h *homeSpeaker) writeConfig(cfg map[string]any) error {
	p := h.activeProfile()
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	tmp := p.configPath + ".agent-tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, p.configPath)
}

func stringIn(m map[string]any, key string, allowed []string, def string) string {
	if v, ok := m[key].(string); ok {
		for _, a := range allowed {
			if v == a {
				return v
			}
		}
	}
	return def
}

func (h *homeSpeaker) state(ctx context.Context) homeSpeakerState {
	p := h.activeProfile()
	st := homeSpeakerState{ActiveDoor: p.activeDoor}
	if _, err := os.Stat(p.binary); err == nil {
		st.Installed = true
	}
	cfg, err := h.readConfig()
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			st.Reason = "HomeSpeaker has not been set up on this Mac (no " + p.configPath + ")"
		} else {
			st.Reason = err.Error()
		}
		return st
	}
	st.Available = true
	st.AppRunning = h.isRunning(ctx, p)
	st.SignedIn = h.signedIn()
	st.HasGeminiKey = h.hasGeminiKey()
	st.Enabled, _ = cfg["enabled"].(bool)
	st.DefaultTarget, _ = cfg["default_target"].(string)
	st.SpeechLength, _ = cfg["speech_length"].(string)
	if st.SpeechLength == "" {
		// The app's own default when the key is absent (SpeakerConfig.effectiveSpeechLength).
		st.SpeechLength = "summary"
	}
	// Absent means the app's defaults (SpeakerConfig.effectivePauseMedia*):
	// off, and one second.
	st.PauseMedia, _ = cfg["pause_media"].(bool)
	st.PauseMediaExtraSeconds = 1
	if v, ok := cfg["pause_media_extra_seconds"].(float64); ok {
		st.PauseMediaExtraSeconds = v
	}
	// The app's defaults when absent (SpeakerConfig.effectiveAnnounceVolume*):
	// off, and 60 %.
	st.AnnounceVolumeEnabled, _ = cfg["announce_volume_enabled"].(bool)
	st.AnnounceVolume = 60
	if v, ok := cfg["announce_volume"].(float64); ok {
		st.AnnounceVolume = int(v)
	}
	// Absent means today's behaviour (local-speech.md): home speakers on,
	// this Mac off, and Siri's Aaron as the Mac's voice.
	st.SpeakHome = true
	if v, ok := cfg["speak_home"].(bool); ok {
		st.SpeakHome = v
	}
	st.SpeakLocal, _ = cfg["speak_local"].(bool)
	st.LocalVoice = defaultLocalVoice
	if v, ok := cfg["local_voice"].(string); ok && strings.TrimSpace(v) != "" {
		st.LocalVoice = v
	}
	st.LocalVoiceName = voiceName(st.LocalVoice)
	st.LocalEngine = stringIn(cfg, "local_engine", localEngines, "apple")
	st.GeminiVoice = stringIn(cfg, "gemini_voice", geminiVoices, "Kore")
	st.AnnouncementStyle = stringIn(cfg, "announcement_style", announcementStyles, "verbatim")
	st.StyleModel = stringIn(cfg, "style_model", styleModels, "apple")
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
	st.AnnounceClaudeCode = boolOr(cfg, "announce_claude_code", true)
	st.AnnounceAntigravity = boolOr(cfg, "announce_antigravity", true)
	st.AnnounceOpenCode = boolOr(cfg, "announce_opencode", true)
	monitor, _ := cfg["chat_monitor"].(map[string]any)
	st.SlackEnabled = boolOr(monitor, "slack_enabled", false)
	st.GoogleChatEnabled = boolOr(monitor, "google_chat_enabled", false)
	st.BeeperEnabled = boolOr(monitor, "beeper_enabled", false)
	st.BeeperAnnounce = stringIn(monitor, "beeper_announce", beeperAnnounceModes, "direct_and_mentions")
	st.MuteOwnMessages = boolOr(monitor, "mute_own_messages", true)
	st.BeeperNetworks = h.beeperNetworks(p, st.AppRunning, monitor)
	// Never null on the wire: [] says "no history", where a missing or null
	// field would read as an agent that predates it.
	st.Recent = append([]homeSpeakerLast{}, h.recentBroadcasts(recentBroadcasts)...)
	if len(st.Recent) > 0 {
		st.Last = &st.Recent[0]
	}
	return st
}

func mutedNetworksFromMonitor(monitor map[string]any) []string {
	if monitor == nil {
		return nil
	}
	switch raw := monitor["beeper_muted_networks"].(type) {
	case []any:
		out := make([]string, 0, len(raw))
		for _, v := range raw {
			if s, ok := v.(string); ok && strings.TrimSpace(s) != "" {
				out = append(out, s)
			}
		}
		return out
	case []string:
		out := make([]string, 0, len(raw))
		for _, s := range raw {
			if strings.TrimSpace(s) != "" {
				out = append(out, s)
			}
		}
		return out
	default:
		return nil
	}
}

// beeperNetworks mirrors BeeperNetworkList in
// apps/desktop/home-speaker/Sources/HomeSpeakerCore/ChatMonitorStatus.swift:
// when the active door is running and speaker_monitor_status.json reports
// is_running:true, its beeper_network_states are merged with
// chat_monitor.beeper_muted_networks ("skipped" stays "skipped"; everything
// else is "muted" or "reading", plus any muted keys not yet discovered),
// sorted case-insensitively by display name.
func (h *homeSpeaker) beeperNetworks(p homeSpeakerProfile, appRunning bool, monitor map[string]any) []homeSpeakerBeeperNetwork {
	var listed []homeSpeakerBeeperNetwork
	if appRunning && p.configPath != "" {
		statusPath := filepath.Join(filepath.Dir(p.configPath), "speaker_monitor_status.json")
		if data, err := os.ReadFile(statusPath); err == nil {
			var status struct {
				IsRunning           bool                       `json:"is_running"`
				BeeperNetworkStates []homeSpeakerBeeperNetwork `json:"beeper_network_states"`
			}
			if json.Unmarshal(data, &status) == nil && status.IsRunning {
				listed = status.BeeperNetworkStates
			}
		}
	}
	muted := mutedNetworksFromMonitor(monitor)
	mutedSet := make(map[string]bool, len(muted))
	for _, k := range muted {
		mutedSet[k] = true
	}
	rows := make([]homeSpeakerBeeperNetwork, 0, len(listed)+len(muted))
	seen := make(map[string]bool, len(listed)+len(muted))
	for _, row := range listed {
		if strings.TrimSpace(row.Key) == "" {
			continue
		}
		if row.Name == "" {
			row.Name = row.Key
		}
		if row.State != "skipped" {
			if mutedSet[row.Key] {
				row.State = "muted"
			} else {
				row.State = "reading"
			}
		}
		rows = append(rows, row)
		seen[row.Key] = true
	}
	for _, key := range muted {
		if !seen[key] {
			rows = append(rows, homeSpeakerBeeperNetwork{Key: key, Name: key, State: "muted"})
			seen[key] = true
		}
	}
	sort.Slice(rows, func(i, j int) bool {
		li, lj := strings.ToLower(rows[i].Name), strings.ToLower(rows[j].Name)
		if li != lj {
			return li < lj
		}
		return rows[i].Key < rows[j].Key
	})
	return rows
}

// boolOr is m[key] when it is a bool, else def -- always as a pointer, so the
// JSON field is present. A nil map (no chat_monitor yet) reads as defaults.
func boolOr(m map[string]any, key string, def bool) *bool {
	v := def
	if b, ok := m[key].(bool); ok {
		v = b
	}
	return &v
}

// defaultLocalVoice is HomeSpeaker's voice for this Mac when local_voice is
// absent (local-speech.md).
const defaultLocalVoice = "com.apple.ttsbundle.siri_Aaron_en-US_premium"

// voiceName is an AVSpeechSynthesisVoice identifier for people: the name is
// its last dotted component ("com.apple.siri.natural.Aaron" -> "Aaron",
// "com.apple.voice.premium.en-US.Zoe" -> "Zoe"). An identifier that does not
// end in a plain name -- one ending in a locale or a bundle suffix -- is shown
// raw rather than as a guess.
func voiceName(id string) string {
	// Installable Siri bundles: "com.apple.ttsbundle.siri_Aaron_en-US_premium" -> "Aaron".
	if m := siriBundleName.FindStringSubmatch(id); m != nil {
		return m[1]
	}
	i := strings.LastIndex(id, ".")
	if i < 0 || i == len(id)-1 {
		return id
	}
	name := id[i+1:]
	for _, r := range name {
		if !unicode.IsLetter(r) {
			return id
		}
	}
	return name
}

var siriBundleName = regexp.MustCompile(`^com\.apple\.ttsbundle\.siri_([A-Za-z]+)_`)

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
	p := h.activeProfile()
	data, err := os.ReadFile(p.secretsPath)
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

// hasGeminiKey is "there is a Gemini API key saved in secrets.json", without
// ever reading the key into a response or a log.
func (h *homeSpeaker) hasGeminiKey() bool {
	p := h.activeProfile()
	data, err := os.ReadFile(p.secretsPath)
	if err != nil {
		return false
	}
	var secrets struct {
		GeminiAPIKey string `json:"geminiAPIKey"`
	}
	if json.Unmarshal(data, &secrets) != nil {
		return false
	}
	return strings.TrimSpace(secrets.GeminiAPIKey) != ""
}

// swiftReferenceEpoch is what Foundation's JSONEncoder writes a Date as by
// default: seconds since 2001-01-01, not since 1970. HomeSpeaker's history
// file uses that default.
var swiftReferenceEpoch = time.Date(2001, 1, 1, 0, 0, 0, 0, time.UTC)

// recentBroadcasts is up to n history entries, newest first (the app
// inserts at the front). An unreadable or missing file is no history, not an
// error: the phone shows "nothing spoken yet".
func (h *homeSpeaker) recentBroadcasts(n int) []homeSpeakerLast {
	p := h.activeProfile()
	data, err := os.ReadFile(p.historyPath)
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
	if len(items) > n {
		items = items[:n]
	}
	out := make([]homeSpeakerLast, 0, len(items))
	for _, it := range items {
		out = append(out, homeSpeakerLast{
			Text:   it.Text,
			Target: it.TargetName,
			Source: it.Source,
			At:     swiftReferenceEpoch.Add(time.Duration(it.Timestamp * float64(time.Second))),
		})
	}
	return out
}

// homeSpeakerUpdate is POST /v1/homespeaker. Every field is a pointer so an
// omitted one is "leave it alone" and never a zero value written by accident.
type homeSpeakerUpdate struct {
	Enabled                *bool    `json:"enabled"`
	DefaultTarget          *string  `json:"default_target"`
	SpeechLength           *string  `json:"speech_length"`
	QuietHoursEnabled      *bool    `json:"quiet_hours_enabled"`
	PauseMedia             *bool    `json:"pause_media"`
	PauseMediaExtraSeconds *float64 `json:"pause_media_extra_seconds"`
	AnnounceVolumeEnabled  *bool    `json:"announce_volume_enabled"`
	AnnounceVolume         *int     `json:"announce_volume"`
	// SpeakHome / SpeakLocal switch the two outputs. The Mac's Apple voice is
	// not settable here on purpose: which voices are installed is only known on
	// the Mac, so it is chosen there. LocalEngine and GeminiVoice ARE settable:
	// the Gemini prebuilt voice list is fixed across every Mac.
	SpeakHome         *bool   `json:"speak_home"`
	SpeakLocal        *bool   `json:"speak_local"`
	LocalEngine       *string `json:"local_engine"`
	GeminiVoice       *string `json:"gemini_voice"`
	AnnouncementStyle *string `json:"announcement_style"`
	StyleModel        *string `json:"style_model"`
	// The sources (HomeSpeaker 1.23+). The coding agents are top-level
	// keys; the chat apps are written inside chat_monitor, keeping every
	// other key there (poll interval, Beeper's URL and token, ...).
	AnnounceClaudeCode  *bool                           `json:"announce_claude_code"`
	AnnounceAntigravity *bool                           `json:"announce_antigravity"`
	AnnounceOpenCode    *bool                           `json:"announce_opencode"`
	SlackEnabled        *bool                           `json:"slack_enabled"`
	GoogleChatEnabled   *bool                           `json:"google_chat_enabled"`
	BeeperEnabled       *bool                           `json:"beeper_enabled"`
	BeeperAnnounce      *string                         `json:"beeper_announce"`
	BeeperNetwork       *homeSpeakerBeeperNetworkUpdate `json:"beeper_network"`
	MuteOwnMessages     *bool                           `json:"mute_own_messages"`
}

// pauseMediaExtraMax is the app's own ceiling (Settings' stepper, 0-10 s).
const pauseMediaExtraMax = 10.0

func (u homeSpeakerUpdate) empty() bool {
	return u.Enabled == nil && u.DefaultTarget == nil && u.SpeechLength == nil &&
		u.QuietHoursEnabled == nil && u.PauseMedia == nil && u.PauseMediaExtraSeconds == nil &&
		u.AnnounceVolumeEnabled == nil && u.AnnounceVolume == nil &&
		u.SpeakHome == nil && u.SpeakLocal == nil &&
		u.LocalEngine == nil && u.GeminiVoice == nil &&
		u.AnnouncementStyle == nil && u.StyleModel == nil &&
		u.AnnounceClaudeCode == nil && u.AnnounceAntigravity == nil && u.AnnounceOpenCode == nil &&
		u.SlackEnabled == nil && u.GoogleChatEnabled == nil && u.BeeperEnabled == nil &&
		u.BeeperAnnounce == nil && u.BeeperNetwork == nil && u.MuteOwnMessages == nil
}

func validateEnum(field, val string, allowed []string) error {
	for _, a := range allowed {
		if val == a {
			return nil
		}
	}
	return &badRequest{fmt.Sprintf("%s must be one of %s", field, strings.Join(allowed, ", "))}
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
		if err := validateEnum("speech_length", *u.SpeechLength, speechLengths); err != nil {
			return "", err
		}
		cfg["speech_length"] = *u.SpeechLength
		changed = append(changed, "speech_length="+*u.SpeechLength)
	}
	if u.QuietHoursEnabled != nil {
		cfg["quiet_hours_enabled"] = *u.QuietHoursEnabled
		changed = append(changed, fmt.Sprintf("quiet_hours_enabled=%v", *u.QuietHoursEnabled))
	}
	if u.PauseMedia != nil {
		cfg["pause_media"] = *u.PauseMedia
		changed = append(changed, fmt.Sprintf("pause_media=%v", *u.PauseMedia))
	}
	if u.PauseMediaExtraSeconds != nil {
		// Refused rather than clamped: the app would clamp it silently and the
		// phone would show a value the Mac is not using.
		if v := *u.PauseMediaExtraSeconds; v < 0 || v > pauseMediaExtraMax {
			return "", &badRequest{fmt.Sprintf("pause_media_extra_seconds must be between 0 and %g", pauseMediaExtraMax)}
		}
		cfg["pause_media_extra_seconds"] = *u.PauseMediaExtraSeconds
		changed = append(changed, fmt.Sprintf("pause_media_extra_seconds=%g", *u.PauseMediaExtraSeconds))
	}
	if u.AnnounceVolumeEnabled != nil {
		cfg["announce_volume_enabled"] = *u.AnnounceVolumeEnabled
		changed = append(changed, fmt.Sprintf("announce_volume_enabled=%v", *u.AnnounceVolumeEnabled))
	}
	if u.AnnounceVolume != nil {
		if v := *u.AnnounceVolume; v < 0 || v > 100 {
			return "", &badRequest{"announce_volume must be between 0 and 100"}
		}
		cfg["announce_volume"] = *u.AnnounceVolume
		changed = append(changed, fmt.Sprintf("announce_volume=%d", *u.AnnounceVolume))
	}
	// Both off is allowed: the user asked for silence, and HomeSpeaker says
	// so ("No outputs selected") rather than the agent overruling it.
	if u.SpeakHome != nil {
		cfg["speak_home"] = *u.SpeakHome
		changed = append(changed, fmt.Sprintf("speak_home=%v", *u.SpeakHome))
	}
	if u.SpeakLocal != nil {
		cfg["speak_local"] = *u.SpeakLocal
		changed = append(changed, fmt.Sprintf("speak_local=%v", *u.SpeakLocal))
	}
	if u.LocalEngine != nil {
		if err := validateEnum("local_engine", *u.LocalEngine, localEngines); err != nil {
			return "", err
		}
		cfg["local_engine"] = *u.LocalEngine
		changed = append(changed, "local_engine="+*u.LocalEngine)
	}
	if u.GeminiVoice != nil {
		if err := validateEnum("gemini_voice", *u.GeminiVoice, geminiVoices); err != nil {
			return "", err
		}
		cfg["gemini_voice"] = *u.GeminiVoice
		changed = append(changed, "gemini_voice="+*u.GeminiVoice)
	}
	if u.AnnouncementStyle != nil {
		if err := validateEnum("announcement_style", *u.AnnouncementStyle, announcementStyles); err != nil {
			return "", err
		}
		cfg["announcement_style"] = *u.AnnouncementStyle
		changed = append(changed, "announcement_style="+*u.AnnouncementStyle)
	}
	if u.StyleModel != nil {
		if err := validateEnum("style_model", *u.StyleModel, styleModels); err != nil {
			return "", err
		}
		cfg["style_model"] = *u.StyleModel
		changed = append(changed, "style_model="+*u.StyleModel)
	}
	for _, f := range []struct {
		key string
		v   *bool
	}{
		{"announce_claude_code", u.AnnounceClaudeCode},
		{"announce_antigravity", u.AnnounceAntigravity},
		{"announce_opencode", u.AnnounceOpenCode},
	} {
		if f.v != nil {
			cfg[f.key] = *f.v
			changed = append(changed, fmt.Sprintf("%s=%v", f.key, *f.v))
		}
	}
	monitorFields := []struct {
		key string
		v   *bool
	}{
		{"slack_enabled", u.SlackEnabled},
		{"google_chat_enabled", u.GoogleChatEnabled},
		{"beeper_enabled", u.BeeperEnabled},
		{"mute_own_messages", u.MuteOwnMessages},
	}
	for _, f := range monitorFields {
		if f.v == nil {
			continue
		}
		// The same map, edited in place: every key the app keeps there
		// survives. A chat_monitor that is missing or not an object starts
		// fresh rather than failing the whole change.
		monitor := ensureChatMonitor(cfg)
		monitor[f.key] = *f.v
		changed = append(changed, fmt.Sprintf("chat_monitor.%s=%v", f.key, *f.v))
	}
	if u.BeeperAnnounce != nil {
		if err := validateEnum("beeper_announce", *u.BeeperAnnounce, beeperAnnounceModes); err != nil {
			return "", err
		}
		monitor := ensureChatMonitor(cfg)
		monitor["beeper_announce"] = *u.BeeperAnnounce
		changed = append(changed, "chat_monitor.beeper_announce="+*u.BeeperAnnounce)
	}
	if u.BeeperNetwork != nil {
		key := strings.TrimSpace(u.BeeperNetwork.Key)
		if !beeperNetworkKeyRe.MatchString(key) {
			return "", &badRequest{fmt.Sprintf("invalid beeper_network.key %q", u.BeeperNetwork.Key)}
		}
		monitor := ensureChatMonitor(cfg)
		muted := mutedNetworksFromMonitor(monitor)
		next := make([]string, 0, len(muted)+1)
		for _, existing := range muted {
			if existing != key {
				next = append(next, existing)
			}
		}
		if !u.BeeperNetwork.Reading {
			next = append(next, key)
		}
		monitor["beeper_muted_networks"] = next
		changed = append(changed, fmt.Sprintf("chat_monitor.beeper_network.%s=%v", key, u.BeeperNetwork.Reading))
	}
	if err := h.writeConfig(cfg); err != nil {
		return "", err
	}
	return strings.Join(changed, " "), nil
}

func ensureChatMonitor(cfg map[string]any) map[string]any {
	monitor, ok := cfg["chat_monitor"].(map[string]any)
	if !ok {
		monitor = map[string]any{}
		cfg["chat_monitor"] = monitor
	}
	return monitor
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
		writeError(w, http.StatusBadRequest, "nothing to change: give enabled, default_target, speech_length, quiet_hours_enabled, pause_media, pause_media_extra_seconds, announce_volume_enabled, announce_volume, speak_home, speak_local, local_engine, gemini_voice, announcement_style, style_model, announce_claude_code, announce_antigravity, announce_opencode, slack_enabled, google_chat_enabled, beeper_enabled, beeper_announce, beeper_network or mute_own_messages")
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

// sayLimit bounds POST /v1/homespeaker/say: Gemini TTS synthesis + local
// audio playback + Google Home broadcast can legitimately exceed 30 s.
const sayLimit = 90 * time.Second

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
	p := srv.speaker.activeProfile()
	if _, err := os.Stat(p.binary); err != nil {
		writeError(w, http.StatusConflict, "HomeSpeaker is not installed at "+p.binary)
		return
	}
	logAct("homespeaker", "say "+text)
	// --say is deliberate speech: it overrides quiet hours but still honours
	// the master switch, and exits 1 with a reason on stderr when refused.
	// The phone's Say box and its Replay both come here; HomeSpeaker lists
	// the line in its history again either way (its CLI has no flag that
	// leaves history alone).
	//
	// Run as a person, not as whichever coding agent's shell started this
	// agent: HomeSpeaker 1.23+ infers the sender from CLAUDECODE /
	// ANTIGRAVITY_AGENT, and would then hold a replay to that agent's
	// switch. Hiding the markers works on every HomeSpeaker version, where
	// `--source user` would be refused by one older than 1.23.
	run := srv.speaker.say
	if run == nil {
		run = srv.speaker.run
	}
	stdout, stderr, err := run(r.Context(), sayLimit, p.binary, "--say", text)
	out := strings.TrimSpace(strings.TrimSpace(stdout) + "\n" + strings.TrimSpace(stderr))
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "output": strings.TrimSpace(out + "\n" + err.Error())})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "output": out})
}

// agentMarkers are the environment variables HomeSpeaker reads to decide
// that a coding agent, not a person, is speaking (BroadcastSource.inferred).
var agentMarkers = []string{"CLAUDECODE", "ANTIGRAVITY_AGENT", "OPENCODE", "AI_AGENT"}

// personEnv is env without the agent markers.
func personEnv(env []string) []string {
	out := make([]string, 0, len(env))
	for _, kv := range env {
		name, _, _ := strings.Cut(kv, "=")
		keep := true
		for _, m := range agentMarkers {
			if name == m {
				keep = false
				break
			}
		}
		if keep {
			out = append(out, kv)
		}
	}
	return out
}

// runAsPersonWithin is runToolWithin with personEnv applied.
func runAsPersonWithin(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error) {
	ctx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Env = personEnv(os.Environ())
	var stdout, stderr strings.Builder
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

// --- v1.5: the speaker's volume ------------------------------------------

// homeSpeakerVolume is GET/POST /v1/homespeaker/volume: the default speaker's
// volume, as HomeSpeaker's own --volume / --set-volume / --mute / --unmute
// print it. The agent only relays: the app holds the Google sign-in, knows
// that a Nest Hub is addressed as its speaker component, and waits out the
// ~3 s before Google reports a change.
type homeSpeakerVolume struct {
	Available bool   `json:"available"`
	Reason    string `json:"reason,omitempty"`
	Speaker   string `json:"speaker,omitempty"`
	Percent   int    `json:"percent"`
	Muted     bool   `json:"muted"`
	Online    bool   `json:"online"`
}

// volumeLimit bounds one call: a set is two confirm windows plus a retry in
// the app (its own limit is 40 s).
const volumeLimit = 45 * time.Second

// runVolume runs HomeSpeaker with a volume flag and parses its JSON. The app
// answers failures in JSON too (exit 1), so a non-zero exit with a parseable
// line is still an answer; only no JSON at all is an error here.
func (h *homeSpeaker) runVolume(ctx context.Context, args ...string) homeSpeakerVolume {
	p := h.activeProfile()
	if _, err := os.Stat(p.binary); err != nil {
		return homeSpeakerVolume{Reason: "HomeSpeaker is not installed at " + p.binary}
	}
	stdout, stderr, err := h.run(ctx, volumeLimit, p.binary, args...)
	var v homeSpeakerVolume
	for _, line := range strings.Split(strings.TrimSpace(stdout), "\n") {
		if json.Unmarshal([]byte(line), &v) == nil {
			return v
		}
	}
	reason := strings.TrimSpace(stderr)
	if reason == "" && err != nil {
		reason = err.Error()
	}
	if reason == "" {
		reason = "HomeSpeaker printed no volume (is it version 1.9 or later?)"
	}
	return homeSpeakerVolume{Reason: reason}
}

// getHomeSpeakerVolume is READ, like /v1/audio for the Mac's own volume: it is
// what the speaker's own buttons show anyone in the room.
func (srv *server) getHomeSpeakerVolume(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, srv.speaker.runVolume(r.Context(), "--volume"))
}

// setHomeSpeakerVolume is ACT: {"percent": 0-100} or {"muted": bool}, exactly
// one. Answers with the level Google reports afterwards.
func (srv *server) setHomeSpeakerVolume(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Percent *int  `json:"percent"`
		Muted   *bool `json:"muted"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	var args []string
	switch {
	case body.Percent != nil && body.Muted != nil, body.Percent == nil && body.Muted == nil:
		writeError(w, http.StatusBadRequest, `give exactly one of "percent" (0-100) or "muted"`)
		return
	case body.Percent != nil:
		if *body.Percent < 0 || *body.Percent > 100 {
			writeError(w, http.StatusBadRequest, "percent must be between 0 and 100")
			return
		}
		args = []string{"--set-volume", fmt.Sprint(*body.Percent)}
	case *body.Muted:
		args = []string{"--mute"}
	default:
		args = []string{"--unmute"}
	}
	logAct("homespeaker", "volume "+strings.Join(args, " "))
	writeJSON(w, srv.speaker.runVolume(r.Context(), args...))
}
