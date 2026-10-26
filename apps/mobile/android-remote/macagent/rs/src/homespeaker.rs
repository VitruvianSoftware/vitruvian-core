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

//! HomeSpeaker (`apps/desktop/home-speaker`) state, settings, volume, and speech endpoints.

use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

use vitruvian_remote_macagent_metrics::json::{JsonObject, JsonValue};
use vitruvian_remote_macagent_metrics::time_util::Timestamp;

use crate::http_util::{log_act, HttpRequest, HttpResponse};
use crate::phone::{first_text_content, PhoneBridge};
use crate::sampler::{find_executable_in_path, run_tool_within};

pub const HOME_SPEAKER_BINARY: &str = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker";
pub const DEFAULT_LOCAL_VOICE: &str = "com.apple.ttsbundle.siri_Aaron_en-US_premium";
pub const RECENT_BROADCASTS: usize = 5;
pub const PAUSE_MEDIA_EXTRA_MAX: f64 = 10.0;
pub const MAX_PHONE_SAY_BODY: usize = 8 << 20;
pub const PHONE_SAY_TIMEOUT: Duration = Duration::from_secs(60);
pub const SAY_LIMIT: Duration = Duration::from_secs(90);
pub const VOLUME_LIMIT: Duration = Duration::from_secs(45);

/// Seconds between 1970-01-01T00:00:00Z and 2001-01-01T00:00:00Z (Swift Foundation `Date` reference epoch).
pub const SWIFT_REFERENCE_EPOCH_UNIX_SECS: i64 = 978_307_200;

pub const SPEECH_LENGTHS: &[&str] = &["headline", "summary", "full"];
pub const LOCAL_ENGINES: &[&str] = &["apple", "gemini"];
pub const GEMINI_VOICES: &[&str] = &[
    "Kore",
    "Puck",
    "Aoede",
    "Charon",
    "Zephyr",
    "Fenrir",
    "Leda",
    "Orus",
    "voice_vaoo7ayczx69",
    "voice_o1be80ujj8bb",
];
pub const ANNOUNCEMENT_STYLES: &[&str] = &["verbatim", "plain", "briefing", "casual", "custom"];
pub const STYLE_MODELS: &[&str] = &["apple", "gemini"];
pub const BEEPER_ANNOUNCE_MODES: &[&str] = &["direct_and_mentions", "all"];
pub const AGENT_MARKERS: &[&str] = &["CLAUDECODE", "ANTIGRAVITY_AGENT", "OPENCODE", "AI_AGENT"];

const BROADCAST_INSTRUCTION: &str = "- Follow the `home-speaker-broadcast` skill: Accompany top-level conversational responses to the user with a concise spoken broadcast (1-2 sentences) by executing the CLI tool `speaker-broadcast \"<summary>\"` (never run `speaker-broadcast` from a background subagent or a delegated `claude -p` helper call). Always use the CLI rather than manual `home_mcp` calls with device IDs, because `speaker-broadcast` dynamically resolves the live `default_target` from `~/.gemini/speaker_broadcast.json`, checks quiet hours, and verifies enabled status on every execution without caching state. When the user asks to turn speaker broadcasts on/off or change the target room, update `~/.gemini/speaker_broadcast.json` (or run `speaker-broadcast --set-target <room>`) and confirm.";

pub type RunnerFn =
    Arc<dyn Fn(Duration, &str, &[String]) -> Result<(String, String), String> + Send + Sync>;
pub type RunningFn = Arc<dyn Fn() -> bool + Send + Sync>;
pub type ReadClipboardFn = Arc<dyn Fn() -> Result<String, String> + Send + Sync>;
pub type ListVoicesFn = Arc<dyn Fn() -> Result<Vec<HomeSpeakerVoice>, String> + Send + Sync>;

#[derive(Clone)]
pub struct HomeSpeaker {
    pub config_path: PathBuf,
    pub history_path: PathBuf,
    pub secrets_path: PathBuf,
    pub door_path: PathBuf,
    pub credentials_path: PathBuf,
    pub monitor_status_path: PathBuf,
    pub claude_settings_path: PathBuf,
    pub claude_md_path: PathBuf,
    pub antigravity_md_path: PathBuf,
    pub opencode_md_path: PathBuf,
    pub legacy_plist_path: PathBuf,
    pub oauth_client_path: PathBuf,
    pub antigravity_tokens_path: PathBuf,
    pub binary: PathBuf,
    pub run: RunnerFn,
    pub say: Option<RunnerFn>,
    pub running: Option<RunningFn>,
    pub list_voices: Option<ListVoicesFn>,
    pub read_clipboard: Option<ReadClipboardFn>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerProfile {
    pub active_door: String,
    pub config_path: PathBuf,
    pub history_path: PathBuf,
    pub secrets_path: PathBuf,
    pub monitor_status_path: PathBuf,
    pub binary: PathBuf,
    pub lock_path: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerVoice {
    pub id: String,
    pub name: String,
    pub lang: String,
}

impl HomeSpeakerVoice {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("id".to_string(), JsonValue::String(self.id.clone()));
        m.insert("name".to_string(), JsonValue::String(self.name.clone()));
        m.insert("lang".to_string(), JsonValue::String(self.lang.clone()));
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerHome {
    pub id: String,
    pub name: String,
}

impl HomeSpeakerHome {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("id".to_string(), JsonValue::String(self.id.clone()));
        m.insert("name".to_string(), JsonValue::String(self.name.clone()));
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerAgentHook {
    pub agent: String,
    pub agent_slug: String,
    pub hook_state: String,
    pub speaks_twice: bool,
    pub configured_by_instruction: bool,
}

impl HomeSpeakerAgentHook {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("agent".to_string(), JsonValue::String(self.agent.clone()));
        m.insert(
            "agent_slug".to_string(),
            JsonValue::String(self.agent_slug.clone()),
        );
        m.insert(
            "hook_state".to_string(),
            JsonValue::String(self.hook_state.clone()),
        );
        m.insert(
            "speaks_twice".to_string(),
            JsonValue::Bool(self.speaks_twice),
        );
        m.insert(
            "configured_by_instruction".to_string(),
            JsonValue::Bool(self.configured_by_instruction),
        );
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerCustomVoice {
    pub id: String,
    pub name: String,
}

impl HomeSpeakerCustomVoice {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("id".to_string(), JsonValue::String(self.id.clone()));
        m.insert("name".to_string(), JsonValue::String(self.name.clone()));
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerBeeperNetwork {
    pub key: String,
    pub name: String,
    pub state: String,
}

impl HomeSpeakerBeeperNetwork {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("key".to_string(), JsonValue::String(self.key.clone()));
        m.insert("name".to_string(), JsonValue::String(self.name.clone()));
        m.insert("state".to_string(), JsonValue::String(self.state.clone()));
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerBeeperNetworkUpdate {
    pub key: String,
    pub reading: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerQuiet {
    pub enabled: bool,
    pub start: String,
    pub end: String,
    pub active: bool,
}

impl HomeSpeakerQuiet {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("enabled".to_string(), JsonValue::Bool(self.enabled));
        m.insert("start".to_string(), JsonValue::String(self.start.clone()));
        m.insert("end".to_string(), JsonValue::String(self.end.clone()));
        m.insert("active".to_string(), JsonValue::Bool(self.active));
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerTarget {
    pub key: String,
    pub name: String,
    pub room: String,
    pub target_type: String,
    pub selected: bool,
}

impl HomeSpeakerTarget {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("key".to_string(), JsonValue::String(self.key.clone()));
        m.insert("name".to_string(), JsonValue::String(self.name.clone()));
        m.insert("room".to_string(), JsonValue::String(self.room.clone()));
        m.insert(
            "type".to_string(),
            JsonValue::String(self.target_type.clone()),
        );
        m.insert("selected".to_string(), JsonValue::Bool(self.selected));
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerLast {
    pub id: String,
    pub text: String,
    pub target: String,
    pub source: String,
    pub at: Timestamp,
}

impl HomeSpeakerLast {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        if !self.id.is_empty() {
            m.insert("id".to_string(), JsonValue::String(self.id.clone()));
        }
        m.insert("text".to_string(), JsonValue::String(self.text.clone()));
        m.insert("target".to_string(), JsonValue::String(self.target.clone()));
        m.insert("source".to_string(), JsonValue::String(self.source.clone()));
        m.insert("at".to_string(), JsonValue::String(self.at.to_rfc3339()));
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HomeSpeakerVolume {
    pub available: bool,
    pub reason: String,
    pub speaker: String,
    pub percent: i64,
    pub muted: bool,
    pub online: bool,
}

impl HomeSpeakerVolume {
    pub fn from_json(v: &JsonValue) -> Option<Self> {
        let obj = v.as_object()?;
        Some(Self {
            available: obj
                .get("available")
                .and_then(|x| x.as_bool())
                .unwrap_or(false),
            reason: obj
                .get("reason")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .to_string(),
            speaker: obj
                .get("speaker")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .to_string(),
            percent: obj.get("percent").and_then(|x| x.as_i64()).unwrap_or(0),
            muted: obj.get("muted").and_then(|x| x.as_bool()).unwrap_or(false),
            online: obj.get("online").and_then(|x| x.as_bool()).unwrap_or(false),
        })
    }

    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("available".to_string(), JsonValue::Bool(self.available));
        if !self.reason.is_empty() {
            m.insert("reason".to_string(), JsonValue::String(self.reason.clone()));
        }
        if !self.speaker.is_empty() {
            m.insert(
                "speaker".to_string(),
                JsonValue::String(self.speaker.clone()),
            );
        }
        m.insert("percent".to_string(), JsonValue::from_i64(self.percent));
        m.insert("muted".to_string(), JsonValue::Bool(self.muted));
        m.insert("online".to_string(), JsonValue::Bool(self.online));
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug)]
pub struct HomeSpeakerState {
    pub available: bool,
    pub reason: String,
    pub installed: bool,
    pub app_running: bool,
    pub signed_in: bool,
    pub active_door: String,
    pub enabled: bool,
    pub default_target: String,
    pub speech_length: String,
    pub pause_media: bool,
    pub pause_media_extra_seconds: f64,
    pub announce_volume_enabled: bool,
    pub announce_volume: i64,
    pub speak_home: bool,
    pub speak_local: bool,
    pub speak_phone: Option<bool>,
    pub local_voice: String,
    pub local_voice_name: String,
    pub phone_pause_media: bool,
    pub phone_headphones_only: bool,
    pub phone_connected: bool,
    pub local_engine: String,
    pub gemini_voice: String,
    pub has_gemini_key: bool,
    pub announcement_style: String,
    pub style_model: String,
    pub custom_style_prompt: String,
    pub home_cast_voice: bool,
    pub custom_voices: Vec<HomeSpeakerCustomVoice>,
    pub structure_name: String,
    pub quiet_hours: HomeSpeakerQuiet,
    pub targets: Vec<HomeSpeakerTarget>,
    pub last: Option<HomeSpeakerLast>,
    pub quiet_hours_active: bool,
    pub available_voices: Vec<HomeSpeakerVoice>,
    pub structure_id: String,
    pub homes: Vec<HomeSpeakerHome>,
    pub account_email: String,
    pub has_oauth_client: bool,
    pub has_antigravity_tokens: bool,
    pub monitor_running: bool,
    pub last_poll_at: String,
    pub slack_identity: String,
    pub active_google_chat_backend: String,
    pub chat_runtime_error: String,
    pub has_slack_token: bool,
    pub has_beeper_token: bool,
    pub has_chat_access: bool,
    pub gws_installed: bool,
    pub gws_account: String,
    pub google_chat_source: String,
    pub poll_interval: i64,
    pub agents: Vec<HomeSpeakerAgentHook>,
    pub legacy_launch_agent: bool,
    pub custom_oauth_client_id: String,
    pub has_custom_oauth_secret: bool,
    pub home_speaker_version: String,
    pub announce_claude_code: Option<bool>,
    pub announce_antigravity: Option<bool>,
    pub announce_opencode: Option<bool>,
    pub slack_enabled: Option<bool>,
    pub google_chat_enabled: Option<bool>,
    pub beeper_enabled: Option<bool>,
    pub beeper_announce: String,
    pub beeper_networks: Vec<HomeSpeakerBeeperNetwork>,
    pub mute_own_messages: Option<bool>,
    pub recent: Vec<HomeSpeakerLast>,
}

impl Default for HomeSpeakerState {
    fn default() -> Self {
        Self {
            available: false,
            reason: String::new(),
            installed: false,
            app_running: false,
            signed_in: false,
            active_door: String::new(),
            enabled: false,
            default_target: String::new(),
            speech_length: String::new(),
            pause_media: false,
            pause_media_extra_seconds: 0.0,
            announce_volume_enabled: false,
            announce_volume: 0,
            speak_home: false,
            speak_local: false,
            speak_phone: None,
            local_voice: String::new(),
            local_voice_name: String::new(),
            phone_pause_media: false,
            phone_headphones_only: false,
            phone_connected: false,
            local_engine: String::new(),
            gemini_voice: String::new(),
            has_gemini_key: false,
            announcement_style: String::new(),
            style_model: String::new(),
            custom_style_prompt: String::new(),
            home_cast_voice: false,
            custom_voices: Vec::new(),
            structure_name: String::new(),
            quiet_hours: HomeSpeakerQuiet {
                enabled: false,
                start: String::new(),
                end: String::new(),
                active: false,
            },
            targets: Vec::new(),
            last: None,
            quiet_hours_active: false,
            available_voices: Vec::new(),
            structure_id: String::new(),
            homes: Vec::new(),
            account_email: String::new(),
            has_oauth_client: false,
            has_antigravity_tokens: false,
            monitor_running: false,
            last_poll_at: String::new(),
            slack_identity: String::new(),
            active_google_chat_backend: String::new(),
            chat_runtime_error: String::new(),
            has_slack_token: false,
            has_beeper_token: false,
            has_chat_access: false,
            gws_installed: false,
            gws_account: String::new(),
            google_chat_source: String::new(),
            poll_interval: 0,
            agents: Vec::new(),
            legacy_launch_agent: false,
            custom_oauth_client_id: String::new(),
            has_custom_oauth_secret: false,
            home_speaker_version: String::new(),
            announce_claude_code: None,
            announce_antigravity: None,
            announce_opencode: None,
            slack_enabled: None,
            google_chat_enabled: None,
            beeper_enabled: None,
            beeper_announce: String::new(),
            beeper_networks: Vec::new(),
            mute_own_messages: None,
            recent: Vec::new(),
        }
    }
}

impl HomeSpeakerState {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("available".to_string(), JsonValue::Bool(self.available));
        if !self.reason.is_empty() {
            m.insert("reason".to_string(), JsonValue::String(self.reason.clone()));
        }
        m.insert("installed".to_string(), JsonValue::Bool(self.installed));
        m.insert("app_running".to_string(), JsonValue::Bool(self.app_running));
        m.insert("signed_in".to_string(), JsonValue::Bool(self.signed_in));
        m.insert(
            "active_door".to_string(),
            JsonValue::String(self.active_door.clone()),
        );
        m.insert("enabled".to_string(), JsonValue::Bool(self.enabled));
        m.insert(
            "default_target".to_string(),
            JsonValue::String(self.default_target.clone()),
        );
        m.insert(
            "speech_length".to_string(),
            JsonValue::String(self.speech_length.clone()),
        );
        m.insert("pause_media".to_string(), JsonValue::Bool(self.pause_media));
        m.insert(
            "pause_media_extra_seconds".to_string(),
            JsonValue::from_f64(self.pause_media_extra_seconds),
        );
        m.insert(
            "announce_volume_enabled".to_string(),
            JsonValue::Bool(self.announce_volume_enabled),
        );
        m.insert(
            "announce_volume".to_string(),
            JsonValue::from_i64(self.announce_volume),
        );
        m.insert("speak_home".to_string(), JsonValue::Bool(self.speak_home));
        m.insert("speak_local".to_string(), JsonValue::Bool(self.speak_local));
        if let Some(sp) = self.speak_phone {
            m.insert("speak_phone".to_string(), JsonValue::Bool(sp));
        }
        m.insert(
            "local_voice".to_string(),
            JsonValue::String(self.local_voice.clone()),
        );
        m.insert(
            "local_voice_name".to_string(),
            JsonValue::String(self.local_voice_name.clone()),
        );
        m.insert(
            "phone_pause_media".to_string(),
            JsonValue::Bool(self.phone_pause_media),
        );
        m.insert(
            "phone_headphones_only".to_string(),
            JsonValue::Bool(self.phone_headphones_only),
        );
        m.insert(
            "phone_connected".to_string(),
            JsonValue::Bool(self.phone_connected),
        );
        m.insert(
            "local_engine".to_string(),
            JsonValue::String(self.local_engine.clone()),
        );
        m.insert(
            "gemini_voice".to_string(),
            JsonValue::String(self.gemini_voice.clone()),
        );
        m.insert(
            "has_gemini_key".to_string(),
            JsonValue::Bool(self.has_gemini_key),
        );
        m.insert(
            "announcement_style".to_string(),
            JsonValue::String(self.announcement_style.clone()),
        );
        m.insert(
            "style_model".to_string(),
            JsonValue::String(self.style_model.clone()),
        );
        if !self.custom_style_prompt.is_empty() {
            m.insert(
                "custom_style_prompt".to_string(),
                JsonValue::String(self.custom_style_prompt.clone()),
            );
        }
        m.insert(
            "home_cast_voice".to_string(),
            JsonValue::Bool(self.home_cast_voice),
        );
        if !self.custom_voices.is_empty() {
            m.insert(
                "custom_voices".to_string(),
                JsonValue::Array(self.custom_voices.iter().map(|v| v.to_json()).collect()),
            );
        }
        m.insert(
            "structure_name".to_string(),
            JsonValue::String(self.structure_name.clone()),
        );
        m.insert("quiet_hours".to_string(), self.quiet_hours.to_json());
        m.insert(
            "targets".to_string(),
            JsonValue::Array(self.targets.iter().map(|t| t.to_json()).collect()),
        );
        if let Some(ref last) = self.last {
            m.insert("last".to_string(), last.to_json());
        }
        m.insert(
            "quiet_hours_active".to_string(),
            JsonValue::Bool(self.quiet_hours_active),
        );
        if !self.available_voices.is_empty() {
            m.insert(
                "available_voices".to_string(),
                JsonValue::Array(self.available_voices.iter().map(|v| v.to_json()).collect()),
            );
        }
        if !self.structure_id.is_empty() {
            m.insert(
                "structure_id".to_string(),
                JsonValue::String(self.structure_id.clone()),
            );
        }
        if !self.homes.is_empty() {
            m.insert(
                "homes".to_string(),
                JsonValue::Array(self.homes.iter().map(|h| h.to_json()).collect()),
            );
        }
        if !self.account_email.is_empty() {
            m.insert(
                "account_email".to_string(),
                JsonValue::String(self.account_email.clone()),
            );
        }
        m.insert(
            "has_oauth_client".to_string(),
            JsonValue::Bool(self.has_oauth_client),
        );
        m.insert(
            "has_antigravity_tokens".to_string(),
            JsonValue::Bool(self.has_antigravity_tokens),
        );
        m.insert(
            "monitor_running".to_string(),
            JsonValue::Bool(self.monitor_running),
        );
        if !self.last_poll_at.is_empty() {
            m.insert(
                "last_poll_at".to_string(),
                JsonValue::String(self.last_poll_at.clone()),
            );
        }
        if !self.slack_identity.is_empty() {
            m.insert(
                "slack_identity".to_string(),
                JsonValue::String(self.slack_identity.clone()),
            );
        }
        if !self.active_google_chat_backend.is_empty() {
            m.insert(
                "active_google_chat_backend".to_string(),
                JsonValue::String(self.active_google_chat_backend.clone()),
            );
        }
        if !self.chat_runtime_error.is_empty() {
            m.insert(
                "chat_runtime_error".to_string(),
                JsonValue::String(self.chat_runtime_error.clone()),
            );
        }
        m.insert(
            "has_slack_token".to_string(),
            JsonValue::Bool(self.has_slack_token),
        );
        m.insert(
            "has_beeper_token".to_string(),
            JsonValue::Bool(self.has_beeper_token),
        );
        m.insert(
            "has_chat_access".to_string(),
            JsonValue::Bool(self.has_chat_access),
        );
        m.insert(
            "gws_installed".to_string(),
            JsonValue::Bool(self.gws_installed),
        );
        if !self.gws_account.is_empty() {
            m.insert(
                "gws_account".to_string(),
                JsonValue::String(self.gws_account.clone()),
            );
        }
        if !self.google_chat_source.is_empty() {
            m.insert(
                "google_chat_source".to_string(),
                JsonValue::String(self.google_chat_source.clone()),
            );
        }
        if self.poll_interval != 0 {
            m.insert(
                "poll_interval".to_string(),
                JsonValue::from_i64(self.poll_interval),
            );
        }
        if !self.agents.is_empty() {
            m.insert(
                "agents".to_string(),
                JsonValue::Array(self.agents.iter().map(|a| a.to_json()).collect()),
            );
        }
        m.insert(
            "legacy_launch_agent".to_string(),
            JsonValue::Bool(self.legacy_launch_agent),
        );
        if !self.custom_oauth_client_id.is_empty() {
            m.insert(
                "custom_oauth_client_id".to_string(),
                JsonValue::String(self.custom_oauth_client_id.clone()),
            );
        }
        m.insert(
            "has_custom_oauth_secret".to_string(),
            JsonValue::Bool(self.has_custom_oauth_secret),
        );
        if !self.home_speaker_version.is_empty() {
            m.insert(
                "home_speaker_version".to_string(),
                JsonValue::String(self.home_speaker_version.clone()),
            );
        }
        m.insert(
            "announce_claude_code".to_string(),
            match self.announce_claude_code {
                Some(b) => JsonValue::Bool(b),
                None => JsonValue::Null,
            },
        );
        m.insert(
            "announce_antigravity".to_string(),
            match self.announce_antigravity {
                Some(b) => JsonValue::Bool(b),
                None => JsonValue::Null,
            },
        );
        m.insert(
            "announce_opencode".to_string(),
            match self.announce_opencode {
                Some(b) => JsonValue::Bool(b),
                None => JsonValue::Null,
            },
        );
        m.insert(
            "slack_enabled".to_string(),
            match self.slack_enabled {
                Some(b) => JsonValue::Bool(b),
                None => JsonValue::Null,
            },
        );
        m.insert(
            "google_chat_enabled".to_string(),
            match self.google_chat_enabled {
                Some(b) => JsonValue::Bool(b),
                None => JsonValue::Null,
            },
        );
        m.insert(
            "beeper_enabled".to_string(),
            match self.beeper_enabled {
                Some(b) => JsonValue::Bool(b),
                None => JsonValue::Null,
            },
        );
        m.insert(
            "beeper_announce".to_string(),
            JsonValue::String(self.beeper_announce.clone()),
        );
        m.insert(
            "beeper_networks".to_string(),
            JsonValue::Array(self.beeper_networks.iter().map(|n| n.to_json()).collect()),
        );
        m.insert(
            "mute_own_messages".to_string(),
            match self.mute_own_messages {
                Some(b) => JsonValue::Bool(b),
                None => JsonValue::Null,
            },
        );
        m.insert(
            "recent".to_string(),
            JsonValue::Array(self.recent.iter().map(|r| r.to_json()).collect()),
        );
        JsonValue::Object(m)
    }
}

#[derive(Clone, Debug, Default)]
pub struct HomeSpeakerUpdate {
    pub enabled: Option<bool>,
    pub default_target: Option<String>,
    pub speech_length: Option<String>,
    pub quiet_hours_enabled: Option<bool>,
    pub quiet_hours_start: Option<String>,
    pub quiet_hours_end: Option<String>,
    pub custom_style_prompt: Option<String>,
    pub local_voice: Option<String>,
    pub preview_voice: bool,
    pub pause_media: Option<bool>,
    pub pause_media_extra_seconds: Option<f64>,
    pub test_media_pause: bool,
    pub announce_volume_enabled: Option<bool>,
    pub announce_volume: Option<i64>,
    pub speak_home: Option<bool>,
    pub speak_local: Option<bool>,
    pub speak_phone: Option<bool>,
    pub phone_pause_media: Option<bool>,
    pub phone_headphones_only: Option<bool>,
    pub local_engine: Option<String>,
    pub gemini_voice: Option<String>,
    pub announcement_style: Option<String>,
    pub style_model: Option<String>,
    pub home_cast_voice: Option<bool>,
    pub active_door: Option<String>,
    pub discover: bool,
    pub structure_id: Option<String>,
    pub remove_target: Option<String>,
    pub sign_out: bool,
    pub import_antigravity: bool,
    pub speak_clipboard: bool,
    pub google_chat_source: Option<String>,
    pub gws_account: Option<String>,
    pub poll_interval: Option<i64>,
    pub slack_token: Option<String>,
    pub beeper_token: Option<String>,
    pub gemini_api_key: Option<String>,
    pub chat_monitor_action: Option<String>,
    pub agent_hook_action: Option<String>,
    pub oauth_client_id: Option<String>,
    pub oauth_client_secret: Option<String>,
    pub reset_settings: bool,
    pub announce_claude_code: Option<bool>,
    pub announce_antigravity: Option<bool>,
    pub announce_opencode: Option<bool>,
    pub slack_enabled: Option<bool>,
    pub google_chat_enabled: Option<bool>,
    pub beeper_enabled: Option<bool>,
    pub beeper_announce: Option<String>,
    pub beeper_network: Option<HomeSpeakerBeeperNetworkUpdate>,
    pub mute_own_messages: Option<bool>,
}

impl HomeSpeakerUpdate {
    pub fn empty(&self) -> bool {
        self.enabled.is_none()
            && self.default_target.is_none()
            && self.speech_length.is_none()
            && self.quiet_hours_enabled.is_none()
            && self.quiet_hours_start.is_none()
            && self.quiet_hours_end.is_none()
            && self.custom_style_prompt.is_none()
            && self.local_voice.is_none()
            && !self.preview_voice
            && self.pause_media.is_none()
            && self.pause_media_extra_seconds.is_none()
            && !self.test_media_pause
            && self.announce_volume_enabled.is_none()
            && self.announce_volume.is_none()
            && self.speak_home.is_none()
            && self.speak_local.is_none()
            && self.speak_phone.is_none()
            && self.phone_pause_media.is_none()
            && self.phone_headphones_only.is_none()
            && self.local_engine.is_none()
            && self.gemini_voice.is_none()
            && self.announcement_style.is_none()
            && self.style_model.is_none()
            && self.home_cast_voice.is_none()
            && self.active_door.is_none()
            && !self.discover
            && self.structure_id.is_none()
            && self.remove_target.is_none()
            && !self.sign_out
            && !self.import_antigravity
            && !self.speak_clipboard
            && self.google_chat_source.is_none()
            && self.gws_account.is_none()
            && self.poll_interval.is_none()
            && self.slack_token.is_none()
            && self.beeper_token.is_none()
            && self.gemini_api_key.is_none()
            && self.chat_monitor_action.is_none()
            && self.agent_hook_action.is_none()
            && self.oauth_client_id.is_none()
            && self.oauth_client_secret.is_none()
            && !self.reset_settings
            && self.announce_claude_code.is_none()
            && self.announce_antigravity.is_none()
            && self.announce_opencode.is_none()
            && self.slack_enabled.is_none()
            && self.google_chat_enabled.is_none()
            && self.beeper_enabled.is_none()
            && self.beeper_announce.is_none()
            && self.beeper_network.is_none()
            && self.mute_own_messages.is_none()
    }

    pub fn from_json(v: &JsonValue) -> Result<Self, String> {
        let obj = v
            .as_object()
            .ok_or_else(|| "cannot unmarshal non-object into HomeSpeakerUpdate".to_string())?;
        let mut u = Self::default();

        fn opt_bool(obj: &JsonObject, key: &str) -> Result<Option<bool>, String> {
            match obj.get(key) {
                None | Some(JsonValue::Null) => Ok(None),
                Some(JsonValue::Bool(b)) => Ok(Some(*b)),
                Some(_) => Err(format!("cannot unmarshal {key} into bool")),
            }
        }
        fn opt_str(obj: &JsonObject, key: &str) -> Result<Option<String>, String> {
            match obj.get(key) {
                None | Some(JsonValue::Null) => Ok(None),
                Some(JsonValue::String(s)) => Ok(Some(s.clone())),
                Some(_) => Err(format!("cannot unmarshal {key} into string")),
            }
        }
        fn opt_f64(obj: &JsonObject, key: &str) -> Result<Option<f64>, String> {
            match obj.get(key) {
                None | Some(JsonValue::Null) => Ok(None),
                Some(v) => match v.as_f64() {
                    Some(n) => Ok(Some(n)),
                    None => Err(format!("cannot unmarshal {key} into number")),
                },
            }
        }
        fn opt_i64(obj: &JsonObject, key: &str) -> Result<Option<i64>, String> {
            match obj.get(key) {
                None | Some(JsonValue::Null) => Ok(None),
                Some(v) => match v.as_i64() {
                    Some(n) => Ok(Some(n)),
                    None => Err(format!("cannot unmarshal {key} into int")),
                },
            }
        }

        u.enabled = opt_bool(obj, "enabled")?;
        u.default_target = opt_str(obj, "default_target")?;
        u.speech_length = opt_str(obj, "speech_length")?;
        u.quiet_hours_enabled = opt_bool(obj, "quiet_hours_enabled")?;
        u.quiet_hours_start = opt_str(obj, "quiet_hours_start")?;
        u.quiet_hours_end = opt_str(obj, "quiet_hours_end")?;
        u.custom_style_prompt = opt_str(obj, "custom_style_prompt")?;
        u.local_voice = opt_str(obj, "local_voice")?;
        u.preview_voice = opt_bool(obj, "preview_voice")?.unwrap_or(false);
        u.pause_media = opt_bool(obj, "pause_media")?;
        u.pause_media_extra_seconds = opt_f64(obj, "pause_media_extra_seconds")?;
        u.test_media_pause = opt_bool(obj, "test_media_pause")?.unwrap_or(false);
        u.announce_volume_enabled = opt_bool(obj, "announce_volume_enabled")?;
        u.announce_volume = opt_i64(obj, "announce_volume")?;
        u.speak_home = opt_bool(obj, "speak_home")?;
        u.speak_local = opt_bool(obj, "speak_local")?;
        u.speak_phone = opt_bool(obj, "speak_phone")?;
        u.phone_pause_media = opt_bool(obj, "phone_pause_media")?;
        u.phone_headphones_only = opt_bool(obj, "phone_headphones_only")?;
        u.local_engine = opt_str(obj, "local_engine")?;
        u.gemini_voice = opt_str(obj, "gemini_voice")?;
        u.announcement_style = opt_str(obj, "announcement_style")?;
        u.style_model = opt_str(obj, "style_model")?;
        u.home_cast_voice = opt_bool(obj, "home_cast_voice")?;
        u.active_door = opt_str(obj, "active_door")?;
        u.discover = opt_bool(obj, "discover")?.unwrap_or(false);
        u.structure_id = opt_str(obj, "structure_id")?;
        u.remove_target = opt_str(obj, "remove_target")?;
        u.sign_out = opt_bool(obj, "sign_out")?.unwrap_or(false);
        u.import_antigravity = opt_bool(obj, "import_antigravity")?.unwrap_or(false);
        u.speak_clipboard = opt_bool(obj, "speak_clipboard")?.unwrap_or(false);
        u.google_chat_source = opt_str(obj, "google_chat_source")?;
        u.gws_account = opt_str(obj, "gws_account")?;
        u.poll_interval = opt_i64(obj, "poll_interval")?;
        u.slack_token = opt_str(obj, "slack_token")?;
        u.beeper_token = opt_str(obj, "beeper_token")?;
        u.gemini_api_key = opt_str(obj, "gemini_api_key")?;
        u.chat_monitor_action = opt_str(obj, "chat_monitor_action")?;
        u.agent_hook_action = opt_str(obj, "agent_hook_action")?;
        u.oauth_client_id = opt_str(obj, "oauth_client_id")?;
        u.oauth_client_secret = opt_str(obj, "oauth_client_secret")?;
        u.reset_settings = opt_bool(obj, "reset_settings")?.unwrap_or(false);
        u.announce_claude_code = opt_bool(obj, "announce_claude_code")?;
        u.announce_antigravity = opt_bool(obj, "announce_antigravity")?;
        u.announce_opencode = opt_bool(obj, "announce_opencode")?;
        u.slack_enabled = opt_bool(obj, "slack_enabled")?;
        u.google_chat_enabled = opt_bool(obj, "google_chat_enabled")?;
        u.beeper_enabled = opt_bool(obj, "beeper_enabled")?;
        u.beeper_announce = opt_str(obj, "beeper_announce")?;
        if let Some(bn) = obj.get("beeper_network") {
            if !bn.is_null() {
                let bno = bn
                    .as_object()
                    .ok_or_else(|| "cannot unmarshal beeper_network".to_string())?;
                let key = bno
                    .get("key")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string();
                let reading = bno
                    .get("reading")
                    .and_then(|x| x.as_bool())
                    .unwrap_or(false);
                u.beeper_network = Some(HomeSpeakerBeeperNetworkUpdate { key, reading });
            }
        }
        u.mute_own_messages = opt_bool(obj, "mute_own_messages")?;
        Ok(u)
    }
}

#[derive(Clone, Debug)]
pub enum ApplyError {
    BadRequest(String),
    NotFound(String),
    Internal(String),
}

impl ApplyError {
    pub fn message(&self) -> &str {
        match self {
            ApplyError::BadRequest(s) | ApplyError::NotFound(s) | ApplyError::Internal(s) => s,
        }
    }
}

pub fn is_in_trash(path: &str) -> bool {
    path.contains("/.Trash/") || path.contains("/.Trashes/")
}

pub fn derive_extension_data_folder(program: &str) -> String {
    let p = Path::new(program);
    if p.file_name().and_then(|s| s.to_str()) != Some("tool") {
        return String::new();
    }
    let Some(bin_dir) = p.parent() else {
        return String::new();
    };
    if bin_dir.file_name().and_then(|s| s.to_str()) != Some("bin") {
        return String::new();
    }
    let Some(ext_dir) = bin_dir.parent() else {
        return String::new();
    };
    let ext_id = ext_dir.file_name().and_then(|s| s.to_str()).unwrap_or("");
    let Some(tools_dir) = ext_dir.parent() else {
        return String::new();
    };
    if tools_dir.file_name().and_then(|s| s.to_str()) != Some("Tools")
        || ext_id.is_empty()
        || ext_id == "."
    {
        return String::new();
    }
    let Some(root_dir) = tools_dir.parent() else {
        return String::new();
    };
    root_dir
        .join("ToolData")
        .join(ext_id)
        .to_string_lossy()
        .into_owned()
}

extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
}

const LOCK_EX: i32 = 2;
const LOCK_NB: i32 = 4;
const LOCK_UN: i32 = 8;

pub fn is_lock_held(path: &Path) -> bool {
    if path.as_os_str().is_empty() {
        return false;
    }
    let Ok(f) = fs::File::open(path) else {
        return false;
    };
    let fd = f.as_raw_fd();
    // SAFETY: `fd` is a valid open file descriptor for the duration of `f`.
    let rc = unsafe { flock(fd, LOCK_EX | LOCK_NB) };
    if rc == 0 {
        unsafe {
            let _ = flock(fd, LOCK_UN);
        }
        return false;
    }
    true
}

pub fn custom_voices(cfg: &JsonObject) -> Vec<HomeSpeakerCustomVoice> {
    let Some(list) = cfg.get("custom_voices").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for item in list {
        let Some(m) = item.as_object() else {
            continue;
        };
        let id = m.get("id").and_then(|v| v.as_str()).unwrap_or("");
        if id.trim().is_empty() {
            continue;
        }
        let mut name = m
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        if name.trim().is_empty() {
            name = id.to_string();
        }
        out.push(HomeSpeakerCustomVoice {
            id: id.to_string(),
            name,
        });
    }
    out
}

pub fn valid_gemini_voice(v: &str, custom: &[HomeSpeakerCustomVoice]) -> bool {
    if GEMINI_VOICES.contains(&v) {
        return true;
    }
    custom.iter().any(|c| c.id == v)
}

pub fn voice_name(id: &str) -> String {
    if let Some(rest) = id.strip_prefix("com.apple.ttsbundle.siri_") {
        if let Some((name, _)) = rest.split_once('_') {
            if !name.is_empty() && name.chars().all(|c| c.is_ascii_alphabetic()) {
                return name.to_string();
            }
        }
    }
    let Some(i) = id.rfind('.') else {
        return id.to_string();
    };
    if i == id.len() - 1 {
        return id.to_string();
    }
    let name = &id[i + 1..];
    if name.chars().all(|r| r.is_alphabetic()) {
        name.to_string()
    } else {
        id.to_string()
    }
}

pub fn dedupe_target_keys(targets: &JsonObject, default_target: &str) -> Vec<String> {
    let mut keys: Vec<String> = targets.keys().map(|s| s.to_string()).collect();
    keys.sort();

    let mut by_device: BTreeMap<String, String> = BTreeMap::new();
    for key in keys {
        let id = targets
            .get(&key)
            .and_then(|v| v.as_object())
            .and_then(|m| m.get("id"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if id.is_empty() {
            by_device.insert(key.clone(), key);
            continue;
        }
        match by_device.get(id) {
            None => {
                by_device.insert(id.to_string(), key);
            }
            Some(existing) => {
                if key == default_target
                    || (existing != default_target && key.len() < existing.len())
                {
                    by_device.insert(id.to_string(), key);
                }
            }
        }
    }
    let mut chosen: Vec<String> = by_device.into_values().collect();
    chosen.sort();
    chosen
}

pub fn parse_hhmm(s: &str) -> Result<(u32, u32), ApplyError> {
    if s.len() != 5 || s.as_bytes()[2] != b':' {
        return Err(ApplyError::BadRequest(format!(
            "invalid time {s:?}; must be HH:MM (24-hour)"
        )));
    }
    let hh = &s[0..2];
    let mm = &s[3..5];
    if !hh.bytes().all(|b| b.is_ascii_digit()) || !mm.bytes().all(|b| b.is_ascii_digit()) {
        return Err(ApplyError::BadRequest(format!(
            "invalid time {s:?}; must be HH:MM (24-hour)"
        )));
    }
    let h: u32 = hh.parse().unwrap_or(99);
    let m: u32 = mm.parse().unwrap_or(99);
    if h > 23 || m > 59 {
        return Err(ApplyError::BadRequest(format!(
            "invalid time {s:?}; must be HH:MM (24-hour)"
        )));
    }
    Ok((h, m))
}

fn parse_loose_hhmm(s: &str) -> Option<(u32, u32)> {
    let (h_str, m_str) = s.split_once(':')?;
    let h: u32 = h_str.parse().ok()?;
    let m: u32 = m_str.parse().ok()?;
    Some((h, m))
}

pub fn is_quiet_hours_active(enabled: bool, start: &str, end: &str, now: Timestamp) -> bool {
    if !enabled {
        return false;
    }
    let Some((sh, sm)) = parse_loose_hhmm(start) else {
        return false;
    };
    let Some((eh, em)) = parse_loose_hhmm(end) else {
        return false;
    };
    let start_m = sh * 60 + sm;
    let end_m = eh * 60 + em;
    let day_secs = now.unix_secs().rem_euclid(86_400) as u32;
    let now_m = (day_secs / 3600) * 60 + ((day_secs % 3600) / 60);
    if start_m == end_m {
        return false;
    }
    if start_m < end_m {
        now_m >= start_m && now_m < end_m
    } else {
        now_m >= start_m || now_m < end_m
    }
}

pub fn default_voice_list() -> Vec<HomeSpeakerVoice> {
    vec![
        HomeSpeakerVoice {
            id: "com.apple.ttsbundle.siri_Aaron_en-US_premium".to_string(),
            name: "Aaron".to_string(),
            lang: "en_US".to_string(),
        },
        HomeSpeakerVoice {
            id: "com.apple.speech.synthesis.voice.Alex".to_string(),
            name: "Alex".to_string(),
            lang: "en_US".to_string(),
        },
        HomeSpeakerVoice {
            id: "com.apple.speech.synthesis.voice.Samantha".to_string(),
            name: "Samantha".to_string(),
            lang: "en_US".to_string(),
        },
        HomeSpeakerVoice {
            id: "com.apple.speech.synthesis.voice.Fred".to_string(),
            name: "Fred".to_string(),
            lang: "en_US".to_string(),
        },
        HomeSpeakerVoice {
            id: "com.apple.speech.synthesis.voice.Victoria".to_string(),
            name: "Victoria".to_string(),
            lang: "en_US".to_string(),
        },
    ]
}

pub fn list_macos_voices() -> Result<Vec<HomeSpeakerVoice>, String> {
    let out = Command::new("say")
        .args(["-v", "?"])
        .output()
        .map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err("say -v ? failed".to_string());
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut voices = Vec::new();
    for line in text.lines() {
        let before_hash = line.split('#').next().unwrap_or("");
        let fields: Vec<&str> = before_hash.split_whitespace().collect();
        if fields.len() >= 2 {
            let lang = fields[fields.len() - 1].to_string();
            let name = fields[..fields.len() - 1].join(" ");
            voices.push(HomeSpeakerVoice {
                id: name.clone(),
                name,
                lang,
            });
        }
    }
    Ok(voices)
}

pub fn person_env(env: &[String]) -> Vec<String> {
    let mut out = Vec::with_capacity(env.len());
    for kv in env {
        let name = kv.split('=').next().unwrap_or(kv.as_str());
        if !AGENT_MARKERS.contains(&name) {
            out.push(kv.clone());
        }
    }
    out
}

pub fn run_as_person_within(
    limit: Duration,
    name: &str,
    args: &[String],
) -> Result<(String, String), String> {
    let mut cmd = Command::new(name);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for marker in AGENT_MARKERS {
        cmd.env_remove(marker);
    }
    let mut child = cmd.spawn().map_err(|e| e.to_string())?;
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => {
                let out = child.wait_with_output().map_err(|e| e.to_string())?;
                let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
                let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
                if out.status.success() {
                    return Ok((stdout, stderr));
                }
                return Err(format!("exit status {}", out.status.code().unwrap_or(1)));
            }
            Ok(None) => {
                if start.elapsed() >= limit {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err("command timed out".to_string());
                }
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(e) => return Err(e.to_string()),
        }
    }
}

fn is_valid_beeper_network_key(key: &str) -> bool {
    !key.is_empty()
        && key.len() <= 64
        && key
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-')
}

fn file_exists(p: &Path) -> bool {
    !p.as_os_str().is_empty() && p.exists()
}

fn string_in(m: Option<&JsonObject>, key: &str, allowed: &[&str], def: &str) -> String {
    if let Some(obj) = m {
        if let Some(v) = obj.get(key).and_then(|x| x.as_str()) {
            if allowed.contains(&v) {
                return v.to_string();
            }
        }
    }
    def.to_string()
}

fn bool_or(m: Option<&JsonObject>, key: &str, def: bool) -> Option<bool> {
    let v = m
        .and_then(|obj| obj.get(key))
        .and_then(|x| x.as_bool())
        .unwrap_or(def);
    Some(v)
}

fn muted_networks_from_monitor(monitor: Option<&JsonObject>) -> Vec<String> {
    let Some(mon) = monitor else {
        return Vec::new();
    };
    let Some(arr) = mon.get("beeper_muted_networks").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    let mut out = Vec::with_capacity(arr.len());
    for item in arr {
        if let Some(s) = item.as_str() {
            if !s.trim().is_empty() {
                out.push(s.to_string());
            }
        }
    }
    out
}

fn validate_enum(field: &str, val: &str, allowed: &[&str]) -> Result<(), ApplyError> {
    if allowed.contains(&val) {
        Ok(())
    } else {
        Err(ApplyError::BadRequest(format!(
            "{field} must be one of {}",
            allowed.join(", ")
        )))
    }
}

fn write_atomic_json(path: &Path, obj: &JsonObject) -> Result<(), ApplyError> {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut data = JsonValue::Object(obj.clone()).to_json_string_pretty();
    data.push('\n');
    let tmp = PathBuf::from(format!("{}.agent-tmp", path.display()));
    fs::write(&tmp, data.as_bytes()).map_err(|e| ApplyError::Internal(e.to_string()))?;
    let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
    fs::rename(&tmp, path).map_err(|e| ApplyError::Internal(e.to_string()))
}

fn ensure_chat_monitor(cfg: &mut JsonObject) -> &mut JsonObject {
    let needs_init = !matches!(cfg.get("chat_monitor"), Some(JsonValue::Object(_)));
    if needs_init {
        cfg.insert(
            "chat_monitor".to_string(),
            JsonValue::Object(JsonObject::new()),
        );
    }
    match cfg.get_mut("chat_monitor") {
        Some(JsonValue::Object(m)) => m,
        _ => unreachable!(),
    }
}

fn append_instruction(path: &Path) -> Result<(), ApplyError> {
    if path.as_os_str().is_empty() {
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let existing = fs::read_to_string(path).unwrap_or_default();
    if existing.contains("speaker_broadcast.json")
        || existing.contains("home-speaker-broadcast")
        || existing.contains("speaker-broadcast")
    {
        return Ok(());
    }
    let mut next = existing;
    if !next.is_empty() && !next.ends_with('\n') {
        next.push('\n');
    }
    next.push_str(BROADCAST_INSTRUCTION);
    next.push('\n');
    fs::write(path, next.as_bytes()).map_err(|e| ApplyError::Internal(e.to_string()))?;
    let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    Ok(())
}

#[derive(Default)]
struct SecretsData {
    google_email: String,
    google_refresh_token: String,
    gemini_api_key: String,
    slack_token: String,
    beeper_token: String,
    oauth_client_id_override: String,
    oauth_client_secret_override: String,
}

#[derive(Default)]
struct CredentialsData {
    slack_token: String,
    beeper_token: String,
    oauth_client_id: String,
    oauth_client_secret: String,
}

#[derive(Default)]
struct MonitorStatusData {
    is_running: bool,
    last_poll_date: String,
    slack_identity: String,
    active_google_chat_backend: String,
    last_error: String,
}

impl HomeSpeaker {
    pub fn new() -> Self {
        let home = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/tmp"));
        Self {
            config_path: home.join(".gemini").join("speaker_broadcast.json"),
            history_path: home.join(".gemini").join("speaker_history.json"),
            secrets_path: home
                .join("Library")
                .join("Application Support")
                .join("HomeSpeaker")
                .join("secrets.json"),
            door_path: home.join(".gemini").join("speaker_door.json"),
            credentials_path: home.join(".gemini").join("chat_credentials.json"),
            monitor_status_path: home.join(".gemini").join("speaker_monitor_status.json"),
            claude_settings_path: home.join(".claude").join("settings.json"),
            claude_md_path: home.join(".claude").join("CLAUDE.md"),
            antigravity_md_path: home.join(".gemini").join("AGENTS.md"),
            opencode_md_path: home.join(".config").join("opencode").join("AGENTS.md"),
            legacy_plist_path: home
                .join("Library")
                .join("LaunchAgents")
                .join("com.james.chat-monitor.plist"),
            oauth_client_path: home.join(".gemini").join("google-oauth-client.json"),
            antigravity_tokens_path: home
                .join(".gemini")
                .join("antigravity")
                .join("mcp_oauth_tokens.json"),
            binary: PathBuf::from(HOME_SPEAKER_BINARY),
            run: Arc::new(|limit, name, args| {
                let (out, err_s, err_opt) = run_tool_within(limit, name, args, None);
                match err_opt {
                    Some(e) => Err(e),
                    None => Ok((out, err_s)),
                }
            }),
            say: Some(Arc::new(|limit, name, args| {
                run_as_person_within(limit, name, args)
            })),
            running: Some(Arc::new(|| {
                Command::new("pgrep")
                    .args(["-x", "HomeSpeaker"])
                    .status()
                    .map(|s| s.success())
                    .unwrap_or(false)
            })),
            read_clipboard: Some(Arc::new(|| {
                let out = Command::new("pbpaste")
                    .output()
                    .map_err(|e| e.to_string())?;
                Ok(String::from_utf8_lossy(&out.stdout).into_owned())
            })),
            list_voices: Some(Arc::new(list_macos_voices)),
        }
    }

    pub fn active_profile(&self) -> HomeSpeakerProfile {
        let app_profile = HomeSpeakerProfile {
            active_door: "app".to_string(),
            config_path: self.config_path.clone(),
            history_path: self.history_path.clone(),
            secrets_path: self.secrets_path.clone(),
            monitor_status_path: self.monitor_status_path.clone(),
            binary: self.binary.clone(),
            lock_path: PathBuf::new(),
        };
        if self.door_path.as_os_str().is_empty() {
            return app_profile;
        }
        let Ok(data) = fs::read_to_string(&self.door_path) else {
            return app_profile;
        };
        let Ok(door_val) = JsonValue::parse(&data) else {
            return app_profile;
        };
        let Some(door_obj) = door_val.as_object() else {
            return app_profile;
        };
        let Some(ext_obj) = door_obj.get("extension").and_then(|v| v.as_object()) else {
            return app_profile;
        };
        let prog = ext_obj
            .get("program")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        if prog.is_empty() || is_in_trash(prog) || !Path::new(prog).exists() {
            return app_profile;
        }
        let mut data_folder = ext_obj
            .get("data_folder")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if data_folder.is_empty() {
            data_folder = derive_extension_data_folder(prog);
        }
        if data_folder.is_empty() {
            return app_profile;
        }
        let chosen = door_obj
            .get("chosen")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let use_extension = match chosen {
            "extension" => true,
            "" => {
                let bin_str = self.binary.to_string_lossy();
                let app_installed = self.binary.exists() && !is_in_trash(&bin_str);
                !app_installed
            }
            _ => false,
        };
        if !use_extension {
            return app_profile;
        }
        let df = PathBuf::from(data_folder);
        HomeSpeakerProfile {
            active_door: "extension".to_string(),
            config_path: df.join("settings.json"),
            history_path: df.join("history.json"),
            secrets_path: df.join("secrets.json"),
            monitor_status_path: df.join("speaker_monitor_status.json"),
            binary: PathBuf::from(prog),
            lock_path: df.join("running.lock"),
        }
    }

    pub fn is_running(&self, p: &HomeSpeakerProfile) -> bool {
        if p.active_door == "extension" {
            if is_lock_held(&p.lock_path) {
                return true;
            }
            return Command::new("pgrep")
                .args(["-f", &p.binary.to_string_lossy()])
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
        }
        if let Some(ref r) = self.running {
            return r();
        }
        false
    }

    pub fn read_config(&self) -> Result<JsonObject, ApplyError> {
        let p = self.active_profile();
        let data = fs::read_to_string(&p.config_path).map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                ApplyError::NotFound(e.to_string())
            } else {
                ApplyError::Internal(e.to_string())
            }
        })?;
        let val = JsonValue::parse(&data).map_err(|e| {
            let base = p
                .config_path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("speaker_broadcast.json");
            ApplyError::Internal(format!("{base}: {e}"))
        })?;
        val.as_object()
            .cloned()
            .ok_or_else(|| ApplyError::Internal("config is not a JSON object".to_string()))
    }

    pub fn write_config(&self, cfg: &JsonObject) -> Result<(), ApplyError> {
        let p = self.active_profile();
        write_atomic_json(&p.config_path, cfg)
    }

    pub fn signed_in(&self) -> bool {
        let p = self.active_profile();
        let Ok(data) = fs::read_to_string(&p.secrets_path) else {
            return false;
        };
        let Ok(val) = JsonValue::parse(&data) else {
            return false;
        };
        val.as_object()
            .and_then(|o| o.get("google"))
            .and_then(|g| g.as_object())
            .and_then(|g| g.get("refreshToken"))
            .and_then(|r| r.as_str())
            .map(|s| !s.is_empty())
            .unwrap_or(false)
    }

    pub fn has_gemini_key(&self) -> bool {
        let p = self.active_profile();
        let Ok(data) = fs::read_to_string(&p.secrets_path) else {
            return false;
        };
        let Ok(val) = JsonValue::parse(&data) else {
            return false;
        };
        let Some(obj) = val.as_object() else {
            return false;
        };
        let k1 = obj
            .get("geminiApiKey")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let k2 = obj
            .get("geminiAPIKey")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let key = if !k1.is_empty() { k1 } else { k2 };
        !key.trim().is_empty()
    }

    pub fn recent_broadcasts(&self, n: usize) -> Vec<HomeSpeakerLast> {
        let p = self.active_profile();
        let Ok(data) = fs::read_to_string(&p.history_path) else {
            return Vec::new();
        };
        let Ok(val) = JsonValue::parse(&data) else {
            return Vec::new();
        };
        let Some(items) = val.as_array() else {
            return Vec::new();
        };
        let mut out = Vec::new();
        for item in items.iter().take(n) {
            let Some(obj) = item.as_object() else {
                continue;
            };
            let id = obj
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let ts = obj.get("timestamp").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let text = obj
                .get("text")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let target = obj
                .get("targetName")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let source = obj
                .get("source")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let unix_secs = SWIFT_REFERENCE_EPOCH_UNIX_SECS + (ts as i64);
            let nanos =
                ((ts.fract() * 1_000_000_000.0).round() as i64).clamp(0, 999_999_999) as u32;
            out.push(HomeSpeakerLast {
                id,
                text,
                target,
                source,
                at: Timestamp::from_unix_nanos(
                    (unix_secs as i128) * 1_000_000_000 + (nanos as i128),
                ),
            });
        }
        out
    }

    pub fn beeper_networks(
        &self,
        p: &HomeSpeakerProfile,
        app_running: bool,
        monitor: Option<&JsonObject>,
    ) -> Vec<HomeSpeakerBeeperNetwork> {
        let mut listed = Vec::new();
        if app_running && !p.config_path.as_os_str().is_empty() {
            if let Some(dir) = p.config_path.parent() {
                let status_path = dir.join("speaker_monitor_status.json");
                if let Ok(data) = fs::read_to_string(&status_path) {
                    if let Ok(val) = JsonValue::parse(&data) {
                        if let Some(obj) = val.as_object() {
                            if obj
                                .get("is_running")
                                .and_then(|v| v.as_bool())
                                .unwrap_or(false)
                            {
                                if let Some(arr) =
                                    obj.get("beeper_network_states").and_then(|v| v.as_array())
                                {
                                    for item in arr {
                                        if let Some(ro) = item.as_object() {
                                            listed.push(HomeSpeakerBeeperNetwork {
                                                key: ro
                                                    .get("key")
                                                    .and_then(|x| x.as_str())
                                                    .unwrap_or("")
                                                    .to_string(),
                                                name: ro
                                                    .get("name")
                                                    .and_then(|x| x.as_str())
                                                    .unwrap_or("")
                                                    .to_string(),
                                                state: ro
                                                    .get("state")
                                                    .and_then(|x| x.as_str())
                                                    .unwrap_or("")
                                                    .to_string(),
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        let muted = muted_networks_from_monitor(monitor);
        let muted_set: HashSet<String> = muted.iter().cloned().collect();
        let mut rows = Vec::with_capacity(listed.len() + muted.len());
        let mut seen = HashSet::new();
        for mut row in listed {
            if row.key.trim().is_empty() {
                continue;
            }
            if row.name.is_empty() {
                row.name = row.key.clone();
            }
            if row.state != "skipped" {
                if muted_set.contains(&row.key) {
                    row.state = "muted".to_string();
                } else {
                    row.state = "reading".to_string();
                }
            }
            seen.insert(row.key.clone());
            rows.push(row);
        }
        for key in muted {
            if !seen.contains(&key) {
                seen.insert(key.clone());
                rows.push(HomeSpeakerBeeperNetwork {
                    key: key.clone(),
                    name: key,
                    state: "muted".to_string(),
                });
            }
        }
        rows.sort_by(|a, b| {
            let la = a.name.to_lowercase();
            let lb = b.name.to_lowercase();
            if la != lb {
                la.cmp(&lb)
            } else {
                a.key.cmp(&b.key)
            }
        });
        rows
    }

    fn read_secrets_data(&self, path: &Path) -> SecretsData {
        let mut sec = SecretsData::default();
        if path.as_os_str().is_empty() {
            return sec;
        }
        let Ok(data) = fs::read_to_string(path) else {
            return sec;
        };
        let Ok(val) = JsonValue::parse(&data) else {
            return sec;
        };
        let Some(obj) = val.as_object() else {
            return sec;
        };
        if let Some(g) = obj.get("google").and_then(|v| v.as_object()) {
            sec.google_email = g
                .get("email")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            sec.google_refresh_token = g
                .get("refreshToken")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
        }
        sec.gemini_api_key = obj
            .get("geminiApiKey")
            .and_then(|v| v.as_str())
            .or_else(|| obj.get("geminiAPIKey").and_then(|v| v.as_str()))
            .unwrap_or("")
            .to_string();
        sec.slack_token = obj
            .get("slackToken")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        sec.beeper_token = obj
            .get("beeperToken")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        sec.oauth_client_id_override = obj
            .get("oauthClientIdOverride")
            .and_then(|v| v.as_str())
            .or_else(|| obj.get("oauthClientIDOverride").and_then(|v| v.as_str()))
            .unwrap_or("")
            .to_string();
        sec.oauth_client_secret_override = obj
            .get("oauthClientSecretOverride")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        sec
    }

    fn read_credentials_data(&self) -> CredentialsData {
        let mut cred = CredentialsData::default();
        if self.credentials_path.as_os_str().is_empty() {
            return cred;
        }
        let Ok(data) = fs::read_to_string(&self.credentials_path) else {
            return cred;
        };
        let Ok(val) = JsonValue::parse(&data) else {
            return cred;
        };
        let Some(obj) = val.as_object() else {
            return cred;
        };
        cred.slack_token = obj
            .get("slack_token")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        cred.beeper_token = obj
            .get("beeper_token")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        cred.oauth_client_id = obj
            .get("oauth_client_id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        cred.oauth_client_secret = obj
            .get("oauth_client_secret")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        cred
    }

    fn read_monitor_status(&self) -> MonitorStatusData {
        let mut ms = MonitorStatusData::default();
        let p = self.active_profile();
        let mut status_path = p.monitor_status_path.clone();
        if !file_exists(&status_path) {
            if file_exists(&self.monitor_status_path) {
                status_path = self.monitor_status_path.clone();
            } else if let Some(dir) = p.config_path.parent() {
                let alt = dir.join("chat_monitor_status.json");
                if file_exists(&alt) {
                    status_path = alt;
                } else {
                    return ms;
                }
            } else {
                return ms;
            }
        }
        let Ok(data) = fs::read_to_string(&status_path) else {
            return ms;
        };
        let Ok(val) = JsonValue::parse(&data) else {
            return ms;
        };
        let Some(raw) = val.as_object() else {
            return ms;
        };
        ms.is_running = raw
            .get("is_running")
            .and_then(|v| v.as_bool())
            .or_else(|| raw.get("running").and_then(|v| v.as_bool()))
            .unwrap_or(false);
        ms.slack_identity = raw
            .get("slack_identity")
            .and_then(|v| v.as_str())
            .or_else(|| raw.get("slackIdentity").and_then(|v| v.as_str()))
            .unwrap_or("")
            .to_string();
        ms.active_google_chat_backend = raw
            .get("active_google_chat_backend")
            .and_then(|v| v.as_str())
            .or_else(|| raw.get("activeGoogleChatBackend").and_then(|v| v.as_str()))
            .unwrap_or("")
            .to_string();
        ms.last_error = raw
            .get("last_error")
            .and_then(|v| v.as_str())
            .or_else(|| raw.get("lastError").and_then(|v| v.as_str()))
            .unwrap_or("")
            .to_string();
        if let Some(s) = raw
            .get("last_poll_date")
            .and_then(|v| v.as_str())
            .or_else(|| raw.get("lastPollDate").and_then(|v| v.as_str()))
        {
            ms.last_poll_date = s.to_string();
        } else if let Some(n) = raw
            .get("last_poll_date")
            .and_then(|v| v.as_f64())
            .or_else(|| raw.get("lastPollDate").and_then(|v| v.as_f64()))
        {
            if n > 0.0 {
                ms.last_poll_date =
                    Timestamp::from_unix_nanos((n as i128) * 1_000_000_000).to_rfc3339();
            }
        }
        ms
    }

    fn inspect_agents(&self, p: &HomeSpeakerProfile) -> Vec<HomeSpeakerAgentHook> {
        let mut out = Vec::with_capacity(3);
        let claude_installed = self
            .claude_settings_path
            .parent()
            .map(file_exists)
            .unwrap_or(false);
        let mut claude_hook_state = "not_installed".to_string();
        let mut claude_speaks_twice = false;
        let mut claude_by_instruction = false;

        let bin_str = p.binary.to_string_lossy();
        let expected_quoted = format!("\"{bin_str}\" --claude-stop-hook");
        let expected_raw = format!("{bin_str} --claude-stop-hook");

        if claude_installed {
            if file_exists(&self.claude_settings_path) {
                if let Ok(data) = fs::read_to_string(&self.claude_settings_path) {
                    if let Ok(val) = JsonValue::parse(&data) {
                        if let Some(stop_arr) = val
                            .as_object()
                            .and_then(|s| s.get("hooks"))
                            .and_then(|h| h.as_object())
                            .and_then(|h| h.get("Stop"))
                            .and_then(|st| st.as_array())
                        {
                            for g in stop_arr {
                                if let Some(inner) = g
                                    .as_object()
                                    .and_then(|gm| gm.get("hooks"))
                                    .and_then(|in_h| in_h.as_array())
                                {
                                    for item in inner {
                                        let cmd = item
                                            .as_object()
                                            .and_then(|m| m.get("command"))
                                            .and_then(|c| c.as_str())
                                            .unwrap_or("");
                                        if cmd.contains("claude-stop-hook")
                                            || cmd.contains("stop_broadcast.py")
                                        {
                                            let trimmed = cmd.trim();
                                            if trimmed == expected_quoted || trimmed == expected_raw
                                            {
                                                claude_hook_state = "installed".to_string();
                                            } else {
                                                claude_hook_state = "stale".to_string();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if file_exists(&self.claude_md_path) {
                if let Ok(s) = fs::read_to_string(&self.claude_md_path) {
                    claude_by_instruction = s.contains("speaker_broadcast.json")
                        || s.contains("home-speaker-broadcast")
                        || s.contains("speaker-broadcast");
                }
            }
            let home_dir = self.claude_settings_path.parent().and_then(|d| d.parent());
            if !claude_by_instruction {
                if let Some(hd) = home_dir {
                    let root_claude = hd.join("CLAUDE.md");
                    if file_exists(&root_claude) {
                        if let Ok(s) = fs::read_to_string(&root_claude) {
                            claude_by_instruction = s.contains("speaker_broadcast.json")
                                || s.contains("home-speaker-broadcast")
                                || s.contains("speaker-broadcast");
                        }
                    }
                }
            }
            if let Some(hd) = home_dir {
                let rival = hd
                    .join(".claude")
                    .join("skills")
                    .join("google-home")
                    .join("hooks")
                    .join("hooks.json");
                if file_exists(&rival) && claude_hook_state == "installed" {
                    if let Ok(s) = fs::read_to_string(&rival) {
                        if s.contains("stop_broadcast") || s.contains("speaker-broadcast") {
                            claude_speaks_twice = true;
                        }
                    }
                }
            }
        }
        out.push(HomeSpeakerAgentHook {
            agent: "Claude Code".to_string(),
            agent_slug: "claude-code".to_string(),
            hook_state: claude_hook_state,
            speaks_twice: claude_speaks_twice,
            configured_by_instruction: claude_by_instruction,
        });

        let mut agy_by_instruction = false;
        if file_exists(&self.antigravity_md_path) {
            if let Ok(s) = fs::read_to_string(&self.antigravity_md_path) {
                agy_by_instruction = s.contains("speaker_broadcast.json")
                    || s.contains("home-speaker-broadcast")
                    || s.contains("speaker-broadcast");
            }
        }
        if !agy_by_instruction {
            if let Some(hd) = self.antigravity_md_path.parent().and_then(|d| d.parent()) {
                let gemini_md = hd.join(".gemini").join("GEMINI.md");
                if file_exists(&gemini_md) {
                    if let Ok(s) = fs::read_to_string(&gemini_md) {
                        agy_by_instruction = s.contains("speaker_broadcast.json")
                            || s.contains("home-speaker-broadcast")
                            || s.contains("speaker-broadcast");
                    }
                }
            }
        }
        out.push(HomeSpeakerAgentHook {
            agent: "Antigravity".to_string(),
            agent_slug: "antigravity".to_string(),
            hook_state: "not_installed".to_string(),
            speaks_twice: false,
            configured_by_instruction: agy_by_instruction,
        });

        let mut opencode_by_instruction = false;
        if file_exists(&self.opencode_md_path) {
            if let Ok(s) = fs::read_to_string(&self.opencode_md_path) {
                opencode_by_instruction = s.contains("speaker_broadcast.json")
                    || s.contains("home-speaker-broadcast")
                    || s.contains("speaker-broadcast");
            }
        }
        out.push(HomeSpeakerAgentHook {
            agent: "OpenCode".to_string(),
            agent_slug: "opencode".to_string(),
            hook_state: "not_installed".to_string(),
            speaks_twice: false,
            configured_by_instruction: opencode_by_instruction,
        });

        out
    }

    fn inspect_version(&self, p: &HomeSpeakerProfile) -> String {
        if !file_exists(&p.binary) {
            return String::new();
        }
        let bin_str = p.binary.to_string_lossy();
        if bin_str.contains(".app/Contents/MacOS/") {
            if let Some(contents_dir) = p.binary.parent().and_then(|d| d.parent()) {
                let plist_path = contents_dir.join("Info.plist");
                if let Ok(str_data) = fs::read_to_string(&plist_path) {
                    if let Some(idx) = str_data.find("CFBundleShortVersionString") {
                        let sub = &str_data[idx..];
                        if let Some(s_idx) = sub.find("<string>") {
                            let sub2 = &sub[s_idx + 8..];
                            if let Some(e_idx) = sub2.find("</string>") {
                                return sub2[..e_idx].trim().to_string();
                            }
                        }
                    }
                }
            }
        }
        if let Some(ext_dir) = p.binary.parent().and_then(|d| d.parent()) {
            let tool_json = ext_dir.join("vitruvian-tool.json");
            if let Ok(data) = fs::read_to_string(&tool_json) {
                if let Ok(val) = JsonValue::parse(&data) {
                    if let Some(ver) = val
                        .as_object()
                        .and_then(|o| o.get("version"))
                        .and_then(|v| v.as_str())
                    {
                        if !ver.is_empty() {
                            return ver.trim().to_string();
                        }
                    }
                }
            }
        }
        String::new()
    }

    pub fn state(&self) -> HomeSpeakerState {
        let p = self.active_profile();
        let mut st = HomeSpeakerState {
            active_door: p.active_door.clone(),
            ..Default::default()
        };
        if file_exists(&p.binary) {
            st.installed = true;
        }
        let cfg = match self.read_config() {
            Ok(c) => c,
            Err(ApplyError::NotFound(_)) => {
                st.reason = format!(
                    "HomeSpeaker has not been set up on this Mac (no {})",
                    p.config_path.display()
                );
                return st;
            }
            Err(e) => {
                st.reason = e.message().to_string();
                return st;
            }
        };
        st.available = true;
        st.app_running = self.is_running(&p);
        st.signed_in = self.signed_in();
        st.has_gemini_key = self.has_gemini_key();
        st.enabled = cfg
            .get("enabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        st.default_target = cfg
            .get("default_target")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        st.speech_length = cfg
            .get("speech_length")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("summary")
            .to_string();
        st.pause_media = cfg
            .get("pause_media")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        st.pause_media_extra_seconds = cfg
            .get("pause_media_extra_seconds")
            .and_then(|v| v.as_f64())
            .unwrap_or(1.0);
        st.announce_volume_enabled = cfg
            .get("announce_volume_enabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        st.announce_volume = cfg
            .get("announce_volume")
            .and_then(|v| v.as_f64())
            .map(|n| n as i64)
            .unwrap_or(60);
        st.speak_home = cfg
            .get("speak_home")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        st.speak_local = cfg
            .get("speak_local")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        st.speak_phone = bool_or(Some(&cfg), "speak_phone", false);
        st.phone_pause_media = cfg
            .get("phone_pause_media")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        st.phone_headphones_only = cfg
            .get("phone_headphones_only")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        st.local_voice = cfg
            .get("local_voice")
            .and_then(|v| v.as_str())
            .filter(|s| !s.trim().is_empty())
            .unwrap_or(DEFAULT_LOCAL_VOICE)
            .to_string();
        st.local_voice_name = voice_name(&st.local_voice);
        st.local_engine = string_in(Some(&cfg), "local_engine", LOCAL_ENGINES, "apple");
        st.custom_voices = custom_voices(&cfg);
        st.gemini_voice = cfg
            .get("gemini_voice")
            .and_then(|v| v.as_str())
            .filter(|v| valid_gemini_voice(v, &st.custom_voices))
            .unwrap_or("Kore")
            .to_string();
        st.announcement_style = string_in(
            Some(&cfg),
            "announcement_style",
            ANNOUNCEMENT_STYLES,
            "verbatim",
        );
        st.custom_style_prompt = cfg
            .get("custom_style_prompt")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        st.home_cast_voice = cfg
            .get("home_cast_voice")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        st.style_model = string_in(Some(&cfg), "style_model", STYLE_MODELS, "apple");
        st.structure_name = cfg
            .get("structure_name")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        st.structure_id = cfg
            .get("structure_id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        if let Some(raw_homes) = cfg.get("homes").and_then(|v| v.as_array()) {
            for raw_h in raw_homes {
                if let Some(hm) = raw_h.as_object() {
                    let id = hm.get("id").and_then(|v| v.as_str()).unwrap_or("");
                    let name = hm.get("name").and_then(|v| v.as_str()).unwrap_or("");
                    if !id.is_empty() {
                        st.homes.push(HomeSpeakerHome {
                            id: id.to_string(),
                            name: name.to_string(),
                        });
                    }
                }
            }
        }
        if st.homes.is_empty() && !st.structure_name.is_empty() {
            st.homes.push(HomeSpeakerHome {
                id: st.structure_id.clone(),
                name: st.structure_name.clone(),
            });
        }

        let q_enabled = cfg
            .get("quiet_hours_enabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let q_start = cfg
            .get("quiet_hours_start")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("00:00")
            .to_string();
        let q_end = cfg
            .get("quiet_hours_end")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("06:00")
            .to_string();
        let q_active = is_quiet_hours_active(q_enabled, &q_start, &q_end, Timestamp::now());
        st.quiet_hours = HomeSpeakerQuiet {
            enabled: q_enabled,
            start: q_start,
            end: q_end,
            active: q_active,
        };
        st.quiet_hours_active = q_active;

        st.available_voices = if let Some(ref lv) = self.list_voices {
            match lv() {
                Ok(list) if !list.is_empty() => list,
                _ => default_voice_list(),
            }
        } else {
            default_voice_list()
        };

        let sec = self.read_secrets_data(&p.secrets_path);
        let cred = self.read_credentials_data();
        if !sec.google_email.is_empty() {
            st.account_email = sec.google_email;
        }
        st.has_oauth_client = !sec.oauth_client_id_override.is_empty()
            || !cred.oauth_client_id.is_empty()
            || file_exists(&self.oauth_client_path);
        st.has_antigravity_tokens = file_exists(&self.antigravity_tokens_path);
        st.custom_oauth_client_id = if !sec.oauth_client_id_override.is_empty() {
            sec.oauth_client_id_override
        } else {
            cred.oauth_client_id
        };
        st.has_custom_oauth_secret =
            !sec.oauth_client_secret_override.is_empty() || !cred.oauth_client_secret.is_empty();
        st.has_slack_token = !sec.slack_token.is_empty() || !cred.slack_token.is_empty();
        st.has_beeper_token = !sec.beeper_token.is_empty() || !cred.beeper_token.is_empty();
        st.has_chat_access = st.has_slack_token || st.has_beeper_token;

        if let Some(targets) = cfg.get("targets").and_then(|v| v.as_object()) {
            for key in dedupe_target_keys(targets, &st.default_target) {
                let t = targets.get(&key).and_then(|v| v.as_object());
                let name = t
                    .and_then(|m| m.get("name"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let room = t
                    .and_then(|m| m.get("room"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let target_type = t
                    .and_then(|m| m.get("type"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let selected = key == st.default_target;
                st.targets.push(HomeSpeakerTarget {
                    key,
                    name,
                    room,
                    target_type,
                    selected,
                });
            }
            st.targets.sort_by(|a, b| {
                let a_struct = a.target_type == "Structure";
                let b_struct = b.target_type == "Structure";
                if a_struct != b_struct {
                    return b_struct.cmp(&a_struct);
                }
                if a.room != b.room {
                    return a.room.cmp(&b.room);
                }
                a.name.cmp(&b.name)
            });
        }

        st.announce_claude_code = bool_or(Some(&cfg), "announce_claude_code", true);
        st.announce_antigravity = bool_or(Some(&cfg), "announce_antigravity", true);
        st.announce_opencode = bool_or(Some(&cfg), "announce_opencode", true);
        let monitor = cfg.get("chat_monitor").and_then(|v| v.as_object());
        st.slack_enabled = bool_or(monitor, "slack_enabled", false);
        st.google_chat_enabled = bool_or(monitor, "google_chat_enabled", false);
        st.beeper_enabled = bool_or(monitor, "beeper_enabled", false);
        st.beeper_announce = string_in(
            monitor,
            "beeper_announce",
            BEEPER_ANNOUNCE_MODES,
            "direct_and_mentions",
        );
        st.mute_own_messages = bool_or(monitor, "mute_own_messages", true);
        st.beeper_networks = self.beeper_networks(&p, st.app_running, monitor);

        let mon_status = self.read_monitor_status();
        st.monitor_running = mon_status.is_running;
        st.last_poll_at = mon_status.last_poll_date;
        st.slack_identity = mon_status.slack_identity;
        st.active_google_chat_backend = mon_status.active_google_chat_backend;
        st.chat_runtime_error = mon_status.last_error;
        st.gws_installed = file_exists(Path::new("/opt/homebrew/bin/gws"))
            || file_exists(Path::new("/usr/local/bin/gws"))
            || find_executable_in_path("gws").is_some();
        st.gws_account = monitor
            .and_then(|m| m.get("gws_account"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        st.google_chat_source = string_in(
            monitor,
            "google_chat_source",
            &["auto", "api", "gws"],
            "auto",
        );
        st.poll_interval = monitor
            .and_then(|m| m.get("poll_interval_seconds"))
            .and_then(|v| v.as_f64())
            .filter(|&pi| pi >= 5.0)
            .map(|pi| pi as i64)
            .unwrap_or(30);

        st.agents = self.inspect_agents(&p);
        st.legacy_launch_agent = file_exists(&self.legacy_plist_path);
        st.home_speaker_version = self.inspect_version(&p);
        st.recent = self.recent_broadcasts(RECENT_BROADCASTS);
        st.last = st.recent.first().cloned();
        st
    }

    fn say_preview_voice(
        &self,
        p: &HomeSpeakerProfile,
        engine: &str,
        voice: &str,
    ) -> Result<(), ApplyError> {
        const PREVIEW_TEXT: &str = "This is how announcements will sound.";
        let run_say = self.say.as_ref().unwrap_or(&self.run);
        let bin_str = p.binary.to_string_lossy().into_owned();
        let args = vec!["--say".to_string(), PREVIEW_TEXT.to_string()];
        if engine == "gemini" {
            let history_before = fs::read(&p.history_path).ok();
            let res = run_say(SAY_LIMIT, &bin_str, &args);
            if let Some(hb) = history_before {
                let _ = fs::write(&p.history_path, hb);
            }
            return res
                .map(|_| ())
                .map_err(|e| ApplyError::Internal(format!("preview voice failed: {e}")));
        }
        let name = voice_name(voice);
        if !name.is_empty() && name != voice {
            let say_args = vec!["-v".to_string(), name, PREVIEW_TEXT.to_string()];
            if (self.run)(Duration::from_secs(10), "say", &say_args).is_ok() {
                return Ok(());
            }
        }
        if !voice.is_empty() {
            let say_args = vec![
                "-v".to_string(),
                voice.to_string(),
                PREVIEW_TEXT.to_string(),
            ];
            if (self.run)(Duration::from_secs(10), "say", &say_args).is_ok() {
                return Ok(());
            }
        }
        run_say(SAY_LIMIT, &bin_str, &args)
            .map(|_| ())
            .map_err(|e| ApplyError::Internal(format!("preview voice failed: {e}")))
    }

    fn write_active_door(&self, door: &str) -> Result<(), ApplyError> {
        if self.door_path.as_os_str().is_empty() {
            return Ok(());
        }
        let mut doc = fs::read_to_string(&self.door_path)
            .ok()
            .and_then(|s| JsonValue::parse(&s).ok())
            .and_then(|v| v.as_object().cloned())
            .unwrap_or_default();
        doc.insert("chosen".to_string(), JsonValue::String(door.to_string()));
        write_atomic_json(&self.door_path, &doc)
    }

    fn update_secret(
        &self,
        secrets_path: &Path,
        camel_key: &str,
        snake_key: &str,
        val: &str,
    ) -> Result<(), ApplyError> {
        let clean = val.trim();
        let legacy_key = match camel_key {
            "geminiApiKey" => "geminiAPIKey",
            "oauthClientIdOverride" => "oauthClientIDOverride",
            "oauthClientSecretOverride" => "oauthClientSecret",
            _ => "",
        };
        if !secrets_path.as_os_str().is_empty() {
            let mut doc = if file_exists(secrets_path) {
                let data = fs::read_to_string(secrets_path)
                    .map_err(|e| ApplyError::Internal(e.to_string()))?;
                JsonValue::parse(&data)
                    .ok()
                    .and_then(|v| v.as_object().cloned())
                    .ok_or_else(|| ApplyError::Internal("failed to parse secrets".to_string()))?
            } else {
                JsonObject::new()
            };
            if !legacy_key.is_empty() {
                if let Some(old_val) = doc.remove(legacy_key) {
                    if !doc.contains_key(camel_key) {
                        doc.insert(camel_key.to_string(), old_val);
                    }
                }
            }
            if clean.is_empty() {
                doc.remove(camel_key);
                if !legacy_key.is_empty() {
                    doc.remove(legacy_key);
                }
            } else {
                doc.insert(camel_key.to_string(), JsonValue::String(clean.to_string()));
            }
            write_atomic_json(secrets_path, &doc)?;
        }
        if !snake_key.is_empty() && !self.credentials_path.as_os_str().is_empty() {
            let mut cred_doc = fs::read_to_string(&self.credentials_path)
                .ok()
                .and_then(|s| JsonValue::parse(&s).ok())
                .and_then(|v| v.as_object().cloned())
                .unwrap_or_default();
            if clean.is_empty() {
                cred_doc.remove(snake_key);
            } else {
                cred_doc.insert(snake_key.to_string(), JsonValue::String(clean.to_string()));
            }
            write_atomic_json(&self.credentials_path, &cred_doc)?;
        }
        Ok(())
    }

    fn clear_google_secrets(&self, secrets_path: &Path) {
        if secrets_path.as_os_str().is_empty() {
            return;
        }
        let Ok(data) = fs::read_to_string(secrets_path) else {
            return;
        };
        let Ok(val) = JsonValue::parse(&data) else {
            return;
        };
        let Some(mut doc) = val.as_object().cloned() else {
            return;
        };
        doc.remove("google");
        let _ = write_atomic_json(secrets_path, &doc);
    }

    fn import_antigravity_tokens(&self, secrets_path: &Path) -> Result<(), ApplyError> {
        if !file_exists(&self.antigravity_tokens_path) {
            return Err(ApplyError::BadRequest(
                "no Antigravity tokens file found".to_string(),
            ));
        }
        let data = fs::read_to_string(&self.antigravity_tokens_path)
            .map_err(|e| ApplyError::Internal(e.to_string()))?;
        let val = JsonValue::parse(&data).map_err(|e| ApplyError::Internal(e))?;
        let home_raw = val
            .as_object()
            .and_then(|o| o.get("https://home.googleapis.com/mcp"))
            .and_then(|v| v.as_object())
            .ok_or_else(|| {
                ApplyError::BadRequest(
                    "no Google Home login found in the Antigravity token file".to_string(),
                )
            })?;
        let client_id = home_raw
            .get("client_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let client_secret = home_raw
            .get("client_secret")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let token_raw = home_raw.get("token").and_then(|v| v.as_object());
        let access_token = token_raw
            .and_then(|t| t.get("access_token"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let refresh_token = token_raw
            .and_then(|t| t.get("refresh_token"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if access_token.is_empty() || refresh_token.is_empty() {
            return Err(ApplyError::BadRequest(
                "no Google Home login found in the Antigravity token file".to_string(),
            ));
        }
        let expiry = token_raw
            .and_then(|t| t.get("expiry"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let mut sec_doc = fs::read_to_string(secrets_path)
            .ok()
            .and_then(|s| JsonValue::parse(&s).ok())
            .and_then(|v| v.as_object().cloned())
            .unwrap_or_default();
        let mut google = JsonObject::new();
        google.insert(
            "clientId".to_string(),
            JsonValue::String(client_id.to_string()),
        );
        google.insert(
            "clientSecret".to_string(),
            JsonValue::String(client_secret.to_string()),
        );
        google.insert(
            "accessToken".to_string(),
            JsonValue::String(access_token.to_string()),
        );
        google.insert(
            "refreshToken".to_string(),
            JsonValue::String(refresh_token.to_string()),
        );
        google.insert("expiry".to_string(), JsonValue::String(expiry.to_string()));
        google.insert(
            "scopes".to_string(),
            JsonValue::Array(vec![JsonValue::String(
                "https://www.googleapis.com/auth/home.graph".to_string(),
            )]),
        );
        sec_doc.insert("google".to_string(), JsonValue::Object(google));
        write_atomic_json(secrets_path, &sec_doc)
    }

    fn execute_agent_hook_action(
        &self,
        action: &str,
        p: &HomeSpeakerProfile,
    ) -> Result<(), ApplyError> {
        let act = action.trim();
        match act {
            "install:claude-code" | "install:Claude Code" | "install_claude_hook" => {
                if self.claude_settings_path.as_os_str().is_empty() {
                    return Ok(());
                }
                let mut settings = if file_exists(&self.claude_settings_path) {
                    let data = fs::read_to_string(&self.claude_settings_path)
                        .map_err(|e| ApplyError::Internal(e.to_string()))?;
                    JsonValue::parse(&data)
                        .ok()
                        .and_then(|v| v.as_object().cloned())
                        .ok_or_else(|| {
                            ApplyError::Internal("failed to parse Claude settings".to_string())
                        })?
                } else {
                    JsonObject::new()
                };
                let mut hooks = settings
                    .get("hooks")
                    .and_then(|v| v.as_object().cloned())
                    .unwrap_or_default();
                let mut kept_groups = filter_claude_stop_groups(&hooks);
                let hook_cmd = format!("\"{}\" --claude-stop-hook", p.binary.display());
                let mut inner_hook = JsonObject::new();
                inner_hook.insert("type".to_string(), JsonValue::String("command".to_string()));
                inner_hook.insert("command".to_string(), JsonValue::String(hook_cmd));
                inner_hook.insert("timeout".to_string(), JsonValue::from_i64(10));
                let mut group = JsonObject::new();
                group.insert(
                    "hooks".to_string(),
                    JsonValue::Array(vec![JsonValue::Object(inner_hook)]),
                );
                kept_groups.push(JsonValue::Object(group));
                hooks.insert("Stop".to_string(), JsonValue::Array(kept_groups));
                settings.insert("hooks".to_string(), JsonValue::Object(hooks));
                write_atomic_json(&self.claude_settings_path, &settings)
            }
            "remove:claude-code" | "remove:Claude Code" | "remove_claude_hook" => {
                if !file_exists(&self.claude_settings_path) {
                    return Ok(());
                }
                let data = fs::read_to_string(&self.claude_settings_path)
                    .map_err(|e| ApplyError::Internal(e.to_string()))?;
                let mut settings = JsonValue::parse(&data)
                    .ok()
                    .and_then(|v| v.as_object().cloned())
                    .ok_or_else(|| {
                        ApplyError::Internal("failed to parse Claude settings".to_string())
                    })?;
                let Some(mut hooks) = settings.get("hooks").and_then(|v| v.as_object().cloned())
                else {
                    return Ok(());
                };
                let kept_groups = filter_claude_stop_groups(&hooks);
                if !kept_groups.is_empty() {
                    hooks.insert("Stop".to_string(), JsonValue::Array(kept_groups));
                } else {
                    hooks.remove("Stop");
                }
                if hooks.is_empty() {
                    settings.remove("hooks");
                } else {
                    settings.insert("hooks".to_string(), JsonValue::Object(hooks));
                }
                write_atomic_json(&self.claude_settings_path, &settings)
            }
            "disable-rival:claude-code"
            | "disable-rival:Claude Code"
            | "disable_rival_hook"
            | "disable-rival" => {
                if let Some(hd) = self.claude_settings_path.parent().and_then(|d| d.parent()) {
                    let rival_path = hd
                        .join(".claude")
                        .join("skills")
                        .join("google-home")
                        .join("hooks")
                        .join("hooks.json");
                    if file_exists(&rival_path) {
                        let disabled_path = PathBuf::from(format!(
                            "{}.disabled-by-homespeaker",
                            rival_path.display()
                        ));
                        let _ = fs::remove_file(&disabled_path);
                        fs::rename(&rival_path, &disabled_path)
                            .map_err(|e| ApplyError::Internal(e.to_string()))?;
                    }
                }
                Ok(())
            }
            "add-instruction:claude-code"
            | "add-instruction:Claude Code"
            | "add_claude_instruction" => append_instruction(&self.claude_md_path),
            "add-instruction:antigravity"
            | "add-instruction:Antigravity"
            | "add_antigravity_instruction" => append_instruction(&self.antigravity_md_path),
            "add-instruction:opencode"
            | "add-instruction:OpenCode"
            | "add_opencode_instruction" => append_instruction(&self.opencode_md_path),
            "remove-legacy-agent" | "remove_legacy_agent" => {
                if file_exists(&self.legacy_plist_path) {
                    let _ = fs::remove_file(&self.legacy_plist_path);
                }
                Ok(())
            }
            _ => Err(ApplyError::BadRequest(format!(
                "unknown agent_hook_action {act:?}"
            ))),
        }
    }

    pub fn apply(&self, u: HomeSpeakerUpdate) -> Result<String, ApplyError> {
        let p = self.active_profile();
        if u.reset_settings {
            let mut preserved_targets: Option<JsonValue> = None;
            let mut preserved_default = String::new();
            let mut preserved_structure_id = String::new();
            let mut preserved_structure_name = String::new();
            if file_exists(&p.config_path) {
                let data =
                    fs::read(&p.config_path).map_err(|e| ApplyError::Internal(e.to_string()))?;
                let bak = PathBuf::from(format!("{}.bak", p.config_path.display()));
                fs::write(&bak, &data).map_err(|e| {
                    ApplyError::Internal(format!("backup settings before reset failed: {e}"))
                })?;
                if let Ok(s) = std::str::from_utf8(&data) {
                    if let Ok(val) = JsonValue::parse(s) {
                        if let Some(existing) = val.as_object() {
                            if let Some(trgs) = existing.get("targets") {
                                if trgs.as_object().is_some() {
                                    preserved_targets = Some(trgs.clone());
                                }
                            }
                            if let Some(def) =
                                existing.get("default_target").and_then(|v| v.as_str())
                            {
                                preserved_default = def.to_string();
                            }
                            if let Some(sid) = existing.get("structure_id").and_then(|v| v.as_str())
                            {
                                preserved_structure_id = sid.to_string();
                            }
                            if let Some(sn) =
                                existing.get("structure_name").and_then(|v| v.as_str())
                            {
                                preserved_structure_name = sn.to_string();
                            }
                        }
                    }
                }
            }
            let mut fresh = JsonObject::new();
            fresh.insert("enabled".to_string(), JsonValue::Bool(true));
            fresh.insert(
                "default_target".to_string(),
                JsonValue::String(preserved_default),
            );
            fresh.insert(
                "speech_length".to_string(),
                JsonValue::String("summary".to_string()),
            );
            fresh.insert("pause_media".to_string(), JsonValue::Bool(false));
            fresh.insert(
                "pause_media_extra_seconds".to_string(),
                JsonValue::from_f64(1.0),
            );
            fresh.insert(
                "announce_volume_enabled".to_string(),
                JsonValue::Bool(false),
            );
            fresh.insert("announce_volume".to_string(), JsonValue::from_i64(60));
            fresh.insert("speak_home".to_string(), JsonValue::Bool(true));
            fresh.insert("speak_local".to_string(), JsonValue::Bool(false));
            fresh.insert(
                "local_voice".to_string(),
                JsonValue::String(DEFAULT_LOCAL_VOICE.to_string()),
            );
            fresh.insert(
                "local_engine".to_string(),
                JsonValue::String("apple".to_string()),
            );
            fresh.insert(
                "gemini_voice".to_string(),
                JsonValue::String("Kore".to_string()),
            );
            fresh.insert(
                "announcement_style".to_string(),
                JsonValue::String("verbatim".to_string()),
            );
            fresh.insert(
                "style_model".to_string(),
                JsonValue::String("apple".to_string()),
            );
            fresh.insert("quiet_hours_enabled".to_string(), JsonValue::Bool(false));
            fresh.insert(
                "quiet_hours_start".to_string(),
                JsonValue::String("00:00".to_string()),
            );
            fresh.insert(
                "quiet_hours_end".to_string(),
                JsonValue::String("06:00".to_string()),
            );
            fresh.insert("announce_claude_code".to_string(), JsonValue::Bool(true));
            fresh.insert("announce_antigravity".to_string(), JsonValue::Bool(true));
            fresh.insert("announce_opencode".to_string(), JsonValue::Bool(true));
            if let Some(trgs) = preserved_targets {
                fresh.insert("targets".to_string(), trgs);
            }
            if !preserved_structure_id.is_empty() {
                fresh.insert(
                    "structure_id".to_string(),
                    JsonValue::String(preserved_structure_id),
                );
            }
            if !preserved_structure_name.is_empty() {
                fresh.insert(
                    "structure_name".to_string(),
                    JsonValue::String(preserved_structure_name),
                );
            }
            self.write_config(&fresh)?;
            return Ok("reset_settings".to_string());
        }

        let mut cfg = self.read_config()?;
        let mut changed = Vec::new();
        let bin_str = p.binary.to_string_lossy().into_owned();

        if let Some(en) = u.enabled {
            cfg.insert("enabled".to_string(), JsonValue::Bool(en));
            changed.push(format!("enabled={en}"));
        }
        if let Some(ref dt) = u.default_target {
            let has_target = cfg
                .get("targets")
                .and_then(|v| v.as_object())
                .map(|t| t.contains_key(dt))
                .unwrap_or(false);
            if !has_target {
                return Err(ApplyError::BadRequest(format!(
                    "unknown speaker {dt:?}; GET /v1/homespeaker lists the keys"
                )));
            }
            cfg.insert("default_target".to_string(), JsonValue::String(dt.clone()));
            changed.push(format!("default_target={dt}"));
        }
        if let Some(ref sl) = u.speech_length {
            validate_enum("speech_length", sl, SPEECH_LENGTHS)?;
            cfg.insert("speech_length".to_string(), JsonValue::String(sl.clone()));
            changed.push(format!("speech_length={sl}"));
        }
        if let Some(qhe) = u.quiet_hours_enabled {
            cfg.insert("quiet_hours_enabled".to_string(), JsonValue::Bool(qhe));
            changed.push(format!("quiet_hours_enabled={qhe}"));
        }
        if let Some(ref qhs) = u.quiet_hours_start {
            parse_hhmm(qhs)?;
            cfg.insert(
                "quiet_hours_start".to_string(),
                JsonValue::String(qhs.clone()),
            );
            changed.push(format!("quiet_hours_start={qhs}"));
        }
        if let Some(ref qhe) = u.quiet_hours_end {
            parse_hhmm(qhe)?;
            cfg.insert(
                "quiet_hours_end".to_string(),
                JsonValue::String(qhe.clone()),
            );
            changed.push(format!("quiet_hours_end={qhe}"));
        }
        if let Some(ref csp) = u.custom_style_prompt {
            cfg.insert(
                "custom_style_prompt".to_string(),
                JsonValue::String(csp.clone()),
            );
            changed.push("custom_style_prompt".to_string());
        }
        if let Some(ref lv) = u.local_voice {
            let clean = lv.trim();
            if clean.is_empty() {
                return Err(ApplyError::BadRequest(
                    "local_voice cannot be empty".to_string(),
                ));
            }
            cfg.insert(
                "local_voice".to_string(),
                JsonValue::String(clean.to_string()),
            );
            changed.push(format!("local_voice={clean}"));
        }
        if u.preview_voice {
            let voice = cfg
                .get("local_voice")
                .and_then(|v| v.as_str())
                .filter(|s| !s.trim().is_empty())
                .unwrap_or(DEFAULT_LOCAL_VOICE)
                .to_string();
            let engine = cfg
                .get("local_engine")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .unwrap_or("apple")
                .to_string();
            self.say_preview_voice(&p, &engine, &voice)?;
            changed.push("preview_voice".to_string());
        }
        if let Some(pm) = u.pause_media {
            cfg.insert("pause_media".to_string(), JsonValue::Bool(pm));
            changed.push(format!("pause_media={pm}"));
        }
        if let Some(pme) = u.pause_media_extra_seconds {
            if !(0.0..=PAUSE_MEDIA_EXTRA_MAX).contains(&pme) {
                return Err(ApplyError::BadRequest(format!(
                    "pause_media_extra_seconds must be between 0 and {PAUSE_MEDIA_EXTRA_MAX}"
                )));
            }
            cfg.insert(
                "pause_media_extra_seconds".to_string(),
                JsonValue::from_f64(pme),
            );
            changed.push(format!("pause_media_extra_seconds={pme}"));
        }
        if u.test_media_pause {
            let args = vec!["--test-media-pause".to_string()];
            (self.run)(Duration::from_secs(30), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("test media pause failed: {e}")))?;
            changed.push("test_media_pause".to_string());
        }
        if let Some(ave) = u.announce_volume_enabled {
            cfg.insert("announce_volume_enabled".to_string(), JsonValue::Bool(ave));
            changed.push(format!("announce_volume_enabled={ave}"));
        }
        if let Some(av) = u.announce_volume {
            if !(0..=100).contains(&av) {
                return Err(ApplyError::BadRequest(
                    "announce_volume must be between 0 and 100".to_string(),
                ));
            }
            cfg.insert("announce_volume".to_string(), JsonValue::from_i64(av));
            changed.push(format!("announce_volume={av}"));
        }
        if let Some(sh) = u.speak_home {
            cfg.insert("speak_home".to_string(), JsonValue::Bool(sh));
            changed.push(format!("speak_home={sh}"));
        }
        if let Some(sl) = u.speak_local {
            cfg.insert("speak_local".to_string(), JsonValue::Bool(sl));
            changed.push(format!("speak_local={sl}"));
        }
        if let Some(sp) = u.speak_phone {
            cfg.insert("speak_phone".to_string(), JsonValue::Bool(sp));
            changed.push(format!("speak_phone={sp}"));
        }
        if let Some(ppm) = u.phone_pause_media {
            cfg.insert("phone_pause_media".to_string(), JsonValue::Bool(ppm));
            changed.push(format!("phone_pause_media={ppm}"));
        }
        if let Some(pho) = u.phone_headphones_only {
            cfg.insert("phone_headphones_only".to_string(), JsonValue::Bool(pho));
            changed.push(format!("phone_headphones_only={pho}"));
        }
        if let Some(ref le) = u.local_engine {
            validate_enum("local_engine", le, LOCAL_ENGINES)?;
            cfg.insert("local_engine".to_string(), JsonValue::String(le.clone()));
            changed.push(format!("local_engine={le}"));
        }
        if let Some(ref gv) = u.gemini_voice {
            let custom = custom_voices(&cfg);
            if !valid_gemini_voice(gv, &custom) {
                let mut allowed: Vec<String> =
                    GEMINI_VOICES.iter().map(|s| s.to_string()).collect();
                for c in custom {
                    allowed.push(c.id);
                }
                return Err(ApplyError::BadRequest(format!(
                    "gemini_voice must be one of {}",
                    allowed.join(", ")
                )));
            }
            cfg.insert("gemini_voice".to_string(), JsonValue::String(gv.clone()));
            changed.push(format!("gemini_voice={gv}"));
        }
        if let Some(ref style) = u.announcement_style {
            validate_enum("announcement_style", style, ANNOUNCEMENT_STYLES)?;
            cfg.insert(
                "announcement_style".to_string(),
                JsonValue::String(style.clone()),
            );
            changed.push(format!("announcement_style={style}"));
        }
        if let Some(ref sm) = u.style_model {
            validate_enum("style_model", sm, STYLE_MODELS)?;
            cfg.insert("style_model".to_string(), JsonValue::String(sm.clone()));
            changed.push(format!("style_model={sm}"));
        }
        if let Some(hcv) = u.home_cast_voice {
            cfg.insert("home_cast_voice".to_string(), JsonValue::Bool(hcv));
            changed.push(format!("home_cast_voice={hcv}"));
        }
        if let Some(ref ad) = u.active_door {
            let door = ad.trim().to_lowercase();
            if door != "app" && door != "extension" {
                return Err(ApplyError::BadRequest(
                    "active_door must be 'app' or 'extension'".to_string(),
                ));
            }
            self.write_active_door(&door)?;
            changed.push(format!("active_door={door}"));
        }
        if u.discover {
            let args = vec!["--discover".to_string(), "--save".to_string()];
            (self.run)(Duration::from_secs(60), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("discover failed: {e}")))?;
            changed.push("discover".to_string());
            if let Ok(reloaded) = self.read_config() {
                cfg = reloaded;
            }
        }
        if let Some(ref sid_raw) = u.structure_id {
            let sid = sid_raw.trim();
            if sid.is_empty() {
                return Err(ApplyError::BadRequest(
                    "structure_id cannot be empty".to_string(),
                ));
            }
            let args = vec![
                "--discover".to_string(),
                "--save".to_string(),
                "--home".to_string(),
                sid.to_string(),
            ];
            (self.run)(Duration::from_secs(60), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("set structure failed: {e}")))?;
            changed.push(format!("structure_id={sid}"));
            if let Ok(reloaded) = self.read_config() {
                cfg = reloaded;
            }
            cfg.insert(
                "structure_id".to_string(),
                JsonValue::String(sid.to_string()),
            );
        }
        if let Some(ref target_key) = u.remove_target {
            if let Some(JsonValue::Object(targets)) = cfg.get_mut("targets") {
                targets.remove(target_key);
            }
            if cfg
                .get("default_target")
                .and_then(|v| v.as_str())
                .map(|d| d == target_key)
                .unwrap_or(false)
            {
                cfg.insert(
                    "default_target".to_string(),
                    JsonValue::String(String::new()),
                );
            }
            changed.push(format!("remove_target={target_key}"));
        }
        if u.sign_out {
            let args = vec!["--sign-out".to_string()];
            (self.run)(Duration::from_secs(30), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("sign out failed: {e}")))?;
            self.clear_google_secrets(&p.secrets_path);
            changed.push("sign_out".to_string());
            if let Ok(reloaded) = self.read_config() {
                cfg = reloaded;
            }
        }
        if u.import_antigravity {
            self.import_antigravity_tokens(&p.secrets_path)?;
            changed.push("import_antigravity".to_string());
        }
        if u.speak_clipboard {
            let Some(ref rc) = self.read_clipboard else {
                return Err(ApplyError::BadRequest(
                    "clipboard reading is unavailable".to_string(),
                ));
            };
            let clip_text = rc().unwrap_or_default();
            if clip_text.trim().is_empty() {
                return Err(ApplyError::BadRequest("clipboard is empty".to_string()));
            }
            let run_say = self.say.as_ref().unwrap_or(&self.run);
            let args = vec!["--say".to_string(), clip_text.trim().to_string()];
            run_say(SAY_LIMIT, &bin_str, &args).map_err(ApplyError::Internal)?;
            changed.push("speak_clipboard".to_string());
        }
        if let Some(ref gcs) = u.google_chat_source {
            validate_enum("google_chat_source", gcs, &["auto", "api", "gws"])?;
            let monitor = ensure_chat_monitor(&mut cfg);
            monitor.insert(
                "google_chat_source".to_string(),
                JsonValue::String(gcs.clone()),
            );
            changed.push(format!("chat_monitor.google_chat_source={gcs}"));
        }
        if let Some(ref ga) = u.gws_account {
            let monitor = ensure_chat_monitor(&mut cfg);
            monitor.insert(
                "gws_account".to_string(),
                JsonValue::String(ga.trim().to_string()),
            );
            changed.push(format!("chat_monitor.gws_account={}", ga.trim()));
        }
        if let Some(pi) = u.poll_interval {
            if pi < 5 {
                return Err(ApplyError::BadRequest(
                    "poll_interval must be at least 5 seconds".to_string(),
                ));
            }
            let monitor = ensure_chat_monitor(&mut cfg);
            monitor.insert("poll_interval_seconds".to_string(), JsonValue::from_i64(pi));
            changed.push(format!("chat_monitor.poll_interval_seconds={pi}"));
        }
        if let Some(ref st) = u.slack_token {
            self.update_secret(&p.secrets_path, "slackToken", "slack_token", st)?;
            changed.push(if st.is_empty() {
                "slack_token=cleared".to_string()
            } else {
                "slack_token=<redacted>".to_string()
            });
        }
        if let Some(ref bt) = u.beeper_token {
            self.update_secret(&p.secrets_path, "beeperToken", "beeper_token", bt)?;
            changed.push(if bt.is_empty() {
                "beeper_token=cleared".to_string()
            } else {
                "beeper_token=<redacted>".to_string()
            });
        }
        if let Some(ref gk) = u.gemini_api_key {
            self.update_secret(&p.secrets_path, "geminiApiKey", "", gk)?;
            changed.push(if gk.is_empty() {
                "gemini_api_key=cleared".to_string()
            } else {
                "gemini_api_key=<redacted>".to_string()
            });
        }
        if let Some(ref ocid) = u.oauth_client_id {
            self.update_secret(
                &p.secrets_path,
                "oauthClientIdOverride",
                "oauth_client_id",
                ocid,
            )?;
            changed.push(if ocid.is_empty() {
                "oauth_client_id=cleared".to_string()
            } else {
                "oauth_client_id=<set>".to_string()
            });
        }
        if let Some(ref ocs) = u.oauth_client_secret {
            self.update_secret(
                &p.secrets_path,
                "oauthClientSecretOverride",
                "oauth_client_secret",
                ocs,
            )?;
            changed.push(if ocs.is_empty() {
                "oauth_client_secret=cleared".to_string()
            } else {
                "oauth_client_secret=<redacted>".to_string()
            });
        }
        if let Some(ref cma) = u.chat_monitor_action {
            let action = cma.trim().to_lowercase();
            if action != "start" && action != "stop" {
                return Err(ApplyError::BadRequest(
                    "chat_monitor_action must be 'start' or 'stop'".to_string(),
                ));
            }
            let args = vec!["--chat-monitor".to_string(), action.clone()];
            (self.run)(Duration::from_secs(30), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("chat monitor {action} failed: {e}")))?;
            changed.push(format!("chat_monitor_action={action}"));
        }
        if let Some(ref aha) = u.agent_hook_action {
            self.execute_agent_hook_action(aha, &p)?;
            changed.push(format!("agent_hook_action={aha}"));
        }
        for (key, val) in [
            ("announce_claude_code", u.announce_claude_code),
            ("announce_antigravity", u.announce_antigravity),
            ("announce_opencode", u.announce_opencode),
        ] {
            if let Some(b) = val {
                cfg.insert(key.to_string(), JsonValue::Bool(b));
                changed.push(format!("{key}={b}"));
            }
        }
        for (key, val) in [
            ("slack_enabled", u.slack_enabled),
            ("google_chat_enabled", u.google_chat_enabled),
            ("beeper_enabled", u.beeper_enabled),
            ("mute_own_messages", u.mute_own_messages),
        ] {
            if let Some(b) = val {
                let monitor = ensure_chat_monitor(&mut cfg);
                monitor.insert(key.to_string(), JsonValue::Bool(b));
                changed.push(format!("chat_monitor.{key}={b}"));
            }
        }
        if let Some(ref ba) = u.beeper_announce {
            validate_enum("beeper_announce", ba, BEEPER_ANNOUNCE_MODES)?;
            let monitor = ensure_chat_monitor(&mut cfg);
            monitor.insert("beeper_announce".to_string(), JsonValue::String(ba.clone()));
            changed.push(format!("chat_monitor.beeper_announce={ba}"));
        }
        if let Some(ref bn) = u.beeper_network {
            let key = bn.key.trim();
            if !is_valid_beeper_network_key(key) {
                return Err(ApplyError::BadRequest(format!(
                    "invalid beeper_network.key {:?}",
                    bn.key
                )));
            }
            let monitor = ensure_chat_monitor(&mut cfg);
            let muted = muted_networks_from_monitor(Some(monitor));
            let mut next: Vec<JsonValue> = muted
                .into_iter()
                .filter(|existing| existing != key)
                .map(JsonValue::String)
                .collect();
            if !bn.reading {
                next.push(JsonValue::String(key.to_string()));
            }
            monitor.insert("beeper_muted_networks".to_string(), JsonValue::Array(next));
            changed.push(format!("chat_monitor.beeper_network.{key}={}", bn.reading));
        }

        self.write_config(&cfg)?;
        Ok(changed.join(" "))
    }

    pub fn run_volume(&self, args: &[String]) -> HomeSpeakerVolume {
        let p = self.active_profile();
        if !file_exists(&p.binary) {
            return HomeSpeakerVolume {
                reason: format!("HomeSpeaker is not installed at {}", p.binary.display()),
                ..Default::default()
            };
        }
        let bin_str = p.binary.to_string_lossy().into_owned();
        let (stdout, stderr, err_msg) = match (self.run)(VOLUME_LIMIT, &bin_str, args) {
            Ok((out, err)) => (out, err, String::new()),
            Err(e) => (String::new(), String::new(), e),
        };
        for line in stdout.trim().lines() {
            if let Ok(val) = JsonValue::parse(line) {
                if let Some(v) = HomeSpeakerVolume::from_json(&val) {
                    return v;
                }
            }
        }
        let mut reason = stderr.trim().to_string();
        if reason.is_empty() && !err_msg.is_empty() {
            for line in err_msg.lines() {
                if let Ok(val) = JsonValue::parse(line) {
                    if let Some(v) = HomeSpeakerVolume::from_json(&val) {
                        return v;
                    }
                }
            }
            reason = err_msg;
        }
        if reason.is_empty() {
            reason = "HomeSpeaker printed no volume (is it version 1.9 or later?)".to_string();
        }
        HomeSpeakerVolume {
            reason,
            ..Default::default()
        }
    }

    pub fn handle_get(&self, phone: &PhoneBridge) -> HttpResponse {
        let mut st = self.state();
        st.phone_connected = phone.connected();
        HttpResponse::json(200, &st.to_json())
    }

    pub fn handle_set(&self, req: &HttpRequest, phone: &PhoneBridge) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let body = match HomeSpeakerUpdate::from_json(&val) {
            Ok(u) => u,
            Err(e) => return HttpResponse::error(400, &e),
        };
        if body.empty() {
            return HttpResponse::error(
                400,
                "nothing to change: give enabled, default_target, speech_length, quiet_hours_enabled, pause_media, pause_media_extra_seconds, announce_volume_enabled, announce_volume, speak_home, speak_local, speak_phone, phone_pause_media, phone_headphones_only, local_engine, gemini_voice, announcement_style, style_model, announce_claude_code, announce_antigravity, announce_opencode, slack_enabled, google_chat_enabled, beeper_enabled, beeper_announce, beeper_network or mute_own_messages",
            );
        }
        match self.apply(body) {
            Ok(changed) => {
                log_act("homespeaker", &changed);
                let mut st = self.state();
                st.phone_connected = phone.connected();
                HttpResponse::json(200, &st.to_json())
            }
            Err(ApplyError::BadRequest(msg)) => HttpResponse::error(400, &msg),
            Err(ApplyError::NotFound(_)) => {
                HttpResponse::error(409, "HomeSpeaker has not been set up on this Mac")
            }
            Err(ApplyError::Internal(msg)) => HttpResponse::error(500, &msg),
        }
    }

    pub fn handle_say(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let Some(obj) = val.as_object() else {
            return HttpResponse::error(400, "invalid JSON body");
        };
        let mut text = obj
            .get("text")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        let replay = obj.get("replay").and_then(|v| v.as_bool()).unwrap_or(false);
        let replay_id = obj
            .get("replay_id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        if !replay_id.is_empty() {
            let mut found = false;
            for item in self.recent_broadcasts(50) {
                if item.id == replay_id {
                    text = item.text;
                    found = true;
                    break;
                }
            }
            if !found {
                return HttpResponse::error(400, "That announcement is no longer in the history");
            }
        }
        if text.is_empty() {
            return HttpResponse::error(400, "text is required");
        }
        let p = self.active_profile();
        if !file_exists(&p.binary) {
            return HttpResponse::error(
                409,
                &format!("HomeSpeaker is not installed at {}", p.binary.display()),
            );
        }
        let is_replay = replay || !replay_id.is_empty();
        let log_label = if is_replay {
            format!("replay {text}")
        } else {
            format!("say {text}")
        };
        log_act("homespeaker", &log_label);

        let history_snapshot = if is_replay && !p.history_path.as_os_str().is_empty() {
            fs::read(&p.history_path).ok()
        } else {
            None
        };
        let run = self.say.as_ref().unwrap_or(&self.run);
        let bin_str = p.binary.to_string_lossy().into_owned();
        let args = vec!["--say".to_string(), text];
        let res = run(SAY_LIMIT, &bin_str, &args);
        if let Some(snap) = history_snapshot {
            let _ = fs::write(&p.history_path, snap);
        }
        let mut resp = JsonObject::new();
        match res {
            Ok((stdout, stderr)) => {
                let out = format!("{}\n{}", stdout.trim(), stderr.trim())
                    .trim()
                    .to_string();
                resp.insert("ok".to_string(), JsonValue::Bool(true));
                resp.insert("output".to_string(), JsonValue::String(out));
            }
            Err(err) => {
                resp.insert("ok".to_string(), JsonValue::Bool(false));
                resp.insert("output".to_string(), JsonValue::String(err));
            }
        }
        HttpResponse::json(200, &JsonValue::Object(resp))
    }

    pub fn handle_phone_say(&self, req: &HttpRequest, phone: &PhoneBridge) -> HttpResponse {
        if req.body.is_empty() {
            return HttpResponse::error(400, "a JSON body is required");
        }
        if req.body.len() > MAX_PHONE_SAY_BODY {
            return HttpResponse::error(400, "request body too large");
        }
        let val = match JsonValue::parse_bytes(&req.body) {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &format!("invalid JSON body: {e}")),
        };
        let Some(obj) = val.as_object() else {
            return HttpResponse::error(400, "invalid JSON body");
        };
        let text = obj
            .get("text")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if text.is_empty() {
            return HttpResponse::error(400, "text is required");
        }
        if !phone.connected() {
            return HttpResponse::json(
                200,
                &phone_say_response_json(false, false, false, "no phone connected", ""),
            );
        }
        let cfg = self.read_config().ok();
        let pause_media = obj
            .get("pause_media")
            .and_then(|v| v.as_bool())
            .or_else(|| {
                cfg.as_ref()
                    .and_then(|c| c.get("phone_pause_media"))
                    .and_then(|v| v.as_bool())
            })
            .unwrap_or(false);
        let headphones_only = obj
            .get("headphones_only")
            .and_then(|v| v.as_bool())
            .or_else(|| {
                cfg.as_ref()
                    .and_then(|c| c.get("phone_headphones_only"))
                    .and_then(|v| v.as_bool())
            })
            .unwrap_or(false);
        let wav_base64 = obj.get("wav_base64").and_then(|v| v.as_str()).unwrap_or("");

        let mut args_obj = JsonObject::new();
        args_obj.insert("text".to_string(), JsonValue::String(text.clone()));
        args_obj.insert(
            "wav_base64".to_string(),
            JsonValue::String(wav_base64.to_string()),
        );
        args_obj.insert("pause_media".to_string(), JsonValue::Bool(pause_media));
        args_obj.insert(
            "headphones_only".to_string(),
            JsonValue::Bool(headphones_only),
        );
        log_act("homespeaker", &format!("phone-say {text}"));

        let res = match phone.dispatch(
            "phone.speak",
            JsonValue::Object(args_obj),
            PHONE_SAY_TIMEOUT,
        ) {
            Ok(r) => r,
            Err(e) => {
                return HttpResponse::json(
                    200,
                    &phone_say_response_json(false, false, false, &e, ""),
                );
            }
        };
        let raw_text = first_text_content(&res);
        if res.is_error {
            return HttpResponse::json(
                200,
                &phone_say_response_json(false, false, false, &raw_text, ""),
            );
        }
        let tool_val = match JsonValue::parse(&raw_text) {
            Ok(v) => v,
            Err(e) => {
                return HttpResponse::json(
                    200,
                    &phone_say_response_json(
                        false,
                        false,
                        false,
                        &format!("invalid phone.speak response: {e}"),
                        "",
                    ),
                );
            }
        };
        let to = tool_val.as_object();
        let spoken = to
            .and_then(|o| o.get("spoken"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let skipped = to
            .and_then(|o| o.get("skipped"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let reason = to
            .and_then(|o| o.get("reason"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let engine = to
            .and_then(|o| o.get("engine"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        HttpResponse::json(
            200,
            &phone_say_response_json(true, spoken, skipped, reason, engine),
        )
    }

    pub fn handle_get_volume(&self) -> HttpResponse {
        let args = vec!["--volume".to_string()];
        let v = self.run_volume(&args);
        HttpResponse::json(200, &v.to_json())
    }

    pub fn handle_set_volume(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let Some(obj) = val.as_object() else {
            return HttpResponse::error(400, "invalid JSON body");
        };
        let percent = obj.get("percent").and_then(|v| v.as_i64());
        let muted = obj.get("muted").and_then(|v| v.as_bool());
        let args = match (percent, muted) {
            (Some(_), Some(_)) | (None, None) => {
                return HttpResponse::error(
                    400,
                    "give exactly one of \"percent\" (0-100) or \"muted\"",
                );
            }
            (Some(p), None) => {
                if !(0..=100).contains(&p) {
                    return HttpResponse::error(400, "percent must be between 0 and 100");
                }
                vec!["--set-volume".to_string(), p.to_string()]
            }
            (None, Some(true)) => vec!["--mute".to_string()],
            (None, Some(false)) => vec!["--unmute".to_string()],
        };
        log_act("homespeaker", &format!("volume {}", args.join(" ")));
        let v = self.run_volume(&args);
        HttpResponse::json(200, &v.to_json())
    }
}

impl Default for HomeSpeaker {
    fn default() -> Self {
        Self::new()
    }
}

fn phone_say_response_json(
    ok: bool,
    spoken: bool,
    skipped: bool,
    reason: &str,
    engine: &str,
) -> JsonValue {
    let mut m = JsonObject::new();
    m.insert("ok".to_string(), JsonValue::Bool(ok));
    m.insert("spoken".to_string(), JsonValue::Bool(spoken));
    if skipped {
        m.insert("skipped".to_string(), JsonValue::Bool(true));
    }
    if !reason.is_empty() {
        m.insert("reason".to_string(), JsonValue::String(reason.to_string()));
    }
    if !engine.is_empty() {
        m.insert("engine".to_string(), JsonValue::String(engine.to_string()));
    }
    JsonValue::Object(m)
}

fn filter_claude_stop_groups(hooks: &JsonObject) -> Vec<JsonValue> {
    let Some(stop_groups) = hooks.get("Stop").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    let mut kept_groups = Vec::new();
    for g in stop_groups {
        let Some(mut gm) = g.as_object().cloned() else {
            continue;
        };
        let Some(inner) = gm.get("hooks").and_then(|v| v.as_array()) else {
            continue;
        };
        let mut kept_inner = Vec::new();
        for item in inner {
            let Some(inm) = item.as_object() else {
                continue;
            };
            let cmd = inm.get("command").and_then(|v| v.as_str()).unwrap_or("");
            if !cmd.contains("claude-stop-hook") && !cmd.contains("stop_broadcast.py") {
                kept_inner.push(JsonValue::Object(inm.clone()));
            }
        }
        if !kept_inner.is_empty() {
            gm.insert("hooks".to_string(), JsonValue::Array(kept_inner));
            kept_groups.push(JsonValue::Object(gm));
        }
    }
    kept_groups
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pair::Store;
    use crate::sampler::KNOWN_TOOLS;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Mutex;

    const HOME_SPEAKER_CONFIG_FIXTURE: &str = r#"{
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
}"#;

    static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir(prefix: &str) -> PathBuf {
        let id = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "vitruvian_hs_test_{}_{}_{}",
            prefix,
            std::process::id(),
            id
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[derive(Clone, Default)]
    struct SayCall {
        inner: Arc<Mutex<(String, Vec<String>)>>,
    }

    impl SayCall {
        fn record(&self, name: &str, args: &[String]) {
            let mut g = self.inner.lock().unwrap();
            *g = (name.to_string(), args.to_vec());
        }
        fn name(&self) -> String {
            self.inner.lock().unwrap().0.clone()
        }
        fn args(&self) -> Vec<String> {
            self.inner.lock().unwrap().1.clone()
        }
    }

    fn new_test_home_speaker(with_config: bool) -> (HomeSpeaker, Store, PhoneBridge, SayCall) {
        let dir = temp_dir("hs");
        let bin = dir.join("HomeSpeaker");
        fs::write(&bin, b"#!/bin/sh\n").unwrap();
        let _ = fs::set_permissions(&bin, fs::Permissions::from_mode(0o755));
        let last = SayCall::default();
        let last_c = last.clone();
        let h = HomeSpeaker {
            config_path: dir.join("speaker_broadcast.json"),
            history_path: dir.join("speaker_history.json"),
            secrets_path: dir.join("secrets.json"),
            door_path: dir.join("speaker_door.json"),
            credentials_path: dir.join("chat_credentials.json"),
            monitor_status_path: dir.join("speaker_monitor_status.json"),
            claude_settings_path: dir.join(".claude").join("settings.json"),
            claude_md_path: dir.join(".claude").join("CLAUDE.md"),
            antigravity_md_path: dir.join(".gemini").join("AGENTS.md"),
            opencode_md_path: dir.join(".config").join("opencode").join("AGENTS.md"),
            legacy_plist_path: dir
                .join("LaunchAgents")
                .join("com.james.chat-monitor.plist"),
            oauth_client_path: dir.join("google-oauth-client.json"),
            antigravity_tokens_path: dir.join("mcp_oauth_tokens.json"),
            binary: bin,
            run: Arc::new(move |_limit, name, args| {
                last_c.record(name, args);
                Ok(("sent to Lake Office display\n".to_string(), String::new()))
            }),
            say: None,
            running: Some(Arc::new(|| true)),
            read_clipboard: Some(Arc::new(|| Ok("clipboard announcement text".to_string()))),
            list_voices: Some(Arc::new(|| Ok(default_voice_list()))),
        };
        if with_config {
            fs::write(&h.config_path, HOME_SPEAKER_CONFIG_FIXTURE).unwrap();
        }
        let store = Store::new(temp_dir("store"));
        store.ensure_token().unwrap();
        let phone = PhoneBridge::new();
        (h, store, phone, last)
    }

    fn post_req(path: &str, body: &str) -> HttpRequest {
        HttpRequest::new_test("POST", path, body).with_header("content-type", "application/json")
    }

    #[test]
    fn test_home_speaker_state_reads_the_apps_own_config() {
        let (h, _, _, _) = new_test_home_speaker(true);
        let st = h.state();
        assert!(st.available && st.installed && st.app_running);
        assert!(!st.signed_in);
        assert!(st.enabled);
        assert_eq!(st.default_target, "lake_office");
        assert_eq!(st.speech_length, "summary");
        assert_eq!(st.targets.len(), 3);
        assert_eq!(st.targets[0].key, "all");
        assert_eq!(st.targets[1].key, "kitchen");
        assert_eq!(st.targets[2].key, "lake_office");
        assert!(st.targets[2].selected && !st.targets[1].selected);
        assert!(st.last.is_none());
    }

    #[test]
    fn test_home_speaker_dedupes_one_device_under_several_aliases() {
        let val = JsonValue::parse(
            r#"{
            "lake_office": {"id": "device@l"},
            "lake_office_display": {"id": "device@l"},
            "kitchen": {"id": "device@k"},
            "all": {"id": "structure@s"}
        }"#,
        )
        .unwrap();
        let mut targets = val.as_object().unwrap().clone();
        let got = dedupe_target_keys(&targets, "kitchen");
        assert_eq!(got, vec!["all", "kitchen", "lake_office"]);
        let got2 = dedupe_target_keys(&targets, "lake_office_display");
        assert_eq!(got2, vec!["all", "kitchen", "lake_office_display"]);
        let mut no_id = JsonObject::new();
        no_id.insert("name".to_string(), JsonValue::String("no id".to_string()));
        targets.insert("mystery".to_string(), JsonValue::Object(no_id));
        assert_eq!(dedupe_target_keys(&targets, "").len(), 4);
    }

    #[test]
    fn test_home_speaker_state_without_a_setup_is_honest() {
        let (h, _, _, _) = new_test_home_speaker(false);
        let st = h.state();
        assert!(!st.available);
        assert!(st.reason.contains("not been set up"));
        assert!(st.installed);
    }

    #[test]
    fn test_home_speaker_signed_in_never_leaks_the_token() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        fs::write(
            &h.secrets_path,
            r#"{"google":{"accessToken":"ya29.x","refreshToken":"1//SECRET-VALUE","clientId":"c","scopes":["s"]}}"#,
        )
        .unwrap();
        let resp = h.handle_get(&phone);
        let body_str = resp.body_string();
        assert!(!body_str.contains("SECRET-VALUE"));
        assert!(h.state().signed_in);

        fs::write(&h.secrets_path, r#"{"google":{"refresh_token":"1//x"}}"#).unwrap();
        assert!(!h.state().signed_in);
    }

    #[test]
    fn test_home_speaker_last_broadcast_uses_swifts_epoch() {
        let (h, _, _, _) = new_test_home_speaker(true);
        let want = Timestamp::parse_rfc3339("2026-09-19T08:14:00Z").unwrap();
        let stamp = want.unix_seconds() - SWIFT_REFERENCE_EPOCH_UNIX_SECS;
        let hist = format!(
            r#"[{{"id":"x","timestamp":{stamp},"text":"Problem. Two hooks.","targetName":"Lake Office display","source":"claude"}}]"#
        );
        fs::write(&h.history_path, hist).unwrap();
        let st = h.state();
        let last = st.last.expect("history present");
        assert_eq!(last.at.unix_seconds(), want.unix_seconds());
        assert_eq!(last.text, "Problem. Two hooks.");
        assert_eq!(last.target, "Lake Office display");
    }

    #[test]
    fn test_home_speaker_update_rewrites_only_what_was_asked_and_keeps_unknown_keys() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        let req = post_req(
            "/v1/homespeaker",
            r#"{"default_target":"kitchen","enabled":false,"speech_length":"full"}"#,
        );
        let resp = h.handle_set(&req, &phone);
        assert_eq!(resp.status, 200);
        let st = h.state();
        assert!(!st.enabled && st.default_target == "kitchen" && st.speech_length == "full");

        let cfg = h.read_config().unwrap();
        assert_eq!(cfg.get("default_target").unwrap().as_str(), Some("kitchen"));
        assert_eq!(cfg.get("enabled").unwrap().as_bool(), Some(false));
        assert_eq!(cfg.get("speech_length").unwrap().as_str(), Some("full"));
        assert!(cfg.contains_key("chat_monitor"));
        assert_eq!(cfg.get("structure_id").unwrap().as_str(), Some("5219a9d7"));
        assert_eq!(cfg.get("targets").unwrap().as_object().unwrap().len(), 4);
        assert!(!PathBuf::from(format!("{}.agent-tmp", h.config_path.display())).exists());
    }

    #[test]
    fn test_home_speaker_update_refuses_what_the_app_would_ignore() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        let before = fs::read(&h.config_path).unwrap();
        for (body, want) in [
            (r#"{"default_target":"garage"}"#, "unknown speaker"),
            (
                r#"{"speech_length":"medium"}"#,
                "speech_length must be one of",
            ),
            (r#"{}"#, "nothing to change"),
            (r#"{"enabled":"yes"}"#, "cannot unmarshal"),
        ] {
            let resp = h.handle_set(&post_req("/v1/homespeaker", body), &phone);
            assert_eq!(resp.status, 400, "body={body}");
            let s = resp.body_string();
            assert!(s.contains(want), "body={body} got={s}");
        }
        let after = fs::read(&h.config_path).unwrap();
        assert_eq!(before, after);
    }

    #[test]
    fn test_home_speaker_say_runs_the_apps_own_say() {
        let (h, _, _, last) = new_test_home_speaker(true);
        let resp = h.handle_say(&post_req(
            "/v1/homespeaker/say",
            r#"{"text":"  dinner is ready  "}"#,
        ));
        assert_eq!(resp.status, 200);
        let out = JsonValue::parse_bytes(&resp.body_bytes()).unwrap();
        assert_eq!(out.get_opt_bool("ok"), Some(true));
        assert_eq!(last.name(), h.binary.to_string_lossy());
        assert_eq!(last.args(), vec!["--say", "dinner is ready"]);
        assert!(out
            .get_str("output")
            .contains("sent to Lake Office display"));

        let resp2 = h.handle_say(&post_req("/v1/homespeaker/say", r#"{"text":"   "}"#));
        assert_eq!(resp2.status, 400);
    }

    #[test]
    fn test_home_speaker_update_without_a_setup_is_a_conflict_not_a_crash() {
        let (h, _, phone, _) = new_test_home_speaker(false);
        let resp = h.handle_set(&post_req("/v1/homespeaker", r#"{"enabled":true}"#), &phone);
        assert_eq!(resp.status, 409);
    }

    #[test]
    fn test_home_speaker_is_a_known_tool_resolved_by_bundle_not_path() {
        assert!(KNOWN_TOOLS.contains(&"homespeaker"));
        let tools = crate::sampler::tool_presence(&["homespeaker"]);
        let got = tools.tools.get("homespeaker").unwrap();
        assert_eq!(got.path, HOME_SPEAKER_BINARY);
        assert_eq!(got.available, Path::new(HOME_SPEAKER_BINARY).exists());
    }

    #[test]
    fn test_home_speaker_pause_media_defaults_and_round_trip() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        let st = h.state();
        assert!(!st.pause_media && st.pause_media_extra_seconds == 1.0);
        let resp = h.handle_set(
            &post_req(
                "/v1/homespeaker",
                r#"{"pause_media":true,"pause_media_extra_seconds":3}"#,
            ),
            &phone,
        );
        assert_eq!(resp.status, 200);
        let st2 = h.state();
        assert!(st2.pause_media && st2.pause_media_extra_seconds == 3.0);
    }

    #[test]
    fn test_home_speaker_pause_media_margin_is_refused_outside_the_apps_range() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        let before = fs::read(&h.config_path).unwrap();
        for body in [
            r#"{"pause_media_extra_seconds":11}"#,
            r#"{"pause_media_extra_seconds":-1}"#,
            r#"{"pause_media":true,"pause_media_extra_seconds":99}"#,
        ] {
            let resp = h.handle_set(&post_req("/v1/homespeaker", body), &phone);
            assert_eq!(resp.status, 400);
            assert!(resp.body_string().contains("between 0 and 10"));
        }
        assert_eq!(before, fs::read(&h.config_path).unwrap());
    }

    #[test]
    fn test_home_speaker_volume_read_and_change_and_refusals() {
        let (mut h, _, _, _) = new_test_home_speaker(true);
        let calls: Arc<Mutex<Vec<Vec<String>>>> = Arc::new(Mutex::new(Vec::new()));
        let state_vol: Arc<Mutex<(i64, bool)>> = Arc::new(Mutex::new((40, false)));
        let calls_c = calls.clone();
        let state_c = state_vol.clone();
        h.run = Arc::new(move |_limit, _name, args| {
            calls_c.lock().unwrap().push(args.to_vec());
            let mut st = state_c.lock().unwrap();
            match args[0].as_str() {
                "--set-volume" => st.0 = args[1].parse().unwrap_or(0),
                "--mute" => st.1 = true,
                "--unmute" => st.1 = false,
                _ => {}
            }
            Ok((
                format!(
                    r#"{{"available":true,"muted":{},"online":true,"percent":{},"speaker":"Lake Office display"}}"#,
                    st.1, st.0
                ),
                String::new(),
            ))
        });

        let r1 = h.handle_get_volume();
        let v1 = HomeSpeakerVolume::from_json(&JsonValue::parse_bytes(&r1.body_bytes()).unwrap())
            .unwrap();
        assert!(v1.available && v1.percent == 40 && v1.speaker == "Lake Office display");

        let r2 = h.handle_set_volume(&post_req("/v1/homespeaker/volume", r#"{"percent":55}"#));
        let v2 = HomeSpeakerVolume::from_json(&JsonValue::parse_bytes(&r2.body_bytes()).unwrap())
            .unwrap();
        assert_eq!(v2.percent, 55);

        let r3 = h.handle_set_volume(&post_req("/v1/homespeaker/volume", r#"{"muted":true}"#));
        let v3 = HomeSpeakerVolume::from_json(&JsonValue::parse_bytes(&r3.body_bytes()).unwrap())
            .unwrap();
        assert!(v3.muted);

        for bad in [
            r#"{}"#,
            r#"{"percent":50,"muted":true}"#,
            r#"{"percent":101}"#,
            r#"{"percent":-1}"#,
        ] {
            let rb = h.handle_set_volume(&post_req("/v1/homespeaker/volume", bad));
            assert_eq!(rb.status, 400);
        }
    }

    #[test]
    fn test_home_speaker_announce_volume_defaults_round_trip_and_range() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        let st = h.state();
        assert!(!st.announce_volume_enabled && st.announce_volume == 60);
        let r = h.handle_set(
            &post_req(
                "/v1/homespeaker",
                r#"{"announce_volume_enabled":true,"announce_volume":45}"#,
            ),
            &phone,
        );
        assert_eq!(r.status, 200);
        let st2 = h.state();
        assert!(st2.announce_volume_enabled && st2.announce_volume == 45);
        let r_bad = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"announce_volume":101}"#),
            &phone,
        );
        assert_eq!(r_bad.status, 400);
    }

    #[test]
    fn test_home_speaker_outputs_default_and_round_trip() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        let st = h.state();
        assert!(st.speak_home && !st.speak_local);
        assert_eq!(st.local_voice, DEFAULT_LOCAL_VOICE);
        assert_eq!(st.local_voice_name, "Aaron");

        let mut cfg = h.read_config().unwrap();
        cfg.insert(
            "local_voice".to_string(),
            JsonValue::String("com.apple.voice.premium.en-US.Zoe".to_string()),
        );
        h.write_config(&cfg).unwrap();

        let r = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"speak_local":true}"#),
            &phone,
        );
        assert_eq!(r.status, 200);
        let st2 = h.state();
        assert!(st2.speak_home && st2.speak_local && st2.local_voice_name == "Zoe");
    }

    #[test]
    fn test_home_speaker_voice_name() {
        for (id, want) in [
            ("com.apple.siri.natural.Aaron", "Aaron"),
            ("com.apple.ttsbundle.siri_Aaron_en-US_premium", "Aaron"),
            ("com.apple.voice.premium.en-US.Zoe", "Zoe"),
            (
                "com.apple.voice.compact.en-US",
                "com.apple.voice.compact.en-US",
            ),
            ("Aaron", "Aaron"),
            ("com.apple.", "com.apple."),
        ] {
            assert_eq!(voice_name(id), want, "voice_name({id:?})");
        }
    }

    #[test]
    fn test_home_speaker_sources_default_and_toggles() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        let resp = h.handle_get(&phone);
        let raw = JsonValue::parse_bytes(&resp.body_bytes()).unwrap();
        assert_eq!(raw.get_opt_bool("announce_claude_code"), Some(true));
        assert_eq!(raw.get_opt_bool("announce_antigravity"), Some(true));
        assert_eq!(raw.get_opt_bool("announce_opencode"), Some(true));
        assert_eq!(raw.get_opt_bool("slack_enabled"), Some(false));
        assert_eq!(raw.get_opt_bool("google_chat_enabled"), Some(false));
        assert_eq!(raw.get_opt_bool("beeper_enabled"), Some(false));
        assert_eq!(raw.get_opt_bool("mute_own_messages"), Some(true));
        assert_eq!(raw.get_str("beeper_announce"), "direct_and_mentions");

        let r = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"beeper_enabled":true}"#),
            &phone,
        );
        assert_eq!(r.status, 200);
        assert_eq!(h.state().beeper_enabled, Some(true));
    }

    #[test]
    fn test_home_speaker_recent_broadcasts() {
        let (h, _, _, _) = new_test_home_speaker(true);
        assert!(h.state().recent.is_empty());
        let base = 789_000_000.0;
        let mut items = Vec::new();
        for i in 0..7 {
            items.push(format!(
                r#"{{"id":"{i}","timestamp":{},"text":"line {i}","targetName":"Kitchen speaker","source":"Claude Code"}}"#,
                base - (i as f64) * 60.0
            ));
        }
        fs::write(&h.history_path, format!("[{}]", items.join(","))).unwrap();
        let st = h.state();
        assert_eq!(st.recent.len(), RECENT_BROADCASTS);
        assert_eq!(st.recent[0].text, "line 0");
        assert_eq!(st.last.as_ref().unwrap().text, "line 0");
    }

    #[test]
    fn test_home_speaker_say_runs_as_a_person() {
        let env = vec![
            "PATH=/usr/bin".to_string(),
            "CLAUDECODE=1".to_string(),
            "ANTIGRAVITY_AGENT=1".to_string(),
            "OPENCODE=1".to_string(),
            "AI_AGENT=claude-code".to_string(),
            "CLAUDECODE_X=keep".to_string(),
            "HOME=/Users/j".to_string(),
        ];
        assert_eq!(
            person_env(&env),
            vec!["PATH=/usr/bin", "CLAUDECODE_X=keep", "HOME=/Users/j"]
        );
    }

    #[test]
    fn test_home_speaker_door_routes_to_extension_when_chosen() {
        let (mut h, _, phone, last) = new_test_home_speaker(true);
        assert_eq!(h.state().active_door, "app");

        let root = temp_dir("ext_root");
        let ext_bin = root
            .join("Tools")
            .join("dev.vitruvian.homespeaker")
            .join("bin")
            .join("tool");
        let data_folder = root.join("ToolData").join("dev.vitruvian.homespeaker");
        fs::create_dir_all(ext_bin.parent().unwrap()).unwrap();
        fs::create_dir_all(&data_folder).unwrap();
        fs::write(&ext_bin, b"#!/bin/sh\n").unwrap();
        fs::write(
            data_folder.join("settings.json"),
            HOME_SPEAKER_CONFIG_FIXTURE,
        )
        .unwrap();
        fs::write(
            data_folder.join("secrets.json"),
            r#"{"google":{"refreshToken":"1//ext-token"},"geminiAPIKey":"AIza-SECRET-GEMINI"}"#,
        )
        .unwrap();

        let lock_path = data_folder.join("running.lock");
        let lock_file = fs::OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .open(&lock_path)
            .unwrap();
        unsafe {
            assert_eq!(flock(lock_file.as_raw_fd(), LOCK_EX | LOCK_NB), 0);
        }

        let door_json = format!(
            r#"{{"version":1,"chosen":"extension","extension":{{"program":"{}","version":"1.19.0","door":1}}}}"#,
            ext_bin.display()
        );
        fs::write(&h.door_path, door_json).unwrap();
        h.running = Some(Arc::new(|| false));

        let st = h.state();
        assert_eq!(st.active_door, "extension");
        assert!(st.available && st.installed && st.app_running);
        assert!(st.signed_in && st.has_gemini_key);

        unsafe {
            let _ = flock(lock_file.as_raw_fd(), LOCK_UN);
        }
        assert!(!h.state().app_running);

        let r = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"default_target":"kitchen"}"#),
            &phone,
        );
        assert_eq!(r.status, 200);
        let r_say = h.handle_say(&post_req(
            "/v1/homespeaker/say",
            r#"{"text":"hello extension"}"#,
        ));
        assert_eq!(r_say.status, 200);
        assert_eq!(last.name(), ext_bin.to_string_lossy());
    }

    #[test]
    fn test_home_speaker_gemini_tts_and_style_defaults_and_custom_voices() {
        let (h, _, phone, _) = new_test_home_speaker(true);
        let st = h.state();
        assert_eq!(st.local_engine, "apple");
        assert_eq!(st.gemini_voice, "Kore");
        assert!(!st.has_gemini_key);
        assert_eq!(st.announcement_style, "verbatim");
        assert_eq!(st.style_model, "apple");

        let mut cfg = h.read_config().unwrap();
        cfg.insert(
            "custom_voices".to_string(),
            JsonValue::parse(r#"[{"id":"clone-james","name":"James"},{"id":"clone-anon"}]"#)
                .unwrap(),
        );
        cfg.insert(
            "gemini_voice".to_string(),
            JsonValue::String("clone-james".to_string()),
        );
        h.write_config(&cfg).unwrap();
        let st2 = h.state();
        assert_eq!(st2.custom_voices.len(), 2);
        assert_eq!(st2.gemini_voice, "clone-james");

        let r = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"gemini_voice":"clone-nobody"}"#),
            &phone,
        );
        assert_eq!(r.status, 400);
        assert!(r.body_string().contains("clone-james"));
    }

    #[test]
    fn test_home_speaker_beeper_networks_and_chat_monitor_parity() {
        let (mut h, _, phone, _) = new_test_home_speaker(true);
        let mut cfg = h.read_config().unwrap();
        cfg.insert(
            "chat_monitor".to_string(),
            JsonValue::parse(
                r#"{"beeper_enabled":true,"beeper_muted_networks":["whatsapp","telegram"],"beeper_token":"keep-secret-token"}"#,
            )
            .unwrap(),
        );
        h.write_config(&cfg).unwrap();
        let status_path = h
            .config_path
            .parent()
            .unwrap()
            .join("speaker_monitor_status.json");
        fs::write(
            &status_path,
            r#"{
              "is_running": true,
              "beeper_network_states": [
                {"key": "whatsapp", "name": "WhatsApp", "state": "reading"},
                {"key": "googlechat", "name": "Google Chat", "state": "skipped"},
                {"key": "matrix", "name": "Beeper", "state": "reading"},
                {"key": "signal", "name": "Signal", "state": "reading"}
              ]
            }"#,
        )
        .unwrap();

        let st = h.state();
        assert_eq!(
            st.beeper_networks,
            vec![
                HomeSpeakerBeeperNetwork {
                    key: "matrix".to_string(),
                    name: "Beeper".to_string(),
                    state: "reading".to_string()
                },
                HomeSpeakerBeeperNetwork {
                    key: "googlechat".to_string(),
                    name: "Google Chat".to_string(),
                    state: "skipped".to_string()
                },
                HomeSpeakerBeeperNetwork {
                    key: "signal".to_string(),
                    name: "Signal".to_string(),
                    state: "reading".to_string()
                },
                HomeSpeakerBeeperNetwork {
                    key: "telegram".to_string(),
                    name: "telegram".to_string(),
                    state: "muted".to_string()
                },
                HomeSpeakerBeeperNetwork {
                    key: "whatsapp".to_string(),
                    name: "WhatsApp".to_string(),
                    state: "muted".to_string()
                },
            ]
        );

        let r = h.handle_set(
            &post_req(
                "/v1/homespeaker",
                r#"{"beeper_network":{"key":"signal","reading":false}}"#,
            ),
            &phone,
        );
        assert_eq!(r.status, 200);
        h.running = Some(Arc::new(|| false));
        let st_stopped = h.state();
        assert_eq!(st_stopped.beeper_networks.len(), 3);
    }

    #[test]
    fn test_home_speaker_is_quiet_hours_active() {
        let now_late = Timestamp::parse_rfc3339("2026-01-01T23:30:00Z").unwrap();
        let now_early = Timestamp::parse_rfc3339("2026-01-01T04:30:00Z").unwrap();
        let now_day = Timestamp::parse_rfc3339("2026-01-01T14:00:00Z").unwrap();
        assert!(!is_quiet_hours_active(false, "22:00", "06:00", now_late));
        assert!(is_quiet_hours_active(true, "22:00", "06:00", now_late));
        assert!(is_quiet_hours_active(true, "22:00", "06:00", now_early));
        assert!(!is_quiet_hours_active(true, "22:00", "06:00", now_day));
        assert!(is_quiet_hours_active(true, "13:00", "15:00", now_day));
    }

    #[test]
    fn test_home_speaker_agent_hooks_and_reset_settings_and_replay() {
        let (h, _, phone, last) = new_test_home_speaker(true);
        let r = h.handle_set(
            &post_req(
                "/v1/homespeaker",
                r#"{"agent_hook_action":"install_claude_hook"}"#,
            ),
            &phone,
        );
        assert_eq!(r.status, 200);
        let st = h.state();
        assert!(st
            .agents
            .iter()
            .any(|a| a.agent == "Claude Code" && a.hook_state == "installed"));

        let r2 = h.handle_set(
            &post_req(
                "/v1/homespeaker",
                r#"{"agent_hook_action":"add_claude_instruction"}"#,
            ),
            &phone,
        );
        assert_eq!(r2.status, 200);
        assert!(fs::read_to_string(&h.claude_md_path)
            .unwrap()
            .contains("speaker-broadcast"));

        let r3 = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"reset_settings":true}"#),
            &phone,
        );
        assert_eq!(r3.status, 200);
        assert!(PathBuf::from(format!("{}.bak", h.config_path.display())).exists());

        // Replay history restoration
        let initial_hist = r#"[{"id":"item-1","text":"First announcement","timestamp":789000,"targetName":"Living Room","source":"claudeCode"},{"id":"item-2","text":"Second announcement","timestamp":789100,"targetName":"Kitchen","source":"user"}]"#;
        fs::write(&h.history_path, initial_hist).unwrap();
        let r_rep = h.handle_say(&post_req(
            "/v1/homespeaker/say",
            r#"{"replay_id":"item-1"}"#,
        ));
        assert_eq!(r_rep.status, 200);
        assert!(last.args().contains(&"First announcement".to_string()));
    }
}
