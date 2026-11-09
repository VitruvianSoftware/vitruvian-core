// Copyright (c) 2026 VitruvianSoftware

//! Pure Rust bridge over [`wand_core::Engine`] used by the thin JNI layer.
//!
//! Keeping all JSON marshaling, handle slot management, error formatting, and panic
//! catching in this module allows full host-side unit testing via `wand_rust_test`
//! without a JVM.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Mutex;
use wand_core::{Config, Engine, Platform};

/// Length of a Daydream BLE notification payload in bytes.
pub const PACKET_LEN: usize = 20;

/// Platform code for Desktop (`0`).
pub const PLATFORM_DESKTOP: i32 = 0;
/// Platform code for Android phones/tablets (`1`).
pub const PLATFORM_ANDROID: i32 = 1;
/// Platform code for Android TV (`2`).
pub const PLATFORM_ANDROID_TV: i32 = 2;

/// Slot backing an opaque JNI `jlong` handle (`Box<Mutex<Option<Bridge>>>`).
///
/// On `destroy_handle`, the inner `Option<Bridge>` is `.take()`n (dropping the
/// [`Bridge`] immediately) while keeping the `Mutex<Option<Bridge>>` allocation
/// valid in the `None` state so any stray post-destroy JNI call returns an error
/// JSON instead of dereferencing freed memory.
pub type HandleSlot = Mutex<Option<Bridge>>;

/// Converts an integer platform code from JNI into a [`Platform`].
pub fn platform_from_int(platform_int: i32) -> Result<Platform, String> {
    match platform_int {
        PLATFORM_DESKTOP => Ok(Platform::Desktop),
        PLATFORM_ANDROID => Ok(Platform::Android),
        PLATFORM_ANDROID_TV => Ok(Platform::AndroidTv),
        other => Err(format!("invalid platform code: {other}")),
    }
}

/// Formats an error message as a JSON object `{"error": "<msg>"}`.
pub fn error_json(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}

/// Extracts a human-readable message from a panic payload.
pub fn panic_payload_message(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = payload.downcast_ref::<&'static str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "unknown panic".to_string()
    }
}

/// Runs `op` inside `catch_unwind`, converting both `Err(String)` and any Rust
/// panic into a JSON `{"error": "..."}` string so panics never cross JNI.
pub fn catch_to_json<F>(op: F) -> String
where
    F: FnOnce() -> Result<String, String>,
{
    match catch_unwind(AssertUnwindSafe(op)) {
        Ok(Ok(json)) => json,
        Ok(Err(err)) => error_json(&err),
        Err(payload) => {
            let msg = panic_payload_message(payload.as_ref());
            error_json(&format!("panic: {msg}"))
        }
    }
}

/// Allocates a new [`HandleSlot`] (`Box<Mutex<Option<Bridge>>>`) and returns its
/// opaque `i64` handle.
pub fn create_handle(platform_int: i32, config_json: &str) -> Result<i64, String> {
    let bridge = Bridge::new(platform_int, config_json)?;
    let boxed: Box<HandleSlot> = Box::new(Mutex::new(Some(bridge)));
    Ok(Box::into_raw(boxed) as i64)
}

/// Marks a handle slot as destroyed by taking and dropping the inner [`Bridge`].
///
/// # Safety
/// `handle` must be `0` or a pointer returned by [`create_handle`].
pub unsafe fn destroy_handle(handle: i64) {
    if handle != 0 {
        let ptr = handle as *const HandleSlot;
        let mutex = unsafe { &*ptr };
        if let Ok(mut guard) = mutex.lock() {
            let _ = guard.take();
        }
    }
}

/// Borrows the [`Bridge`] inside a [`HandleSlot`], returning an `Err` if `handle`
/// is `0` or has already been destroyed via [`destroy_handle`].
///
/// # Safety
/// `handle` must be `0` or a pointer returned by [`create_handle`].
pub unsafe fn with_bridge<R, F>(handle: i64, f: F) -> Result<R, String>
where
    F: FnOnce(&mut Bridge) -> Result<R, String>,
{
    if handle == 0 {
        return Err("null WandNative handle".to_string());
    }
    let ptr = handle as *const HandleSlot;
    let mutex = unsafe { &*ptr };
    let mut guard = mutex
        .lock()
        .map_err(|_| "WandNative bridge mutex poisoned".to_string())?;
    let bridge = guard
        .as_mut()
        .ok_or_else(|| "WandNative handle already destroyed".to_string())?;
    f(bridge)
}

/// Stateful wrapper around [`wand_core::Engine`] exposed to JNI via an opaque handle.
pub struct Bridge {
    engine: Engine,
}

impl Bridge {
    /// Creates a new [`Bridge`] for `platform_int` (`1` = Android, `2` = AndroidTv)
    /// and an optional JSON-encoded [`Config`]. When `config_json` is empty or
    /// whitespace, [`Config::for_platform`] is used.
    pub fn new(platform_int: i32, config_json: &str) -> Result<Self, String> {
        let platform = platform_from_int(platform_int)?;
        let config = if config_json.trim().is_empty() {
            Config::for_platform(platform)
        } else {
            serde_json::from_str::<Config>(config_json)
                .map_err(|e| format!("invalid config JSON: {e}"))?
        };
        Ok(Self {
            engine: Engine::new(config, platform),
        })
    }

    /// Returns the serialized default [`Config`] JSON for `platform_int` (`1` = Android, `2` = AndroidTv).
    pub fn default_config(platform_int: i32) -> Result<String, String> {
        let platform = platform_from_int(platform_int)?;
        let cfg = Config::for_platform(platform);
        serde_json::to_string(&cfg).map_err(|e| format!("failed to serialize default config: {e}"))
    }

    /// Feeds a 20-byte BLE notification packet and timestamp (in microseconds)
    /// into the engine and returns a JSON array of emitted [`wand_core::Action`]s.
    pub fn feed(&mut self, bytes: &[u8], t_us: u64) -> Result<String, String> {
        let packet: &[u8; PACKET_LEN] = bytes.try_into().map_err(|_| {
            format!(
                "invalid packet length: expected {PACKET_LEN}, got {}",
                bytes.len()
            )
        })?;
        let actions = self.engine.feed(packet, t_us);
        serde_json::to_string(&actions).map_err(|e| format!("failed to serialize actions: {e}"))
    }

    /// Advances button long-press and double-press timers at `t_us` (in microseconds)
    /// without a new BLE packet and returns a JSON array of emitted [`wand_core::Action`]s.
    pub fn tick(&mut self, t_us: u64) -> Result<String, String> {
        let actions = self.engine.tick(t_us);
        serde_json::to_string(&actions).map_err(|e| format!("failed to serialize actions: {e}"))
    }

    /// Releases every active Hold/Toggle binding (e.g. emitting `MouseUp` for held clicks),
    /// resets button and pointer state machines, and returns a JSON array of release [`wand_core::Action`]s.
    pub fn release_all(&mut self) -> Result<String, String> {
        let actions = self.engine.release_all();
        serde_json::to_string(&actions).map_err(|e| format!("failed to serialize actions: {e}"))
    }

    /// Updates the engine configuration from a JSON string.
    pub fn set_config(&mut self, config_json: &str) -> Result<(), String> {
        let config = serde_json::from_str::<Config>(config_json)
            .map_err(|e| format!("invalid config JSON: {e}"))?;
        self.engine.set_config(config);
        Ok(())
    }

    /// Serializes the active engine configuration as a JSON string.
    pub fn get_config(&self) -> Result<String, String> {
        serde_json::to_string(self.engine.config())
            .map_err(|e| format!("failed to serialize config: {e}"))
    }

    /// Enables or disables test mode (suppresses action emission while keeping `last_sample` live).
    pub fn set_test_mode(&mut self, enabled: bool) {
        self.engine.set_test_mode(enabled);
    }

    /// Returns whether test mode is currently active.
    pub fn is_test_mode(&self) -> bool {
        self.engine.is_test_mode()
    }

    /// Requests gyro/orientation recentering on the next packet.
    pub fn recalibrate(&mut self) {
        self.engine.recalibrate();
    }

    /// Returns the most recently decoded [`wand_core::Sample`] as JSON (or `"null"` if none).
    pub fn last_sample(&self) -> Result<String, String> {
        serde_json::to_string(&self.engine.last_sample())
            .map_err(|e| format!("failed to serialize sample: {e}"))
    }

    /// Returns `true` when the battery percentage (0-100) is below the low-battery threshold (< 15%).
    pub fn battery_low(level: i32) -> bool {
        let clamped = level.clamp(0, 100) as u8;
        wand_core::battery_low(clamped)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wand_core::replay::parse;
    use wand_core::{Action, Button, NavAction, Press};

    const SESSION_REPLAY: &str = r#"# Copyright (c) 2026 VitruvianSoftware
# Deterministic replay session exercising touch move, click, gyro toggle, gyro move, and scroll.
# Format: <t_us> <40 hex chars>

# 1. Touch down at (x=64/255, y=64/255) - first sample anchored (no jump)
10000 0000000000000000000000000000000008080000
# 2. Touch move to (x=128/255, y=64/255) -> Move { dx > 0, dy == 0 }
20000 0004000000000000000000000000000010080000
# 3. Touch release
30000 0008000000000000000000000000000000000000
# 4. Click press -> MouseDown
40000 000c000000000000000000000000000000000100
# 5. Click release (< 500ms) -> MouseUp
90000 0010000000000000000000000000000000000000
# 6. App press
100000 0014000000000000000000000000000000000400
# 7. App release -> ToggleGyro
150000 0018000000000000000000000000000000000000
# 8. Gyro motion in gyro mode (xGyro raw = 128) -> Move { dx > 0, dy == 0 }
170000 001c000000000000000000004000000000000000
# 9. VolUp press
200000 0020000000000000000000000000000000001000
# 10. VolUp release -> Scroll { dx: 0.0, dy: 1.0 }
250000 0024000000000000000000000000000000000000
"#;

    #[test]
    fn config_json_round_trip_android_and_tv() {
        let mut bridge = Bridge::new(PLATFORM_ANDROID, "").expect("create default android bridge");
        let initial_json = bridge.get_config().expect("get_config");
        let mut cfg: Config = serde_json::from_str(&initial_json).expect("parse initial config");
        assert_eq!(cfg.platform, Platform::Android);
        cfg.settings.touch_sensitivity = 625.0;
        cfg.settings.reverse_scroll = true;
        cfg.settings.scroll_strength = 2.5;
        cfg.settings.overlay_cursor_size = 36.0;

        let updated_input = serde_json::to_string(&cfg).expect("serialize updated config");
        bridge.set_config(&updated_input).expect("set_config");

        let round_trip_json = bridge.get_config().expect("get_config after set");
        let round_trip_cfg: Config =
            serde_json::from_str(&round_trip_json).expect("parse round trip");
        assert_eq!(round_trip_cfg, cfg);

        let tv_bridge = Bridge::new(PLATFORM_ANDROID_TV, "").expect("create default tv bridge");
        let tv_cfg: Config = serde_json::from_str(&tv_bridge.get_config().unwrap()).unwrap();
        assert_eq!(tv_cfg.platform, Platform::AndroidTv);
    }

    #[test]
    fn default_config_android_home_short_back_long_home_and_tv_app_short_toggle_gyro() {
        let android_json =
            Bridge::default_config(PLATFORM_ANDROID).expect("default_config android");
        let android_cfg: Config =
            serde_json::from_str(&android_json).expect("parse android default config");
        assert_eq!(android_cfg.platform, Platform::Android);
        assert_eq!(
            android_cfg
                .bindings
                .get(&(Button::Home, Press::Short))
                .map(|b| &b.action),
            Some(&Action::Nav(NavAction::Back)),
            "Android Home short must default to Back"
        );
        assert_eq!(
            android_cfg
                .bindings
                .get(&(Button::Home, Press::Long))
                .map(|b| &b.action),
            Some(&Action::Nav(NavAction::Home)),
            "Android Home long must default to Home"
        );

        let tv_json = Bridge::default_config(PLATFORM_ANDROID_TV).expect("default_config tv");
        let tv_cfg: Config = serde_json::from_str(&tv_json).expect("parse tv default config");
        assert_eq!(tv_cfg.platform, Platform::AndroidTv);
        assert_eq!(
            tv_cfg
                .bindings
                .get(&(Button::App, Press::Short))
                .map(|b| &b.action),
            Some(&Action::ToggleGyro),
            "TV App short must default to ToggleGyro"
        );
    }

    #[test]
    fn release_all_and_tick_bridge_through_wand_core() {
        let mut bridge = Bridge::new(PLATFORM_ANDROID, "").expect("create bridge");

        // Feed packet #4 (Click down -> MouseDown)
        let click_down_records =
            parse("40000 000c000000000000000000000000000000000100\n").expect("parse click down");
        let down_json = bridge
            .feed(&click_down_records[0].packet, click_down_records[0].t_us)
            .expect("feed click down");
        let down_actions: Vec<Action> = serde_json::from_str(&down_json).unwrap();
        assert_eq!(down_actions, vec![Action::MouseDown]);

        // release_all while click is held emits MouseUp
        let release_json = bridge.release_all().expect("release_all");
        let release_actions: Vec<Action> = serde_json::from_str(&release_json).unwrap();
        assert_eq!(release_actions, vec![Action::MouseUp]);

        // Second release_all is empty
        let release_again_json = bridge.release_all().expect("release_all again");
        let release_again: Vec<Action> = serde_json::from_str(&release_again_json).unwrap();
        assert!(release_again.is_empty());

        // Press Home button (bit 1 -> 0x0200 at byte 18) at t=100_000us, then tick past 500ms without packet
        let mut home_down_pkt = [0u8; 20];
        home_down_pkt[18] = 0x02;
        let initial_home_json = bridge
            .feed(&home_down_pkt, 100_000)
            .expect("feed home down");
        let initial_home_actions: Vec<Action> = serde_json::from_str(&initial_home_json).unwrap();
        assert!(initial_home_actions.is_empty());

        let tick_json = bridge
            .tick(650_000)
            .expect("tick past long press threshold");
        let tick_actions: Vec<Action> = serde_json::from_str(&tick_json).unwrap();
        assert_eq!(tick_actions, vec![Action::Nav(NavAction::Home)]);
    }

    #[test]
    fn stray_call_after_destroy_handle_returns_error_json_not_uaf() {
        let handle = create_handle(PLATFORM_ANDROID, "").expect("create handle");
        assert_ne!(handle, 0);

        let before = catch_to_json(|| unsafe { with_bridge(handle, |b| b.get_config()) });
        assert!(!before.contains("\"error\""));

        unsafe {
            destroy_handle(handle);
        }

        // Calling after destroy must safely return error JSON instead of touching freed Bridge memory
        let after_cfg = catch_to_json(|| unsafe { with_bridge(handle, |b| b.get_config()) });
        let val: serde_json::Value = serde_json::from_str(&after_cfg).expect("valid error json");
        assert_eq!(
            val.get("error").and_then(|v| v.as_str()),
            Some("WandNative handle already destroyed")
        );

        let after_feed =
            catch_to_json(|| unsafe { with_bridge(handle, |b| b.feed(&[0u8; 20], 10_000)) });
        let feed_val: serde_json::Value =
            serde_json::from_str(&after_feed).expect("valid error json");
        assert_eq!(
            feed_val.get("error").and_then(|v| v.as_str()),
            Some("WandNative handle already destroyed")
        );

        // Double destroy is also a safe no-op
        unsafe {
            destroy_handle(handle);
        }
    }

    #[test]
    fn feed_session_replay_packets_produces_actions() {
        let replay_text = std::fs::read_to_string("apps/suites/wand/core/testdata/session.replay")
            .unwrap_or_else(|_| SESSION_REPLAY.to_string());
        let records = parse(&replay_text).expect("parse session.replay");
        assert!(!records.is_empty(), "session.replay must contain packets");

        let mut bridge = Bridge::new(PLATFORM_ANDROID, "").expect("create bridge");
        let mut all_actions: Vec<Action> = Vec::new();
        for record in &records {
            let json = bridge
                .feed(&record.packet, record.t_us)
                .expect("feed packet");
            let batch: Vec<Action> = serde_json::from_str(&json).expect("deserialize action batch");
            all_actions.extend(batch);
        }

        assert!(
            !all_actions.is_empty(),
            "feeding session.replay must emit a non-empty action list"
        );
        assert!(
            all_actions
                .iter()
                .any(|a| matches!(a, Action::Move { dx, .. } if *dx > 0.0)),
            "expected positive Move action in {all_actions:?}"
        );
        assert!(all_actions.contains(&Action::MouseDown));
        assert!(all_actions.contains(&Action::MouseUp));
        assert!(all_actions.contains(&Action::ToggleGyro));
        assert!(
            all_actions
                .iter()
                .any(|a| matches!(a, Action::Scroll { dy, .. } if *dy > 0.0)),
            "expected positive Scroll action in {all_actions:?}"
        );

        let sample_json = bridge.last_sample().expect("last_sample");
        assert_ne!(sample_json, "null");
        let sample: wand_core::Sample =
            serde_json::from_str(&sample_json).expect("deserialize Sample");
        assert_eq!(sample.seq, 9);
    }

    #[test]
    fn bad_config_json_returns_error_not_panic() {
        let bad_new = Bridge::new(PLATFORM_ANDROID, "{not-valid-json");
        assert!(bad_new.is_err());

        let mut bridge = Bridge::new(PLATFORM_ANDROID, "").expect("valid bridge");
        let bad_set = bridge.set_config("{broken: true");
        assert!(bad_set.is_err());

        let caught = catch_to_json(|| {
            bridge.set_config("{broken: true")?;
            Ok("{\"ok\":true}".to_string())
        });
        let val: serde_json::Value = serde_json::from_str(&caught).expect("error json is valid");
        assert!(val
            .get("error")
            .and_then(|v| v.as_str())
            .is_some_and(|s| s.contains("invalid config JSON")));

        let panic_caught = catch_to_json(|| -> Result<String, String> {
            panic!("simulated panic in JNI bridge");
        });
        let panic_val: serde_json::Value =
            serde_json::from_str(&panic_caught).expect("panic json is valid");
        assert!(panic_val
            .get("error")
            .and_then(|v| v.as_str())
            .is_some_and(|s| s.contains("simulated panic")));
    }

    #[test]
    fn test_mode_recalibrate_and_battery_low() {
        let mut bridge = Bridge::new(PLATFORM_ANDROID, "").expect("create bridge");
        assert!(!bridge.is_test_mode());
        bridge.set_test_mode(true);
        assert!(bridge.is_test_mode());

        let records = parse(SESSION_REPLAY).expect("parse replay");
        for record in &records {
            let json = bridge
                .feed(&record.packet, record.t_us)
                .expect("feed in test mode");
            assert_eq!(json, "[]", "test mode must suppress actions");
        }
        assert_ne!(bridge.last_sample().unwrap(), "null");

        bridge.recalibrate();
        bridge.set_test_mode(false);
        assert!(!bridge.is_test_mode());

        assert!(Bridge::battery_low(0));
        assert!(Bridge::battery_low(14));
        assert!(!Bridge::battery_low(15));
        assert!(!Bridge::battery_low(100));
    }

    #[test]
    fn invalid_platform_and_packet_length_return_error_not_panic() {
        let bad_platform = Bridge::new(99, "");
        assert!(
            bad_platform
                .err()
                .is_some_and(|e| e.contains("invalid platform code")),
            "expected invalid platform error"
        );

        let mut bridge = Bridge::new(PLATFORM_ANDROID, "").expect("valid bridge");
        let short_pkt = bridge.feed(&[0u8; 19], 10_000);
        assert!(
            short_pkt
                .err()
                .is_some_and(|e| e.contains("invalid packet length")),
            "expected short packet length error"
        );

        let long_pkt = bridge.feed(&[0u8; 21], 20_000);
        assert!(
            long_pkt
                .err()
                .is_some_and(|e| e.contains("invalid packet length")),
            "expected long packet length error"
        );
    }

    #[test]
    fn android_tv_gyro_touchpad_swipe_emits_dpad_action() {
        let mut bridge = Bridge::new(PLATFORM_ANDROID_TV, "").expect("create tv bridge");
        let records = parse(
            r#"
10000 0014000000000000000000000000000000000400
60000 0018000000000000000000000000000000000000
70000 001c000000000000000000000000000004080000
90000 0020000000000000000000000000000018080000
110000 0024000000000000000000000000000000000000
"#,
        )
        .expect("parse tv swipe replay");

        let mut actions: Vec<Action> = Vec::new();
        for rec in &records {
            let json = bridge.feed(&rec.packet, rec.t_us).expect("feed tv packet");
            let batch: Vec<Action> = serde_json::from_str(&json).expect("parse action batch");
            actions.extend(batch);
        }

        assert!(actions.contains(&Action::ToggleGyro));
        assert!(
            actions.contains(&Action::DPad(wand_core::Direction::Right)),
            "expected DPad(Right) on Android TV gyro touchpad swipe, got {actions:?}"
        );
    }
}
