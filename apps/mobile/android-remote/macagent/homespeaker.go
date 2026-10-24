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
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
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
	configPath            string
	historyPath           string
	secretsPath           string
	doorPath              string
	credentialsPath       string
	monitorStatusPath     string
	claudeSettingsPath    string
	claudeMDPath          string
	antigravityMDPath     string
	opencodeMDPath        string
	legacyPlistPath       string
	oauthClientPath       string
	antigravityTokensPath string
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
	// listVoices lists available system synthesis voices.
	listVoices func(ctx context.Context) ([]homeSpeakerVoice, error)
	// readClipboard reads system clipboard text.
	readClipboard func(ctx context.Context) (string, error)
}

const homeSpeakerBinary = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"

func newHomeSpeaker() *homeSpeaker {
	home, _ := os.UserHomeDir()
	return &homeSpeaker{
		configPath:            filepath.Join(home, ".gemini", "speaker_broadcast.json"),
		historyPath:           filepath.Join(home, ".gemini", "speaker_history.json"),
		secretsPath:           filepath.Join(home, "Library", "Application Support", "HomeSpeaker", "secrets.json"),
		doorPath:              filepath.Join(home, ".gemini", "speaker_door.json"),
		credentialsPath:       filepath.Join(home, ".gemini", "chat_credentials.json"),
		monitorStatusPath:     filepath.Join(home, ".gemini", "speaker_monitor_status.json"),
		claudeSettingsPath:    filepath.Join(home, ".claude", "settings.json"),
		claudeMDPath:          filepath.Join(home, ".claude", "CLAUDE.md"),
		antigravityMDPath:     filepath.Join(home, ".gemini", "AGENTS.md"),
		opencodeMDPath:        filepath.Join(home, ".config", "opencode", "AGENTS.md"),
		legacyPlistPath:       filepath.Join(home, "Library", "LaunchAgents", "com.james.chat-monitor.plist"),
		oauthClientPath:       filepath.Join(home, ".gemini", "google-oauth-client.json"),
		antigravityTokensPath: filepath.Join(home, ".gemini", "antigravity", "mcp_oauth_tokens.json"),
		binary:                homeSpeakerBinary,
		run:                   runToolWithin,
		say:                   runAsPersonWithin,
		running: func(ctx context.Context) bool {
			return exec.CommandContext(ctx, "pgrep", "-x", "HomeSpeaker").Run() == nil
		},
		readClipboard: func(ctx context.Context) (string, error) {
			out, err := exec.CommandContext(ctx, "pbpaste").Output()
			return string(out), err
		},
		listVoices: listMacOSVoices,
	}
}

// homeSpeakerProfile is the resolved file and binary layout for whichever
// distribution (standalone .app or Vitruvian extension) is active on this Mac.
type homeSpeakerProfile struct {
	activeDoor        string
	configPath        string
	historyPath       string
	secretsPath       string
	monitorStatusPath string
	binary            string
	lockPath          string
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
		activeDoor:        "app",
		configPath:        h.configPath,
		historyPath:       h.historyPath,
		secretsPath:       h.secretsPath,
		monitorStatusPath: h.monitorStatusPath,
		binary:            h.binary,
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
		activeDoor:        "extension",
		configPath:        filepath.Join(dataFolder, "settings.json"),
		historyPath:       filepath.Join(dataFolder, "history.json"),
		secretsPath:       filepath.Join(dataFolder, "secrets.json"),
		monitorStatusPath: filepath.Join(dataFolder, "speaker_monitor_status.json"),
		binary:            prog,
		lockPath:          filepath.Join(dataFolder, "running.lock"),
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
	geminiVoices        = []string{"Kore", "Puck", "Aoede", "Charon", "Zephyr", "Fenrir", "Leda", "Orus", "voice_vaoo7ayczx69", "voice_o1be80ujj8bb"}
	announcementStyles  = []string{"verbatim", "plain", "briefing", "casual", "custom"}
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
	SpeakPhone     *bool  `json:"speak_phone,omitempty"`
	LocalVoice     string `json:"local_voice"`
	LocalVoiceName string `json:"local_voice_name"`
	// PhonePauseMedia / PhoneHeadphonesOnly / PhoneConnected (agent v1.12+):
	// whether phone announcements pause phone media, whether they require
	// wired or Bluetooth headphones on the phone, and whether the phone
	// bridge is currently linked.
	PhonePauseMedia     bool `json:"phone_pause_media"`
	PhoneHeadphonesOnly bool `json:"phone_headphones_only"`
	PhoneConnected      bool `json:"phone_connected"`
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
	// CustomStylePrompt is the instruction used when AnnouncementStyle is
	// "custom" (SpeakerConfig.customStylePrompt). Set on the Mac.
	CustomStylePrompt string `json:"custom_style_prompt,omitempty"`
	// HomeCastVoice: Google Home plays the selected local voice (Gemini)
	// cast to the speaker instead of its own cloud voice.
	HomeCastVoice bool `json:"home_cast_voice"`
	// CustomVoices are cloned voices the Mac knows about; any of their ids
	// is a valid gemini_voice alongside the prebuilt ones.
	CustomVoices []homeSpeakerCustomVoice `json:"custom_voices,omitempty"`

	StructureName string              `json:"structure_name"`
	QuietHours    homeSpeakerQuiet    `json:"quiet_hours"`
	Targets       []homeSpeakerTarget `json:"targets"`
	Last          *homeSpeakerLast    `json:"last,omitempty"`

	QuietHoursActive        bool                   `json:"quiet_hours_active"`
	AvailableVoices         []homeSpeakerVoice     `json:"available_voices,omitempty"`
	StructureID             string                 `json:"structure_id,omitempty"`
	Homes                   []homeSpeakerHome      `json:"homes,omitempty"`
	AccountEmail            string                 `json:"account_email,omitempty"`
	HasOAuthClient          bool                   `json:"has_oauth_client"`
	HasAntigravityTokens    bool                   `json:"has_antigravity_tokens"`
	MonitorRunning          bool                   `json:"monitor_running"`
	LastPollAt              string                 `json:"last_poll_at,omitempty"`
	SlackIdentity           string                 `json:"slack_identity,omitempty"`
	ActiveGoogleChatBackend string                 `json:"active_google_chat_backend,omitempty"`
	ChatRuntimeError        string                 `json:"chat_runtime_error,omitempty"`
	HasSlackToken           bool                   `json:"has_slack_token"`
	HasBeeperToken          bool                   `json:"has_beeper_token"`
	HasChatAccess           bool                   `json:"has_chat_access"`
	GWSInstalled            bool                   `json:"gws_installed"`
	GWSAccount              string                 `json:"gws_account,omitempty"`
	GoogleChatSource        string                 `json:"google_chat_source,omitempty"`
	PollInterval            int                    `json:"poll_interval,omitempty"`
	Agents                  []homeSpeakerAgentHook `json:"agents,omitempty"`
	LegacyLaunchAgent       bool                   `json:"legacy_launch_agent"`
	CustomOAuthClientID     string                 `json:"custom_oauth_client_id,omitempty"`
	HasCustomOAuthSecret    bool                   `json:"has_custom_oauth_secret"`
	HomeSpeakerVersion      string                 `json:"home_speaker_version,omitempty"`

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

type homeSpeakerVoice struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Lang string `json:"lang"`
}

type homeSpeakerHome struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type homeSpeakerAgentHook struct {
	Agent                   string `json:"agent"`
	AgentSlug               string `json:"agent_slug"`
	HookState               string `json:"hook_state"`
	SpeaksTwice             bool   `json:"speaks_twice"`
	ConfiguredByInstruction bool   `json:"configured_by_instruction"`
}

// homeSpeakerCustomVoice is one entry of the config's custom_voices list.
type homeSpeakerCustomVoice struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// customVoices reads cfg["custom_voices"], skipping entries without an id.
func customVoices(cfg map[string]any) []homeSpeakerCustomVoice {
	list, _ := cfg["custom_voices"].([]any)
	var out []homeSpeakerCustomVoice
	for _, item := range list {
		m, _ := item.(map[string]any)
		id, _ := m["id"].(string)
		if strings.TrimSpace(id) == "" {
			continue
		}
		name, _ := m["name"].(string)
		if strings.TrimSpace(name) == "" {
			name = id
		}
		out = append(out, homeSpeakerCustomVoice{ID: id, Name: name})
	}
	return out
}

// validGeminiVoice says whether v is a prebuilt Gemini voice or the id of
// one of the custom voices.
func validGeminiVoice(v string, custom []homeSpeakerCustomVoice) bool {
	if slices.Contains(geminiVoices, v) {
		return true
	}
	for _, c := range custom {
		if c.ID == v {
			return true
		}
	}
	return false
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
	Active  bool   `json:"active"`
}

type homeSpeakerTarget struct {
	Key      string `json:"key"`
	Name     string `json:"name"`
	Room     string `json:"room"`
	Type     string `json:"type"`
	Selected bool   `json:"selected"`
}

type homeSpeakerLast struct {
	ID     string    `json:"id,omitempty"`
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
	st.SpeakPhone = boolOr(cfg, "speak_phone", false)
	st.PhonePauseMedia, _ = cfg["phone_pause_media"].(bool)
	st.PhoneHeadphonesOnly, _ = cfg["phone_headphones_only"].(bool)
	st.LocalVoice = defaultLocalVoice
	if v, ok := cfg["local_voice"].(string); ok && strings.TrimSpace(v) != "" {
		st.LocalVoice = v
	}
	st.LocalVoiceName = voiceName(st.LocalVoice)
	st.LocalEngine = stringIn(cfg, "local_engine", localEngines, "apple")
	st.CustomVoices = customVoices(cfg)
	st.GeminiVoice = "Kore"
	if v, ok := cfg["gemini_voice"].(string); ok && validGeminiVoice(v, st.CustomVoices) {
		st.GeminiVoice = v
	}
	st.AnnouncementStyle = stringIn(cfg, "announcement_style", announcementStyles, "verbatim")
	st.CustomStylePrompt, _ = cfg["custom_style_prompt"].(string)
	st.HomeCastVoice, _ = cfg["home_cast_voice"].(bool)
	st.StyleModel = stringIn(cfg, "style_model", styleModels, "apple")
	st.StructureName, _ = cfg["structure_name"].(string)
	st.StructureID, _ = cfg["structure_id"].(string)
	if rawHomes, ok := cfg["homes"].([]any); ok {
		for _, rawH := range rawHomes {
			if hm, ok := rawH.(map[string]any); ok {
				id, _ := hm["id"].(string)
				name, _ := hm["name"].(string)
				if id != "" {
					st.Homes = append(st.Homes, homeSpeakerHome{ID: id, Name: name})
				}
			}
		}
	}
	if len(st.Homes) == 0 && st.StructureName != "" {
		st.Homes = append(st.Homes, homeSpeakerHome{ID: st.StructureID, Name: st.StructureName})
	}

	st.QuietHours.Enabled, _ = cfg["quiet_hours_enabled"].(bool)
	st.QuietHours.Start, _ = cfg["quiet_hours_start"].(string)
	if st.QuietHours.Start == "" {
		st.QuietHours.Start = "00:00"
	}
	st.QuietHours.End, _ = cfg["quiet_hours_end"].(string)
	if st.QuietHours.End == "" {
		st.QuietHours.End = "06:00"
	}
	st.QuietHours.Active = isQuietHoursActive(st.QuietHours.Enabled, st.QuietHours.Start, st.QuietHours.End, time.Now())
	st.QuietHoursActive = st.QuietHours.Active

	if h.listVoices != nil {
		if vList, err := h.listVoices(ctx); err == nil && len(vList) > 0 {
			st.AvailableVoices = vList
		} else {
			st.AvailableVoices = defaultVoiceList()
		}
	} else {
		st.AvailableVoices = defaultVoiceList()
	}

	sec := h.readSecretsData(p.secretsPath)
	cred := h.readCredentialsData()
	if sec.Google != nil && sec.Google.Email != "" {
		st.AccountEmail = sec.Google.Email
	}
	st.HasOAuthClient = sec.OAuthClientIDOverride != "" || cred.OAuthClientID != "" || fileExists(h.oauthClientPath)
	st.HasAntigravityTokens = fileExists(h.antigravityTokensPath)
	st.CustomOAuthClientID = sec.OAuthClientIDOverride
	if st.CustomOAuthClientID == "" {
		st.CustomOAuthClientID = cred.OAuthClientID
	}
	st.HasCustomOAuthSecret = sec.OAuthClientSecretOverride != "" || cred.OAuthClientSecret != ""
	if sec.SlackToken != "" || cred.SlackToken != "" {
		st.HasSlackToken = true
	}
	if sec.BeeperToken != "" || cred.BeeperToken != "" {
		st.HasBeeperToken = true
	}
	st.HasChatAccess = st.HasSlackToken || st.HasBeeperToken
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

	monStatus := h.readMonitorStatus()
	st.MonitorRunning = monStatus.IsRunning
	st.LastPollAt = monStatus.LastPollDate
	st.SlackIdentity = monStatus.SlackIdentity
	st.ActiveGoogleChatBackend = monStatus.ActiveGoogleChatBackend
	st.ChatRuntimeError = monStatus.LastError
	st.GWSInstalled = fileExists("/opt/homebrew/bin/gws") || fileExists("/usr/local/bin/gws") || exec.Command("which", "gws").Run() == nil
	st.GWSAccount, _ = monitor["gws_account"].(string)
	st.GoogleChatSource = stringIn(monitor, "google_chat_source", []string{"auto", "api", "gws"}, "auto")
	st.PollInterval = 30
	if pi, ok := monitor["poll_interval_seconds"].(float64); ok && pi >= 5 {
		st.PollInterval = int(pi)
	}

	st.Agents = h.inspectAgents(p)
	st.LegacyLaunchAgent = fileExists(h.legacyPlistPath)
	st.HomeSpeakerVersion = h.inspectVersion(p)
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
		GeminiApiKey string `json:"geminiApiKey"`
		GeminiAPIKey string `json:"geminiAPIKey"`
	}
	if json.Unmarshal(data, &secrets) != nil {
		return false
	}
	key := secrets.GeminiApiKey
	if key == "" {
		key = secrets.GeminiAPIKey
	}
	return strings.TrimSpace(key) != ""
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
		ID         string  `json:"id"`
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
			ID:     it.ID,
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
	Enabled                *bool                           `json:"enabled"`
	DefaultTarget          *string                         `json:"default_target"`
	SpeechLength           *string                         `json:"speech_length"`
	QuietHoursEnabled      *bool                           `json:"quiet_hours_enabled"`
	QuietHoursStart        *string                         `json:"quiet_hours_start,omitempty"`
	QuietHoursEnd          *string                         `json:"quiet_hours_end,omitempty"`
	CustomStylePrompt      *string                         `json:"custom_style_prompt,omitempty"`
	LocalVoice             *string                         `json:"local_voice,omitempty"`
	PreviewVoice           bool                            `json:"preview_voice,omitempty"`
	PauseMedia             *bool                           `json:"pause_media"`
	PauseMediaExtraSeconds *float64                        `json:"pause_media_extra_seconds"`
	TestMediaPause         bool                            `json:"test_media_pause,omitempty"`
	AnnounceVolumeEnabled  *bool                           `json:"announce_volume_enabled"`
	AnnounceVolume         *int                            `json:"announce_volume"`
	SpeakHome              *bool                           `json:"speak_home"`
	SpeakLocal             *bool                           `json:"speak_local"`
	SpeakPhone             *bool                           `json:"speak_phone"`
	PhonePauseMedia        *bool                           `json:"phone_pause_media"`
	PhoneHeadphonesOnly    *bool                           `json:"phone_headphones_only"`
	LocalEngine            *string                         `json:"local_engine"`
	GeminiVoice            *string                         `json:"gemini_voice"`
	AnnouncementStyle      *string                         `json:"announcement_style"`
	StyleModel             *string                         `json:"style_model"`
	HomeCastVoice          *bool                           `json:"home_cast_voice"`
	ActiveDoor             *string                         `json:"active_door,omitempty"`
	Discover               bool                            `json:"discover,omitempty"`
	StructureID            *string                         `json:"structure_id,omitempty"`
	RemoveTarget           *string                         `json:"remove_target,omitempty"`
	SignOut                bool                            `json:"sign_out,omitempty"`
	ImportAntigravity      bool                            `json:"import_antigravity,omitempty"`
	SpeakClipboard         bool                            `json:"speak_clipboard,omitempty"`
	GoogleChatSource       *string                         `json:"google_chat_source,omitempty"`
	GWSAccount             *string                         `json:"gws_account,omitempty"`
	PollInterval           *int                            `json:"poll_interval,omitempty"`
	SlackToken             *string                         `json:"slack_token,omitempty"`
	BeeperToken            *string                         `json:"beeper_token,omitempty"`
	GeminiAPIKey           *string                         `json:"gemini_api_key,omitempty"`
	ChatMonitorAction      *string                         `json:"chat_monitor_action,omitempty"`
	AgentHookAction        *string                         `json:"agent_hook_action,omitempty"`
	OAuthClientID          *string                         `json:"oauth_client_id,omitempty"`
	OAuthClientSecret      *string                         `json:"oauth_client_secret,omitempty"`
	ResetSettings          bool                            `json:"reset_settings,omitempty"`
	AnnounceClaudeCode     *bool                           `json:"announce_claude_code"`
	AnnounceAntigravity    *bool                           `json:"announce_antigravity"`
	AnnounceOpenCode       *bool                           `json:"announce_opencode"`
	SlackEnabled           *bool                           `json:"slack_enabled"`
	GoogleChatEnabled      *bool                           `json:"google_chat_enabled"`
	BeeperEnabled          *bool                           `json:"beeper_enabled"`
	BeeperAnnounce         *string                         `json:"beeper_announce"`
	BeeperNetwork          *homeSpeakerBeeperNetworkUpdate `json:"beeper_network"`
	MuteOwnMessages        *bool                           `json:"mute_own_messages"`
}

// pauseMediaExtraMax is the app's own ceiling (Settings' stepper, 0-10 s).
const pauseMediaExtraMax = 10.0

func (u homeSpeakerUpdate) empty() bool {
	return u.Enabled == nil && u.DefaultTarget == nil && u.SpeechLength == nil &&
		u.QuietHoursEnabled == nil && u.QuietHoursStart == nil && u.QuietHoursEnd == nil &&
		u.CustomStylePrompt == nil && u.LocalVoice == nil && !u.PreviewVoice &&
		u.PauseMedia == nil && u.PauseMediaExtraSeconds == nil && !u.TestMediaPause &&
		u.AnnounceVolumeEnabled == nil && u.AnnounceVolume == nil &&
		u.SpeakHome == nil && u.SpeakLocal == nil && u.SpeakPhone == nil &&
		u.PhonePauseMedia == nil && u.PhoneHeadphonesOnly == nil &&
		u.LocalEngine == nil && u.GeminiVoice == nil &&
		u.AnnouncementStyle == nil && u.StyleModel == nil && u.HomeCastVoice == nil &&
		u.ActiveDoor == nil && !u.Discover && u.StructureID == nil && u.RemoveTarget == nil &&
		!u.SignOut && !u.ImportAntigravity && !u.SpeakClipboard &&
		u.GoogleChatSource == nil && u.GWSAccount == nil && u.PollInterval == nil &&
		u.SlackToken == nil && u.BeeperToken == nil && u.GeminiAPIKey == nil &&
		u.ChatMonitorAction == nil && u.AgentHookAction == nil &&
		u.OAuthClientID == nil && u.OAuthClientSecret == nil && !u.ResetSettings &&
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
func (h *homeSpeaker) apply(ctx context.Context, u homeSpeakerUpdate) (string, error) {
	p := h.activeProfile()
	if u.ResetSettings {
		var preservedTargets map[string]any
		var preservedDefault string
		var preservedStructureID string
		var preservedStructureName string
		if fileExists(p.configPath) {
			data, err := os.ReadFile(p.configPath)
			if err != nil {
				return "", err
			}
			if err := os.WriteFile(p.configPath+".bak", data, 0o600); err != nil {
				return "", fmt.Errorf("backup settings before reset failed: %w", err)
			}
			var existing map[string]any
			if json.Unmarshal(data, &existing) == nil {
				if trgs, ok := existing["targets"].(map[string]any); ok {
					preservedTargets = trgs
				}
				if def, ok := existing["default_target"].(string); ok {
					preservedDefault = def
				}
				if sid, ok := existing["structure_id"].(string); ok {
					preservedStructureID = sid
				}
				if sn, ok := existing["structure_name"].(string); ok {
					preservedStructureName = sn
				}
			}
		}
		freshCfg := map[string]any{
			"enabled":                   true,
			"default_target":            preservedDefault,
			"speech_length":             "summary",
			"pause_media":               false,
			"pause_media_extra_seconds": 1.0,
			"announce_volume_enabled":   false,
			"announce_volume":           60,
			"speak_home":                true,
			"speak_local":               false,
			"local_voice":               defaultLocalVoice,
			"local_engine":              "apple",
			"gemini_voice":              "Kore",
			"announcement_style":        "verbatim",
			"style_model":               "apple",
			"quiet_hours_enabled":       false,
			"quiet_hours_start":         "00:00",
			"quiet_hours_end":           "06:00",
			"announce_claude_code":      true,
			"announce_antigravity":      true,
			"announce_opencode":         true,
		}
		if preservedTargets != nil {
			freshCfg["targets"] = preservedTargets
		}
		if preservedStructureID != "" {
			freshCfg["structure_id"] = preservedStructureID
		}
		if preservedStructureName != "" {
			freshCfg["structure_name"] = preservedStructureName
		}
		if err := h.writeConfig(freshCfg); err != nil {
			return "", err
		}
		return "reset_settings", nil
	}

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
	if u.QuietHoursStart != nil {
		if err := parseHHMM(*u.QuietHoursStart); err != nil {
			return "", err
		}
		cfg["quiet_hours_start"] = *u.QuietHoursStart
		changed = append(changed, "quiet_hours_start="+*u.QuietHoursStart)
	}
	if u.QuietHoursEnd != nil {
		if err := parseHHMM(*u.QuietHoursEnd); err != nil {
			return "", err
		}
		cfg["quiet_hours_end"] = *u.QuietHoursEnd
		changed = append(changed, "quiet_hours_end="+*u.QuietHoursEnd)
	}
	if u.CustomStylePrompt != nil {
		cfg["custom_style_prompt"] = *u.CustomStylePrompt
		changed = append(changed, "custom_style_prompt")
	}
	if u.LocalVoice != nil {
		clean := strings.TrimSpace(*u.LocalVoice)
		if clean == "" {
			return "", &badRequest{"local_voice cannot be empty"}
		}
		cfg["local_voice"] = clean
		changed = append(changed, "local_voice="+clean)
	}
	if u.PreviewVoice {
		voice := defaultLocalVoice
		if v, ok := cfg["local_voice"].(string); ok && strings.TrimSpace(v) != "" {
			voice = v
		}
		engine := "apple"
		if e, ok := cfg["local_engine"].(string); ok && e != "" {
			engine = e
		}
		if err := h.sayPreviewVoice(ctx, p, engine, voice); err != nil {
			return "", err
		}
		changed = append(changed, "preview_voice")
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
	if u.TestMediaPause {
		_, stderr, err := h.run(ctx, 30*time.Second, p.binary, "--test-media-pause")
		if err != nil {
			return "", fmt.Errorf("test media pause failed: %w (stderr: %s)", err, strings.TrimSpace(stderr))
		}
		changed = append(changed, "test_media_pause")
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
	if u.SpeakPhone != nil {
		cfg["speak_phone"] = *u.SpeakPhone
		changed = append(changed, fmt.Sprintf("speak_phone=%v", *u.SpeakPhone))
	}
	if u.PhonePauseMedia != nil {
		cfg["phone_pause_media"] = *u.PhonePauseMedia
		changed = append(changed, fmt.Sprintf("phone_pause_media=%v", *u.PhonePauseMedia))
	}
	if u.PhoneHeadphonesOnly != nil {
		cfg["phone_headphones_only"] = *u.PhoneHeadphonesOnly
		changed = append(changed, fmt.Sprintf("phone_headphones_only=%v", *u.PhoneHeadphonesOnly))
	}
	if u.LocalEngine != nil {
		if err := validateEnum("local_engine", *u.LocalEngine, localEngines); err != nil {
			return "", err
		}
		cfg["local_engine"] = *u.LocalEngine
		changed = append(changed, "local_engine="+*u.LocalEngine)
	}
	if u.GeminiVoice != nil {
		if custom := customVoices(cfg); !validGeminiVoice(*u.GeminiVoice, custom) {
			allowed := slices.Clone(geminiVoices)
			for _, c := range custom {
				allowed = append(allowed, c.ID)
			}
			return "", &badRequest{fmt.Sprintf("gemini_voice must be one of %s", strings.Join(allowed, ", "))}
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
	if u.HomeCastVoice != nil {
		cfg["home_cast_voice"] = *u.HomeCastVoice
		changed = append(changed, fmt.Sprintf("home_cast_voice=%v", *u.HomeCastVoice))
	}
	if u.ActiveDoor != nil {
		door := strings.ToLower(strings.TrimSpace(*u.ActiveDoor))
		if door != "app" && door != "extension" {
			return "", &badRequest{"active_door must be 'app' or 'extension'"}
		}
		if err := h.writeActiveDoor(door); err != nil {
			return "", err
		}
		changed = append(changed, "active_door="+door)
	}
	if u.Discover {
		_, stderr, err := h.run(ctx, 60*time.Second, p.binary, "--discover", "--save")
		if err != nil {
			return "", fmt.Errorf("discover failed: %w (stderr: %s)", err, strings.TrimSpace(stderr))
		}
		changed = append(changed, "discover")
		if reloaded, rerr := h.readConfig(); rerr == nil {
			cfg = reloaded
		}
	}
	if u.StructureID != nil {
		sid := strings.TrimSpace(*u.StructureID)
		if sid == "" {
			return "", &badRequest{"structure_id cannot be empty"}
		}
		_, stderr, err := h.run(ctx, 60*time.Second, p.binary, "--discover", "--save", "--home", sid)
		if err != nil {
			return "", fmt.Errorf("set structure failed: %w (stderr: %s)", err, strings.TrimSpace(stderr))
		}
		changed = append(changed, "structure_id="+sid)
		if reloaded, rerr := h.readConfig(); rerr == nil {
			cfg = reloaded
		}
		cfg["structure_id"] = sid
	}
	if u.RemoveTarget != nil {
		targetKey := *u.RemoveTarget
		if targets, ok := cfg["targets"].(map[string]any); ok {
			delete(targets, targetKey)
			if def, ok := cfg["default_target"].(string); ok && def == targetKey {
				cfg["default_target"] = ""
			}
		}
		changed = append(changed, "remove_target="+targetKey)
	}
	if u.SignOut {
		_, stderr, err := h.run(ctx, 30*time.Second, p.binary, "--sign-out")
		if err != nil {
			return "", fmt.Errorf("sign out failed: %w (stderr: %s)", err, strings.TrimSpace(stderr))
		}
		h.clearGoogleSecrets(p.secretsPath)
		changed = append(changed, "sign_out")
		if reloaded, rerr := h.readConfig(); rerr == nil {
			cfg = reloaded
		}
	}
	if u.ImportAntigravity {
		if err := h.importAntigravityTokens(p.secretsPath); err != nil {
			return "", err
		}
		changed = append(changed, "import_antigravity")
	}
	if u.SpeakClipboard {
		if h.readClipboard == nil {
			return "", &badRequest{"clipboard reading is unavailable"}
		}
		clipText, err := h.readClipboard(ctx)
		if err != nil || strings.TrimSpace(clipText) == "" {
			return "", &badRequest{"clipboard is empty"}
		}
		runSay := h.say
		if runSay == nil {
			runSay = h.run
		}
		_, _, err = runSay(ctx, sayLimit, p.binary, "--say", strings.TrimSpace(clipText))
		if err != nil {
			return "", err
		}
		changed = append(changed, "speak_clipboard")
	}
	if u.GoogleChatSource != nil {
		if err := validateEnum("google_chat_source", *u.GoogleChatSource, []string{"auto", "api", "gws"}); err != nil {
			return "", err
		}
		monitor := ensureChatMonitor(cfg)
		monitor["google_chat_source"] = *u.GoogleChatSource
		changed = append(changed, "chat_monitor.google_chat_source="+*u.GoogleChatSource)
	}
	if u.GWSAccount != nil {
		monitor := ensureChatMonitor(cfg)
		monitor["gws_account"] = strings.TrimSpace(*u.GWSAccount)
		changed = append(changed, "chat_monitor.gws_account="+strings.TrimSpace(*u.GWSAccount))
	}
	if u.PollInterval != nil {
		if *u.PollInterval < 5 {
			return "", &badRequest{"poll_interval must be at least 5 seconds"}
		}
		monitor := ensureChatMonitor(cfg)
		monitor["poll_interval_seconds"] = *u.PollInterval
		changed = append(changed, fmt.Sprintf("chat_monitor.poll_interval_seconds=%d", *u.PollInterval))
	}
	if u.SlackToken != nil {
		if err := h.updateSecret(p.secretsPath, "slackToken", "slack_token", u.SlackToken); err != nil {
			return "", err
		}
		if *u.SlackToken == "" {
			changed = append(changed, "slack_token=cleared")
		} else {
			changed = append(changed, "slack_token=<redacted>")
		}
	}
	if u.BeeperToken != nil {
		if err := h.updateSecret(p.secretsPath, "beeperToken", "beeper_token", u.BeeperToken); err != nil {
			return "", err
		}
		if *u.BeeperToken == "" {
			changed = append(changed, "beeper_token=cleared")
		} else {
			changed = append(changed, "beeper_token=<redacted>")
		}
	}
	if u.GeminiAPIKey != nil {
		if err := h.updateSecret(p.secretsPath, "geminiApiKey", "", u.GeminiAPIKey); err != nil {
			return "", err
		}
		if *u.GeminiAPIKey == "" {
			changed = append(changed, "gemini_api_key=cleared")
		} else {
			changed = append(changed, "gemini_api_key=<redacted>")
		}
	}
	if u.OAuthClientID != nil {
		if err := h.updateSecret(p.secretsPath, "oauthClientIdOverride", "oauth_client_id", u.OAuthClientID); err != nil {
			return "", err
		}
		if *u.OAuthClientID == "" {
			changed = append(changed, "oauth_client_id=cleared")
		} else {
			changed = append(changed, "oauth_client_id=<set>")
		}
	}
	if u.OAuthClientSecret != nil {
		if err := h.updateSecret(p.secretsPath, "oauthClientSecretOverride", "oauth_client_secret", u.OAuthClientSecret); err != nil {
			return "", err
		}
		if *u.OAuthClientSecret == "" {
			changed = append(changed, "oauth_client_secret=cleared")
		} else {
			changed = append(changed, "oauth_client_secret=<redacted>")
		}
	}
	if u.ChatMonitorAction != nil {
		action := strings.ToLower(strings.TrimSpace(*u.ChatMonitorAction))
		if action != "start" && action != "stop" {
			return "", &badRequest{"chat_monitor_action must be 'start' or 'stop'"}
		}
		_, stderr, err := h.run(ctx, 30*time.Second, p.binary, "--chat-monitor", action)
		if err != nil {
			return "", fmt.Errorf("chat monitor %s failed: %w (stderr: %s)", action, err, strings.TrimSpace(stderr))
		}
		changed = append(changed, "chat_monitor_action="+action)
	}
	if u.AgentHookAction != nil {
		if err := h.executeAgentHookAction(ctx, *u.AgentHookAction, p); err != nil {
			return "", err
		}
		changed = append(changed, "agent_hook_action="+*u.AgentHookAction)
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

var hhmmRe = regexp.MustCompile(`^([01][0-9]|2[0-3]):[0-5][0-9]$`)

func parseHHMM(s string) error {
	if !hhmmRe.MatchString(s) {
		return &badRequest{fmt.Sprintf("invalid time %q; must be HH:MM (24-hour)", s)}
	}
	return nil
}

func isQuietHoursActive(enabled bool, start, end string, now time.Time) bool {
	if !enabled {
		return false
	}
	var sH, sM, eH, eM int
	if _, err := fmt.Sscanf(start, "%d:%d", &sH, &sM); err != nil {
		return false
	}
	if _, err := fmt.Sscanf(end, "%d:%d", &eH, &eM); err != nil {
		return false
	}
	startM := sH*60 + sM
	endM := eH*60 + eM
	nowM := now.Hour()*60 + now.Minute()
	if startM == endM {
		return false
	}
	if startM < endM {
		return nowM >= startM && nowM < endM
	}
	return nowM >= startM || nowM < endM
}

func defaultVoiceList() []homeSpeakerVoice {
	return []homeSpeakerVoice{
		{ID: "com.apple.ttsbundle.siri_Aaron_en-US_premium", Name: "Aaron", Lang: "en_US"},
		{ID: "com.apple.speech.synthesis.voice.Alex", Name: "Alex", Lang: "en_US"},
		{ID: "com.apple.speech.synthesis.voice.Samantha", Name: "Samantha", Lang: "en_US"},
		{ID: "com.apple.speech.synthesis.voice.Fred", Name: "Fred", Lang: "en_US"},
		{ID: "com.apple.speech.synthesis.voice.Victoria", Name: "Victoria", Lang: "en_US"},
	}
}

func listMacOSVoices(ctx context.Context) ([]homeSpeakerVoice, error) {
	cmd := exec.CommandContext(ctx, "say", "-v", "?")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	var voices []homeSpeakerVoice
	scanner := bufio.NewScanner(bytes.NewReader(out))
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, "#", 2)
		fields := strings.Fields(parts[0])
		if len(fields) >= 2 {
			lang := fields[len(fields)-1]
			name := strings.Join(fields[:len(fields)-1], " ")
			voices = append(voices, homeSpeakerVoice{
				ID:   name,
				Name: name,
				Lang: lang,
			})
		}
	}
	return voices, nil
}

func (h *homeSpeaker) sayPreviewVoice(ctx context.Context, p homeSpeakerProfile, engine, voice string) error {
	const previewText = "This is how announcements will sound."
	if engine == "gemini" {
		historyBefore, _ := os.ReadFile(p.historyPath)
		runSay := h.say
		if runSay == nil {
			runSay = h.run
		}
		_, stderr, err := runSay(ctx, sayLimit, p.binary, "--say", previewText)
		if historyBefore != nil {
			_ = os.WriteFile(p.historyPath, historyBefore, 0o600)
		}
		if err != nil {
			return fmt.Errorf("preview voice failed: %w (stderr: %s)", err, strings.TrimSpace(stderr))
		}
		return nil
	}
	name := voiceName(voice)
	if name != "" && name != voice {
		if _, _, err := h.run(ctx, 10*time.Second, "say", "-v", name, previewText); err == nil {
			return nil
		}
	}
	if voice != "" {
		if _, _, err := h.run(ctx, 10*time.Second, "say", "-v", voice, previewText); err == nil {
			return nil
		}
	}
	runSay := h.say
	if runSay == nil {
		runSay = h.run
	}
	_, stderr, err := runSay(ctx, sayLimit, p.binary, "--say", previewText)
	if err != nil {
		return fmt.Errorf("preview voice failed: %w (stderr: %s)", err, strings.TrimSpace(stderr))
	}
	return nil
}

func (h *homeSpeaker) writeActiveDoor(door string) error {
	if h.doorPath == "" {
		return nil
	}
	var doc map[string]any
	data, err := os.ReadFile(h.doorPath)
	if err == nil {
		_ = json.Unmarshal(data, &doc)
	}
	if doc == nil {
		doc = make(map[string]any)
	}
	doc["chosen"] = door
	marshaled, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return err
	}
	tmp := h.doorPath + ".agent-tmp"
	if err := os.WriteFile(tmp, append(marshaled, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, h.doorPath)
}

func (h *homeSpeaker) updateSecret(secretsPath, camelKey, snakeKey string, val *string) error {
	if val == nil {
		return nil
	}
	clean := strings.TrimSpace(*val)
	var legacyKey string
	switch camelKey {
	case "geminiApiKey":
		legacyKey = "geminiAPIKey"
	case "oauthClientIdOverride":
		legacyKey = "oauthClientIDOverride"
	case "oauthClientSecretOverride":
		legacyKey = "oauthClientSecret"
	}

	if secretsPath != "" {
		_ = os.MkdirAll(filepath.Dir(secretsPath), 0o700)
		var doc map[string]any
		if fileExists(secretsPath) {
			data, err := os.ReadFile(secretsPath)
			if err != nil {
				return err
			}
			if err := json.Unmarshal(data, &doc); err != nil {
				return fmt.Errorf("failed to parse secrets: %w", err)
			}
		}
		if doc == nil {
			doc = make(map[string]any)
		}
		if legacyKey != "" {
			if oldVal, ok := doc[legacyKey]; ok && doc[camelKey] == nil {
				doc[camelKey] = oldVal
			}
			delete(doc, legacyKey)
		}
		if clean == "" {
			delete(doc, camelKey)
			if legacyKey != "" {
				delete(doc, legacyKey)
			}
		} else {
			doc[camelKey] = clean
		}
		marshaled, err := json.MarshalIndent(doc, "", "  ")
		if err != nil {
			return err
		}
		tmp := secretsPath + ".agent-tmp"
		if err := os.WriteFile(tmp, append(marshaled, '\n'), 0o600); err != nil {
			return err
		}
		if err := os.Rename(tmp, secretsPath); err != nil {
			return err
		}
	}
	if snakeKey != "" && h.credentialsPath != "" {
		_ = os.MkdirAll(filepath.Dir(h.credentialsPath), 0o700)
		var credDoc map[string]any
		if fileExists(h.credentialsPath) {
			data, err := os.ReadFile(h.credentialsPath)
			if err == nil {
				_ = json.Unmarshal(data, &credDoc)
			}
		}
		if credDoc == nil {
			credDoc = make(map[string]any)
		}
		if clean == "" {
			delete(credDoc, snakeKey)
		} else {
			credDoc[snakeKey] = clean
		}
		marshaled, err := json.MarshalIndent(credDoc, "", "  ")
		if err != nil {
			return err
		}
		tmp := h.credentialsPath + ".agent-tmp"
		if err := os.WriteFile(tmp, append(marshaled, '\n'), 0o600); err != nil {
			return err
		}
		if err := os.Rename(tmp, h.credentialsPath); err != nil {
			return err
		}
	}
	return nil
}

func (h *homeSpeaker) clearGoogleSecrets(secretsPath string) {
	if secretsPath == "" {
		return
	}
	data, err := os.ReadFile(secretsPath)
	if err != nil {
		return
	}
	var doc map[string]any
	if json.Unmarshal(data, &doc) != nil {
		return
	}
	delete(doc, "google")
	marshaled, err := json.MarshalIndent(doc, "", "  ")
	if err == nil {
		tmp := secretsPath + ".agent-tmp"
		if err := os.WriteFile(tmp, append(marshaled, '\n'), 0o600); err == nil {
			_ = os.Rename(tmp, secretsPath)
		}
	}
}

func (h *homeSpeaker) importAntigravityTokens(secretsPath string) error {
	if h.antigravityTokensPath == "" || !fileExists(h.antigravityTokensPath) {
		return &badRequest{"no Antigravity tokens file found"}
	}
	data, err := os.ReadFile(h.antigravityTokensPath)
	if err != nil {
		return err
	}
	var tokensDoc map[string]any
	if err := json.Unmarshal(data, &tokensDoc); err != nil {
		return err
	}
	mcpEndpoint := "https://home.googleapis.com/mcp"
	homeRaw, ok := tokensDoc[mcpEndpoint].(map[string]any)
	if !ok {
		return &badRequest{"no Google Home login found in the Antigravity token file"}
	}
	clientID, _ := homeRaw["client_id"].(string)
	clientSecret, _ := homeRaw["client_secret"].(string)
	tokenRaw, _ := homeRaw["token"].(map[string]any)
	accessToken, _ := tokenRaw["access_token"].(string)
	refreshToken, _ := tokenRaw["refresh_token"].(string)
	if accessToken == "" || refreshToken == "" {
		return &badRequest{"no Google Home login found in the Antigravity token file"}
	}
	expiry, _ := tokenRaw["expiry"].(string)

	_ = os.MkdirAll(filepath.Dir(secretsPath), 0o700)
	var secDoc map[string]any
	secData, err := os.ReadFile(secretsPath)
	if err == nil {
		_ = json.Unmarshal(secData, &secDoc)
	}
	if secDoc == nil {
		secDoc = make(map[string]any)
	}
	secDoc["google"] = map[string]any{
		"clientId":     clientID,
		"clientSecret": clientSecret,
		"accessToken":  accessToken,
		"refreshToken": refreshToken,
		"expiry":       expiry,
		"scopes":       []string{"https://www.googleapis.com/auth/home.graph"},
	}
	marshaled, err := json.MarshalIndent(secDoc, "", "  ")
	if err != nil {
		return err
	}
	tmp := secretsPath + ".agent-tmp"
	if err := os.WriteFile(tmp, append(marshaled, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, secretsPath)
}

const broadcastInstruction = `- Follow the ` + "`home-speaker-broadcast`" + ` skill: Accompany top-level conversational responses to the user with a concise spoken broadcast (1-2 sentences) by executing the CLI tool ` + "`speaker-broadcast \"<summary>\"`" + ` (never run ` + "`speaker-broadcast`" + ` from a background subagent or a delegated ` + "`claude -p`" + ` helper call). Always use the CLI rather than manual ` + "`home_mcp`" + ` calls with device IDs, because ` + "`speaker-broadcast`" + ` dynamically resolves the live ` + "`default_target`" + ` from ` + "`~/.gemini/speaker_broadcast.json`" + `, checks quiet hours, and verifies enabled status on every execution without caching state. When the user asks to turn speaker broadcasts on/off or change the target room, update ` + "`~/.gemini/speaker_broadcast.json`" + ` (or run ` + "`speaker-broadcast --set-target <room>`" + `) and confirm.`

func (h *homeSpeaker) executeAgentHookAction(ctx context.Context, action string, p homeSpeakerProfile) error {
	action = strings.TrimSpace(action)
	switch action {
	case "install:claude-code", "install:Claude Code", "install_claude_hook":
		if h.claudeSettingsPath == "" {
			return nil
		}
		_ = os.MkdirAll(filepath.Dir(h.claudeSettingsPath), 0o700)
		var settings map[string]any
		if fileExists(h.claudeSettingsPath) {
			data, err := os.ReadFile(h.claudeSettingsPath)
			if err != nil {
				return err
			}
			if err := json.Unmarshal(data, &settings); err != nil {
				return fmt.Errorf("failed to parse Claude settings: %w", err)
			}
		}
		if settings == nil {
			settings = make(map[string]any)
		}
		hooks, _ := settings["hooks"].(map[string]any)
		if hooks == nil {
			hooks = make(map[string]any)
			settings["hooks"] = hooks
		}
		stopGroups, _ := hooks["Stop"].([]any)
		var keptGroups []any
		for _, g := range stopGroups {
			gm, ok := g.(map[string]any)
			if !ok {
				continue
			}
			inner, _ := gm["hooks"].([]any)
			var keptInner []any
			for _, in := range inner {
				inm, ok := in.(map[string]any)
				if !ok {
					continue
				}
				cmd, _ := inm["command"].(string)
				if !strings.Contains(cmd, "claude-stop-hook") && !strings.Contains(cmd, "stop_broadcast.py") {
					keptInner = append(keptInner, inm)
				}
			}
			if len(keptInner) > 0 {
				gm["hooks"] = keptInner
				keptGroups = append(keptGroups, gm)
			}
		}
		hookCmd := fmt.Sprintf("\"%s\" --claude-stop-hook", p.binary)
		newEntry := map[string]any{
			"hooks": []any{
				map[string]any{
					"type":    "command",
					"command": hookCmd,
					"timeout": 10,
				},
			},
		}
		keptGroups = append(keptGroups, newEntry)
		hooks["Stop"] = keptGroups
		data, err := json.MarshalIndent(settings, "", "  ")
		if err != nil {
			return err
		}
		tmp := h.claudeSettingsPath + ".agent-tmp"
		if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
			return err
		}
		return os.Rename(tmp, h.claudeSettingsPath)

	case "remove:claude-code", "remove:Claude Code", "remove_claude_hook":
		if h.claudeSettingsPath == "" || !fileExists(h.claudeSettingsPath) {
			return nil
		}
		data, err := os.ReadFile(h.claudeSettingsPath)
		if err != nil {
			return err
		}
		var settings map[string]any
		if err := json.Unmarshal(data, &settings); err != nil {
			return fmt.Errorf("failed to parse Claude settings: %w", err)
		}
		hooks, ok := settings["hooks"].(map[string]any)
		if !ok {
			return nil
		}
		stopGroups, _ := hooks["Stop"].([]any)
		var keptGroups []any
		for _, g := range stopGroups {
			gm, ok := g.(map[string]any)
			if !ok {
				continue
			}
			inner, _ := gm["hooks"].([]any)
			var keptInner []any
			for _, in := range inner {
				inm, ok := in.(map[string]any)
				if !ok {
					continue
				}
				cmd, _ := inm["command"].(string)
				if !strings.Contains(cmd, "claude-stop-hook") && !strings.Contains(cmd, "stop_broadcast.py") {
					keptInner = append(keptInner, inm)
				}
			}
			if len(keptInner) > 0 {
				gm["hooks"] = keptInner
				keptGroups = append(keptGroups, gm)
			}
		}
		if len(keptGroups) > 0 {
			hooks["Stop"] = keptGroups
		} else {
			delete(hooks, "Stop")
		}
		if len(hooks) == 0 {
			delete(settings, "hooks")
		}
		data, err = json.MarshalIndent(settings, "", "  ")
		if err != nil {
			return err
		}
		tmp := h.claudeSettingsPath + ".agent-tmp"
		if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
			return err
		}
		return os.Rename(tmp, h.claudeSettingsPath)

	case "disable-rival:claude-code", "disable-rival:Claude Code", "disable_rival_hook", "disable-rival":
		homeDir := filepath.Dir(filepath.Dir(h.claudeSettingsPath))
		rivalPath := filepath.Join(homeDir, ".claude", "skills", "google-home", "hooks", "hooks.json")
		if fileExists(rivalPath) {
			disabledPath := rivalPath + ".disabled-by-homespeaker"
			_ = os.Remove(disabledPath)
			if err := os.Rename(rivalPath, disabledPath); err != nil {
				return err
			}
		}
		return nil

	case "add-instruction:claude-code", "add-instruction:Claude Code", "add_claude_instruction":
		return appendInstruction(h.claudeMDPath)
	case "add-instruction:antigravity", "add-instruction:Antigravity", "add_antigravity_instruction":
		return appendInstruction(h.antigravityMDPath)
	case "add-instruction:opencode", "add-instruction:OpenCode", "add_opencode_instruction":
		return appendInstruction(h.opencodeMDPath)

	case "remove-legacy-agent", "remove_legacy_agent":
		if h.legacyPlistPath != "" && fileExists(h.legacyPlistPath) {
			_ = exec.CommandContext(ctx, "launchctl", "bootout", fmt.Sprintf("gui/%d/com.james.chat-monitor", os.Getuid())).Run()
			_ = os.Remove(h.legacyPlistPath)
		}
		return nil

	default:
		return &badRequest{fmt.Sprintf("unknown agent_hook_action %q", action)}
	}
}

func appendInstruction(path string) error {
	if path == "" {
		return nil
	}
	_ = os.MkdirAll(filepath.Dir(path), 0o700)
	existing, _ := os.ReadFile(path)
	str := string(existing)
	if strings.Contains(str, "speaker_broadcast.json") || strings.Contains(str, "home-speaker-broadcast") || strings.Contains(str, "speaker-broadcast") {
		return nil
	}
	if len(str) > 0 && !strings.HasSuffix(str, "\n") {
		str += "\n"
	}
	str += broadcastInstruction + "\n"
	return os.WriteFile(path, []byte(str), 0o600)
}

type homeSpeakerSecretsData struct {
	Google *struct {
		Email        string `json:"email,omitempty"`
		RefreshToken string `json:"refreshToken,omitempty"`
	} `json:"google,omitempty"`
	GeminiApiKey              string `json:"geminiApiKey,omitempty"`
	GeminiAPIKey              string `json:"geminiAPIKey,omitempty"`
	SlackToken                string `json:"slackToken,omitempty"`
	BeeperToken               string `json:"beeperToken,omitempty"`
	OAuthClientIdOverride     string `json:"oauthClientIdOverride,omitempty"`
	OAuthClientIDOverride     string `json:"oauthClientIDOverride,omitempty"`
	OAuthClientSecretOverride string `json:"oauthClientSecretOverride,omitempty"`
}

func (h *homeSpeaker) readSecretsData(path string) homeSpeakerSecretsData {
	var sec homeSpeakerSecretsData
	if path == "" {
		return sec
	}
	data, err := os.ReadFile(path)
	if err == nil {
		_ = json.Unmarshal(data, &sec)
	}
	if sec.GeminiApiKey == "" {
		sec.GeminiApiKey = sec.GeminiAPIKey
	}
	if sec.OAuthClientIdOverride == "" {
		sec.OAuthClientIdOverride = sec.OAuthClientIDOverride
	}
	return sec
}

type homeSpeakerCredentialsData struct {
	SlackToken        string `json:"slack_token,omitempty"`
	BeeperToken       string `json:"beeper_token,omitempty"`
	OAuthClientID     string `json:"oauth_client_id,omitempty"`
	OAuthClientSecret string `json:"oauth_client_secret,omitempty"`
}

func (h *homeSpeaker) readCredentialsData() homeSpeakerCredentialsData {
	var cred homeSpeakerCredentialsData
	if h.credentialsPath == "" {
		return cred
	}
	data, err := os.ReadFile(h.credentialsPath)
	if err == nil {
		_ = json.Unmarshal(data, &cred)
	}
	return cred
}

type homeSpeakerMonitorStatusData struct {
	IsRunning               bool   `json:"is_running"`
	LastPollDate            string `json:"last_poll_date,omitempty"`
	SlackIdentity           string `json:"slack_identity,omitempty"`
	ActiveGoogleChatBackend string `json:"active_google_chat_backend,omitempty"`
	LastError               string `json:"last_error,omitempty"`
}

func (h *homeSpeaker) readMonitorStatus() homeSpeakerMonitorStatusData {
	var ms homeSpeakerMonitorStatusData
	p := h.activeProfile()
	statusPath := p.monitorStatusPath
	if statusPath == "" || !fileExists(statusPath) {
		if fileExists(h.monitorStatusPath) {
			statusPath = h.monitorStatusPath
		} else if p.configPath != "" && fileExists(filepath.Join(filepath.Dir(p.configPath), "chat_monitor_status.json")) {
			statusPath = filepath.Join(filepath.Dir(p.configPath), "chat_monitor_status.json")
		} else {
			return ms
		}
	}
	data, err := os.ReadFile(statusPath)
	if err != nil {
		return ms
	}
	var raw map[string]any
	if json.Unmarshal(data, &raw) != nil {
		return ms
	}
	if v, ok := raw["is_running"].(bool); ok {
		ms.IsRunning = v
	} else if v, ok := raw["running"].(bool); ok {
		ms.IsRunning = v
	}
	if v, ok := raw["slack_identity"].(string); ok {
		ms.SlackIdentity = v
	} else if v, ok := raw["slackIdentity"].(string); ok {
		ms.SlackIdentity = v
	}
	if v, ok := raw["active_google_chat_backend"].(string); ok {
		ms.ActiveGoogleChatBackend = v
	} else if v, ok := raw["activeGoogleChatBackend"].(string); ok {
		ms.ActiveGoogleChatBackend = v
	}
	if v, ok := raw["last_error"].(string); ok {
		ms.LastError = v
	} else if v, ok := raw["lastError"].(string); ok {
		ms.LastError = v
	}
	if v, ok := raw["last_poll_date"].(string); ok {
		ms.LastPollDate = v
	} else if v, ok := raw["lastPollDate"].(string); ok {
		ms.LastPollDate = v
	} else if v, ok := raw["last_poll_date"].(float64); ok && v > 0 {
		ms.LastPollDate = time.Unix(int64(v), 0).UTC().Format(time.RFC3339)
	} else if v, ok := raw["lastPollDate"].(float64); ok && v > 0 {
		ms.LastPollDate = time.Unix(int64(v), 0).UTC().Format(time.RFC3339)
	}
	return ms
}

func fileExists(path string) bool {
	if path == "" {
		return false
	}
	_, err := os.Stat(path)
	return err == nil
}

func (h *homeSpeaker) inspectAgents(p homeSpeakerProfile) []homeSpeakerAgentHook {
	var out []homeSpeakerAgentHook

	// Claude Code
	claudeInstalled := fileExists(filepath.Dir(h.claudeSettingsPath))
	claudeHookState := "not_installed"
	claudeSpeaksTwice := false
	claudeByInstruction := false

	expectedQuotedCmd := fmt.Sprintf("\"%s\" --claude-stop-hook", p.binary)
	expectedRawCmd := p.binary + " --claude-stop-hook"
	expectedGoQCmd := fmt.Sprintf("%q --claude-stop-hook", p.binary)

	if claudeInstalled {
		if fileExists(h.claudeSettingsPath) {
			data, err := os.ReadFile(h.claudeSettingsPath)
			if err == nil {
				var settings map[string]any
				if json.Unmarshal(data, &settings) == nil {
					if hooks, ok := settings["hooks"].(map[string]any); ok {
						if stop, ok := hooks["Stop"].([]any); ok {
							for _, g := range stop {
								if gm, ok := g.(map[string]any); ok {
									if inner, ok := gm["hooks"].([]any); ok {
										for _, in := range inner {
											if inm, ok := in.(map[string]any); ok {
												cmd, _ := inm["command"].(string)
												if strings.Contains(cmd, "claude-stop-hook") || strings.Contains(cmd, "stop_broadcast.py") {
													trimmed := strings.TrimSpace(cmd)
													if trimmed == expectedQuotedCmd || trimmed == expectedRawCmd || trimmed == expectedGoQCmd {
														claudeHookState = "installed"
													} else {
														claudeHookState = "stale"
													}
												}
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
		if fileExists(h.claudeMDPath) {
			data, err := os.ReadFile(h.claudeMDPath)
			if err == nil {
				str := string(data)
				claudeByInstruction = strings.Contains(str, "speaker_broadcast.json") || strings.Contains(str, "home-speaker-broadcast") || strings.Contains(str, "speaker-broadcast")
			}
		}
		if !claudeByInstruction {
			homeDir := filepath.Dir(filepath.Dir(h.claudeSettingsPath))
			rootClaudeMD := filepath.Join(homeDir, "CLAUDE.md")
			if fileExists(rootClaudeMD) {
				data, err := os.ReadFile(rootClaudeMD)
				if err == nil {
					str := string(data)
					claudeByInstruction = strings.Contains(str, "speaker_broadcast.json") || strings.Contains(str, "home-speaker-broadcast") || strings.Contains(str, "speaker-broadcast")
				}
			}
		}
		homeDir := filepath.Dir(filepath.Dir(h.claudeSettingsPath))
		rivalPath := filepath.Join(homeDir, ".claude", "skills", "google-home", "hooks", "hooks.json")
		if fileExists(rivalPath) && claudeHookState == "installed" {
			data, err := os.ReadFile(rivalPath)
			if err == nil {
				str := string(data)
				if strings.Contains(str, "stop_broadcast") || strings.Contains(str, "speaker-broadcast") {
					claudeSpeaksTwice = true
				}
			}
		}
	}
	out = append(out, homeSpeakerAgentHook{
		Agent:                   "Claude Code",
		AgentSlug:               "claude-code",
		HookState:               claudeHookState,
		SpeaksTwice:             claudeSpeaksTwice,
		ConfiguredByInstruction: claudeByInstruction,
	})

	// Antigravity
	agyByInstruction := false
	if fileExists(h.antigravityMDPath) {
		data, err := os.ReadFile(h.antigravityMDPath)
		if err == nil {
			str := string(data)
			agyByInstruction = strings.Contains(str, "speaker_broadcast.json") || strings.Contains(str, "home-speaker-broadcast") || strings.Contains(str, "speaker-broadcast")
		}
	}
	if !agyByInstruction {
		homeDir := filepath.Dir(filepath.Dir(h.antigravityMDPath))
		geminiMD := filepath.Join(homeDir, ".gemini", "GEMINI.md")
		if fileExists(geminiMD) {
			data, err := os.ReadFile(geminiMD)
			if err == nil {
				str := string(data)
				agyByInstruction = strings.Contains(str, "speaker_broadcast.json") || strings.Contains(str, "home-speaker-broadcast") || strings.Contains(str, "speaker-broadcast")
			}
		}
	}
	out = append(out, homeSpeakerAgentHook{
		Agent:                   "Antigravity",
		AgentSlug:               "antigravity",
		HookState:               "not_installed",
		ConfiguredByInstruction: agyByInstruction,
	})

	// OpenCode
	openCodeByInstruction := false
	if fileExists(h.opencodeMDPath) {
		data, err := os.ReadFile(h.opencodeMDPath)
		if err == nil {
			str := string(data)
			openCodeByInstruction = strings.Contains(str, "speaker_broadcast.json") || strings.Contains(str, "home-speaker-broadcast") || strings.Contains(str, "speaker-broadcast")
		}
	}
	out = append(out, homeSpeakerAgentHook{
		Agent:                   "OpenCode",
		AgentSlug:               "opencode",
		HookState:               "not_installed",
		ConfiguredByInstruction: openCodeByInstruction,
	})

	return out
}

func (h *homeSpeaker) inspectVersion(p homeSpeakerProfile) string {
	if p.binary == "" || !fileExists(p.binary) {
		return ""
	}
	if strings.Contains(p.binary, ".app/Contents/MacOS/") {
		plistPath := filepath.Join(filepath.Dir(filepath.Dir(p.binary)), "Info.plist")
		if data, err := os.ReadFile(plistPath); err == nil {
			str := string(data)
			if idx := strings.Index(str, "CFBundleShortVersionString"); idx != -1 {
				sub := str[idx:]
				if sIdx := strings.Index(sub, "<string>"); sIdx != -1 {
					sub = sub[sIdx+8:]
					if eIdx := strings.Index(sub, "</string>"); eIdx != -1 {
						return strings.TrimSpace(sub[:eIdx])
					}
				}
			}
		}
	}
	toolJSON := filepath.Join(filepath.Dir(filepath.Dir(p.binary)), "vitruvian-tool.json")
	if data, err := os.ReadFile(toolJSON); err == nil {
		var tool struct {
			Version string `json:"version"`
		}
		if json.Unmarshal(data, &tool) == nil && tool.Version != "" {
			return strings.TrimSpace(tool.Version)
		}
	}
	return ""
}

// --- handlers -------------------------------------------------------------

// getHomeSpeaker is GET /v1/homespeaker: READ. Which speaker the Mac talks to
// is on its menu bar for anyone at the keyboard.
func (srv *server) getHomeSpeaker(w http.ResponseWriter, r *http.Request) {
	st := srv.speaker.state(r.Context())
	st.PhoneConnected = srv.phone.Connected()
	writeJSON(w, st)
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
		writeError(w, http.StatusBadRequest, "nothing to change: give enabled, default_target, speech_length, quiet_hours_enabled, pause_media, pause_media_extra_seconds, announce_volume_enabled, announce_volume, speak_home, speak_local, speak_phone, phone_pause_media, phone_headphones_only, local_engine, gemini_voice, announcement_style, style_model, announce_claude_code, announce_antigravity, announce_opencode, slack_enabled, google_chat_enabled, beeper_enabled, beeper_announce, beeper_network or mute_own_messages")
		return
	}
	changed, err := srv.speaker.apply(r.Context(), body)
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
	st := srv.speaker.state(r.Context())
	st.PhoneConnected = srv.phone.Connected()
	writeJSON(w, st)
}

// maxPhoneSayBody bounds POST /v1/homespeaker/phone-say so base64-encoded WAV
// audio from Gemini TTS fits comfortably.
const maxPhoneSayBody = 8 << 20

// phoneSayTimeout bounds how long the agent waits for phone.speak to finish
// playing audio on the phone.
const phoneSayTimeout = 60 * time.Second

type homeSpeakerPhoneSayRequest struct {
	Text           string `json:"text"`
	WavBase64      string `json:"wav_base64,omitempty"`
	PauseMedia     *bool  `json:"pause_media,omitempty"`
	HeadphonesOnly *bool  `json:"headphones_only,omitempty"`
}

type homeSpeakerPhoneSayResponse struct {
	OK      bool   `json:"ok"`
	Spoken  bool   `json:"spoken"`
	Skipped bool   `json:"skipped,omitempty"`
	Reason  string `json:"reason,omitempty"`
	Engine  string `json:"engine,omitempty"`
}

// homeSpeakerPhoneSay is POST /v1/homespeaker/phone-say: dispatches phone.speak
// over the active phone bridge so HomeSpeaker on the Mac (or a paired caller)
// can speak an announcement on the phone.
func (srv *server) homeSpeakerPhoneSay(w http.ResponseWriter, r *http.Request) {
	if r.Body == nil {
		writeError(w, http.StatusBadRequest, "a JSON body is required")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxPhoneSayBody)
	var req homeSpeakerPhoneSayRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body: "+err.Error())
		return
	}
	text := strings.TrimSpace(req.Text)
	if text == "" {
		writeError(w, http.StatusBadRequest, "text is required")
		return
	}
	if !srv.phone.Connected() {
		writeJSON(w, homeSpeakerPhoneSayResponse{
			OK:     false,
			Spoken: false,
			Reason: "no phone connected",
		})
		return
	}
	cfg, _ := srv.speaker.readConfig()
	pauseMedia := false
	if req.PauseMedia != nil {
		pauseMedia = *req.PauseMedia
	} else if cfg != nil {
		pauseMedia, _ = cfg["phone_pause_media"].(bool)
	}
	headphonesOnly := false
	if req.HeadphonesOnly != nil {
		headphonesOnly = *req.HeadphonesOnly
	} else if cfg != nil {
		headphonesOnly, _ = cfg["phone_headphones_only"].(bool)
	}
	argsJSON, err := json.Marshal(map[string]any{
		"text":            text,
		"wav_base64":      req.WavBase64,
		"pause_media":     pauseMedia,
		"headphones_only": headphonesOnly,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	logAct("homespeaker", "phone-say "+text)
	res, err := srv.phone.dispatch(r.Context(), "phone.speak", argsJSON, phoneSayTimeout)
	if err != nil {
		writeJSON(w, homeSpeakerPhoneSayResponse{
			OK:     false,
			Spoken: false,
			Reason: err.Error(),
		})
		return
	}
	rawText := firstTextContent(res.Content)
	if res.IsError {
		writeJSON(w, homeSpeakerPhoneSayResponse{
			OK:     false,
			Spoken: false,
			Reason: rawText,
		})
		return
	}
	var toolOut struct {
		Spoken  bool   `json:"spoken"`
		Skipped bool   `json:"skipped"`
		Reason  string `json:"reason"`
		Engine  string `json:"engine"`
	}
	if err := json.Unmarshal([]byte(rawText), &toolOut); err != nil {
		writeJSON(w, homeSpeakerPhoneSayResponse{
			OK:     false,
			Spoken: false,
			Reason: "invalid phone.speak response: " + err.Error(),
		})
		return
	}
	writeJSON(w, homeSpeakerPhoneSayResponse{
		OK:      true,
		Spoken:  toolOut.Spoken,
		Skipped: toolOut.Skipped,
		Reason:  toolOut.Reason,
		Engine:  toolOut.Engine,
	})
}

// sayLimit bounds POST /v1/homespeaker/say: Gemini TTS synthesis + local
// audio playback + Google Home broadcast can legitimately exceed 30 s.
const sayLimit = 90 * time.Second

// homeSpeakerSay is POST /v1/homespeaker/say: ACT. The text is spoken in the
// house, which is at least as much of an act as the clipboard.
func (srv *server) homeSpeakerSay(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Text     string `json:"text,omitempty"`
		Replay   bool   `json:"replay,omitempty"`
		ReplayID string `json:"replay_id,omitempty"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	text := strings.TrimSpace(body.Text)
	if body.ReplayID != "" {
		found := false
		for _, item := range srv.speaker.recentBroadcasts(50) {
			if item.ID == body.ReplayID {
				text = item.Text
				found = true
				break
			}
		}
		if !found {
			writeError(w, http.StatusBadRequest, "That announcement is no longer in the history")
			return
		}
	}
	if text == "" {
		writeError(w, http.StatusBadRequest, "text is required")
		return
	}
	p := srv.speaker.activeProfile()
	if _, err := os.Stat(p.binary); err != nil {
		writeError(w, http.StatusConflict, "HomeSpeaker is not installed at "+p.binary)
		return
	}
	isReplay := body.Replay || body.ReplayID != ""
	logLabel := "say " + text
	if isReplay {
		logLabel = "replay " + text
	}
	logAct("homespeaker", logLabel)

	var historySnapshot []byte
	if isReplay && p.historyPath != "" {
		if data, err := os.ReadFile(p.historyPath); err == nil {
			historySnapshot = data
		}
	}

	run := srv.speaker.say
	if run == nil {
		run = srv.speaker.run
	}
	stdout, stderr, err := run(r.Context(), sayLimit, p.binary, "--say", text)
	if historySnapshot != nil {
		_ = os.WriteFile(p.historyPath, historySnapshot, 0o600)
	}
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
