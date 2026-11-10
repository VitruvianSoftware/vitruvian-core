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

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use vitruvian_remote_macagent_metrics::json::{JsonObject, JsonValue};
use vitruvian_remote_macagent_metrics::time_util::Timestamp;
use vitruvian_remote_macagent_metrics::Tool;

use crate::http_util::{log_act, HttpRequest, HttpResponse};
use crate::phone::{first_text_content, PhoneBridge};
use crate::sampler::run_tool_within;

pub const HOME_SPEAKER_BINARY: &str = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker";
pub const DEFAULT_LOCAL_VOICE: &str = "com.apple.ttsbundle.siri_Aaron_en-US_premium";
pub const RECENT_BROADCASTS: usize = 5;
pub const MAX_PHONE_SAY_BODY: usize = 8 << 20;
pub const PHONE_SAY_TIMEOUT: Duration = Duration::from_secs(60);
pub const SAY_LIMIT: Duration = Duration::from_secs(90);
pub const VOLUME_LIMIT: Duration = Duration::from_secs(45);
/// The oldest Home Speaker that answers `--state` and `--apply`. Older programs would take them
/// for unknown arguments and start their menu-bar app.
pub const MIN_HOME_SPEAKER_VERSION: &str = "1.41.0";
/// Bounds on `--version` and `--state`.
pub const VERSION_LIMIT: Duration = Duration::from_secs(15);
pub const STATE_LIMIT: Duration = Duration::from_secs(15);
/// Bound on one `--apply` (a switch of doors copies files).
pub const APPLY_LIMIT: Duration = Duration::from_secs(120);
/// The `contract_version` of the `--state` document this helper reads.
const STATE_CONTRACT_VERSION: i64 = 1;

/// Returned with HTTP 409 when a sign-in, grant-chat, or disconnect-chat job is already running (`HomeSpeakerTool.swift:2116`).
pub const SIGN_IN_ALREADY_RUNNING: &str = "A HomeSpeaker sign-in is already running on the Mac";
pub const AGENT_MARKERS: &[&str] = &["CLAUDECODE", "ANTIGRAVITY_AGENT", "OPENCODE", "AI_AGENT"];

pub type RunnerFn =
    Arc<dyn Fn(Duration, &str, &[String]) -> Result<(String, String), String> + Send + Sync>;
/// Output of a program run: stdout, stderr and the exit status.
pub type CaptureFn =
    Arc<dyn Fn(Duration, &str, &[String]) -> Result<(String, String, i32), String> + Send + Sync>;
pub type ReadClipboardFn = Arc<dyn Fn() -> Result<String, String> + Send + Sync>;

#[derive(Clone)]
pub struct HomeSpeaker {
    /// The app's program. The extension's is named by the choice file.
    pub binary: PathBuf,
    /// The choice file (`speaker_door.json`): read only, to learn which program is chosen.
    pub door_path: PathBuf,
    pub run: RunnerFn,
    /// Like `run`, but keeps stdout when the program exits non-zero (`--apply` explains a refusal there).
    pub run_capture: Option<CaptureFn>,
    pub launch: Option<RunnerFn>,
    pub say: Option<RunnerFn>,
    pub read_clipboard: Option<ReadClipboardFn>,
    /// Single-flight counter for sign-in / grant-chat / disconnect-chat jobs.
    pub sign_in_busy: Arc<AtomicUsize>,
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
    /// Courier only: read through Courier although HomeSpeaker's own Slack
    /// or Google Chat reader covers it (`chat_monitor.courier_read_anyway`).
    /// Sent only when true, so Beeper's rows keep their shape.
    pub read_anyway: bool,
}

impl HomeSpeakerBeeperNetwork {
    pub fn to_json(&self) -> JsonValue {
        let mut m = JsonObject::new();
        m.insert("key".to_string(), JsonValue::String(self.key.clone()));
        m.insert("name".to_string(), JsonValue::String(self.name.clone()));
        m.insert("state".to_string(), JsonValue::String(self.state.clone()));
        if self.read_anyway {
            m.insert("read_anyway".to_string(), JsonValue::Bool(true));
        }
        JsonValue::Object(m)
    }
}

/// `courier_read_anyway`: read one of Courier's networks although
/// HomeSpeaker's own reader covers it (`on`), or leave it to that reader.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerReadAnywayUpdate {
    pub key: String,
    pub on: bool,
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
    pub extension_installed: bool,
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
    pub snooze_until: Option<String>,
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
    pub has_courier_token: bool,
    pub has_google_chat_token: bool,
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
    /// The running monitor has listed Beeper's networks; until it has,
    /// only the saved mutes are known.
    pub beeper_networks_listed: bool,
    pub courier_enabled: Option<bool>,
    pub courier_announce: String,
    pub courier_networks: Vec<HomeSpeakerBeeperNetwork>,
    pub courier_networks_listed: bool,
    pub mute_own_messages: Option<bool>,
    pub recent: Vec<HomeSpeakerLast>,
    /// Home Speaker's own warnings about its setup.
    pub warnings: Vec<String>,
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
            extension_installed: false,
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
            snooze_until: None,
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
            has_courier_token: false,
            has_google_chat_token: false,
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
            beeper_networks_listed: false,
            courier_enabled: None,
            courier_announce: String::new(),
            courier_networks: Vec::new(),
            courier_networks_listed: false,
            mute_own_messages: None,
            recent: Vec::new(),
            warnings: Vec::new(),
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
        m.insert(
            "extension_installed".to_string(),
            JsonValue::Bool(self.extension_installed),
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
        m.insert(
            "snooze_until".to_string(),
            match self.snooze_until {
                Some(ref s) => JsonValue::String(s.clone()),
                None => JsonValue::Null,
            },
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
            "has_courier_token".to_string(),
            JsonValue::Bool(self.has_courier_token),
        );
        m.insert(
            "has_google_chat_token".to_string(),
            JsonValue::Bool(self.has_google_chat_token),
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
            "beeper_networks_listed".to_string(),
            JsonValue::Bool(self.beeper_networks_listed),
        );
        m.insert(
            "courier_enabled".to_string(),
            match self.courier_enabled {
                Some(b) => JsonValue::Bool(b),
                None => JsonValue::Null,
            },
        );
        m.insert(
            "courier_announce".to_string(),
            JsonValue::String(self.courier_announce.clone()),
        );
        m.insert(
            "courier_networks".to_string(),
            JsonValue::Array(self.courier_networks.iter().map(|n| n.to_json()).collect()),
        );
        m.insert(
            "courier_networks_listed".to_string(),
            JsonValue::Bool(self.courier_networks_listed),
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
        m.insert(
            "warnings".to_string(),
            JsonValue::Array(
                self.warnings
                    .iter()
                    .map(|w| JsonValue::String(w.clone()))
                    .collect(),
            ),
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
    pub snooze_until: Option<String>,
    pub snooze_minutes: Option<i64>,
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
    pub sign_in: bool,
    pub sign_out: bool,
    pub import_antigravity: bool,
    pub grant_chat: bool,
    pub disconnect_chat: bool,
    pub speak_clipboard: bool,
    pub google_chat_source: Option<String>,
    pub gws_account: Option<String>,
    pub poll_interval: Option<i64>,
    pub slack_token: Option<String>,
    pub beeper_token: Option<String>,
    pub courier_token: Option<String>,
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
    pub courier_enabled: Option<bool>,
    pub courier_announce: Option<String>,
    pub courier_network: Option<HomeSpeakerBeeperNetworkUpdate>,
    pub courier_read_anyway: Option<HomeSpeakerReadAnywayUpdate>,
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
            && self.snooze_until.is_none()
            && self.snooze_minutes.is_none()
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
            && !self.sign_in
            && !self.sign_out
            && !self.import_antigravity
            && !self.grant_chat
            && !self.disconnect_chat
            && !self.speak_clipboard
            && self.google_chat_source.is_none()
            && self.gws_account.is_none()
            && self.poll_interval.is_none()
            && self.slack_token.is_none()
            && self.beeper_token.is_none()
            && self.courier_token.is_none()
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
            && self.courier_enabled.is_none()
            && self.courier_announce.is_none()
            && self.courier_network.is_none()
            && self.courier_read_anyway.is_none()
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
        u.snooze_until = match obj.get("snooze_until") {
            None => None,
            Some(JsonValue::Null) => Some(String::new()),
            Some(JsonValue::String(s)) => Some(s.clone()),
            Some(_) => return Err("cannot unmarshal snooze_until into string".to_string()),
        };
        u.snooze_minutes = opt_i64(obj, "snooze_minutes")?;
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
        u.sign_in = opt_bool(obj, "sign_in")?.unwrap_or(false);
        u.sign_out = opt_bool(obj, "sign_out")?.unwrap_or(false);
        u.import_antigravity = opt_bool(obj, "import_antigravity")?.unwrap_or(false);
        u.grant_chat = opt_bool(obj, "grant_chat")?.unwrap_or(false);
        u.disconnect_chat = opt_bool(obj, "disconnect_chat")?.unwrap_or(false);
        u.speak_clipboard = opt_bool(obj, "speak_clipboard")?.unwrap_or(false);
        u.google_chat_source = opt_str(obj, "google_chat_source")?;
        u.gws_account = opt_str(obj, "gws_account")?;
        u.poll_interval = opt_i64(obj, "poll_interval")?;
        u.slack_token = opt_str(obj, "slack_token")?;
        u.beeper_token = opt_str(obj, "beeper_token")?;
        u.courier_token = opt_str(obj, "courier_token")?;
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
        fn opt_network(
            obj: &JsonObject,
            field: &str,
            flag: &str,
        ) -> Result<Option<(String, bool)>, String> {
            match obj.get(field) {
                None | Some(JsonValue::Null) => Ok(None),
                Some(v) => {
                    let o = v
                        .as_object()
                        .ok_or_else(|| format!("cannot unmarshal {field}"))?;
                    let key = o
                        .get("key")
                        .and_then(|x| x.as_str())
                        .unwrap_or("")
                        .to_string();
                    let on = o.get(flag).and_then(|x| x.as_bool()).unwrap_or(false);
                    Ok(Some((key, on)))
                }
            }
        }
        u.beeper_network = opt_network(obj, "beeper_network", "reading")?
            .map(|(key, reading)| HomeSpeakerBeeperNetworkUpdate { key, reading });
        u.courier_enabled = opt_bool(obj, "courier_enabled")?;
        u.courier_announce = opt_str(obj, "courier_announce")?;
        u.courier_network = opt_network(obj, "courier_network", "reading")?
            .map(|(key, reading)| HomeSpeakerBeeperNetworkUpdate { key, reading });
        u.courier_read_anyway = opt_network(obj, "courier_read_anyway", "on")?
            .map(|(key, on)| HomeSpeakerReadAnywayUpdate { key, on });
        u.mute_own_messages = opt_bool(obj, "mute_own_messages")?;
        Ok(u)
    }
}

#[derive(Clone, Debug)]
pub enum ApplyError {
    BadRequest(String),
    Conflict(String),
    Internal(String),
}

impl ApplyError {
    pub fn message(&self) -> &str {
        match self {
            ApplyError::BadRequest(s) | ApplyError::Conflict(s) | ApplyError::Internal(s) => s,
        }
    }
}

pub fn is_in_trash(path: &str) -> bool {
    path.contains("/.Trash/") || path.contains("/.Trashes/")
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

pub fn parse_snooze_timestamp(s: &str) -> Result<Timestamp, ApplyError> {
    let trimmed = s.trim();
    if trimmed.len() < 20 || !trimmed.is_ascii() {
        return Err(ApplyError::BadRequest(format!(
            "invalid snooze_until {s:?}; must be ISO-8601 timestamp"
        )));
    }
    let year: i32 = trimmed[0..4].parse().map_err(|_| {
        ApplyError::BadRequest(format!(
            "invalid snooze_until {s:?}; must be ISO-8601 timestamp"
        ))
    })?;
    let month: u32 = trimmed[5..7].parse().map_err(|_| {
        ApplyError::BadRequest(format!(
            "invalid snooze_until {s:?}; must be ISO-8601 timestamp"
        ))
    })?;
    let day: u32 = trimmed[8..10].parse().map_err(|_| {
        ApplyError::BadRequest(format!(
            "invalid snooze_until {s:?}; must be ISO-8601 timestamp"
        ))
    })?;
    let (cy, cm, cd, _, _, _) = Timestamp::from_ymd_hms(year, month, day, 0, 0, 0).ymd_hms();
    if (cy, cm, cd) != (year, month, day) {
        return Err(ApplyError::BadRequest(format!(
            "invalid snooze_until {s:?}; must be ISO-8601 timestamp"
        )));
    }
    let ts = Timestamp::parse_rfc3339(trimmed).map_err(|_| {
        ApplyError::BadRequest(format!(
            "invalid snooze_until {s:?}; must be ISO-8601 timestamp"
        ))
    })?;
    if ts.is_zero() {
        return Err(ApplyError::BadRequest(format!(
            "invalid snooze_until {s:?}; must be ISO-8601 timestamp"
        )));
    }
    Ok(ts)
}

pub fn preview_say_args(voice: &str, text: &str) -> Vec<Vec<String>> {
    let mut candidates = Vec::new();
    let trimmed = voice.trim();
    if !trimmed.is_empty() && trimmed != "default" && trimmed != DEFAULT_LOCAL_VOICE {
        let name = voice_name(trimmed);
        if !name.is_empty() && name != trimmed {
            candidates.push(vec!["-v".to_string(), name, text.to_string()]);
        }
        candidates.push(vec![
            "-v".to_string(),
            trimmed.to_string(),
            text.to_string(),
        ]);
    } else if trimmed == DEFAULT_LOCAL_VOICE {
        let name = voice_name(trimmed);
        if !name.is_empty() {
            candidates.push(vec!["-v".to_string(), name, text.to_string()]);
        }
    }
    candidates.push(vec![text.to_string()]);
    candidates
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

pub fn spawn_as_person_detached(name: &str, args: &[String]) -> Result<(String, String), String> {
    spawn_as_person_detached_with_busy(name, args, None)
}

fn spawn_as_person_detached_with_busy(
    name: &str,
    args: &[String],
    busy: Option<Arc<AtomicUsize>>,
) -> Result<(String, String), String> {
    let mut cmd = Command::new(name);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    for marker in AGENT_MARKERS {
        cmd.env_remove(marker);
    }
    let mut child = cmd.spawn().map_err(|e| e.to_string())?;
    if let Some(ref b) = busy {
        b.fetch_add(1, Ordering::SeqCst);
    }
    std::thread::spawn(move || {
        let _ = child.wait();
        if let Some(b) = busy {
            b.fetch_sub(1, Ordering::SeqCst);
        }
    });
    Ok((String::new(), String::new()))
}

fn file_exists(p: &Path) -> bool {
    !p.as_os_str().is_empty() && p.exists()
}

struct SignInBusyGuard {
    busy: Arc<AtomicUsize>,
}

impl Drop for SignInBusyGuard {
    fn drop(&mut self) {
        self.busy.fetch_sub(1, Ordering::SeqCst);
    }
}

impl HomeSpeaker {
    pub fn new() -> Self {
        let home = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/tmp"));
        let sign_in_busy = Arc::new(AtomicUsize::new(0));
        let launch_busy = sign_in_busy.clone();
        Self {
            door_path: home.join(".gemini").join("speaker_door.json"),
            binary: PathBuf::from(HOME_SPEAKER_BINARY),
            run: Arc::new(|limit, name, args| {
                let (out, err_s, err_opt) = run_tool_within(limit, name, args, None);
                match err_opt {
                    Some(e) => Err(e),
                    None => Ok((out, err_s)),
                }
            }),
            run_capture: Some(Arc::new(run_capturing_exit)),
            launch: Some(Arc::new(move |_limit, name, args| {
                spawn_as_person_detached_with_busy(name, args, Some(launch_busy.clone()))
            })),
            say: Some(Arc::new(|limit, name, args| {
                run_as_person_within(limit, name, args)
            })),
            read_clipboard: Some(Arc::new(|| {
                let out = Command::new("pbpaste")
                    .output()
                    .map_err(|e| e.to_string())?;
                Ok(String::from_utf8_lossy(&out.stdout).into_owned())
            })),
            sign_in_busy,
        }
    }

    fn acquire_sign_in_busy(&self) -> Result<SignInBusyGuard, ApplyError> {
        self.sign_in_busy
            .compare_exchange(0, 1, Ordering::SeqCst, Ordering::SeqCst)
            .map(|_| SignInBusyGuard {
                busy: self.sign_in_busy.clone(),
            })
            .map_err(|_| ApplyError::Conflict(SIGN_IN_ALREADY_RUNNING.to_string()))
    }

    fn launch_or_run(
        &self,
        limit: Duration,
        name: &str,
        args: &[String],
    ) -> Result<(String, String), String> {
        let runner = self.launch.as_ref().unwrap_or(&self.run);
        runner(limit, name, args)
    }

    /// HomeSpeaker as a `/v1/tools` entry: present when the active door's program exists, or when
    /// only the Vitruvian extension is installed (no `/Applications/HomeSpeaker.app`). Checking the
    /// app bundle alone hid HomeSpeaker on extension-only Macs.
    pub fn tool(&self) -> Tool {
        let p = self.active_program();
        if file_exists(&p.binary) {
            return Tool {
                available: true,
                path: p.binary.to_string_lossy().into_owned(),
            };
        }
        if let Some(program) = self.extension_program() {
            return Tool {
                available: true,
                path: program,
            };
        }
        Tool {
            available: false,
            path: p.binary.to_string_lossy().into_owned(),
        }
    }

    /// The choice file, parsed. The helper only ever reads it, to learn which program is chosen.
    fn door_file(&self) -> Option<JsonValue> {
        if self.door_path.as_os_str().is_empty() {
            return None;
        }
        JsonValue::parse(&fs::read_to_string(&self.door_path).ok()?).ok()
    }

    /// The extension's program named in the choice file, when it is there to run.
    fn extension_program(&self) -> Option<String> {
        let door = self.door_file()?;
        let ext = door.as_object()?.get("extension")?.as_object()?;
        if ext.get("door").and_then(|v| v.as_i64()).unwrap_or(0) < 1 {
            return None;
        }
        let prog = ext.get("program").and_then(|v| v.as_str()).unwrap_or("");
        (!prog.is_empty() && !is_in_trash(prog) && Path::new(prog).exists())
            .then(|| prog.to_string())
    }

    pub fn extension_installed(&self) -> bool {
        self.extension_program().is_some()
    }

    /// The program the helper talks to: the app or the extension, as the choice file says.
    pub fn active_program(&self) -> HomeSpeakerProgram {
        let app = HomeSpeakerProgram {
            door: "app".to_string(),
            binary: self.binary.clone(),
        };
        let (Some(door), Some(ext)) = (self.door_file(), self.extension_program()) else {
            return app;
        };
        let use_extension = match door
            .as_object()
            .and_then(|o| o.get("chosen"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
        {
            "extension" => true,
            "" => !(self.binary.exists() && !is_in_trash(&self.binary.to_string_lossy())),
            _ => false,
        };
        if use_extension {
            HomeSpeakerProgram {
                door: "extension".to_string(),
                binary: PathBuf::from(ext),
            }
        } else {
            app
        }
    }

    /// Runs one Home Speaker command and keeps its output even when it exits non-zero:
    /// `--apply` explains a refusal in JSON on stdout and exits 1.
    fn call_program(
        &self,
        limit: Duration,
        program: &HomeSpeakerProgram,
        args: &[String],
    ) -> Result<(String, String, i32), String> {
        let name = program.binary.to_string_lossy();
        if let Some(capture) = self.run_capture.as_ref() {
            return capture(limit, &name, args);
        }
        // A plain runner reports a non-zero exit as "exit status N", without the output.
        match (self.run)(limit, &name, args) {
            Ok((out, err)) => Ok((out, err, 0)),
            Err(e) => match e
                .strip_prefix("exit status ")
                .and_then(|n| n.trim().parse().ok())
            {
                Some(code) => Ok((String::new(), String::new(), code)),
                None => Err(e),
            },
        }
    }

    /// Asks `program` for its version, once per request (`verified` remembers who has answered).
    /// Below `MIN_HOME_SPEAKER_VERSION` nothing else may be run on it: an old program would
    /// read `--state` as an unknown argument and start its menu-bar app.
    fn check_version(
        &self,
        program: &HomeSpeakerProgram,
        verified: &mut Vec<PathBuf>,
    ) -> Result<(), VersionProblem> {
        if verified.contains(&program.binary) {
            return Ok(());
        }
        let args = vec!["--version".to_string()];
        let (stdout, _, code) = self
            .call_program(VERSION_LIMIT, program, &args)
            .map_err(VersionProblem::Unreadable)?;
        if code != 0 {
            return Err(VersionProblem::Unreadable(format!(
                "--version exited with status {code}"
            )));
        }
        let Some(have) = parse_version_output(&stdout) else {
            return Err(VersionProblem::Unreadable(
                "it did not print a version".to_string(),
            ));
        };
        if version_at_least(&have, MIN_HOME_SPEAKER_VERSION) {
            verified.push(program.binary.clone());
            return Ok(());
        }
        Err(VersionProblem::TooOld(format!(
            "Update Home Speaker on {} (have {have}, need {MIN_HOME_SPEAKER_VERSION})",
            crate::sampler::get_hostname()
        )))
    }

    /// `--state --json` from `program`, after the version gate.
    fn fetch_state_doc(
        &self,
        program: &HomeSpeakerProgram,
        verified: &mut Vec<PathBuf>,
    ) -> Result<JsonValue, String> {
        match self.check_version(program, verified) {
            Ok(()) => {}
            Err(VersionProblem::TooOld(sentence)) => return Err(sentence),
            Err(VersionProblem::Unreadable(e)) => {
                return Err(format!("Could not read the Home Speaker version: {e}"))
            }
        }
        let args = vec!["--state".to_string(), "--json".to_string()];
        let (stdout, _, code) = self
            .call_program(STATE_LIMIT, program, &args)
            .map_err(|e| format!("Home Speaker did not answer --state: {e}"))?;
        if code != 0 {
            return Err(format!("Home Speaker's --state exited with status {code}"));
        }
        let doc = JsonValue::parse(stdout.trim())
            .map_err(|_| "Home Speaker's --state answer was not JSON".to_string())?;
        let Some(obj) = doc.as_object() else {
            return Err("Home Speaker's --state answer was not a JSON object".to_string());
        };
        match obj.get("contract_version").and_then(|v| v.as_i64()) {
            Some(STATE_CONTRACT_VERSION) => Ok(doc),
            other => Err(format!(
                "Home Speaker answered --state in contract version {}, this helper reads {STATE_CONTRACT_VERSION}",
                other.map(|n| n.to_string()).unwrap_or_else(|| "none".to_string())
            )),
        }
    }

    pub fn state(&self) -> HomeSpeakerState {
        self.state_checked(&mut Vec::new())
    }

    fn state_checked(&self, verified: &mut Vec<PathBuf>) -> HomeSpeakerState {
        let program = self.active_program();
        let mut st = HomeSpeakerState {
            active_door: program.door.clone(),
            extension_installed: self.extension_installed(),
            ..Default::default()
        };
        if !file_exists(&program.binary) {
            st.reason = format!(
                "HomeSpeaker is not installed at {}",
                program.binary.display()
            );
            return st;
        }
        st.installed = true;
        match self.check_version(&program, verified) {
            Ok(()) => {}
            Err(VersionProblem::TooOld(sentence)) => {
                st.reason = sentence;
                return st;
            }
            Err(VersionProblem::Unreadable(e)) => {
                st.reason = format!("Could not read the Home Speaker version: {e}");
                return st;
            }
        }
        match self.fetch_state_doc(&program, verified) {
            Ok(doc) => map_state_doc(&doc, &program, st),
            Err(e) => {
                st.reason = e;
                st
            }
        }
    }

    fn say_preview_voice(&self, voice: &str) -> Result<(), ApplyError> {
        const PREVIEW_TEXT: &str = "This is how announcements will sound.";
        let mut last_err = String::new();
        for say_args in preview_say_args(voice, PREVIEW_TEXT) {
            match (self.run)(Duration::from_secs(10), "say", &say_args) {
                Ok(_) => return Ok(()),
                Err(e) => last_err = e,
            }
        }
        Err(ApplyError::Internal(format!(
            "preview voice failed: {last_err}"
        )))
    }

    /// Applies one phone update: Home Speaker's own `--apply` for settings, secrets, snooze, chat
    /// networks, hooks and the door; its command-line flags for sign-in, discovery, speech and the
    /// chat monitor. Order: the plain batch, the flag commands, then `agentHook`, then `switchTo`
    /// last (a switch changes which program is chosen). The first failure stops everything.
    pub fn apply(&self, u: HomeSpeakerUpdate) -> Result<String, ApplyError> {
        self.apply_checked(u, &mut Vec::new())
    }

    fn apply_checked(
        &self,
        u: HomeSpeakerUpdate,
        verified: &mut Vec<PathBuf>,
    ) -> Result<String, ApplyError> {
        let current_id = if u.oauth_client_id.is_none() && u.oauth_client_secret.is_some() {
            let doc = self
                .fetch_state_doc(&self.active_program(), verified)
                .map_err(ApplyError::Conflict)?;
            doc.get("sign_in")
                .map(|s| s.get_str("custom_oauth_client_id").to_string())
        } else {
            None
        };
        let plan = plan_ops_with(&u, current_id.as_deref())?;
        let mut changed = Vec::new();
        if !plan.plain.is_empty() {
            self.run_apply(&plan.plain, verified)?;
            changed.extend(plan.plain.iter().map(op_summary));
        }

        let program = self.active_program();
        let bin_str = program.binary.to_string_lossy().into_owned();
        if u.test_media_pause {
            let args = vec!["--test-media-pause".to_string()];
            (self.run)(Duration::from_secs(30), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("test media pause failed: {e}")))?;
            changed.push("test_media_pause".to_string());
        }
        if u.discover {
            let args = vec!["--discover".to_string(), "--save".to_string()];
            (self.run)(Duration::from_secs(60), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("discover failed: {e}")))?;
            changed.push("discover".to_string());
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
        }
        if u.sign_in {
            if !file_exists(&program.binary) {
                return Err(ApplyError::BadRequest(format!(
                    "HomeSpeaker is not installed at {}",
                    program.binary.display()
                )));
            }
            let _busy = self.acquire_sign_in_busy()?;
            let args = vec!["--sign-in".to_string()];
            self.launch_or_run(Duration::from_secs(300), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("sign in failed: {e}")))?;
            changed.push("sign_in".to_string());
        }
        if u.sign_out {
            let args = vec!["--sign-out".to_string()];
            (self.run)(Duration::from_secs(30), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("sign out failed: {e}")))?;
            changed.push("sign_out".to_string());
        }
        if u.grant_chat {
            if !file_exists(&program.binary) {
                return Err(ApplyError::BadRequest(format!(
                    "HomeSpeaker is not installed at {}",
                    program.binary.display()
                )));
            }
            let _busy = self.acquire_sign_in_busy()?;
            let args = vec!["--sign-in".to_string(), "--chat".to_string()];
            self.launch_or_run(Duration::from_secs(300), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("grant chat failed: {e}")))?;
            changed.push("grant_chat".to_string());
        }
        if u.disconnect_chat {
            let _busy = self.acquire_sign_in_busy()?;
            let args = vec!["--sign-out".to_string(), "--chat".to_string()];
            (self.run)(Duration::from_secs(30), &bin_str, &args)
                .map_err(|e| ApplyError::Internal(format!("disconnect chat failed: {e}")))?;
            changed.push("disconnect_chat".to_string());
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
        if u.preview_voice {
            let doc = self
                .fetch_state_doc(&program, verified)
                .map_err(ApplyError::Conflict)?;
            let voice = doc
                .as_object()
                .map(|d| DocSettings::of(d).str("local_voice"))
                .filter(|v| !v.trim().is_empty())
                .unwrap_or_else(|| DEFAULT_LOCAL_VOICE.to_string());
            self.say_preview_voice(&voice)?;
            changed.push("preview_voice".to_string());
        }

        if let Some(hook) = plan.hook {
            self.run_apply(std::slice::from_ref(&hook), verified)?;
            changed.push(op_summary(&hook));
        }
        if let Some(switch) = plan.switch {
            self.run_apply(std::slice::from_ref(&switch), verified)?;
            changed.push(op_summary(&switch));
        }
        Ok(changed.join(" "))
    }

    /// Sends `ops` to the chosen program's `--apply`. One batch, one call. A `not_chosen`
    /// refusal means the choice file this helper read was stale: read it again and retry once
    /// on the program it names.
    fn run_apply(&self, ops: &[JsonValue], verified: &mut Vec<PathBuf>) -> Result<(), ApplyError> {
        let mut program = self.active_program();
        let mut retried = false;
        loop {
            if !file_exists(&program.binary) {
                return Err(ApplyError::Conflict(format!(
                    "HomeSpeaker is not installed at {}",
                    program.binary.display()
                )));
            }
            match self.check_version(&program, verified) {
                Ok(()) => {}
                Err(VersionProblem::TooOld(sentence)) => {
                    return Err(ApplyError::Conflict(sentence))
                }
                Err(VersionProblem::Unreadable(e)) => {
                    return Err(ApplyError::Internal(format!(
                        "Could not read the Home Speaker version: {e}"
                    )))
                }
            }
            let mut envelope = JsonObject::new();
            envelope.insert(
                "contract_version",
                JsonValue::from_i64(STATE_CONTRACT_VERSION),
            );
            envelope.insert("operations", JsonValue::Array(ops.to_vec()));
            let args = vec![
                "--apply".to_string(),
                "--json".to_string(),
                JsonValue::Object(envelope).to_json_string(),
            ];
            let (stdout, _, exit) =
                self.call_program(APPLY_LIMIT, &program, &args)
                    .map_err(|e| {
                        ApplyError::Internal(format!("Home Speaker did not answer --apply: {e}"))
                    })?;
            // A refusal exits 1 with a JSON error: a valid answer. A non-zero exit without
            // JSON, or "ok" with a failing exit, is an error.
            let answer = JsonValue::parse(stdout.trim()).map_err(|_| {
                ApplyError::Internal(if exit != 0 {
                    format!("Home Speaker's --apply exited with status {exit}")
                } else {
                    "Home Speaker's --apply answer was not JSON".to_string()
                })
            })?;
            if answer.get_opt_bool("ok") == Some(true) {
                return if exit == 0 {
                    Ok(())
                } else {
                    Err(ApplyError::Internal(format!(
                        "Home Speaker's --apply exited with status {exit}"
                    )))
                };
            }
            let err = answer.get("error");
            let code = err.map(|e| e.get_str("code")).unwrap_or("");
            let message = err
                .map(|e| e.get_str("message"))
                .filter(|m| !m.is_empty())
                .unwrap_or("Home Speaker refused the change")
                .to_string();
            if code == "not_chosen" && !retried {
                let named = err
                    .and_then(|e| e.get_opt_str("chosen"))
                    .and_then(|door| self.program_for_door(&door));
                if let Some(next) = named {
                    program = next;
                    retried = true;
                    continue;
                }
            }
            return Err(match code {
                "not_chosen" => ApplyError::Conflict(message),
                "timed_out" | "apply_failed" | "config_unreadable" => ApplyError::Internal(message),
                _ => ApplyError::BadRequest(message),
            });
        }
    }

    /// The program for `door`, read from the choice file now.
    fn program_for_door(&self, door: &str) -> Option<HomeSpeakerProgram> {
        let binary = match door {
            "app" => self.binary.clone(),
            "extension" => PathBuf::from(self.extension_program()?),
            _ => return None,
        };
        file_exists(&binary).then(|| HomeSpeakerProgram {
            door: door.to_string(),
            binary,
        })
    }

    pub fn run_volume(&self, args: &[String]) -> HomeSpeakerVolume {
        let p = self.active_program();
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
                "nothing to change: give enabled, default_target, speech_length, quiet_hours_enabled, pause_media, pause_media_extra_seconds, announce_volume_enabled, announce_volume, speak_home, speak_local, speak_phone, phone_pause_media, phone_headphones_only, local_engine, gemini_voice, announcement_style, style_model, announce_claude_code, announce_antigravity, announce_opencode, slack_enabled, google_chat_enabled, beeper_enabled, beeper_announce, beeper_network, courier_enabled, courier_announce, courier_network, courier_read_anyway or mute_own_messages",
            );
        }
        let mut verified = Vec::new();
        match self.apply_checked(body, &mut verified) {
            Ok(changed) => {
                log_act("homespeaker", &changed);
                let mut st = self.state_checked(&mut verified);
                st.phone_connected = phone.connected();
                HttpResponse::json(200, &st.to_json())
            }
            Err(ApplyError::BadRequest(msg)) => HttpResponse::error(400, &msg),
            Err(ApplyError::Conflict(msg)) => HttpResponse::error(409, &msg),
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
        if text.is_empty() && replay_id.is_empty() {
            return HttpResponse::error(400, "text is required");
        }
        let p = self.active_program();
        if !file_exists(&p.binary) {
            return HttpResponse::error(
                409,
                &format!("HomeSpeaker is not installed at {}", p.binary.display()),
            );
        }
        let is_replay = replay || !replay_id.is_empty();
        if is_replay {
            // `--no-history` arrives with the minimum version: gate it. Plain say is not gated.
            match self.check_version(&p, &mut Vec::new()) {
                Ok(()) => {}
                Err(VersionProblem::TooOld(sentence)) => {
                    return HttpResponse::error(409, &sentence)
                }
                Err(VersionProblem::Unreadable(e)) => {
                    return HttpResponse::error(
                        409,
                        &format!("Could not read the Home Speaker version: {e}"),
                    )
                }
            }
        }
        if !replay_id.is_empty() {
            // The history is Home Speaker's: ask it, do not read its file.
            let doc = match self.fetch_state_doc(&p, &mut Vec::new()) {
                Ok(d) => d,
                Err(e) => return HttpResponse::error(409, &e),
            };
            let found = doc
                .get_array("recent")
                .unwrap_or(&[])
                .iter()
                .find(|r| r.get_str("id") == replay_id)
                .map(|r| r.get_str("text").to_string());
            match found {
                Some(t) => text = t,
                None => {
                    return HttpResponse::error(
                        400,
                        "That announcement is no longer in the history",
                    )
                }
            }
        }
        if text.is_empty() {
            return HttpResponse::error(400, "text is required");
        }
        let log_label = if is_replay {
            format!("replay {text}")
        } else {
            format!("say {text}")
        };
        log_act("homespeaker", &log_label);

        let run = self.say.as_ref().unwrap_or(&self.run);
        let bin_str = p.binary.to_string_lossy().into_owned();
        let mut args = vec!["--say".to_string(), text];
        if is_replay {
            // A replay is not a new announcement: keep it out of the history.
            args.push("--no-history".to_string());
        }
        let res = run(SAY_LIMIT, &bin_str, &args);
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
        // What the phone was not told, Home Speaker's settings say.
        let doc = self
            .fetch_state_doc(&self.active_program(), &mut Vec::new())
            .ok();
        let setting = |key: &str| {
            doc.as_ref()
                .and_then(|d| d.as_object())
                .and_then(|d| DocSettings::of(d).bool(key))
        };
        let pause_media = obj
            .get("pause_media")
            .and_then(|v| v.as_bool())
            .or_else(|| setting("phone_pause_media"))
            .unwrap_or(false);
        let headphones_only = obj
            .get("headphones_only")
            .and_then(|v| v.as_bool())
            .or_else(|| setting("phone_headphones_only"))
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

/// Runs `name` and keeps its output when it exits non-zero; only a failure to start it, or the
/// time limit, is an error.
pub fn run_capturing_exit(
    limit: Duration,
    name: &str,
    args: &[String],
) -> Result<(String, String, i32), String> {
    let (out, err, failure) = run_tool_within(limit, name, args, None);
    match failure {
        None => Ok((out, err, 0)),
        Some(e) => match e
            .strip_prefix("exit status ")
            .and_then(|n| n.trim().parse().ok())
        {
            Some(code) => Ok((out, err, code)),
            None => Err(e),
        },
    }
}

/// The program the helper talks to.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HomeSpeakerProgram {
    pub door: String,
    pub binary: PathBuf,
}

enum VersionProblem {
    /// The update sentence, ready to show.
    TooOld(String),
    Unreadable(String),
}

/// The version in `HomeSpeaker --version`'s answer ("HomeSpeaker 1.41.0").
fn parse_version_output(out: &str) -> Option<String> {
    let line = out.lines().map(str::trim).find(|l| !l.is_empty())?;
    let token = line.split_whitespace().last()?.trim_start_matches('v');
    let numbers: Vec<&str> = token.split(['-', '+']).next()?.split('.').collect();
    if (2..=3).contains(&numbers.len()) && numbers.iter().all(|p| p.parse::<u64>().is_ok()) {
        Some(token.to_string())
    } else {
        None
    }
}

fn version_parts(v: &str) -> Vec<u64> {
    v.split(['-', '+'])
        .next()
        .unwrap_or("")
        .split('.')
        .map(|p| p.parse::<u64>().unwrap_or(0))
        .collect()
}

/// `have >= need`, comparing dotted numbers part by part.
pub fn version_at_least(have: &str, need: &str) -> bool {
    let (h, n) = (version_parts(have), version_parts(need));
    for i in 0..h.len().max(n.len()) {
        let (a, b) = (
            h.get(i).copied().unwrap_or(0),
            n.get(i).copied().unwrap_or(0),
        );
        if a != b {
            return a > b;
        }
    }
    true
}

fn doc_str(o: &JsonObject, key: &str) -> String {
    o.get(key)
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
}

fn doc_bool(o: &JsonObject, key: &str) -> bool {
    o.get(key).and_then(|v| v.as_bool()).unwrap_or(false)
}

fn doc_obj<'a>(o: &'a JsonObject, key: &str) -> Option<&'a JsonObject> {
    o.get(key).and_then(|v| v.as_object())
}

fn doc_entry(o: &JsonObject) -> Option<HomeSpeakerLast> {
    let at = Timestamp::parse_rfc3339(o.get("at")?.as_str()?).ok()?;
    Some(HomeSpeakerLast {
        id: doc_str(o, "id"),
        text: doc_str(o, "text"),
        target: doc_str(o, "target"),
        source: doc_str(o, "source"),
        at,
    })
}

/// Reads the settings out of the document by key.
struct DocSettings<'a>(Vec<(&'a str, &'a JsonValue)>);

impl<'a> DocSettings<'a> {
    fn of(doc: &'a JsonObject) -> Self {
        let mut v = Vec::new();
        if let Some(items) = doc.get("settings").and_then(|s| s.as_array()) {
            for item in items {
                if let Some(o) = item.as_object() {
                    if let (Some(k), Some(val)) =
                        (o.get("key").and_then(|k| k.as_str()), o.get("value"))
                    {
                        v.push((k, val));
                    }
                }
            }
        }
        Self(v)
    }
    fn get(&self, key: &str) -> Option<&JsonValue> {
        self.0.iter().find(|(k, _)| *k == key).map(|(_, v)| *v)
    }
    fn bool(&self, key: &str) -> Option<bool> {
        self.get(key).and_then(|v| v.as_bool())
    }
    fn str(&self, key: &str) -> String {
        self.get(key)
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string()
    }
    fn i64(&self, key: &str) -> i64 {
        self.get(key)
            .and_then(|v| v.as_f64())
            .map(|n| n as i64)
            .unwrap_or(0)
    }
    fn f64(&self, key: &str) -> f64 {
        self.get(key).and_then(|v| v.as_f64()).unwrap_or(0.0)
    }
}

fn doc_networks(chat: &JsonObject, key: &str) -> Vec<HomeSpeakerBeeperNetwork> {
    let mut out = Vec::new();
    if let Some(rows) = chat.get(key).and_then(|v| v.as_array()) {
        for row in rows {
            if let Some(o) = row.as_object() {
                out.push(HomeSpeakerBeeperNetwork {
                    key: doc_str(o, "key"),
                    name: doc_str(o, "name"),
                    state: doc_str(o, "state"),
                    read_anyway: doc_bool(o, "read_anyway"),
                });
            }
        }
    }
    out
}

/// Maps Home Speaker's `--state` document (contract v1) onto the fields the phone reads.
fn map_state_doc(
    doc: &JsonValue,
    program: &HomeSpeakerProgram,
    mut st: HomeSpeakerState,
) -> HomeSpeakerState {
    let Some(d) = doc.as_object() else {
        return st;
    };
    st.installed = true;
    st.active_door = doc_str(d, "active_door");
    st.extension_installed = doc_bool(d, "extension_installed");
    st.app_running = match d.get("chosen").and_then(|v| v.as_str()) {
        Some(_) => doc_bool(d, "chosen_running"),
        None if program.door == "extension" => doc_bool(d, "extension_running"),
        None => doc_bool(d, "app_running"),
    };
    st.warnings = d
        .get("warnings")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|w| w.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    if !doc_bool(d, "config_initialized") {
        st.reason = d
            .get("config_problem")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("HomeSpeaker has not been set up on this Mac")
            .to_string();
        return st;
    }
    st.available = true;

    let s = DocSettings::of(d);
    st.enabled = s.bool("enabled").unwrap_or(false);
    st.default_target = s.str("default_target");
    st.speech_length = s.str("speech_length");
    st.pause_media = s.bool("pause_media").unwrap_or(false);
    st.pause_media_extra_seconds = s.f64("pause_media_extra_seconds");
    st.announce_volume_enabled = s.bool("announce_volume_enabled").unwrap_or(false);
    st.announce_volume = s.i64("announce_volume");
    st.speak_home = s.bool("speak_home").unwrap_or(false);
    st.speak_local = s.bool("speak_local").unwrap_or(false);
    st.speak_phone = s.bool("speak_phone");
    st.phone_pause_media = s.bool("phone_pause_media").unwrap_or(false);
    st.phone_headphones_only = s.bool("phone_headphones_only").unwrap_or(false);
    st.local_voice = s.str("local_voice");
    st.local_voice_name = doc_str(d, "local_voice_name");
    st.local_engine = s.str("local_engine");
    st.gemini_voice = s.str("gemini_voice");
    st.announcement_style = s.str("announcement_style");
    st.style_model = s.str("style_model");
    st.custom_style_prompt = s.str("custom_style_prompt");
    st.home_cast_voice = s.bool("home_cast_voice").unwrap_or(false);
    st.announce_claude_code = s.bool("announce_claude_code");
    st.announce_antigravity = s.bool("announce_antigravity");
    st.announce_opencode = s.bool("announce_opencode");
    st.slack_enabled = s.bool("slack_enabled");
    st.google_chat_enabled = s.bool("google_chat_enabled");
    st.beeper_enabled = s.bool("beeper_enabled");
    st.beeper_announce = s.str("beeper_announce");
    st.courier_enabled = s.bool("courier_enabled");
    st.courier_announce = s.str("courier_announce");
    st.mute_own_messages = s.bool("mute_own_messages");
    st.gws_account = s.str("gws_account");
    st.google_chat_source = s.str("google_chat_source");
    st.poll_interval = s.i64("poll_interval_seconds");

    st.structure_id = doc_str(d, "structure_id");
    st.structure_name = doc_str(d, "structure_name");
    if let Some(homes) = d.get("homes").and_then(|v| v.as_array()) {
        for h in homes.iter().filter_map(|h| h.as_object()) {
            st.homes.push(HomeSpeakerHome {
                id: doc_str(h, "id"),
                name: doc_str(h, "name"),
            });
        }
    }
    if let Some(q) = doc_obj(d, "quiet_hours") {
        st.quiet_hours = HomeSpeakerQuiet {
            enabled: doc_bool(q, "enabled"),
            start: doc_str(q, "start"),
            end: doc_str(q, "end"),
            active: doc_bool(q, "active"),
        };
        st.quiet_hours_active = st.quiet_hours.active;
    }
    st.snooze_until = d
        .get("snooze_until")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_string);

    if let Some(speakers) = d.get("speakers").and_then(|v| v.as_array()) {
        for sp in speakers.iter().filter_map(|v| v.as_object()) {
            st.targets.push(HomeSpeakerTarget {
                key: doc_str(sp, "key"),
                name: doc_str(sp, "name"),
                room: doc_str(sp, "room"),
                target_type: doc_str(sp, "type"),
                selected: doc_bool(sp, "is_default"),
            });
        }
    }
    if let Some(voices) = d.get("available_voices").and_then(|v| v.as_array()) {
        for v in voices.iter().filter_map(|v| v.as_object()) {
            st.available_voices.push(HomeSpeakerVoice {
                id: doc_str(v, "id"),
                name: doc_str(v, "name"),
                lang: doc_str(v, "language"),
            });
        }
    }
    if let Some(voices) = d.get("custom_voices").and_then(|v| v.as_array()) {
        for v in voices.iter().filter_map(|v| v.as_object()) {
            st.custom_voices.push(HomeSpeakerCustomVoice {
                id: doc_str(v, "id"),
                name: doc_str(v, "name"),
            });
        }
    }

    if let Some(si) = doc_obj(d, "sign_in") {
        st.signed_in = doc_bool(si, "signed_in");
        st.account_email = doc_str(si, "email");
        st.has_oauth_client = doc_bool(si, "has_oauth_client");
        st.has_antigravity_tokens = doc_bool(si, "has_antigravity_tokens");
        st.custom_oauth_client_id = doc_str(si, "custom_oauth_client_id");
        st.has_custom_oauth_secret = doc_bool(si, "has_custom_oauth_secret");
        st.has_gemini_key = doc_bool(si, "has_gemini_key");
    }
    if let Some(chat) = doc_obj(d, "chat") {
        st.has_slack_token = doc_bool(chat, "has_slack_token");
        st.has_beeper_token = doc_bool(chat, "has_beeper_token");
        st.has_courier_token = doc_bool(chat, "has_courier_token");
        st.has_google_chat_token = doc_bool(chat, "has_google_chat_token");
        st.has_chat_access = doc_bool(chat, "has_chat_access");
        st.gws_installed = doc_bool(chat, "gws_installed");
        st.beeper_networks = doc_networks(chat, "beeper_networks");
        st.beeper_networks_listed = doc_bool(chat, "beeper_networks_listed");
        st.courier_networks = doc_networks(chat, "courier_networks");
        st.courier_networks_listed = doc_bool(chat, "courier_networks_listed");
        if let Some(m) = doc_obj(chat, "monitor") {
            st.monitor_running = doc_bool(m, "is_running");
            st.last_poll_at = doc_str(m, "last_poll_at");
            st.slack_identity = doc_str(m, "slack_identity");
            st.active_google_chat_backend = doc_str(m, "active_google_chat_backend");
            st.chat_runtime_error = doc_str(m, "last_error");
        }
    }
    if let Some(hooks) = doc_obj(d, "hooks") {
        for key in ["claude_code", "antigravity", "opencode"] {
            if let Some(h) = doc_obj(hooks, key) {
                st.agents.push(HomeSpeakerAgentHook {
                    agent: doc_str(h, "display_name"),
                    agent_slug: doc_str(h, "agent"),
                    hook_state: doc_str(h, "hook_state"),
                    speaks_twice: doc_bool(h, "speaks_twice"),
                    configured_by_instruction: doc_bool(h, "configured_by_instruction"),
                });
            }
        }
    }
    st.legacy_launch_agent = doc_bool(d, "legacy_launch_agent");
    st.home_speaker_version = doc_str(d, "home_speaker_version");
    if let Some(rows) = d.get("recent").and_then(|v| v.as_array()) {
        st.recent = rows
            .iter()
            .filter_map(|r| r.as_object())
            .filter_map(doc_entry)
            .take(RECENT_BROADCASTS)
            .collect();
    }
    st.last = doc_obj(d, "last")
        .and_then(doc_entry)
        .or_else(|| st.recent.first().cloned());
    st
}

/// What one update asks of `--apply`.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct OpPlan {
    /// Settings, secrets, snooze, networks, imports: one batch.
    pub plain: Vec<JsonValue>,
    /// `agentHook` changes files outside Home Speaker's settings, so it goes alone.
    pub hook: Option<JsonValue>,
    /// `switchTo` goes alone and last.
    pub switch: Option<JsonValue>,
}

fn op_object(name: &str) -> JsonObject {
    let mut o = JsonObject::new();
    o.insert("op", JsonValue::String(name.to_string()));
    o
}

fn set_op(key: &str, value: JsonValue) -> JsonValue {
    let mut o = op_object("set");
    o.insert("key", JsonValue::String(key.to_string()));
    o.insert("value", value);
    JsonValue::Object(o)
}

/// An operation as a log line: its name and what it touches, never a value.
fn op_summary(op: &JsonValue) -> String {
    let name = op.get_str("op");
    let target = ["key", "name", "agent", "side", "app"]
        .iter()
        .map(|k| op.get_str(k))
        .find(|s| !s.is_empty());
    match target {
        Some(t) => format!("{name}:{t}"),
        None => name.to_string(),
    }
}

/// `claude-code` / `Claude Code`, `antigravity`, `opencode` as the program's agent names.
fn agent_for_slug(slug: &str) -> Option<&'static str> {
    match slug.trim().to_lowercase().replace([' ', '-'], "_").as_str() {
        "claude_code" => Some("claude_code"),
        "antigravity" => Some("antigravity"),
        "opencode" => Some("opencode"),
        _ => None,
    }
}

/// `install:claude-code`, `remove:opencode`, `add-instruction:antigravity`, `disable-rival[:slug]`
/// as an `agentHook` op; `remove-legacy-agent` as `removeLegacyAgent`.
fn agent_hook_op(action: &str) -> Result<JsonValue, ApplyError> {
    let act = action.trim();
    let unsupported = || {
        ApplyError::BadRequest(format!(
            "{act:?} is not an agent_hook_action Home Speaker knows"
        ))
    };
    let norm = act.to_lowercase().replace('_', "-");
    if norm == "remove-legacy-agent" {
        return Ok(JsonValue::Object(op_object("removeLegacyAgent")));
    }
    if norm == "disable-rival" || norm == "disable-rival-hook" || norm.starts_with("disable-rival:")
    {
        // No slug means Claude Code, the one hook with a rival.
        let agent = match act.split_once(':') {
            Some((_, slug)) => agent_for_slug(slug).ok_or_else(unsupported)?,
            None => "claude_code",
        };
        let mut o = op_object("agentHook");
        o.insert("agent", JsonValue::String(agent.to_string()));
        o.insert("action", JsonValue::String("disableRival".to_string()));
        return Ok(JsonValue::Object(o));
    }
    let Some((verb, slug)) = act.split_once(':') else {
        return Err(unsupported());
    };
    let verb = match verb.trim().to_lowercase().as_str() {
        "install" => "install",
        "remove" => "remove",
        "add-instruction" => "addInstruction",
        _ => return Err(unsupported()),
    };
    let agent = agent_for_slug(slug).ok_or_else(unsupported)?;
    let mut o = op_object("agentHook");
    o.insert("agent", JsonValue::String(agent.to_string()));
    o.insert("action", JsonValue::String(verb.to_string()));
    Ok(JsonValue::Object(o))
}

/// Turns the phone's update into `--apply` operations. No checking of values here: Home
/// Speaker's own rules are the one rule, and it answers a refusal.
pub fn plan_ops(u: &HomeSpeakerUpdate) -> Result<OpPlan, ApplyError> {
    plan_ops_with(u, None)
}

/// `plan_ops`, given the custom OAuth client id Home Speaker has now, for an update that
/// carries a secret without an id (the phone does).
pub fn plan_ops_with(
    u: &HomeSpeakerUpdate,
    current_oauth_id: Option<&str>,
) -> Result<OpPlan, ApplyError> {
    let mut plain = Vec::new();
    if u.reset_settings {
        plain.push(JsonValue::Object(op_object("reset")));
    }
    // Secrets first, so a token and "turn Courier on" can travel in one update.
    if u.oauth_client_id.is_some() || u.oauth_client_secret.is_some() {
        let id: &str = match (u.oauth_client_id.as_deref(), current_oauth_id) {
            (Some(id), _) => id,
            (None, Some(current)) if !current.is_empty() => current,
            _ => {
                return Err(ApplyError::BadRequest(
                    "Enter the client ID first.".to_string(),
                ))
            }
        };
        let mut o = op_object("saveOAuthClient");
        o.insert("client_id", JsonValue::String(id.to_string()));
        if let Some(ref secret) = u.oauth_client_secret {
            o.insert("client_secret", JsonValue::String(secret.clone()));
        }
        plain.push(JsonValue::Object(o));
    }
    for (name, value) in [
        ("slack", &u.slack_token),
        ("beeper", &u.beeper_token),
        ("courier", &u.courier_token),
        ("geminiKey", &u.gemini_api_key),
    ] {
        if let Some(v) = value {
            let mut o = op_object("setSecret");
            o.insert("name", JsonValue::String(name.to_string()));
            o.insert("value", JsonValue::String(v.clone()));
            plain.push(JsonValue::Object(o));
        }
    }

    let bools = [
        ("enabled", u.enabled),
        ("quiet_hours_enabled", u.quiet_hours_enabled),
        ("pause_media", u.pause_media),
        ("announce_volume_enabled", u.announce_volume_enabled),
        ("speak_home", u.speak_home),
        ("speak_local", u.speak_local),
        ("speak_phone", u.speak_phone),
        ("phone_pause_media", u.phone_pause_media),
        ("phone_headphones_only", u.phone_headphones_only),
        ("home_cast_voice", u.home_cast_voice),
        ("announce_claude_code", u.announce_claude_code),
        ("announce_antigravity", u.announce_antigravity),
        ("announce_opencode", u.announce_opencode),
        ("slack_enabled", u.slack_enabled),
        ("google_chat_enabled", u.google_chat_enabled),
        ("beeper_enabled", u.beeper_enabled),
        ("courier_enabled", u.courier_enabled),
        ("mute_own_messages", u.mute_own_messages),
    ];
    for (key, v) in bools {
        if let Some(b) = v {
            plain.push(set_op(key, JsonValue::Bool(b)));
        }
    }
    for (key, v) in [
        ("speech_length", &u.speech_length),
        ("quiet_hours_start", &u.quiet_hours_start),
        ("quiet_hours_end", &u.quiet_hours_end),
        ("custom_style_prompt", &u.custom_style_prompt),
        ("local_voice", &u.local_voice),
        ("local_engine", &u.local_engine),
        ("gemini_voice", &u.gemini_voice),
        ("announcement_style", &u.announcement_style),
        ("style_model", &u.style_model),
        ("google_chat_source", &u.google_chat_source),
        ("gws_account", &u.gws_account),
        ("beeper_announce", &u.beeper_announce),
        ("courier_announce", &u.courier_announce),
    ] {
        if let Some(s) = v {
            plain.push(set_op(key, JsonValue::String(s.clone())));
        }
    }
    if let Some(n) = u.pause_media_extra_seconds {
        // The catalog's kind is a whole number.
        plain.push(set_op(
            "pause_media_extra_seconds",
            JsonValue::from_i64(n.round() as i64),
        ));
    }
    if let Some(n) = u.announce_volume {
        plain.push(set_op("announce_volume", JsonValue::from_i64(n)));
    }
    if let Some(n) = u.poll_interval {
        plain.push(set_op("poll_interval_seconds", JsonValue::from_i64(n)));
    }

    if let Some(ref key) = u.default_target {
        let mut o = op_object("setDefaultSpeaker");
        o.insert("key", JsonValue::String(key.clone()));
        plain.push(JsonValue::Object(o));
    }
    if let Some(ref key) = u.remove_target {
        let mut o = op_object("removeSpeaker");
        o.insert("key", JsonValue::String(key.clone()));
        plain.push(JsonValue::Object(o));
    }

    if let Some(minutes) = u.snooze_minutes {
        let mut o = op_object("snooze");
        o.insert("minutes", JsonValue::from_i64(minutes));
        plain.push(JsonValue::Object(o));
    } else if let Some(ref until) = u.snooze_until {
        let mut o = op_object("snooze");
        if until.trim().is_empty() {
            o.insert("clear", JsonValue::Bool(true));
        } else {
            // The program snoozes for a number of minutes: count them to the asked time.
            let ts = parse_snooze_timestamp(until)?;
            let secs = ts.unix_seconds() - Timestamp::now().unix_seconds();
            if secs <= 0 {
                return Err(ApplyError::BadRequest(
                    "snooze_until is in the past".to_string(),
                ));
            }
            o.insert("minutes", JsonValue::from_i64((secs + 59) / 60));
        }
        plain.push(JsonValue::Object(o));
    }

    for (app, update) in [
        ("beeper", &u.beeper_network),
        ("courier", &u.courier_network),
    ] {
        if let Some(n) = update {
            let mut o = op_object("setNetwork");
            o.insert("app", JsonValue::String(app.to_string()));
            o.insert("key", JsonValue::String(n.key.clone()));
            o.insert("reading", JsonValue::Bool(n.reading));
            plain.push(JsonValue::Object(o));
        }
    }
    if let Some(ref ra) = u.courier_read_anyway {
        let mut o = op_object("setReadAnyway");
        o.insert("key", JsonValue::String(ra.key.clone()));
        o.insert("on", JsonValue::Bool(ra.on));
        plain.push(JsonValue::Object(o));
    }
    if u.import_antigravity {
        plain.push(JsonValue::Object(op_object("importAntigravity")));
    }

    let hook = match u.agent_hook_action {
        Some(ref a) => Some(agent_hook_op(a)?),
        None => None,
    };
    let switch = u.active_door.as_ref().map(|door| {
        let mut o = op_object("switchTo");
        o.insert("side", JsonValue::String(door.trim().to_lowercase()));
        JsonValue::Object(o)
    });
    Ok(OpPlan {
        plain,
        hook,
        switch,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sampler::KNOWN_TOOLS;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Mutex;

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

    fn post_req(path: &str, body: &str) -> HttpRequest {
        HttpRequest::new_test("POST", path, body).with_header("content-type", "application/json")
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
    fn test_home_speaker_is_a_known_tool_resolved_by_bundle_not_path() {
        assert!(KNOWN_TOOLS.contains(&"homespeaker"));
        let tools = crate::sampler::tool_presence(&["homespeaker"]);
        let got = tools.tools.get("homespeaker").unwrap();
        assert_eq!(got.path, HOME_SPEAKER_BINARY);
        assert_eq!(got.available, Path::new(HOME_SPEAKER_BINARY).exists());
    }

    // ---- The program answers; the helper relays (golden `--state` document, fake runner). ----

    const GOLDEN_STATE_PATH: &str = "apps/desktop/home-speaker/testdata/state_v1.json";

    fn golden_state() -> String {
        fs::read_to_string(GOLDEN_STATE_PATH).expect("golden state_v1.json is in the test data")
    }

    type CallLog = Arc<Mutex<Vec<Vec<String>>>>;

    /// A helper whose "Home Speaker" is a closure: nothing real is ever run. `handler` sees the
    /// arguments of every program call (`--version`, `--state`, `--apply`, ...).
    fn relay_speaker(
        prefix: &str,
        handler: impl Fn(&str, &[String]) -> Result<(String, String), String> + Send + Sync + 'static,
    ) -> (HomeSpeaker, PathBuf, CallLog) {
        let dir = temp_dir(prefix);
        let bin = dir.join("HomeSpeaker");
        fs::write(&bin, b"#!/bin/sh\n").unwrap();
        let calls: CallLog = Arc::new(Mutex::new(Vec::new()));
        let calls_c = calls.clone();
        let mut h = HomeSpeaker::new();
        h.binary = bin.clone();
        h.door_path = dir.join("speaker_door.json");
        h.run_capture = None;
        h.launch = None;
        h.say = None;
        h.read_clipboard = Some(Arc::new(|| Ok("clipboard announcement text".to_string())));
        h.run = Arc::new(move |_limit, name, args| {
            // Anything that is not the scratch program (`say`, ...) is recorded under its own name.
            let mut entry = args.to_vec();
            if name != bin.to_string_lossy() {
                entry.insert(0, name.to_string());
            }
            calls_c.lock().unwrap().push(entry);
            handler(name, args)
        });
        (h, dir, calls)
    }

    fn state_answering(
        version: &'static str,
        state: String,
    ) -> impl Fn(&str, &[String]) -> Result<(String, String), String> {
        move |_name: &str, args: &[String]| match args {
            [f] if f == "--version" => Ok((format!("HomeSpeaker {version}\n"), String::new())),
            [a, b] if a == "--state" && b == "--json" => Ok((state.clone(), String::new())),
            _ => Err(format!("unexpected arguments: {args:?}")),
        }
    }

    fn body_of(resp: &HttpResponse) -> JsonValue {
        JsonValue::parse(&resp.body_string()).unwrap()
    }

    fn strs(v: &JsonValue, key: &str) -> Vec<String> {
        v.get_array(key)
            .unwrap_or(&[])
            .iter()
            .map(|x| x.as_str().unwrap_or("").to_string())
            .collect()
    }

    #[test]
    fn test_golden_state_v1_maps_every_phone_field_and_records_exact_args() {
        let (h, _dir, calls) =
            relay_speaker("golden_get", state_answering("1.41.0", golden_state()));
        let resp = h.handle_get(&PhoneBridge::new());
        assert_eq!(resp.status, 200);
        assert_eq!(
            calls.lock().unwrap().clone(),
            vec![
                vec!["--version".to_string()],
                vec!["--state".to_string(), "--json".to_string()]
            ],
            "exactly --version, then --state --json"
        );
        let b = body_of(&resp);
        // Running / door / install state.
        assert!(b.get_bool("available") && b.get_bool("installed"));
        assert!(b.get_bool("app_running"), "chosen_running");
        assert_eq!(b.get_str("active_door"), "app");
        assert!(b.get_bool("extension_installed"));
        assert!(!b.get_bool("phone_connected"));
        assert_eq!(b.get_str("home_speaker_version"), "1.19.1");
        assert!(!b.get_bool("legacy_launch_agent"));
        // Settings, by key.
        assert!(b.get_bool("enabled"));
        assert_eq!(b.get_str("default_target"), "office");
        assert_eq!(b.get_str("speech_length"), "summary");
        assert!(b.get_bool("pause_media"));
        assert_eq!(b.get_f64("pause_media_extra_seconds"), 3.0);
        assert!(b.get_bool("announce_volume_enabled"));
        assert_eq!(b.get_i64("announce_volume"), 65);
        assert!(b.get_bool("speak_home") && b.get_bool("speak_local"));
        assert_eq!(b.get_opt_bool("speak_phone"), Some(true));
        assert!(!b.get_bool("phone_pause_media") && !b.get_bool("phone_headphones_only"));
        assert_eq!(
            b.get_str("local_voice"),
            "com.apple.voice.premium.en-US.Ava"
        );
        assert_eq!(b.get_str("local_voice_name"), "Ava");
        assert_eq!(b.get_str("local_engine"), "gemini");
        assert_eq!(b.get_str("gemini_voice"), "Kore");
        assert_eq!(b.get_str("announcement_style"), "briefing");
        assert_eq!(b.get_str("style_model"), "gemini");
        assert!(b.get_bool("home_cast_voice"));
        assert_eq!(b.get_opt_bool("announce_claude_code"), Some(true));
        assert_eq!(b.get_opt_bool("announce_antigravity"), Some(true));
        assert_eq!(b.get_opt_bool("announce_opencode"), Some(false));
        assert_eq!(b.get_opt_bool("slack_enabled"), Some(true));
        assert_eq!(b.get_opt_bool("google_chat_enabled"), Some(true));
        assert_eq!(b.get_opt_bool("beeper_enabled"), Some(true));
        assert_eq!(b.get_str("beeper_announce"), "direct_and_mentions");
        assert_eq!(b.get_opt_bool("courier_enabled"), Some(true));
        assert_eq!(b.get_str("courier_announce"), "all");
        assert_eq!(b.get_opt_bool("mute_own_messages"), Some(true));
        assert_eq!(b.get_str("gws_account"), "ops@example.com");
        assert_eq!(b.get_str("google_chat_source"), "gws");
        assert_eq!(b.get_i64("poll_interval"), 30, "poll_interval_seconds");
        // Home, quiet hours, snooze.
        assert_eq!(b.get_str("structure_name"), "Home");
        assert_eq!(b.get_str("structure_id"), "home-structure-1");
        assert_eq!(b.get_array("homes").unwrap().len(), 1);
        assert_eq!(
            b.get_array("homes").unwrap()[0].get_str("id"),
            "home-structure-1"
        );
        let q = b.get("quiet_hours").unwrap();
        assert!(q.get_bool("enabled") && q.get_bool("active"));
        assert_eq!((q.get_str("start"), q.get_str("end")), ("22:30", "07:00"));
        assert!(b.get_bool("quiet_hours_active"));
        assert!(b.get("snooze_until").unwrap().is_null());
        // Speakers -> targets.
        let targets = b.get_array("targets").unwrap();
        assert_eq!(targets.len(), 3);
        let office = targets
            .iter()
            .find(|t| t.get_str("key") == "office")
            .unwrap();
        assert_eq!(office.get_str("name"), "Office Mini");
        assert_eq!(office.get_str("room"), "Office");
        assert_eq!(office.get_str("type"), "sdm.devices.types.SPEAKER");
        assert!(office.get_bool("selected"));
        assert_eq!(targets.iter().filter(|t| t.get_bool("selected")).count(), 1);
        // Voices.
        let voices = b.get_array("available_voices").unwrap();
        assert_eq!(voices.len(), 2);
        assert_eq!(voices[0].get_str("id"), "com.apple.voice.premium.en-US.Ava");
        assert_eq!(voices[0].get_str("lang"), "en-US");
        assert_eq!(
            b.get_array("custom_voices").unwrap()[0].get_str("name"),
            "Studio Narrator"
        );
        // Sign-in.
        assert!(b.get_bool("signed_in"));
        assert_eq!(b.get_str("account_email"), "owner@example.com");
        assert!(b.get_bool("has_gemini_key") && b.get_bool("has_oauth_client"));
        assert!(b.get_bool("has_antigravity_tokens") && b.get_bool("has_custom_oauth_secret"));
        assert_eq!(
            b.get_str("custom_oauth_client_id"),
            "custom-client-id.apps.googleusercontent.com"
        );
        // Chat.
        assert!(b.get_bool("has_slack_token") && b.get_bool("has_beeper_token"));
        assert!(b.get_bool("has_courier_token") && b.get_bool("has_google_chat_token"));
        assert!(b.get_bool("has_chat_access") && b.get_bool("gws_installed"));
        assert!(b.get_bool("monitor_running"));
        assert_eq!(b.get_str("last_poll_at"), "2026-11-10T23:14:50Z");
        assert_eq!(b.get_str("slack_identity"), "owner (Vitruvian)");
        assert_eq!(
            b.get_str("active_google_chat_backend"),
            "gws (ops@example.com)"
        );
        assert!(
            b.get("chat_runtime_error").is_none(),
            "last_error null: nothing to say"
        );
        let beeper = b.get_array("beeper_networks").unwrap();
        assert_eq!(beeper.len(), 2);
        assert_eq!(
            (beeper[0].get_str("key"), beeper[0].get_str("state")),
            ("signal", "muted")
        );
        assert!(b.get_bool("beeper_networks_listed") && b.get_bool("courier_networks_listed"));
        let courier = b.get_array("courier_networks").unwrap();
        assert!(courier[1].get_bool("read_anyway"));
        assert!(courier[0].get("read_anyway").is_none());
        // Hooks -> agents.
        let agents = b.get_array("agents").unwrap();
        let slugs: Vec<&str> = agents.iter().map(|a| a.get_str("agent_slug")).collect();
        assert_eq!(slugs, vec!["claude-code", "antigravity", "opencode"]);
        assert_eq!(agents[0].get_str("agent"), "Claude Code");
        assert_eq!(agents[0].get_str("hook_state"), "installed");
        assert_eq!(agents[1].get_str("hook_state"), "not_installed");
        assert!(
            !agents[0].get_bool("speaks_twice") && !agents[0].get_bool("configured_by_instruction")
        );
        // History.
        let last = b.get("last").unwrap();
        assert_eq!(last.get_str("text"), "All tests passed on main.");
        assert_eq!(last.get_str("target"), "Office Mini + this Mac");
        assert_eq!(last.get_str("source"), "Claude Code");
        assert_eq!(last.get_str("id"), "00000000-0000-0000-0000-000000000001");
        assert_eq!(last.get_str("at"), "2026-11-10T23:14:00Z");
        assert_eq!(b.get_array("recent").unwrap().len(), 1);
        assert!(strs(&b, "warnings").is_empty());
    }

    #[test]
    fn test_get_too_old_answers_the_update_sentence_and_never_runs_state() {
        let (h, _dir, calls) = relay_speaker("too_old", state_answering("1.40.0", golden_state()));
        let b = body_of(&h.handle_get(&PhoneBridge::new()));
        assert!(!b.get_bool("available"));
        assert!(b.get_bool("installed"));
        let reason = b.get_str("reason");
        assert!(reason.starts_with("Update Home Speaker on "), "{reason}");
        assert!(reason.ends_with("(have 1.40.0, need 1.41.0)"), "{reason}");
        assert_eq!(
            calls.lock().unwrap().clone(),
            vec![vec!["--version".to_string()]],
            "an old program must never be given --state"
        );
    }

    #[test]
    fn test_version_comparison_is_numeric_not_textual() {
        assert!(version_at_least("1.41.0", "1.41.0"));
        assert!(version_at_least("1.100.0", "1.41.0"));
        assert!(version_at_least("2.0", "1.41.0"));
        assert!(version_at_least("1.41.1-beta", "1.41.0"));
        assert!(!version_at_least("1.9.9", "1.41.0"));
        assert!(!version_at_least("1.39.99", "1.41.0"));
        assert_eq!(
            parse_version_output("HomeSpeaker 1.41.0\n").as_deref(),
            Some("1.41.0")
        );
        assert_eq!(parse_version_output("v1.41.2").as_deref(), Some("1.41.2"));
        assert_eq!(parse_version_output("garbage"), None);
        assert_eq!(parse_version_output(""), None);
    }

    #[test]
    fn test_get_missing_program_keeps_the_not_installed_answer() {
        let (h, dir, calls) = relay_speaker("missing", state_answering("1.41.0", golden_state()));
        fs::remove_file(dir.join("HomeSpeaker")).unwrap();
        let b = body_of(&h.handle_get(&PhoneBridge::new()));
        assert!(!b.get_bool("available") && !b.get_bool("installed"));
        assert!(
            b.get_str("reason").contains("not installed"),
            "{}",
            b.get_str("reason")
        );
        assert!(
            calls.lock().unwrap().is_empty(),
            "nothing is run when there is no program"
        );
    }

    #[test]
    fn test_get_state_timeout_and_bad_json_are_clear_errors_not_crashes() {
        let (h, _d, _c) = relay_speaker("state_timeout", |_n, args| match args {
            [f] if f == "--version" => Ok(("HomeSpeaker 1.41.0".to_string(), String::new())),
            _ => Err("HomeSpeaker: no answer within 15s".to_string()),
        });
        let b = body_of(&h.handle_get(&PhoneBridge::new()));
        assert!(!b.get_bool("available") && b.get_bool("installed"));
        assert!(
            b.get_str("reason").contains("did not answer --state"),
            "{}",
            b.get_str("reason")
        );
        assert!(b.get_str("reason").contains("no answer within 15s"));

        for junk in [
            "not json at all",
            "[1,2,3]",
            "",
            "{\"contract_version\":2}",
            "{}",
        ] {
            let junk = junk.to_string();
            let (h, _d, _c) = relay_speaker("state_junk", state_answering("1.41.0", junk.clone()));
            let resp = h.handle_get(&PhoneBridge::new());
            assert_eq!(resp.status, 200, "{junk:?}");
            let b = body_of(&resp);
            assert!(!b.get_bool("available"), "{junk:?}");
            assert!(!b.get_str("reason").is_empty(), "{junk:?}");
        }

        let (h, _d, _c) = relay_speaker("version_junk", |_, _| {
            Ok(("no version here".to_string(), String::new()))
        });
        let b = body_of(&h.handle_get(&PhoneBridge::new()));
        assert!(!b.get_bool("available"));
        assert!(b
            .get_str("reason")
            .contains("Could not read the Home Speaker version"));
    }

    #[test]
    fn test_get_config_not_initialized_says_so_and_runs_nothing_more() {
        let state = golden_state().replace(
            "\"config_initialized\": true",
            "\"config_initialized\": false",
        );
        let (h, _d, _c) = relay_speaker("uninit", state_answering("1.41.0", state));
        let b = body_of(&h.handle_get(&PhoneBridge::new()));
        assert!(!b.get_bool("available") && b.get_bool("installed"));
        assert!(b.get_str("reason").contains("not been set up"));
    }

    #[test]
    fn test_capturing_runner_keeps_stdout_of_a_refusal_and_reports_a_timeout() {
        // /bin/sh stands in for any program: this is about the runner, not Home Speaker.
        let args = vec![
            "-c".to_string(),
            "echo '{\"ok\":false}'; exit 1".to_string(),
        ];
        let (out, _, code) = run_capturing_exit(Duration::from_secs(10), "/bin/sh", &args).unwrap();
        assert_eq!(code, 1);
        assert_eq!(out.trim(), "{\"ok\":false}");
        let slow = vec!["-c".to_string(), "sleep 5".to_string()];
        let err = run_capturing_exit(Duration::from_millis(200), "/bin/sh", &slow).unwrap_err();
        assert!(err.contains("no answer within"), "{err}");
        assert!(run_capturing_exit(Duration::from_secs(1), "/nonexistent/program", &[]).is_err());
    }

    // ---- POST: the update becomes `--apply` operations. ----

    fn plan_for(body: &str) -> Result<OpPlan, ApplyError> {
        plan_ops(&HomeSpeakerUpdate::from_json(&JsonValue::parse(body).unwrap()).unwrap())
    }

    fn plain_json(body: &str) -> String {
        JsonValue::Array(plan_for(body).unwrap().plain).to_json_string()
    }

    #[test]
    fn test_every_catalog_setting_maps_to_a_set_op_with_the_catalog_key() {
        let bools = [
            "enabled",
            "quiet_hours_enabled",
            "pause_media",
            "announce_volume_enabled",
            "speak_home",
            "speak_local",
            "speak_phone",
            "phone_pause_media",
            "phone_headphones_only",
            "home_cast_voice",
            "announce_claude_code",
            "announce_antigravity",
            "announce_opencode",
            "slack_enabled",
            "google_chat_enabled",
            "beeper_enabled",
            "courier_enabled",
            "mute_own_messages",
        ];
        for key in bools {
            assert_eq!(
                plain_json(&format!("{{\"{key}\":true}}")),
                format!("[{{\"op\":\"set\",\"key\":\"{key}\",\"value\":true}}]"),
                "{key}"
            );
        }
        let strings = [
            "speech_length",
            "quiet_hours_start",
            "quiet_hours_end",
            "custom_style_prompt",
            "local_voice",
            "local_engine",
            "gemini_voice",
            "announcement_style",
            "style_model",
            "google_chat_source",
            "gws_account",
            "beeper_announce",
            "courier_announce",
        ];
        for key in strings {
            assert_eq!(
                plain_json(&format!("{{\"{key}\":\"x\"}}")),
                format!("[{{\"op\":\"set\",\"key\":\"{key}\",\"value\":\"x\"}}]"),
                "{key}"
            );
        }
        // The phone's name differs from the catalog key for the poll interval.
        assert_eq!(
            plain_json(r#"{"poll_interval":45}"#),
            r#"[{"op":"set","key":"poll_interval_seconds","value":45}]"#
        );
        assert_eq!(
            plain_json(r#"{"announce_volume":70}"#),
            r#"[{"op":"set","key":"announce_volume","value":70}]"#
        );
        assert_eq!(
            plain_json(r#"{"pause_media_extra_seconds":2.5}"#),
            r#"[{"op":"set","key":"pause_media_extra_seconds","value":3}]"#
        );
    }

    #[test]
    fn test_every_other_post_field_maps_to_its_op() {
        let cases: [(&str, &str); 17] = [
            (
                r#"{"default_target":"kitchen"}"#,
                r#"[{"op":"setDefaultSpeaker","key":"kitchen"}]"#,
            ),
            (
                r#"{"remove_target":"bedroom"}"#,
                r#"[{"op":"removeSpeaker","key":"bedroom"}]"#,
            ),
            (r#"{"reset_settings":true}"#, r#"[{"op":"reset"}]"#),
            (
                r#"{"oauth_client_id":"cid","oauth_client_secret":"sec"}"#,
                r#"[{"op":"saveOAuthClient","client_id":"cid","client_secret":"sec"}]"#,
            ),
            (
                r#"{"oauth_client_id":"cid"}"#,
                r#"[{"op":"saveOAuthClient","client_id":"cid"}]"#,
            ),
            (
                r#"{"slack_token":"xoxb-1"}"#,
                r#"[{"op":"setSecret","name":"slack","value":"xoxb-1"}]"#,
            ),
            (
                r#"{"beeper_token":"b"}"#,
                r#"[{"op":"setSecret","name":"beeper","value":"b"}]"#,
            ),
            (
                r#"{"courier_token":"c"}"#,
                r#"[{"op":"setSecret","name":"courier","value":"c"}]"#,
            ),
            (
                r#"{"gemini_api_key":""}"#,
                r#"[{"op":"setSecret","name":"geminiKey","value":""}]"#,
            ),
            (
                r#"{"snooze_minutes":30}"#,
                r#"[{"op":"snooze","minutes":30}]"#,
            ),
            (
                r#"{"snooze_until":""}"#,
                r#"[{"op":"snooze","clear":true}]"#,
            ),
            (
                r#"{"beeper_network":{"key":"signal","reading":false}}"#,
                r#"[{"op":"setNetwork","app":"beeper","key":"signal","reading":false}]"#,
            ),
            (
                r#"{"courier_network":{"key":"imessage","reading":true}}"#,
                r#"[{"op":"setNetwork","app":"courier","key":"imessage","reading":true}]"#,
            ),
            (
                r#"{"courier_read_anyway":{"key":"slack","on":true}}"#,
                r#"[{"op":"setReadAnyway","key":"slack","on":true}]"#,
            ),
            (
                r#"{"import_antigravity":true}"#,
                r#"[{"op":"importAntigravity"}]"#,
            ),
            (
                r#"{"enabled":true,"slack_token":"s","courier_enabled":true,"default_target":"office"}"#,
                r#"[{"op":"setSecret","name":"slack","value":"s"},{"op":"set","key":"enabled","value":true},{"op":"set","key":"courier_enabled","value":true},{"op":"setDefaultSpeaker","key":"office"}]"#,
            ),
            (
                r#"{"reset_settings":true,"enabled":true}"#,
                r#"[{"op":"reset"},{"op":"set","key":"enabled","value":true}]"#,
            ),
        ];
        for (body, expected) in cases {
            assert_eq!(plain_json(body), expected, "{body}");
        }
        // A secret alone is a mistake: the program needs the id with it.
        assert!(matches!(
            plan_for(r#"{"oauth_client_secret":"sec"}"#),
            Err(ApplyError::BadRequest(_))
        ));
        // A time in the future is counted in minutes (the program snoozes for minutes).
        let at = Timestamp::from_unix_secs(Timestamp::now().unix_seconds() + 5400).to_rfc3339();
        assert_eq!(
            plain_json(&format!("{{\"snooze_until\":\"{at}\"}}")),
            r#"[{"op":"snooze","minutes":90}]"#
        );
        assert!(matches!(
            plan_for(r#"{"snooze_until":"2001-01-01T00:00:00Z"}"#),
            Err(ApplyError::BadRequest(_))
        ));
    }

    #[test]
    fn test_hook_and_door_ops_are_kept_out_of_the_plain_batch() {
        let plan = plan_for(r#"{"agent_hook_action":"install:claude-code","active_door":"Extension","enabled":false}"#).unwrap();
        assert_eq!(plan.plain.len(), 1);
        assert_eq!(
            plan.hook.unwrap().to_json_string(),
            r#"{"op":"agentHook","agent":"claude_code","action":"install"}"#
        );
        assert_eq!(
            plan.switch.unwrap().to_json_string(),
            r#"{"op":"switchTo","side":"extension"}"#
        );
        for (action, want) in [
            (
                "remove:opencode",
                r#"{"op":"agentHook","agent":"opencode","action":"remove"}"#,
            ),
            (
                "add-instruction:antigravity",
                r#"{"op":"agentHook","agent":"antigravity","action":"addInstruction"}"#,
            ),
            (
                "install:Claude Code",
                r#"{"op":"agentHook","agent":"claude_code","action":"install"}"#,
            ),
        ] {
            let plan = plan_for(&format!("{{\"agent_hook_action\":\"{action}\"}}")).unwrap();
            assert_eq!(plan.hook.unwrap().to_json_string(), want, "{action}");
            assert!(plan.plain.is_empty() && plan.switch.is_none());
        }
        // The two actions that used to be refused now have operations, and go alone as well.
        for action in [
            "disable-rival:claude-code",
            "disable-rival:Claude Code",
            "disable_rival_hook",
            "disable-rival",
        ] {
            let plan = plan_for(&format!("{{\"agent_hook_action\":\"{action}\"}}")).unwrap();
            assert_eq!(
                plan.hook.unwrap().to_json_string(),
                r#"{"op":"agentHook","agent":"claude_code","action":"disableRival"}"#,
                "{action}"
            );
            assert!(plan.plain.is_empty() && plan.switch.is_none());
        }
        for action in ["remove-legacy-agent", "remove_legacy_agent"] {
            let plan = plan_for(&format!("{{\"agent_hook_action\":\"{action}\"}}")).unwrap();
            assert_eq!(
                plan.hook.unwrap().to_json_string(),
                r#"{"op":"removeLegacyAgent"}"#,
                "{action}"
            );
            assert!(plan.plain.is_empty() && plan.switch.is_none());
        }
        assert!(matches!(
            plan_for(r#"{"agent_hook_action":"install:emacs"}"#),
            Err(ApplyError::BadRequest(_))
        ));
    }

    fn apply_ok() -> Result<(String, String), String> {
        Ok((
            r#"{"ok":true,"results":[],"state":{}}"#.to_string(),
            String::new(),
        ))
    }

    fn refusal(
        code: &str,
        message: &str,
        chosen: Option<&str>,
    ) -> Result<(String, String), String> {
        let chosen = chosen
            .map(|c| format!(",\"chosen\":\"{c}\""))
            .unwrap_or_default();
        Ok((
            format!(
                "{{\"ok\":false,\"error\":{{\"op_index\":0,\"code\":\"{code}\",\"message\":\"{message}\"{chosen}}}}}"
            ),
            String::new(),
        ))
    }

    fn applies(calls: &CallLog) -> Vec<String> {
        calls
            .lock()
            .unwrap()
            .iter()
            .filter_map(|c| {
                // A call to a program other than the scratch one carries its path first.
                let args: &[String] = if c[0].starts_with("--") { c } else { &c[1..] };
                (args.first().map(String::as_str) == Some("--apply")).then(|| {
                    assert_eq!(args[1], "--json");
                    args[2].clone()
                })
            })
            .collect()
    }

    fn state_and_apply(
        state: String,
    ) -> impl Fn(&str, &[String]) -> Result<(String, String), String> {
        let answer = state_answering("1.41.0", state);
        move |name, args| match args.first().map(String::as_str) {
            Some("--apply") => apply_ok(),
            _ => answer(name, args),
        }
    }

    #[test]
    fn test_post_runs_version_then_apply_with_the_exact_envelope_then_state() {
        let (h, _d, calls) = relay_speaker("post_exact", state_and_apply(golden_state()));
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"enabled":false,"poll_interval":45}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 200, "{}", resp.body_string());
        assert!(
            body_of(&resp).get_bool("available"),
            "the reply is the GET shape"
        );
        let calls = calls.lock().unwrap().clone();
        assert_eq!(
            calls,
            vec![
                vec!["--version".to_string()],
                vec![
                    "--apply".to_string(),
                    "--json".to_string(),
                    r#"{"contract_version":1,"operations":[{"op":"set","key":"enabled","value":false},{"op":"set","key":"poll_interval_seconds","value":45}]}"#.to_string()
                ],
                vec!["--state".to_string(), "--json".to_string()],
            ],
            "the version is asked once per request, before the first --apply"
        );
    }

    #[test]
    fn test_mixed_update_sends_plain_then_hook_then_switch_and_stops_at_the_first_failure() {
        let body = r#"{"active_door":"extension","agent_hook_action":"install:claude-code","enabled":false,"default_target":"kitchen"}"#;
        let (h, _d, calls) = relay_speaker("post_mixed", state_and_apply(golden_state()));
        let resp = h.handle_set(&post_req("/v1/homespeaker", body), &PhoneBridge::new());
        assert_eq!(resp.status, 200, "{}", resp.body_string());
        assert_eq!(
            applies(&calls),
            vec![
                r#"{"contract_version":1,"operations":[{"op":"set","key":"enabled","value":false},{"op":"setDefaultSpeaker","key":"kitchen"}]}"#,
                r#"{"contract_version":1,"operations":[{"op":"agentHook","agent":"claude_code","action":"install"}]}"#,
                r#"{"contract_version":1,"operations":[{"op":"switchTo","side":"extension"}]}"#,
            ]
        );

        // The hook is refused: the switch is never sent, and the refusal comes back as a 400.
        let seen = state_answering("1.41.0", golden_state());
        let (h, _d, calls) = relay_speaker("post_hook_fails", move |name, args| {
            match args.first().map(String::as_str) {
                Some("--apply") if args[2].contains("agentHook") => refusal(
                    "agent_hook_failed",
                    "Could not write the Claude Code settings",
                    None,
                ),
                Some("--apply") => apply_ok(),
                _ => seen(name, args),
            }
        });
        let resp = h.handle_set(&post_req("/v1/homespeaker", body), &PhoneBridge::new());
        assert_eq!(resp.status, 400);
        assert!(resp
            .body_string()
            .contains("Could not write the Claude Code settings"));
        let sent = applies(&calls);
        assert_eq!(
            sent.len(),
            2,
            "plain, then the hook that failed; no switch: {sent:?}"
        );
        assert!(!sent.iter().any(|s| s.contains("switchTo")));

        // The plain batch is refused: neither the hook nor the switch is sent.
        let (h, _d, calls) = relay_speaker("post_plain_fails", |_n, args| {
            match args.first().map(String::as_str) {
                Some("--version") => Ok(("HomeSpeaker 1.41.0".to_string(), String::new())),
                _ => refusal(
                    "invalid_choice",
                    "speech_length must be one of headline, summary, full",
                    None,
                ),
            }
        });
        let resp = h.handle_set(&post_req("/v1/homespeaker", body), &PhoneBridge::new());
        assert_eq!(resp.status, 400);
        assert!(resp.body_string().contains("speech_length must be one of"));
        assert_eq!(applies(&calls).len(), 1);
    }

    #[test]
    fn test_apply_errors_map_to_400_409_and_500() {
        let post = |answer: Result<(String, String), String>| {
            let seen = state_answering("1.41.0", golden_state());
            let (h, _d, _c) = relay_speaker("post_errors", move |name, args| {
                match args.first().map(String::as_str) {
                    Some("--apply") => answer.clone(),
                    _ => seen(name, args),
                }
            });
            h.handle_set(
                &post_req("/v1/homespeaker", r#"{"enabled":true}"#),
                &PhoneBridge::new(),
            )
        };
        let r = post(refusal(
            "out_of_range",
            "announce_volume must be 0 to 100",
            None,
        ));
        assert_eq!(r.status, 400);
        assert!(r.body_string().contains("announce_volume must be 0 to 100"));
        assert_eq!(post(refusal("timed_out", "timed out", None)).status, 500);
        assert_eq!(
            post(refusal("config_unreadable", "unreadable", None)).status,
            500
        );
        assert_eq!(post(Err("no answer within 120s".to_string())).status, 500);
        assert_eq!(
            post(Ok(("not json".to_string(), String::new()))).status,
            500
        );
        assert_eq!(
            post(refusal("not_chosen", "use the extension", None)).status,
            409
        );
    }

    #[test]
    fn test_post_to_an_old_program_answers_the_update_sentence_and_never_runs_apply() {
        let (h, _d, calls) = relay_speaker("post_old", state_answering("1.40.0", golden_state()));
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"enabled":true}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 409);
        assert!(resp.body_string().contains("(have 1.40.0, need 1.41.0)"));
        assert_eq!(
            calls.lock().unwrap().clone(),
            vec![vec!["--version".to_string()]]
        );

        let (h, dir, calls) =
            relay_speaker("post_missing", state_answering("1.41.0", golden_state()));
        fs::remove_file(dir.join("HomeSpeaker")).unwrap();
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"enabled":true}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 409);
        assert!(resp.body_string().contains("not installed"));
        assert!(calls.lock().unwrap().is_empty());
    }

    #[test]
    fn test_not_chosen_rereads_the_choice_file_and_retries_once_on_the_named_program() {
        let door = |dir: &Path, chosen: &str, ext: &Path| {
            fs::write(
                dir.join("speaker_door.json"),
                format!(
                    r#"{{"version":1,"chosen":"{chosen}","extension":{{"program":"{}","version":"1.41.0","door":1}}}}"#,
                    ext.display()
                ),
            )
            .unwrap();
        };
        // The choice file said "app", but Home Speaker says the extension is chosen.
        let ext_root = temp_dir("retry_ext");
        let ext = ext_root.join("tool");
        fs::write(&ext, b"#!/bin/sh\n").unwrap();
        let ext_name = ext.to_string_lossy().into_owned();
        let seen = state_answering("1.41.0", golden_state());
        let ext_name_c = ext_name.clone();
        let (h, dir, calls) = relay_speaker("retry_named", move |name, args| {
            match args.first().map(String::as_str) {
                Some("--apply") if name != ext_name_c => {
                    refusal("not_chosen", "The extension is chosen", Some("extension"))
                }
                Some("--apply") => apply_ok(),
                _ => seen(name, args),
            }
        });
        door(&dir, "app", &ext);
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"enabled":false}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 200, "{}", resp.body_string());
        let log = calls.lock().unwrap().clone();
        let on_extension: Vec<&Vec<String>> = log
            .iter()
            .filter(|c| c.first() == Some(&ext_name))
            .collect();
        assert!(
            on_extension
                .iter()
                .any(|c| c.get(1).map(String::as_str) == Some("--apply")),
            "{log:?}"
        );
        assert_eq!(
            applies(&calls).len(),
            2,
            "one refused, one retried: {log:?}"
        );

        // Refused again: no second retry, the refusal is a 409.
        let seen = state_answering("1.41.0", golden_state());
        let (h, dir, calls) = relay_speaker("retry_once", move |name, args| {
            match args.first().map(String::as_str) {
                Some("--apply") => {
                    refusal("not_chosen", "The extension is chosen", Some("extension"))
                }
                _ => seen(name, args),
            }
        });
        door(&dir, "app", &ext);
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"enabled":false}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 409);
        assert_eq!(applies(&calls).len(), 2, "exactly one retry");
    }

    // ---- Commands the helper still runs as program flags, and speech. ----

    #[test]
    fn test_direct_program_commands_keep_their_flags_and_touch_no_files() {
        let (h, dir, calls) = relay_speaker("flags", |_n, _a| Ok((String::new(), String::new())));
        let post =
            |body: &str| h.handle_set(&post_req("/v1/homespeaker", body), &PhoneBridge::new());
        // Each answers from a closure that returns no state, so only the flags matter here.
        for (body, expect) in [
            (r#"{"sign_out":true}"#, vec!["--sign-out"]),
            (r#"{"disconnect_chat":true}"#, vec!["--sign-out", "--chat"]),
            (r#"{"discover":true}"#, vec!["--discover", "--save"]),
            (
                r#"{"structure_id":"home-2"}"#,
                vec!["--discover", "--save", "--home", "home-2"],
            ),
            (
                r#"{"chat_monitor_action":"start"}"#,
                vec!["--chat-monitor", "start"],
            ),
            (
                r#"{"chat_monitor_action":"stop"}"#,
                vec!["--chat-monitor", "stop"],
            ),
            (r#"{"test_media_pause":true}"#, vec!["--test-media-pause"]),
            (
                r#"{"speak_clipboard":true}"#,
                vec!["--say", "clipboard announcement text"],
            ),
            (r#"{"sign_in":true}"#, vec!["--sign-in"]),
            (r#"{"grant_chat":true}"#, vec!["--sign-in", "--chat"]),
        ] {
            calls.lock().unwrap().clear();
            let _ = post(body);
            let want: Vec<String> = expect.iter().map(|s| s.to_string()).collect();
            assert_eq!(calls.lock().unwrap().first(), Some(&want), "{body}");
        }
        let mut files: Vec<String> = fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        files.sort();
        assert_eq!(files, vec!["HomeSpeaker"], "the helper wrote nothing");
    }

    #[test]
    fn test_preview_voice_uses_the_programs_local_voice_and_macos_say_only() {
        assert_eq!(
            preview_say_args(DEFAULT_LOCAL_VOICE, "Hi"),
            vec![
                vec!["-v".to_string(), "Aaron".to_string(), "Hi".to_string()],
                vec!["Hi".to_string()],
            ]
        );
        assert_eq!(
            preview_say_args("default", "Hi"),
            vec![vec!["Hi".to_string()]]
        );
        let seen = state_answering("1.41.0", golden_state());
        let (h, _d, calls) = relay_speaker("preview", move |name, args| {
            if name == "say" {
                return Ok((String::new(), String::new()));
            }
            seen(name, args)
        });
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"preview_voice":true}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 200, "{}", resp.body_string());
        let log = calls.lock().unwrap().clone();
        assert!(
            log.iter().any(|c| c
                == &vec![
                    "say".to_string(),
                    "-v".to_string(),
                    "Ava".to_string(),
                    "This is how announcements will sound.".to_string()
                ]),
            "{log:?}"
        );
        assert!(
            !log.iter().any(|c| c.iter().any(|a| a == "--say")),
            "preview is never a broadcast"
        );
    }

    #[test]
    fn test_replay_looks_the_announcement_up_in_the_programs_history() {
        let seen = state_answering("1.41.0", golden_state());
        let (h, _d, calls) = relay_speaker("replay", move |name, args| {
            match args.first().map(String::as_str) {
                Some("--say") => Ok(("spoken".to_string(), String::new())),
                _ => seen(name, args),
            }
        });
        let r = h.handle_say(&post_req(
            "/v1/homespeaker/say",
            r#"{"replay_id":"00000000-0000-0000-0000-000000000001"}"#,
        ));
        assert_eq!(r.status, 200, "{}", r.body_string());
        let said = |calls: &CallLog| {
            calls
                .lock()
                .unwrap()
                .iter()
                .filter(|c| c.first().map(String::as_str) == Some("--say"))
                .cloned()
                .collect::<Vec<_>>()
        };
        assert_eq!(
            said(&calls),
            vec![vec![
                "--say".to_string(),
                "All tests passed on main.".to_string(),
                "--no-history".to_string()
            ]],
            "a replay is kept out of the history"
        );
        let r = h.handle_say(&post_req(
            "/v1/homespeaker/say",
            r#"{"text":"again","replay":true}"#,
        ));
        assert_eq!(r.status, 200);
        assert_eq!(
            said(&calls)[1],
            vec![
                "--say".to_string(),
                "again".to_string(),
                "--no-history".to_string()
            ]
        );
        let r = h.handle_say(&post_req("/v1/homespeaker/say", r#"{"replay_id":"nope"}"#));
        assert_eq!(r.status, 400);
        assert!(r.body_string().contains("no longer in the history"));
    }

    // ---- Speech, volume, sign-in, tool presence and the choice file. ----

    #[test]
    fn test_home_speaker_say_runs_the_apps_own_say() {
        let (h, _d, calls) = relay_speaker("say", |_n, _a| {
            Ok(("sent to Lake Office display\n".to_string(), String::new()))
        });
        let resp = h.handle_say(&post_req(
            "/v1/homespeaker/say",
            r#"{"text":"  dinner is ready  "}"#,
        ));
        assert_eq!(resp.status, 200);
        let out = JsonValue::parse_bytes(&resp.body_bytes()).unwrap();
        assert_eq!(out.get_opt_bool("ok"), Some(true));
        assert_eq!(
            calls.lock().unwrap().clone(),
            vec![vec!["--say".to_string(), "dinner is ready".to_string()]]
        );
        assert!(out
            .get_str("output")
            .contains("sent to Lake Office display"));

        let resp2 = h.handle_say(&post_req("/v1/homespeaker/say", r#"{"text":"   "}"#));
        assert_eq!(resp2.status, 400);
    }

    #[test]
    fn test_home_speaker_volume_read_and_change_and_refusals() {
        let state_vol: Arc<Mutex<(i64, bool)>> = Arc::new(Mutex::new((40, false)));
        let state_c = state_vol.clone();
        let (h, _d, _calls) = relay_speaker("volume", move |_name, args| {
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
    fn test_snooze_until_with_non_ascii_text_is_a_400_not_a_panic() {
        let (h, _d, calls) =
            relay_speaker("snooze_ascii", |_n, _a| Ok((String::new(), String::new())));
        let resp = h.handle_set(
            &post_req(
                "/v1/homespeaker",
                r#"{"snooze_until":"2026é0123456789012345"}"#,
            ),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 400);
        assert!(
            calls.lock().unwrap().is_empty(),
            "nothing is sent to the program"
        );
    }

    #[test]
    fn test_sign_in_and_grant_chat_launch_the_program_with_its_own_flags() {
        let launched: CallLog = Arc::new(Mutex::new(Vec::new()));
        let launched_c = launched.clone();
        let (mut h, dir, _calls) =
            relay_speaker("sign_in", |_n, _a| Ok((String::new(), String::new())));
        h.launch = Some(Arc::new(move |_limit, name, args| {
            let mut entry = vec![name.to_string()];
            entry.extend(args.iter().cloned());
            launched_c.lock().unwrap().push(entry);
            Ok((String::new(), String::new()))
        }));
        let bin = dir.join("HomeSpeaker").to_string_lossy().into_owned();
        let phone = PhoneBridge::new();
        assert_eq!(
            h.handle_set(&post_req("/v1/homespeaker", r#"{"sign_in":true}"#), &phone)
                .status,
            200
        );
        assert_eq!(
            h.handle_set(
                &post_req("/v1/homespeaker", r#"{"grant_chat":true}"#),
                &phone
            )
            .status,
            200
        );
        assert_eq!(
            launched.lock().unwrap().clone(),
            vec![
                vec![bin.clone(), "--sign-in".to_string()],
                vec![bin, "--sign-in".to_string(), "--chat".to_string()],
            ]
        );
        // Refuses cleanly when the program is gone.
        fs::remove_file(dir.join("HomeSpeaker")).unwrap();
        assert_eq!(
            h.handle_set(&post_req("/v1/homespeaker", r#"{"sign_in":true}"#), &phone)
                .status,
            400
        );
        assert_eq!(
            h.handle_set(
                &post_req("/v1/homespeaker", r#"{"grant_chat":true}"#),
                &phone
            )
            .status,
            400
        );
    }

    #[test]
    fn test_home_speaker_sign_in_single_flight_guard_returns_409_while_busy() {
        let (mut h, _d, _calls) =
            relay_speaker("single_flight", |_n, _a| Ok((String::new(), String::new())));
        let (started_tx, started_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let release_rx = Arc::new(Mutex::new(release_rx));
        let r_rx = release_rx.clone();
        h.launch = Some(Arc::new(move |_limit, _name, _args| {
            let _ = started_tx.send(());
            let _ = r_rx.lock().unwrap().recv();
            Ok((String::new(), String::new()))
        }));
        let h = Arc::new(h);
        let h_bg = h.clone();
        let bg = std::thread::spawn(move || {
            let pb = PhoneBridge::new();
            h_bg.handle_set(&post_req("/v1/homespeaker", r#"{"sign_in":true}"#), &pb)
        });
        started_rx.recv().unwrap();

        // While the first sign-in is running, sign_in, grant_chat, and disconnect_chat all return 409.
        let phone = PhoneBridge::new();
        for payload in [
            r#"{"sign_in":true}"#,
            r#"{"grant_chat":true}"#,
            r#"{"disconnect_chat":true}"#,
        ] {
            let r_conflict = h.handle_set(&post_req("/v1/homespeaker", payload), &phone);
            assert_eq!(r_conflict.status, 409);
            let err_val = JsonValue::parse(&r_conflict.body_string()).unwrap();
            assert_eq!(err_val.get_str("error"), SIGN_IN_ALREADY_RUNNING);
        }

        release_tx.send(()).unwrap();
        assert_eq!(bg.join().unwrap().status, 200);
        release_tx.send(()).unwrap();
        let r_next = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"grant_chat":true}"#),
            &phone,
        );
        assert_eq!(r_next.status, 200);
    }

    fn door_file_naming(dir: &Path, chosen: &str, ext: &Path) {
        fs::write(
            dir.join("speaker_door.json"),
            format!(
                r#"{{"version":1,"chosen":"{chosen}","extension":{{"program":"{}","version":"1.41.0","door":1}}}}"#,
                ext.display()
            ),
        )
        .unwrap();
    }

    #[test]
    fn test_choice_file_picks_which_program_the_helper_talks_to() {
        let (h, dir, _c) = relay_speaker("choice", |_n, _a| Ok((String::new(), String::new())));
        let app = dir.join("HomeSpeaker");
        let ext = temp_dir("choice_ext").join("tool");
        fs::write(&ext, b"#!/bin/sh\n").unwrap();

        // No choice file: the app.
        assert_eq!(h.active_program().binary, app);
        assert_eq!(h.active_program().door, "app");
        assert!(!h.extension_installed());

        door_file_naming(&dir, "extension", &ext);
        assert!(h.extension_installed());
        assert_eq!(h.active_program().binary, ext);
        assert_eq!(h.active_program().door, "extension");

        door_file_naming(&dir, "app", &ext);
        assert_eq!(h.active_program().binary, app);

        // No choice recorded: the extension only when the app is not installed.
        door_file_naming(&dir, "", &ext);
        assert_eq!(h.active_program().door, "app");
        fs::remove_file(&app).unwrap();
        assert_eq!(h.active_program().door, "extension");

        // An extension that is gone, or in the Trash, is not used.
        fs::remove_file(&ext).unwrap();
        assert!(!h.extension_installed());
        assert_eq!(h.active_program().door, "app");
        assert!(is_in_trash("/Users/j/.Trash/tool"));

        // Garbage in the choice file means the app, not a crash.
        fs::write(dir.join("speaker_door.json"), "not json").unwrap();
        assert_eq!(h.active_program().door, "app");
    }

    #[test]
    fn test_home_speaker_tool_counts_an_extension_only_mac() {
        let (h, dir, _c) = relay_speaker("tool_ext", |_n, _a| Ok((String::new(), String::new())));
        fs::remove_file(dir.join("HomeSpeaker")).unwrap();
        assert!(!h.tool().available);
        let ext_bin = temp_dir("hs_tool_ext").join("tool");
        fs::write(&ext_bin, b"#!/bin/sh\n").unwrap();
        door_file_naming(&dir, "extension", &ext_bin);
        let tool = h.tool();
        assert!(
            tool.available,
            "an installed extension must make HomeSpeaker a present tool"
        );
        assert_eq!(tool.path, ext_bin.to_string_lossy());
    }

    #[test]
    fn test_probe_mixed_update_runs_plain_then_flag_then_hook_then_switch_and_stops_on_flag_failure(
    ) {
        let body = r#"{"enabled":false,"discover":true,"agent_hook_action":"remove-legacy-agent","active_door":"extension"}"#;
        let seen = state_and_apply(golden_state());
        let (h, _d, calls) = relay_speaker("probe_four_stage", move |name, args| {
            if args
                .iter()
                .map(String::as_str)
                .eq(["--discover", "--save"].into_iter())
            {
                return Ok(("saved".to_string(), String::new()));
            }
            seen(name, args)
        });
        let resp = h.handle_set(&post_req("/v1/homespeaker", body), &PhoneBridge::new());
        assert_eq!(resp.status, 200, "{}", resp.body_string());
        assert_eq!(
            calls.lock().unwrap().clone(),
            vec![
                vec!["--version".to_string()],
                vec![
                    "--apply".to_string(),
                    "--json".to_string(),
                    r#"{"contract_version":1,"operations":[{"op":"set","key":"enabled","value":false}]}"#.to_string(),
                ],
                vec!["--discover".to_string(), "--save".to_string()],
                vec![
                    "--apply".to_string(),
                    "--json".to_string(),
                    r#"{"contract_version":1,"operations":[{"op":"removeLegacyAgent"}]}"#.to_string(),
                ],
                vec![
                    "--apply".to_string(),
                    "--json".to_string(),
                    r#"{"contract_version":1,"operations":[{"op":"switchTo","side":"extension"}]}"#.to_string(),
                ],
                vec!["--state".to_string(), "--json".to_string()],
            ]
        );

        let seen = state_and_apply(golden_state());
        let (h, _d, calls) = relay_speaker("probe_flag_fails", move |name, args| {
            if args.first().map(String::as_str) == Some("--discover") {
                return Err("cast discovery timed out".to_string());
            }
            seen(name, args)
        });
        let resp = h.handle_set(&post_req("/v1/homespeaker", body), &PhoneBridge::new());
        assert_eq!(resp.status, 500);
        assert_eq!(
            applies(&calls),
            vec![
                r#"{"contract_version":1,"operations":[{"op":"set","key":"enabled","value":false}]}"#
            ],
            "flag failure must stop before removeLegacyAgent and switchTo"
        );
    }

    #[test]
    fn test_probe_secrets_never_appear_in_act_logs_or_http_responses() {
        let cases = [
            (
                r#"{"oauth_client_id":"probe-id.apps.googleusercontent.com","oauth_client_secret":"GOCSPX-PROBE-OAUTH-SECRET"}"#,
                "GOCSPX-PROBE-OAUTH-SECRET",
                "saveOAuthClient",
            ),
            (
                r#"{"slack_token":"xoxp-PROBE-SLACK-SECRET"}"#,
                "xoxp-PROBE-SLACK-SECRET",
                "setSecret:slack",
            ),
            (
                r#"{"beeper_token":"bp-PROBE-BEEPER-SECRET"}"#,
                "bp-PROBE-BEEPER-SECRET",
                "setSecret:beeper",
            ),
            (
                r#"{"courier_token":"cr-PROBE-COURIER-SECRET"}"#,
                "cr-PROBE-COURIER-SECRET",
                "setSecret:courier",
            ),
            (
                r#"{"gemini_api_key":"AIza-PROBE-GEMINI-SECRET"}"#,
                "AIza-PROBE-GEMINI-SECRET",
                "setSecret:geminiKey",
            ),
        ];
        let capture = crate::http_util::LogCapture::start();
        let (h, _d, _calls) = relay_speaker("probe_secrets_ok", state_and_apply(golden_state()));
        let seen = state_answering("1.41.0", golden_state());
        let (h_err, _d2, _c2) = relay_speaker("probe_secrets_err", move |name, args| {
            match args.first().map(String::as_str) {
                Some("--apply") => refusal("invalid_value", "Invalid token format", None),
                _ => seen(name, args),
            }
        });
        for (body, secret, want_summary) in cases {
            let u = HomeSpeakerUpdate::from_json(&JsonValue::parse(body).unwrap()).unwrap();
            let summary = h.apply(u).unwrap();
            assert_eq!(summary, want_summary);
            assert!(!summary.contains(secret));

            let ok_resp = h.handle_set(&post_req("/v1/homespeaker", body), &PhoneBridge::new());
            assert_eq!(ok_resp.status, 200);
            assert!(
                !ok_resp.body_string().contains(secret),
                "secret leaked to 200 response: {secret}"
            );

            let err_resp =
                h_err.handle_set(&post_req("/v1/homespeaker", body), &PhoneBridge::new());
            assert_eq!(err_resp.status, 400);
            assert!(
                !err_resp.body_string().contains(secret),
                "secret leaked to error response: {secret}"
            );
        }
        let logged = capture.contents();
        for (_, secret, _) in cases {
            assert!(
                !logged.contains(secret),
                "secret leaked to act log: {secret}"
            );
        }
    }

    #[test]
    fn test_probe_not_chosen_retry_verifies_named_program_version_and_missing_target_returns_409() {
        let ext_dir = temp_dir("probe_retry_old_ext");
        let ext = ext_dir.join("tool");
        fs::write(&ext, b"#!/bin/sh\n").unwrap();
        let ext_name = ext.to_string_lossy().into_owned();
        let ext_name_c = ext_name.clone();
        let (h, dir, calls) = relay_speaker("probe_retry_old", move |name, args| {
            match args.first().map(String::as_str) {
                Some("--version") if name == ext_name_c => {
                    Ok(("HomeSpeaker 1.40.0\n".to_string(), String::new()))
                }
                Some("--version") => Ok(("HomeSpeaker 1.41.0\n".to_string(), String::new())),
                Some("--apply") if name != ext_name_c => {
                    refusal("not_chosen", "The extension is chosen", Some("extension"))
                }
                Some("--apply") => panic!("must never run --apply on <1.41.0 extension"),
                _ => Err("unexpected".to_string()),
            }
        });
        door_file_naming(&dir, "app", &ext);
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"enabled":false}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 409);
        assert!(resp.body_string().contains("(have 1.40.0, need 1.41.0)"));
        assert_eq!(applies(&calls).len(), 1, "only the first door got --apply");
        assert!(calls
            .lock()
            .unwrap()
            .contains(&vec![ext_name, "--version".to_string()]));

        // Missing target binary on not_chosen returns 409 without retrying.
        fs::remove_file(&ext).unwrap();
        let (h2, dir2, calls2) = relay_speaker("probe_retry_gone", move |_name, args| {
            match args.first().map(String::as_str) {
                Some("--version") => Ok(("HomeSpeaker 1.41.0\n".to_string(), String::new())),
                Some("--apply") => {
                    refusal("not_chosen", "The extension is chosen", Some("extension"))
                }
                _ => Err("unexpected".to_string()),
            }
        });
        door_file_naming(&dir2, "app", &ext);
        let resp2 = h2.handle_set(
            &post_req("/v1/homespeaker", r#"{"enabled":false}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp2.status, 409);
        assert_eq!(applies(&calls2).len(), 1);
    }

    #[test]
    fn test_probe_v1_tools_endpoint_reports_homespeaker_from_scratch_door_without_voice_cache() {
        let (h, dir, _c) = relay_speaker("probe_v1_tools", |_n, _a| {
            Ok((String::new(), String::new()))
        });
        let store_dir = temp_dir("probe_srv_store");
        let sampler =
            crate::sampler::Sampler::new(Duration::from_secs(60), "", "", Vec::new(), None);
        let store = Arc::new(crate::pair::Store::new(store_dir));
        store.ensure_token().unwrap();
        let mut srv = crate::server::Server::new(sampler, store, "", "");
        Arc::get_mut(&mut srv).unwrap().speaker = Arc::new(h);

        let get_hs_tool = |srv: &crate::server::Server| -> JsonValue {
            let resp = srv.handle(&HttpRequest::new_test("GET", "/v1/tools", ""));
            assert_eq!(resp.status, 200);
            body_of(&resp)
                .get("tools")
                .unwrap()
                .get("homespeaker")
                .unwrap()
                .clone()
        };

        let app_path = dir.join("HomeSpeaker").to_string_lossy().into_owned();
        let t1 = get_hs_tool(&srv);
        assert!(t1.get_bool("available"));
        assert_eq!(t1.get_str("path"), app_path);

        fs::remove_file(dir.join("HomeSpeaker")).unwrap();
        let t2 = get_hs_tool(&srv);
        assert!(!t2.get_bool("available"));

        let ext_bin = temp_dir("probe_v1_tools_ext").join("tool");
        fs::write(&ext_bin, b"#!/bin/sh\n").unwrap();
        door_file_naming(&dir, "extension", &ext_bin);
        let t3 = get_hs_tool(&srv);
        assert!(t3.get_bool("available"));
        assert_eq!(t3.get_str("path"), ext_bin.to_string_lossy());
    }

    // ---- QA round 1 ----

    /// Makes the scratch program answer with an exit status, too: `(stdout, exit code)` per call.
    fn with_exit_codes(
        h: &mut HomeSpeaker,
        f: impl Fn(&[String]) -> (String, i32) + Send + Sync + 'static,
    ) {
        h.run_capture = Some(Arc::new(move |_limit, _name, args| {
            let (out, code) = f(args);
            Ok((out, String::new(), code))
        }));
    }

    #[test]
    fn test_oauth_secret_alone_uses_the_current_custom_client_id() {
        let (h, _d, calls) = relay_speaker("oauth_alone", state_and_apply(golden_state()));
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"oauth_client_secret":"new-secret"}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 200, "{}", resp.body_string());
        assert_eq!(
            applies(&calls),
            vec![
                r#"{"contract_version":1,"operations":[{"op":"saveOAuthClient","client_id":"custom-client-id.apps.googleusercontent.com","client_secret":"new-secret"}]}"#
            ]
        );
        // Clearing the secret is the same thing with a blank one.
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"oauth_client_secret":""}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 200);
        assert!(applies(&calls)[1].contains(r#""client_secret":"""#));

        // No custom id saved: say so, and send nothing.
        let none = golden_state().replace(
            "\"custom_oauth_client_id\": \"custom-client-id.apps.googleusercontent.com\"",
            "\"custom_oauth_client_id\": \"\"",
        );
        let (h, _d, calls) = relay_speaker("oauth_no_id", state_and_apply(none));
        let resp = h.handle_set(
            &post_req("/v1/homespeaker", r#"{"oauth_client_secret":"s"}"#),
            &PhoneBridge::new(),
        );
        assert_eq!(resp.status, 400);
        assert!(resp.body_string().contains("Enter the client ID first."));
        assert!(applies(&calls).is_empty());
    }

    #[test]
    fn test_version_must_exit_zero_and_look_like_a_version() {
        for (out, code) in [
            ("HomeSpeaker 1.41.0\n", 1),
            ("HomeSpeaker 41\n", 0),
            ("HomeSpeaker 1.41.0.1\n", 0),
            ("usage: HomeSpeaker [options]\n", 0),
            ("", 0),
        ] {
            let (mut h, _d, calls) =
                relay_speaker("ver_strict", |_n, _a| Ok((String::new(), String::new())));
            let out = out.to_string();
            with_exit_codes(&mut h, move |_a| (out.clone(), code));
            let b = body_of(&h.handle_get(&PhoneBridge::new()));
            assert!(!b.get_bool("available"));
            assert!(
                b.get_str("reason")
                    .contains("Could not read the Home Speaker version"),
                "{code} {}",
                b.get_str("reason")
            );
            let resp = h.handle_set(
                &post_req("/v1/homespeaker", r#"{"enabled":true}"#),
                &PhoneBridge::new(),
            );
            assert_eq!(resp.status, 500);
            assert!(
                calls.lock().unwrap().is_empty(),
                "run_capture is the only runner here"
            );
        }
    }

    #[test]
    fn test_state_needs_exit_zero_and_apply_refusals_with_json_stay_refusals() {
        let golden = golden_state();
        let g = golden.clone();
        let (mut h, _d, _c) =
            relay_speaker("state_exit", |_n, _a| Ok((String::new(), String::new())));
        with_exit_codes(&mut h, move |a| match a[0].as_str() {
            "--version" => ("HomeSpeaker 1.41.0".to_string(), 0),
            _ => (g.clone(), 1),
        });
        let b = body_of(&h.handle_get(&PhoneBridge::new()));
        assert!(!b.get_bool("available"));
        assert!(
            b.get_str("reason").contains("--state"),
            "{}",
            b.get_str("reason")
        );

        let post = |apply_out: &'static str, code: i32| {
            let g = golden.clone();
            let (mut h, _d, _c) =
                relay_speaker("apply_exit", |_n, _a| Ok((String::new(), String::new())));
            with_exit_codes(&mut h, move |a| match a[0].as_str() {
                "--version" => ("HomeSpeaker 1.41.0".to_string(), 0),
                "--apply" => (apply_out.to_string(), code),
                _ => (g.clone(), 0),
            });
            h.handle_set(
                &post_req("/v1/homespeaker", r#"{"enabled":true}"#),
                &PhoneBridge::new(),
            )
        };
        let refused =
            r#"{"ok":false,"error":{"code":"invalid_choice","message":"Pick a real choice"}}"#;
        let r = post(refused, 1);
        assert_eq!(r.status, 400);
        assert!(r.body_string().contains("Pick a real choice"));
        assert_eq!(
            post("boom", 1).status,
            500,
            "non-zero without JSON is an error"
        );
        assert_eq!(
            post(r#"{"ok":true}"#, 1).status,
            500,
            "ok:true with a failing exit is an error"
        );
        assert_eq!(
            post(r#"{"ok":true,"results":[],"state":{}}"#, 0).status,
            200
        );
    }

    #[test]
    fn test_replay_is_gated_by_version_but_plain_say_is_not() {
        let seen = state_answering("1.40.0", golden_state());
        let (h, _d, calls) = relay_speaker("replay_gate", move |name, args| {
            match args.first().map(String::as_str) {
                Some("--say") => Ok(("spoken".to_string(), String::new())),
                _ => seen(name, args),
            }
        });
        for body in [r#"{"text":"again","replay":true}"#, r#"{"replay_id":"x"}"#] {
            let r = h.handle_say(&post_req("/v1/homespeaker/say", body));
            assert_eq!(r.status, 409, "{body}");
            assert!(r.body_string().contains("(have 1.40.0, need 1.41.0)"));
        }
        assert!(!calls.lock().unwrap().iter().any(|c| c[0] == "--say"));
        let r = h.handle_say(&post_req("/v1/homespeaker/say", r#"{"text":"hello"}"#));
        assert_eq!(r.status, 200);
        assert_eq!(
            calls.lock().unwrap().last().unwrap(),
            &vec!["--say".to_string(), "hello".to_string()]
        );
    }

    #[test]
    fn test_disable_rival_takes_its_agent_from_the_slug() {
        for (action, agent) in [
            ("disable-rival:claude-code", "claude_code"),
            ("disable-rival:Claude Code", "claude_code"),
            ("disable-rival:antigravity", "antigravity"),
            ("disable-rival:OpenCode", "opencode"),
            ("disable-rival", "claude_code"),
        ] {
            let plan = plan_for(&format!("{{\"agent_hook_action\":\"{action}\"}}")).unwrap();
            assert_eq!(
                plan.hook.unwrap().to_json_string(),
                format!(
                    "{{\"op\":\"agentHook\",\"agent\":\"{agent}\",\"action\":\"disableRival\"}}"
                ),
                "{action}"
            );
        }
        assert!(matches!(
            plan_for(r#"{"agent_hook_action":"disable-rival:emacs"}"#),
            Err(ApplyError::BadRequest(_))
        ));
    }

    #[test]
    fn test_pause_margin_is_sent_as_a_whole_number() {
        assert_eq!(
            plain_json(r#"{"pause_media_extra_seconds":2.6}"#),
            r#"[{"op":"set","key":"pause_media_extra_seconds","value":3}]"#
        );
        assert_eq!(
            plain_json(r#"{"pause_media_extra_seconds":3}"#),
            r#"[{"op":"set","key":"pause_media_extra_seconds","value":3}]"#
        );
    }

    // ---- The helper no longer reads or writes Home Speaker's files. ----

    #[test]
    fn test_source_never_reads_or_writes_homespeakers_files_or_the_coding_agents_hooks() {
        let src = include_str!("homespeaker.rs");
        let prod = src.split("#[cfg(test)]").next().unwrap();
        // Strings that are pieces of the names, so this test does not trip over itself.
        let forbidden = [
            ["speaker_", "broadcast.json"].concat(),
            ["secrets", ".json"].concat(),
            ["speaker_", "history.json"].concat(),
            ["speaker_", "monitor_status.json"].concat(),
            ["speaker_", "door.json.lock"].concat(),
            [".claude/", "settings.json"].concat(),
            ["chat_", "credentials.json"].concat(),
            ["google-oauth-", "client.json"].concat(),
            ["mcp_oauth_", "tokens.json"].concat(),
            ["claude-stop-", "hook"].concat(),
            ["antigravity-", "hook"].concat(),
            ["opencode-", "hook"].concat(),
            ["com.james.", "chat-monitor"].concat(),
            ["write_atomic", "_"].concat(),
            ["flock", "("].concat(),
            ["fs::", "write("].concat(),
            ["fs::", "rename("].concat(),
            ["fs::remove", "_file("].concat(),
            ["File::", "create("].concat(),
            ["OpenOptions", "::new"].concat(),
        ];
        for word in &forbidden {
            assert!(
                !prod.contains(word.as_str()),
                "homespeaker.rs must not touch {word}: ask Home Speaker's --state / --apply"
            );
        }
        // The one file it still reads is the choice file.
        assert!(prod.contains("speaker_door.json"));
        assert_eq!(prod.matches("fs::read_to_string").count(), 1);
    }
}
