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

//! Desktop TOML configuration loading, saving, invalid-file `.bak` backup,
//! platform path resolution, and 500 ms debounced persistence.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use wand_core::{
    Binding, Button, Config, Platform, Press, RADIAL_SLOT_COUNT, RadialSlot, default_bindings,
};

/// Maximum number of timestamped `.bak` files retained when corrupt configs are encountered.
pub const MAX_CONFIG_BACKUPS: usize = 3;

static NEXT_BACKUP_SEQ: AtomicU64 = AtomicU64::new(1);

/// Debounce interval for persisting settings changes to disk (`500 ms`).
pub const SAVE_DEBOUNCE: Duration = Duration::from_millis(500);

/// Key in `Config.extra` storing the desktop UI theme preference.
pub const EXTRA_KEY_THEME: &str = "theme";

/// Key in `Config.extra` storing whether touchpad scrolling in gyro mode is enabled.
pub const EXTRA_KEY_GYRO_TOUCHPAD_SCROLL: &str = "gyro_touchpad_scroll";

/// Desktop UI theme preference persisted in `config.toml`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ThemePreference {
    /// Follow the operating system's light/dark appearance (default).
    #[default]
    System,
    /// Force Vitruvian light theme.
    Light,
    /// Force Vitruvian dark theme.
    Dark,
}

impl ThemePreference {
    /// Stable lowercase identifier stored in config.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }

    /// Display label in the header theme selector.
    pub const fn label(self) -> &'static str {
        match self {
            Self::System => "System",
            Self::Light => "Light",
            Self::Dark => "Dark",
        }
    }

    /// Parses a theme string, falling back to `System`.
    pub fn from_str_lossy(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "light" => Self::Light,
            "dark" => Self::Dark,
            _ => Self::System,
        }
    }
}

/// Reads the persisted [`ThemePreference`] from `config.extra`.
pub fn get_theme(config: &Config) -> ThemePreference {
    config
        .extra
        .get(EXTRA_KEY_THEME)
        .and_then(|v| v.as_str())
        .map(ThemePreference::from_str_lossy)
        .unwrap_or(ThemePreference::System)
}

/// Writes `theme` into `config.extra`.
pub fn set_theme(config: &mut Config, theme: ThemePreference) {
    config.extra.insert(
        EXTRA_KEY_THEME.to_string(),
        serde_json::Value::String(theme.as_str().to_string()),
    );
}

/// Reads whether touchpad scrolling in gyro mode is enabled from `config.extra` (defaults to `true`).
pub fn get_gyro_touchpad_scroll(config: &Config) -> bool {
    config
        .extra
        .get(EXTRA_KEY_GYRO_TOUCHPAD_SCROLL)
        .and_then(|v| v.as_bool())
        .unwrap_or(true)
}

/// Writes `enabled` for touchpad scrolling in gyro mode into `config.extra`.
pub fn set_gyro_touchpad_scroll(config: &mut Config, enabled: bool) {
    config.extra.insert(
        EXTRA_KEY_GYRO_TOUCHPAD_SCROLL.to_string(),
        serde_json::Value::Bool(enabled),
    );
}

/// Resolves the platform-specific config path for a given OS name (`"macos"` or `"linux"`),
/// `home` directory, and optional `xdg_config_home`.
///
/// - macOS: `<HOME>/Library/Application Support/dev.vitruvian.wand/config.toml`
/// - Linux: `<XDG_CONFIG_HOME>/wand/config.toml` (fallback `<HOME>/.config/wand/config.toml`)
pub fn config_path_for(os: &str, home: Option<&Path>, xdg_config_home: Option<&Path>) -> PathBuf {
    let home_dir = home
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));

    if os == "macos" {
        home_dir
            .join("Library")
            .join("Application Support")
            .join("dev.vitruvian.wand")
            .join("config.toml")
    } else {
        let base = match xdg_config_home {
            Some(p) if !p.as_os_str().is_empty() => p.to_path_buf(),
            _ => home_dir.join(".config"),
        };
        base.join("wand").join("config.toml")
    }
}

/// Returns the default `config.toml` path for the current host OS and environment variables.
pub fn default_config_path() -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let xdg = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from);
    config_path_for(std::env::consts::OS, home.as_deref(), xdg.as_deref())
}

/// Returns all existing `.bak` backup files for `path`, sorted oldest-to-newest.
pub fn backup_config_paths(path: &Path) -> Vec<PathBuf> {
    let Some(parent) = path.parent() else {
        return Vec::new();
    };
    let Some(file_name) = path.file_name().and_then(|s| s.to_str()) else {
        return Vec::new();
    };
    let prefix = format!("{file_name}.");
    let legacy_name = format!("{file_name}.bak");

    let Ok(entries) = fs::read_dir(parent) else {
        return Vec::new();
    };

    let mut backups: Vec<(String, PathBuf)> = entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().into_string().ok()?;
            if name == legacy_name || (name.starts_with(&prefix) && name.ends_with(".bak")) {
                Some((name, entry.path()))
            } else {
                None
            }
        })
        .collect();

    backups.sort_by(|a, b| a.0.cmp(&b.0));
    backups.into_iter().map(|(_, p)| p).collect()
}

/// Returns the most recent backup path for `path` if one exists on disk, or `<path>.bak` otherwise.
pub fn backup_config_path(path: &Path) -> PathBuf {
    if let Some(latest) = backup_config_paths(path).pop() {
        return latest;
    }
    let mut os = path.as_os_str().to_os_string();
    os.push(".bak");
    PathBuf::from(os)
}

/// Creates a new timestamped `.bak` copy of `path` and prunes older backups so at most
/// [`MAX_CONFIG_BACKUPS`] (3) are kept.
fn create_timestamped_backup(path: &Path) -> PathBuf {
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let seq = NEXT_BACKUP_SEQ.fetch_add(1, Ordering::Relaxed);
    let mut os = path.as_os_str().to_os_string();
    os.push(format!(".{now_ms:013}-{seq:06}.bak"));
    let bak_path = PathBuf::from(os);
    let _ = fs::copy(path, &bak_path);

    let all_backups = backup_config_paths(path);
    if all_backups.len() > MAX_CONFIG_BACKUPS {
        let to_remove = all_backups.len() - MAX_CONFIG_BACKUPS;
        for old in all_backups.into_iter().take(to_remove) {
            let _ = fs::remove_file(old);
        }
    }
    bak_path
}

/// Serializes `config` into a formatted TOML string (clamping any non-finite or out-of-range settings).
pub fn serialize_config_toml(config: &Config) -> Result<String, String> {
    let sanitized = config.clone().sanitized();
    let mut json_val =
        serde_json::to_value(&sanitized).map_err(|e| format!("failed to serialize Config: {e}"))?;
    strip_nulls(&mut json_val);
    let table: toml::Table = serde_json::from_value(json_val)
        .map_err(|e| format!("failed to convert Config to TOML table: {e}"))?;
    toml::to_string_pretty(&table).map_err(|e| format!("failed to format TOML: {e}"))
}

/// Parses a TOML string into a sanitized [`Config`], recovering valid fields if individual fields
/// are malformed.
pub fn deserialize_config_toml(raw: &str) -> Result<Config, String> {
    let (cfg, _) = deserialize_config_toml_detailed(raw)?;
    Ok(cfg)
}

fn deserialize_config_toml_detailed(raw: &str) -> Result<(Config, bool), String> {
    match toml::from_str::<toml::Table>(raw) {
        Ok(table) => Ok(parse_config_table(&table)),
        Err(err) => {
            if let Some(salvaged) = salvage_toml_table(raw) {
                let (cfg, _) = parse_config_table(&salvaged);
                Ok((cfg, true))
            } else {
                Err(format!("invalid TOML syntax: {err}"))
            }
        }
    }
}

/// Attempts to salvage valid lines from a TOML document that has syntax errors on isolated lines.
fn salvage_toml_table(raw: &str) -> Option<toml::Table> {
    let mut accepted_lines: Vec<&str> = Vec::new();
    let mut accepted_key_count = 0usize;

    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        accepted_lines.push(line);
        let candidate = accepted_lines.join("\n");
        if toml::from_str::<toml::Table>(&candidate).is_ok() {
            if !trimmed.starts_with('[') {
                accepted_key_count += 1;
            }
        } else {
            accepted_lines.pop();
        }
    }

    if accepted_key_count == 0 {
        return None;
    }
    toml::from_str::<toml::Table>(&accepted_lines.join("\n")).ok()
}

fn parse_config_table(table: &toml::Table) -> (Config, bool) {
    let mut cfg = Config::for_platform(Platform::Desktop);
    let mut had_bad_field = false;

    for (k, v) in table {
        match k.as_str() {
            "version" => {
                if let Some(i) = v.as_integer()
                    && u32::try_from(i).is_ok()
                {
                    cfg.version = i as u32;
                } else {
                    had_bad_field = true;
                }
            }
            "platform" => {
                if v.clone().try_into::<Platform>().is_err() {
                    had_bad_field = true;
                }
                cfg.platform = Platform::Desktop;
            }
            "settings" => {
                if let Some(settings_tbl) = v.as_table() {
                    if parse_settings_table(settings_tbl, &mut cfg.settings) {
                        had_bad_field = true;
                    }
                } else {
                    had_bad_field = true;
                }
            }
            "bindings" => {
                if let Some(bindings_tbl) = v.as_table() {
                    if parse_bindings_table(bindings_tbl, &mut cfg.bindings) {
                        had_bad_field = true;
                    }
                } else {
                    had_bad_field = true;
                }
            }
            "radial_slots" => {
                if let Some(arr) = v.as_array() {
                    for (idx, item) in arr.iter().enumerate().take(RADIAL_SLOT_COUNT) {
                        match item.clone().try_into::<RadialSlot>() {
                            Ok(slot) => cfg.radial_slots[idx] = slot,
                            Err(_) => had_bad_field = true,
                        }
                    }
                } else {
                    had_bad_field = true;
                }
            }
            _ => {
                if let Some(json_v) = toml_to_json_value(v) {
                    cfg.extra.insert(k.clone(), json_v);
                }
            }
        }
    }

    cfg.platform = Platform::Desktop;
    cfg.sanitize();
    (cfg, had_bad_field)
}

fn as_f32_lossy(v: &toml::Value) -> Option<f32> {
    v.as_float()
        .map(|f| f as f32)
        .or_else(|| v.as_integer().map(|i| i as f32))
}

fn as_u64_lossy(v: &toml::Value, default: u64) -> Option<u64> {
    if let Some(i) = v.as_integer() {
        Some(if i < 0 { 0 } else { i as u64 })
    } else if let Some(f) = v.as_float() {
        if f.is_nan() {
            Some(default)
        } else if f <= 0.0 {
            Some(0)
        } else if f >= u64::MAX as f64 {
            Some(u64::MAX)
        } else {
            Some(f as u64)
        }
    } else {
        None
    }
}

fn parse_settings_table(tbl: &toml::Table, settings: &mut wand_core::Settings) -> bool {
    let mut had_bad_field = false;

    for (k, v) in tbl {
        match k.as_str() {
            "pointing_mode" => match v.clone().try_into::<wand_core::PointingMode>() {
                Ok(m) => settings.pointing_mode = m,
                Err(_) => had_bad_field = true,
            },
            "pointing_span_deg" => match as_f32_lossy(v) {
                Some(x) => settings.pointing_span_deg = x,
                None => had_bad_field = true,
            },
            "screen_width_px" => match as_u64_lossy(v, settings.screen_width_px) {
                Some(x) => settings.screen_width_px = x,
                None => had_bad_field = true,
            },
            "motion_glide" => match v.as_bool() {
                Some(b) => settings.motion_glide = b,
                None => had_bad_field = true,
            },
            "touch_sensitivity" => match as_f32_lossy(v) {
                Some(x) => settings.touch_sensitivity = x,
                None => had_bad_field = true,
            },
            "gyro_x_speed" => match as_f32_lossy(v) {
                Some(x) => settings.gyro_x_speed = x,
                None => had_bad_field = true,
            },
            "gyro_y_speed" => match as_f32_lossy(v) {
                Some(x) => settings.gyro_y_speed = x,
                None => had_bad_field = true,
            },
            "gyro_deadzone" => match as_f32_lossy(v) {
                Some(x) => settings.gyro_deadzone = x,
                None => had_bad_field = true,
            },
            "touch_deadzone" => match as_f32_lossy(v) {
                Some(x) => settings.touch_deadzone = x,
                None => had_bad_field = true,
            },
            "acceleration_curve" => match as_f32_lossy(v) {
                Some(x) => settings.acceleration_curve = x,
                None => had_bad_field = true,
            },
            "ema_smoothing" => match as_f32_lossy(v) {
                Some(x) => settings.ema_smoothing = x,
                None => had_bad_field = true,
            },
            "scroll_strength" => match as_f32_lossy(v) {
                Some(x) => settings.scroll_strength = x,
                None => had_bad_field = true,
            },
            "radial_dead_radius" => match as_f32_lossy(v) {
                Some(x) => settings.radial_dead_radius = x,
                None => had_bad_field = true,
            },
            "overlay_cursor_size" => match as_f32_lossy(v) {
                Some(x) => settings.overlay_cursor_size = x,
                None => had_bad_field = true,
            },
            "long_press_ms" => match as_u64_lossy(v, settings.long_press_ms) {
                Some(x) => settings.long_press_ms = x,
                None => had_bad_field = true,
            },
            "double_press_ms" => match as_u64_lossy(v, settings.double_press_ms) {
                Some(x) => settings.double_press_ms = x,
                None => had_bad_field = true,
            },
            "reverse_scroll" => match v.as_bool() {
                Some(b) => settings.reverse_scroll = b,
                None => had_bad_field = true,
            },
            "horizontal_scroll" => match v.as_bool() {
                Some(b) => settings.horizontal_scroll = b,
                None => had_bad_field = true,
            },
            "tap_in_touch_mode" => match v.as_bool() {
                Some(b) => settings.tap_in_touch_mode = b,
                None => had_bad_field = true,
            },
            "tap_in_gyro_mode" => match v.as_bool() {
                Some(b) => settings.tap_in_gyro_mode = b,
                None => had_bad_field = true,
            },
            "auto_reconnect" => match v.as_bool() {
                Some(b) => settings.auto_reconnect = b,
                None => had_bad_field = true,
            },
            "overlay_cursor" => match v.as_bool() {
                Some(b) => settings.overlay_cursor = b,
                None => had_bad_field = true,
            },
            other => {
                if let Some(json_v) = toml_to_json_value(v) {
                    settings.extra.insert(other.to_string(), json_v);
                }
            }
        }
    }

    had_bad_field
}

fn parse_bindings_table(
    tbl: &toml::Table,
    bindings: &mut BTreeMap<(Button, Press), Binding>,
) -> bool {
    let defaults = default_bindings(Platform::Desktop);
    let mut parsed = BTreeMap::new();
    let mut had_bad_field = false;

    for (k, v) in tbl {
        if let Some((btn_str, press_str)) = k.split_once('.').or_else(|| k.split_once(':')) {
            if let (Ok(button), Ok(press)) = (btn_str.parse::<Button>(), press_str.parse::<Press>())
            {
                match v.clone().try_into::<Binding>() {
                    Ok(binding) => {
                        parsed.insert((button, press), binding);
                    }
                    Err(_) => {
                        had_bad_field = true;
                        if let Some(def) = defaults.get(&(button, press)) {
                            parsed.insert((button, press), def.clone());
                        }
                    }
                }
            } else {
                had_bad_field = true;
            }
        } else if let (Ok(button), Some(sub_tbl)) = (k.parse::<Button>(), v.as_table()) {
            for (press_str, pv) in sub_tbl {
                if let Ok(press) = press_str.parse::<Press>() {
                    match pv.clone().try_into::<Binding>() {
                        Ok(binding) => {
                            parsed.insert((button, press), binding);
                        }
                        Err(_) => {
                            had_bad_field = true;
                            if let Some(def) = defaults.get(&(button, press)) {
                                parsed.insert((button, press), def.clone());
                            }
                        }
                    }
                } else {
                    had_bad_field = true;
                }
            }
        } else {
            had_bad_field = true;
        }
    }

    if !parsed.is_empty() || !had_bad_field {
        *bindings = parsed;
    }
    had_bad_field
}

fn toml_to_json_value(v: &toml::Value) -> Option<serde_json::Value> {
    match v {
        toml::Value::String(s) => Some(serde_json::Value::String(s.clone())),
        toml::Value::Integer(i) => Some(serde_json::Value::Number((*i).into())),
        toml::Value::Float(f) => {
            if f.is_finite() {
                serde_json::Number::from_f64(*f).map(serde_json::Value::Number)
            } else {
                None
            }
        }
        toml::Value::Boolean(b) => Some(serde_json::Value::Bool(*b)),
        toml::Value::Datetime(dt) => Some(serde_json::Value::String(dt.to_string())),
        toml::Value::Array(arr) => {
            let items: Vec<serde_json::Value> = arr.iter().filter_map(toml_to_json_value).collect();
            Some(serde_json::Value::Array(items))
        }
        toml::Value::Table(tbl) => {
            let mut map = serde_json::Map::new();
            for (k, val) in tbl {
                if let Some(jv) = toml_to_json_value(val) {
                    map.insert(k.clone(), jv);
                }
            }
            Some(serde_json::Value::Object(map))
        }
    }
}

fn strip_nulls(val: &mut serde_json::Value) {
    match val {
        serde_json::Value::Object(map) => {
            map.retain(|_, v| !v.is_null());
            for v in map.values_mut() {
                strip_nulls(v);
            }
        }
        serde_json::Value::Array(arr) => {
            for item in arr {
                strip_nulls(item);
            }
        }
        _ => {}
    }
}

/// Loads [`Config`] from `path`.
///
/// - If `path` does not exist, returns `Config::for_platform(Platform::Desktop)`.
/// - If `path` has a single malformed field, recovers all valid fields and defaults only the bad
///   fields, while writing a timestamped `.bak` backup (keeping the last 3).
/// - If `path` is unreadable or completely invalid TOML, backs up the file to a timestamped `.bak`
///   (keeping the last 3) and returns defaults.
pub fn load_config_from(path: &Path) -> Config {
    if !path.exists() {
        return Config::for_platform(Platform::Desktop);
    }

    match fs::read_to_string(path) {
        Ok(contents) => match deserialize_config_toml_detailed(&contents) {
            Ok((cfg, had_bad_field)) => {
                if had_bad_field {
                    let bak = create_timestamped_backup(path);
                    log::warn!(
                        "Config at {} had malformed field(s); backed up to {} and defaulted bad fields",
                        path.display(),
                        bak.display()
                    );
                }
                cfg
            }
            Err(err) => {
                let bak = create_timestamped_backup(path);
                log::warn!(
                    "Invalid config at {} ({err}); backed up to {} and using defaults",
                    path.display(),
                    bak.display()
                );
                Config::for_platform(Platform::Desktop)
            }
        },
        Err(err) => {
            let bak = create_timestamped_backup(path);
            log::warn!(
                "Could not read config at {} ({err}); backed up to {} and using defaults",
                path.display(),
                bak.display()
            );
            Config::for_platform(Platform::Desktop)
        }
    }
}

/// Writes `config` as TOML to `path`, creating parent directories as needed.
pub fn save_config_to(path: &Path, config: &Config) -> Result<(), String> {
    if let Some(parent) = path.parent()
        && !parent.as_os_str().is_empty()
    {
        fs::create_dir_all(parent)
            .map_err(|e| format!("failed to create config dir {}: {e}", parent.display()))?;
    }
    let toml_text = serialize_config_toml(config)?;
    fs::write(path, toml_text)
        .map_err(|e| format!("failed to write config {}: {e}", path.display()))
}

/// Debounced configuration saver that coalesces rapid UI edits into a single disk write after 500 ms.
#[derive(Debug, Clone)]
pub struct DebouncedSaver {
    path: PathBuf,
    debounce: Duration,
    dirty_since: Option<Instant>,
}

impl DebouncedSaver {
    /// Creates a new [`DebouncedSaver`] writing to `path` with the default 500 ms debounce.
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            debounce: SAVE_DEBOUNCE,
            dirty_since: None,
        }
    }

    /// Creates a new [`DebouncedSaver`] with a custom debounce interval.
    pub fn with_debounce(path: PathBuf, debounce: Duration) -> Self {
        Self {
            path,
            debounce,
            dirty_since: None,
        }
    }

    /// Returns the target config file path.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Returns `true` if there is a pending unsaved change.
    pub const fn is_dirty(&self) -> bool {
        self.dirty_since.is_some()
    }

    /// Marks the configuration as modified at `now`.
    pub fn mark_dirty_at(&mut self, now: Instant) {
        self.dirty_since = Some(now);
    }

    /// Marks the configuration as modified at `Instant::now()`.
    pub fn mark_dirty(&mut self) {
        self.mark_dirty_at(Instant::now());
    }

    /// Saves `config` if it has been dirty for at least `self.debounce` as of `now`.
    /// Returns `Ok(true)` when a save was performed.
    pub fn poll_save(&mut self, config: &Config, now: Instant) -> Result<bool, String> {
        if let Some(since) = self.dirty_since
            && now.saturating_duration_since(since) >= self.debounce
        {
            self.dirty_since = None;
            save_config_to(&self.path, config)?;
            return Ok(true);
        }
        Ok(false)
    }

    /// Immediately writes `config` to disk if dirty.
    pub fn flush(&mut self, config: &Config) -> Result<bool, String> {
        if self.dirty_since.take().is_some() {
            save_config_to(&self.path, config)?;
            Ok(true)
        } else {
            Ok(false)
        }
    }
}
