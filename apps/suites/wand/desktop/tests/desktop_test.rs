// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

//! Unit and integration tests for `wand_desktop`.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use wand_core::{
    Action, Binding, BrightnessAction, Button, Config, Direction, Engine, KeyChord, MediaAction,
    NavAction, Platform, PointingMode, Press, RadialSlot, SystemAction, VolumeAction,
};

use wand_desktop::ble::{INITIAL_BACKOFF, matches_daydream_peripheral, next_backoff};
use wand_desktop::cli::{CliCommand, parse_cli_args};
use wand_desktop::config::{
    DebouncedSaver, MAX_CONFIG_BACKUPS, SAVE_DEBOUNCE, ThemePreference, backup_config_path,
    backup_config_paths, config_path_for, deserialize_config_toml, get_gyro_touchpad_scroll,
    get_theme, load_config_from, save_config_to, set_gyro_touchpad_scroll, set_theme,
};
use wand_desktop::glide::{
    GLIDE_DEFAULT_DURATION_US, GLIDE_MAX_DURATION_US, GLIDE_MIN_DURATION_US, GLIDE_TICK_US, Glide,
};
use wand_desktop::injector::{
    FakeInjector, Injector, InjectorError, PIXEL_SCALE, SCROLL_PIXEL_STEP, scale_move_delta,
    scale_scroll_pixels, scale_scroll_pixels_accum,
};
use wand_desktop::input::{
    InputCmd, InputCommand, InputPipeline, drive_replay_with_injector, spawn_input_thread,
};
use wand_desktop::launch::build_launch_command;
use wand_desktop::linux::{
    KEY_C, LinuxKeySpec, LinuxPointToConverter, linux_action_key_spec, linux_keycode_for_key,
};
#[cfg(target_os = "macos")]
use wand_desktop::macos::{
    CANONICAL_KEY_NAMES, DisplayRect, MacosKeySpec, MacosPointToState, NX_KEYTYPE_BRIGHTNESS_UP,
    NX_KEYTYPE_PLAY, clamp_to_bounds, clamp_to_display_rects, display_containing_point,
    macos_action_key_spec, macos_keycode_for_key,
};
use wand_desktop::radial_overlay::{
    RADIAL_VIEWPORT_SIZE, RadialOverlayController, compute_radial_viewport_origin,
};
use wand_desktop::status::Status;
use wand_desktop::tray::format_tray_tooltip;
use wand_desktop::ui::hold_delay_hint;

const GOLDEN_REPLAY: &str = include_str!("../../core/testdata/session.replay");
const DAYDREAM_AXES_REPLAY: &str = include_str!("../../core/testdata/daydream_axes.replay");
static NEXT_TEST_DIR_ID: AtomicU64 = AtomicU64::new(1);

struct TestDir(PathBuf);

impl TestDir {
    fn new() -> Self {
        let base = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let id = NEXT_TEST_DIR_ID.fetch_add(1, Ordering::Relaxed);
        let dir = base.join(format!("wand-desktop-test-{}-{id}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("create test dir");
        Self(dir)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TestDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[test]
fn config_paths_follow_macos_and_linux_conventions() {
    let mac = config_path_for("macos", Some(Path::new("/Users/alice")), None);
    assert_eq!(
        mac,
        PathBuf::from("/Users/alice/Library/Application Support/dev.vitruvian.wand/config.toml")
    );

    let linux_xdg = config_path_for(
        "linux",
        Some(Path::new("/home/alice")),
        Some(Path::new("/home/alice/.custom-cfg")),
    );
    assert_eq!(
        linux_xdg,
        PathBuf::from("/home/alice/.custom-cfg/wand/config.toml")
    );

    let linux_fallback = config_path_for("linux", Some(Path::new("/home/alice")), None);
    assert_eq!(
        linux_fallback,
        PathBuf::from("/home/alice/.config/wand/config.toml")
    );
}

#[test]
fn config_load_save_roundtrip_and_invalid_backup() {
    let dir = TestDir::new();
    let cfg_path = dir.path().join("wand").join("config.toml");

    // Missing file returns desktop defaults without creating a backup.
    let loaded_default = load_config_from(&cfg_path);
    assert_eq!(loaded_default, Config::for_platform(Platform::Desktop));
    assert!(!backup_config_path(&cfg_path).exists());

    // Save customized config and reload.
    let mut custom = Config::for_platform(Platform::Desktop);
    custom.settings.touch_sensitivity = 625.0;
    custom.settings.reverse_scroll = true;
    set_theme(&mut custom, ThemePreference::Dark);
    set_gyro_touchpad_scroll(&mut custom, false);
    save_config_to(&cfg_path, &custom).expect("save config");

    let reloaded = load_config_from(&cfg_path);
    assert_eq!(reloaded.settings.touch_sensitivity, 625.0);
    assert!(reloaded.settings.reverse_scroll);
    assert_eq!(get_theme(&reloaded), ThemePreference::Dark);
    assert!(!get_gyro_touchpad_scroll(&reloaded));

    // Corrupt the file and verify `.bak` backup is written and defaults returned.
    let corrupt_contents = "not = [valid = toml";
    std::fs::write(&cfg_path, corrupt_contents).expect("write corrupt config");
    let recovered = load_config_from(&cfg_path);
    assert_eq!(recovered, Config::for_platform(Platform::Desktop));

    let bak = backup_config_path(&cfg_path);
    assert!(bak.exists(), "expected backup file at {}", bak.display());
    assert_eq!(
        std::fs::read_to_string(&bak).expect("read backup"),
        corrupt_contents
    );
}

#[test]
fn debounced_saver_waits_500ms_before_writing() {
    let dir = TestDir::new();
    let cfg_path = dir.path().join("config.toml");
    let mut saver = DebouncedSaver::new(cfg_path.clone());
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.gyro_x_speed = 42.0;

    let t0 = Instant::now();
    saver.mark_dirty_at(t0);
    assert!(saver.is_dirty());

    // Before 500 ms: no flush.
    assert!(
        !saver
            .poll_save(&cfg, t0 + Duration::from_millis(250))
            .expect("poll check")
    );
    assert!(!cfg_path.exists());

    // At 500 ms: flushes to disk.
    assert!(
        saver
            .poll_save(&cfg, t0 + SAVE_DEBOUNCE)
            .expect("flush due")
    );
    assert!(!saver.is_dirty());
    assert!(cfg_path.exists());
    let on_disk = load_config_from(&cfg_path);
    assert_eq!(on_disk.settings.gyro_x_speed, 42.0);
}

#[test]
fn cli_parsing_handles_all_subcommands_and_flags() {
    let args = |items: &[&str]| -> Vec<String> { items.iter().map(|s| (*s).to_owned()).collect() };

    assert_eq!(parse_cli_args(args(&[])), Ok(CliCommand::Gui));
    assert_eq!(parse_cli_args(args(&["doctor"])), Ok(CliCommand::Doctor));
    assert_eq!(
        parse_cli_args(args(&["record", "/tmp/capture.replay"])),
        Ok(CliCommand::Record {
            path: PathBuf::from("/tmp/capture.replay")
        })
    );
    assert_eq!(
        parse_cli_args(args(&["replay", "/tmp/capture.replay"])),
        Ok(CliCommand::Replay {
            path: PathBuf::from("/tmp/capture.replay"),
            inject: false,
        })
    );
    assert_eq!(
        parse_cli_args(args(&["replay", "/tmp/capture.replay", "--inject"])),
        Ok(CliCommand::Replay {
            path: PathBuf::from("/tmp/capture.replay"),
            inject: true,
        })
    );
    assert_eq!(
        parse_cli_args(args(&["replay", "--inject", "/tmp/capture.replay"])),
        Ok(CliCommand::Replay {
            path: PathBuf::from("/tmp/capture.replay"),
            inject: true,
        })
    );

    assert!(parse_cli_args(args(&["record"])).is_err());
    assert!(parse_cli_args(args(&["replay"])).is_err());
    assert!(parse_cli_args(args(&["unknown"])).is_err());
}

#[test]
fn pixel_scale_crosses_1440px_in_about_two_full_touchpad_swipes() {
    let cfg = Config::for_platform(Platform::Desktop);
    assert_eq!(cfg.settings.touch_sensitivity, 400.0);

    // One full swipe across the touchpad produces a normalized delta of ~1.0,
    // which the engine multiplies by `touch_sensitivity` (400.0).
    let one_swipe_engine_dx = cfg.settings.touch_sensitivity * 1.0;
    let (one_swipe_px, _) = scale_move_delta(one_swipe_engine_dx, 0.0);
    let two_swipes_px = one_swipe_px * 2.0;

    assert_eq!(one_swipe_px, 400.0 * PIXEL_SCALE);
    assert!(
        (1350.0..=1550.0).contains(&two_swipes_px),
        "expected two swipes ({two_swipes_px} px) to be ~1440 px"
    );

    let (sx, sy) = scale_scroll_pixels(1.0, 2.0);
    assert_eq!(sx, SCROLL_PIXEL_STEP as i32);
    assert_eq!(sy, (2.0 * SCROLL_PIXEL_STEP) as i32);
}

#[test]
fn replay_session_drives_fake_injector_with_exact_expected_actions() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.motion_glide = false;
    let mut engine = Engine::new(cfg, Platform::Desktop);
    let mut fake = FakeInjector::new();

    let emitted =
        drive_replay_with_injector(&mut engine, GOLDEN_REPLAY, &mut fake).expect("drive replay");

    assert_eq!(emitted.len(), 6, "expected 6 actions from session.replay");
    assert_eq!(fake.actions, emitted);

    // 1. Touch swipe right -> Move { dx: 100.39216, dy: 0.0 }
    match emitted[0] {
        Action::Move { dx, dy } => {
            assert!((dx - 100.39216).abs() < 1e-3, "unexpected touch dx: {dx}");
            assert_eq!(dy, 0.0);
        }
        ref other => panic!("expected Move at index 0, got {other:?}"),
    }

    // 2 & 3. Click hold -> MouseDown then MouseUp
    assert_eq!(emitted[1], Action::MouseDown);
    assert_eq!(emitted[2], Action::MouseUp);

    // 4. App short press -> ToggleGyro
    assert_eq!(emitted[3], Action::ToggleGyro);

    // 5. Gyro pitch up (positive gyro.x) in gyro mode -> pointer aims up: PointTo { x == 0, y < 0 }
    let unglided_point_to = match emitted[4] {
        Action::PointTo { x, y } => {
            assert_eq!(x, 0.0);
            assert!(
                y < -0.01,
                "expected negative (upward) gyro PointTo.y, got {y}"
            );
            (x, y)
        }
        ref other => panic!("expected PointTo at index 4, got {other:?}"),
    };

    // 6. Touchpad swipe in gyro mode -> Scroll { dx: 0.0, dy: 1.0 }
    assert_eq!(emitted[5], Action::Scroll { dx: 0.0, dy: 1.0 });

    // Variant with motion_glide = true (default on Desktop): final PointTo position matches.
    let glide_cfg = Config::for_platform(Platform::Desktop);
    assert!(glide_cfg.settings.motion_glide);
    let mut glide_engine = Engine::new(glide_cfg, Platform::Desktop);
    let mut glide_fake = FakeInjector::new();
    let glide_emitted =
        drive_replay_with_injector(&mut glide_engine, GOLDEN_REPLAY, &mut glide_fake)
            .expect("drive replay with glide");
    assert_eq!(glide_fake.actions, glide_emitted);
    let last_glide_point_to = glide_fake
        .actions
        .iter()
        .rev()
        .find_map(|a| match *a {
            Action::PointTo { x, y } => Some((x, y)),
            _ => None,
        })
        .expect("expected PointTo in glide replay");
    assert_eq!(last_glide_point_to, unglided_point_to);

    // Multi-packet gyro replay variant with motion_glide = false vs true:
    // with glide on, more intermediate PointTo steps are emitted and the final position matches exactly.
    let multi_gyro_replay = "\
100000 0014000000000000000000000000000000000400
150000 0018000000000000000000000000000000000000
170000 001c000000000000000000004000000000000000
200000 0020000000000000000000004000000000000000
230000 0024000000000000000000004000000000000000
";
    let mut raw_cfg = Config::for_platform(Platform::Desktop);
    raw_cfg.settings.motion_glide = false;
    let mut raw_eng = Engine::new(raw_cfg, Platform::Desktop);
    let mut raw_inj = FakeInjector::new();
    drive_replay_with_injector(&mut raw_eng, multi_gyro_replay, &mut raw_inj)
        .expect("multi gyro raw");

    let mut smooth_eng = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
    let mut smooth_inj = FakeInjector::new();
    drive_replay_with_injector(&mut smooth_eng, multi_gyro_replay, &mut smooth_inj)
        .expect("multi gyro smooth");

    let raw_pts: Vec<(f32, f32)> = raw_inj
        .actions
        .iter()
        .filter_map(|a| match *a {
            Action::PointTo { x, y } => Some((x, y)),
            _ => None,
        })
        .collect();
    let smooth_pts: Vec<(f32, f32)> = smooth_inj
        .actions
        .iter()
        .filter_map(|a| match *a {
            Action::PointTo { x, y } => Some((x, y)),
            _ => None,
        })
        .collect();
    assert_eq!(raw_pts.len(), 3);
    assert!(
        smooth_pts.len() > raw_pts.len(),
        "expected 125 Hz glide to emit intermediate PointTo steps ({} vs {})",
        smooth_pts.len(),
        raw_pts.len()
    );
    assert_eq!(smooth_pts.last(), raw_pts.last());

    // Also verify Relative mode replay with FakeInjector stays exact.
    let mut rel_cfg = Config::for_platform(Platform::Desktop);
    rel_cfg.settings.pointing_mode = PointingMode::Relative;
    let mut rel_engine = Engine::new(rel_cfg, Platform::Desktop);
    let mut rel_fake = FakeInjector::new();
    let rel_emitted = drive_replay_with_injector(&mut rel_engine, GOLDEN_REPLAY, &mut rel_fake)
        .expect("drive relative replay");
    assert_eq!(rel_emitted.len(), 6);
    assert_eq!(rel_fake.actions, rel_emitted);
    match rel_emitted[4] {
        Action::Move { dx, dy } => {
            assert_eq!(dx, 0.0);
            assert!(dy < -1.0, "expected negative (upward) gyro dy, got {dy}");
        }
        ref other => panic!("expected Move at index 4 in relative mode, got {other:?}"),
    }
}

#[test]
fn linux_and_macos_keycode_tables_cover_every_key_and_key_action() {
    #[cfg(not(target_os = "macos"))]
    const CANONICAL_KEY_NAMES: &[&str] = &[
        "a",
        "b",
        "c",
        "d",
        "e",
        "f",
        "g",
        "h",
        "i",
        "j",
        "k",
        "l",
        "m",
        "n",
        "o",
        "p",
        "q",
        "r",
        "s",
        "t",
        "u",
        "v",
        "w",
        "x",
        "y",
        "z",
        "0",
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "Return",
        "Space",
        "Tab",
        "Backspace",
        "Delete",
        "Escape",
        "Up",
        "Down",
        "Left",
        "Right",
        "Home",
        "End",
        "PageUp",
        "PageDown",
        "F1",
        "F2",
        "F3",
        "F4",
        "F5",
        "F6",
        "F7",
        "F8",
        "F9",
        "F10",
        "F11",
        "F12",
        "-",
        "=",
        "[",
        "]",
        "\\",
        ";",
        "'",
        ",",
        ".",
        "/",
        "`",
    ];
    #[cfg(target_os = "macos")]
    let mut mac_codes = HashSet::new();
    let mut linux_codes = HashSet::new();

    for &key in CANONICAL_KEY_NAMES {
        #[cfg(target_os = "macos")]
        {
            let mac = macos_keycode_for_key(key)
                .unwrap_or_else(|| panic!("missing macOS keycode for canonical key '{key}'"));
            assert!(
                mac_codes.insert(mac),
                "duplicate macOS virtual keycode {mac:#x} for '{key}'"
            );
        }
        let lin = linux_keycode_for_key(key)
            .unwrap_or_else(|| panic!("missing Linux keycode for canonical key '{key}'"));
        assert!(
            linux_codes.insert(lin),
            "duplicate Linux evdev keycode {lin} for '{key}'"
        );
    }

    let key_actions = [
        Action::Key(KeyChord::new("a")),
        Action::System(SystemAction::Copy),
        Action::System(SystemAction::Paste),
        Action::System(SystemAction::Cut),
        Action::System(SystemAction::Undo),
        Action::System(SystemAction::AppSwitcher),
        Action::System(SystemAction::MissionControl),
        Action::System(SystemAction::ShowDesktop),
        Action::Nav(NavAction::Back),
        Action::Nav(NavAction::Home),
        Action::Nav(NavAction::Recents),
        Action::Nav(NavAction::Notifications),
        Action::Nav(NavAction::QuickSettings),
        Action::Media(MediaAction::PlayPause),
        Action::Media(MediaAction::Next),
        Action::Media(MediaAction::Previous),
        Action::Volume(VolumeAction::Up),
        Action::Volume(VolumeAction::Down),
        Action::Volume(VolumeAction::Mute),
        Action::Brightness(BrightnessAction::Up),
        Action::Brightness(BrightnessAction::Down),
        Action::DPad(Direction::Up),
        Action::DPad(Direction::Down),
        Action::DPad(Direction::Left),
        Action::DPad(Direction::Right),
        Action::DPad(Direction::Center),
    ];

    for act in &key_actions {
        #[cfg(target_os = "macos")]
        {
            let mac_spec = macos_action_key_spec(act);
            assert!(
                mac_spec.is_some(),
                "macOS key spec missing for action {act:?}"
            );
        }
        let lin_spec = linux_action_key_spec(act);
        assert!(
            lin_spec.is_some(),
            "Linux key spec missing for action {act:?}"
        );
    }

    // Verify media/brightness map to NSSystemDefined on macOS and dedicated evdev keys on Linux.
    #[cfg(target_os = "macos")]
    {
        assert_eq!(
            macos_action_key_spec(&Action::Media(MediaAction::PlayPause)),
            Some(MacosKeySpec::SystemDefined {
                nx_key: NX_KEYTYPE_PLAY
            })
        );
        assert_eq!(
            macos_action_key_spec(&Action::Brightness(BrightnessAction::Up)),
            Some(MacosKeySpec::SystemDefined {
                nx_key: NX_KEYTYPE_BRIGHTNESS_UP
            })
        );
    }
    assert_eq!(
        linux_action_key_spec(&Action::System(SystemAction::Copy)),
        Some(LinuxKeySpec {
            keycode: KEY_C,
            ctrl: true,
            alt: false,
            shift: false,
            meta: false,
        })
    );

    // Non-key actions must return None.
    for non_key in [
        Action::LeftClick,
        Action::RightClick,
        Action::MouseDown,
        Action::MouseUp,
        Action::Move { dx: 1.0, dy: 2.0 },
        Action::Scroll { dx: 0.0, dy: 1.0 },
        Action::RadialMenu,
        Action::ToggleGyro,
        Action::LaunchApp("Safari".to_owned()),
    ] {
        #[cfg(target_os = "macos")]
        assert!(macos_action_key_spec(&non_key).is_none());
        assert!(linux_action_key_spec(&non_key).is_none());
    }
}

#[test]
fn radial_overlay_controller_and_viewport_origin_glue() {
    let mut slots = vec![RadialSlot::default(); 8];
    slots[0].action = Some(Action::Media(MediaAction::PlayPause));
    slots[2].action = Some(Action::Media(MediaAction::Next));

    let mut ctrl = RadialOverlayController::new(15.0);
    assert!(!ctrl.is_open());

    ctrl.open();
    assert!(ctrl.is_open());
    assert_eq!(ctrl.selected_slot(), None);

    // Deadzone movement keeps slot None.
    assert_eq!(ctrl.feed_move(2.0, -2.0), None);

    // Move Up (negative Y in screen space) -> slot 0.
    assert_eq!(ctrl.feed_move(0.0, -50.0), Some(0));
    let chosen = ctrl.release(&slots);
    assert_eq!(chosen, Some(Action::Media(MediaAction::PlayPause)));
    assert!(!ctrl.is_open());

    // Move Right (positive X) -> slot 2.
    ctrl.open();
    assert_eq!(ctrl.feed_move(60.0, 0.0), Some(2));
    assert_eq!(ctrl.release(&slots), Some(Action::Media(MediaAction::Next)));

    // Wayland centres on screen; X11/macOS centres on cursor.
    let origin_cursor =
        compute_radial_viewport_origin(false, Some((500.0, 400.0)), (1920.0, 1080.0));
    assert_eq!(
        origin_cursor,
        (
            500.0 - RADIAL_VIEWPORT_SIZE * 0.5,
            400.0 - RADIAL_VIEWPORT_SIZE * 0.5
        )
    );
    let origin_wayland =
        compute_radial_viewport_origin(true, Some((500.0, 400.0)), (1920.0, 1080.0));
    assert_eq!(
        origin_wayland,
        (
            (1920.0 - RADIAL_VIEWPORT_SIZE) * 0.5,
            (1080.0 - RADIAL_VIEWPORT_SIZE) * 0.5
        )
    );

    // Verify InputPipeline radial status synchronization.
    let status = Arc::new(Mutex::new(Status::default()));
    let _pipeline = InputPipeline::new(
        Config::for_platform(Platform::Desktop),
        Box::new(FakeInjector::new()),
        Arc::clone(&status),
    );
    assert!(!status.lock().unwrap().radial_open);
}

#[test]
fn low_battery_triggers_once_per_connection_and_updates_tooltip() {
    let mut status = Status::default();
    status.on_connected("Daydream");

    // 50% battery: no alert.
    assert!(!status.update_battery(50));
    assert!(!status.low_battery_alert_active);
    assert_eq!(Status::battery_level_bars(50), 3);

    // Drop to 14% (< 15%): triggers once.
    assert!(status.update_battery(14));
    assert!(status.low_battery_alert_active);
    assert_eq!(format_tray_tooltip(&status), "Wand — Low battery (14%)");

    // Drop further to 10% in the same connection: does NOT re-trigger.
    assert!(!status.update_battery(10));
    assert!(status.low_battery_alert_active);

    // New connection resets the once-per-connection latch.
    status.on_disconnected();
    assert!(!status.low_battery_alert_active);
    status.on_connected("Daydream");
    assert!(status.update_battery(12));
    assert!(status.low_battery_alert_active);
}

#[test]
fn helpers_clamp_bounds_and_build_launch_commands() {
    #[cfg(target_os = "macos")]
    assert_eq!(
        clamp_to_bounds(-50.0, 1200.0, 0.0, 0.0, 1440.0, 900.0),
        (0.0, 900.0)
    );
    assert_eq!(
        build_launch_command("macos", "com.apple.Safari"),
        Ok((
            "open".to_owned(),
            vec!["-b".to_owned(), "com.apple.Safari".to_owned()]
        ))
    );
    assert_eq!(
        build_launch_command("macos", "Calculator"),
        Ok((
            "open".to_owned(),
            vec!["-a".to_owned(), "Calculator".to_owned()]
        ))
    );
    assert_eq!(
        build_launch_command("linux", "/usr/share/applications/firefox.desktop"),
        Ok((
            "gio".to_owned(),
            vec![
                "launch".to_owned(),
                "/usr/share/applications/firefox.desktop".to_owned()
            ]
        ))
    );
    assert_eq!(
        build_launch_command("linux", "org.mozilla.firefox"),
        Ok((
            "gtk-launch".to_owned(),
            vec!["org.mozilla.firefox".to_owned()]
        ))
    );
}

fn make_packet(touch_x: u8, touch_y: u8, buttons: u8) -> [u8; 20] {
    let mut b = [0u8; 20];
    b[16] = (touch_x >> 3) & 0x1F;
    b[17] = ((touch_x & 0x07) << 5) | ((touch_y >> 3) & 0x1F);
    b[18] = ((touch_y & 0x07) << 5) | (buttons & 0x1F);
    b
}

struct RecordingInjector {
    recorded: Arc<Mutex<Vec<Action>>>,
}

impl Injector for RecordingInjector {
    fn apply(&mut self, action: &Action) -> Result<(), InjectorError> {
        self.recorded.lock().unwrap().push(action.clone());
        Ok(())
    }
}

#[test]
fn known_defect_radial_slot_runs_once() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::Click, Press::Short),
        Binding::hold(Action::RadialMenu),
    );
    let target_action = Action::Key(KeyChord::new("a"));
    cfg.radial_slots[2].action = Some(target_action.clone());

    let recorded = Arc::new(Mutex::new(Vec::<Action>::new()));
    let injector = Box::new(RecordingInjector {
        recorded: Arc::clone(&recorded),
    });
    let status = Arc::new(Mutex::new(Status::default()));
    let mut pipeline = InputPipeline::new(cfg, injector, status);

    pipeline.process_packet(&make_packet(100, 100, 0x00), 0);
    pipeline.process_packet(&make_packet(160, 100, 0x00), 20_000);
    pipeline.process_packet(&make_packet(160, 100, 0x01), 40_000);
    pipeline.process_packet(&make_packet(220, 100, 0x01), 60_000);
    pipeline.process_packet(&make_packet(0, 0, 0x00), 80_000);

    let actions = recorded.lock().unwrap();
    let count = actions.iter().filter(|a| *a == &target_action).count();
    assert_eq!(
        count, 1,
        "expected radial slot action {target_action:?} to fire once, got {count} in {actions:?}"
    );
}

#[test]
fn ble_backoff_doubles_and_caps() {
    let mut seq = Vec::new();
    let mut cur = INITIAL_BACKOFF;
    for _ in 0..6 {
        seq.push(cur);
        cur = next_backoff(cur);
    }
    assert_eq!(
        seq,
        vec![
            Duration::from_secs(1),
            Duration::from_secs(2),
            Duration::from_secs(4),
            Duration::from_secs(8),
            Duration::from_secs(16),
            Duration::from_secs(16),
        ]
    );
    assert!(matches_daydream_peripheral(
        Some("Daydream controller"),
        &[]
    ));
    assert!(!matches_daydream_peripheral(Some("Keyboard"), &[]));
}

#[derive(Clone)]
struct SharedFakeInjector {
    inner: Arc<Mutex<FakeInjector>>,
}

impl SharedFakeInjector {
    fn new() -> (Self, Arc<Mutex<FakeInjector>>) {
        let inner = Arc::new(Mutex::new(FakeInjector::new()));
        (
            Self {
                inner: Arc::clone(&inner),
            },
            inner,
        )
    }
}

impl Injector for SharedFakeInjector {
    fn apply(&mut self, action: &Action) -> Result<(), InjectorError> {
        self.inner.lock().unwrap().apply(action)
    }
}

#[test]
fn session_mousedown_then_disconnect_or_shutdown_yields_mouseup_to_fake_injector() {
    let cfg = Config::for_platform(Platform::Desktop);
    let (inj, fake_arc) = SharedFakeInjector::new();
    let status = Arc::new(Mutex::new(Status::default()));
    let mut pipeline = InputPipeline::new(cfg.clone(), Box::new(inj), Arc::clone(&status));

    // Press Click button (default Short = Hold LeftClick -> emits MouseDown immediately).
    pipeline.handle_command(InputCommand::Packet {
        bytes: make_packet(0, 0, 0x01),
        t_us: 10_000,
    });
    assert_eq!(fake_arc.lock().unwrap().actions, vec![Action::MouseDown]);

    // Simulate BLE disconnect sending InputCmd::ReleaseAll -> must emit MouseUp to FakeInjector.
    pipeline.handle_command(InputCmd::ReleaseAll);
    assert_eq!(
        fake_arc.lock().unwrap().actions,
        vec![Action::MouseDown, Action::MouseUp]
    );

    // Also verify that InputCommand::Shutdown on the input thread releases an active MouseDown before breaking.
    let (inj2, fake_arc2) = SharedFakeInjector::new();
    let status2 = Arc::new(Mutex::new(Status::default()));
    let (tx, handle) = spawn_input_thread(cfg, Box::new(inj2), status2);
    tx.send(InputCommand::Packet {
        bytes: make_packet(0, 0, 0x01),
        t_us: 10_000,
    })
    .expect("send press");
    tx.send(InputCommand::Shutdown).expect("send shutdown");
    handle.join().expect("join input thread");

    assert_eq!(
        fake_arc2.lock().unwrap().actions,
        vec![Action::MouseDown, Action::MouseUp]
    );
}

#[test]
fn desktop_input_tick_fires_long_press_with_no_further_packets() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.long_press_ms = 100; // 100 ms threshold
    cfg.bindings.insert(
        (Button::Home, Press::Long),
        Binding::once(Action::Media(MediaAction::PlayPause)),
    );

    let (inj, fake_arc) = SharedFakeInjector::new();
    let status = Arc::new(Mutex::new(Status::default()));
    let (tx, handle) = spawn_input_thread(cfg, Box::new(inj), status);

    // Send a single packet with Home pressed (0x02), and NO subsequent packets.
    tx.send(InputCommand::Packet {
        bytes: make_packet(0, 0, 0x02),
        t_us: 0,
    })
    .expect("send home press");

    // Wait up to 350 ms for the 20 ms input thread timer loop to cross the 100 ms long-press threshold.
    let deadline = Instant::now() + Duration::from_millis(350);
    while Instant::now() < deadline {
        if fake_arc
            .lock()
            .unwrap()
            .actions
            .contains(&Action::Media(MediaAction::PlayPause))
        {
            break;
        }
        std::thread::sleep(Duration::from_millis(15));
    }

    tx.send(InputCommand::Shutdown).expect("shutdown");
    handle.join().expect("join");

    let emitted = fake_arc.lock().unwrap().actions.clone();
    assert!(
        emitted.contains(&Action::Media(MediaAction::PlayPause)),
        "expected long press to fire via 20 ms tick without further packets, got {emitted:?}"
    );
}

#[test]
fn bindings_ui_hold_delay_hint_reflects_long_and_double_tradeoff() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    // Default Click has Short = Hold(LeftClick) and no Long/Double -> no hint.
    assert_eq!(
        hold_delay_hint(&cfg.bindings, Button::Click, Press::Short),
        None
    );

    // Bind Long on Click -> hint appears under Short cell.
    cfg.bindings.insert(
        (Button::Click, Press::Long),
        Binding::once(Action::RightClick),
    );
    assert_eq!(
        hold_delay_hint(&cfg.bindings, Button::Click, Press::Short),
        Some("Long is also bound, so this clicks on release and cannot drag")
    );
    assert_eq!(
        hold_delay_hint(&cfg.bindings, Button::Click, Press::Long),
        None
    );
}

#[test]
fn config_toml_with_nan_inf_and_out_of_range_clamps_to_documented_ranges() {
    let toml_with_nan = r#"
[settings]
touch_sensitivity = nan
gyro_x_speed = inf
gyro_y_speed = -inf
gyro_deadzone = 99.0
touch_deadzone = -1.0
acceleration_curve = 99.0
ema_smoothing = -5.0
scroll_strength = 0.0
radial_dead_radius = 500.0
overlay_cursor_size = 2.0
long_press_ms = 10
double_press_ms = 999999
"#;

    let cfg = deserialize_config_toml(toml_with_nan).expect("parse TOML with NaN/inf");
    assert_eq!(cfg.settings.touch_sensitivity, 400.0); // NaN -> default
    assert_eq!(cfg.settings.gyro_x_speed, 60.0); // +inf -> max
    assert_eq!(cfg.settings.gyro_y_speed, 1.0); // -inf -> min
    assert_eq!(cfg.settings.gyro_deadzone, 0.5);
    assert_eq!(cfg.settings.touch_deadzone, 0.0);
    assert_eq!(cfg.settings.acceleration_curve, 3.0);
    assert_eq!(cfg.settings.ema_smoothing, 0.0);
    assert_eq!(cfg.settings.scroll_strength, 0.1);
    assert_eq!(cfg.settings.radial_dead_radius, 100.0);
    assert_eq!(cfg.settings.overlay_cursor_size, 8.0);
    assert_eq!(cfg.settings.long_press_ms, 100);
    assert_eq!(cfg.settings.double_press_ms, 2000);
}

#[test]
fn slow_swipe_accumulates_fractional_scroll_remainder_between_packets() {
    let mut fake = FakeInjector::new();
    // SCROLL_PIXEL_STEP is 24.0; dy = 0.0125 -> 0.3 px per packet.
    // Without remainder accumulation, scale_scroll_pixels(0.0, 0.0125) rounds 0.3 -> 0 forever.
    assert_eq!(scale_scroll_pixels(0.0, 0.0125), (0, 0));

    // After 3 packets: 0.9 px (no integer pixel emitted yet).
    // On the 4th packet: 1.2 px -> 1 pixel emitted, 0.2 remainder kept.
    for _ in 0..3 {
        fake.apply(&Action::Scroll {
            dx: 0.0,
            dy: 0.0125,
        })
        .expect("apply fractional scroll");
    }
    assert!(
        fake.pixel_scrolls.is_empty(),
        "expected no integer scroll before remainder crosses 1 px, got {:?}",
        fake.pixel_scrolls
    );

    fake.apply(&Action::Scroll {
        dx: 0.0,
        dy: 0.0125,
    })
    .expect("apply 4th fractional scroll");
    assert_eq!(fake.pixel_scrolls, vec![(0, 1)]);

    // Also test scale_scroll_pixels_accum directly across 10 small steps of dy = -0.015625 (-0.375 px each -> -3.75 px total).
    let mut rem_x = 0.0;
    let mut rem_y = 0.0;
    let mut total_py = 0;
    for _ in 0..10 {
        let (_, py) = scale_scroll_pixels_accum(0.0, -0.015625, &mut rem_x, &mut rem_y);
        total_py += py;
    }
    assert_eq!(total_py, -3);
    assert!((rem_y - (-0.75)).abs() < 1e-5);
}

#[test]
fn config_preserves_unknown_settings_keys_recovers_single_bad_field_and_retains_last_3_backups() {
    let dir = TestDir::new();
    let cfg_path = dir.path().join("config.toml");

    // 1. Unknown key inside [settings] + one bad field (`gyro_x_speed = "not_a_number"`).
    // Valid fields (`touch_sensitivity = 720.0`, `reverse_scroll = true`, `future_flag = "enabled"`)
    // must be preserved while only `gyro_x_speed` falls back to default (18.0).
    let partial_bad = r#"
[settings]
touch_sensitivity = 720.0
gyro_x_speed = "not_a_number"
reverse_scroll = true
future_flag = "enabled"
future_count = 42
"#;
    std::fs::write(&cfg_path, partial_bad).expect("write partial_bad");
    let loaded = load_config_from(&cfg_path);
    assert_eq!(loaded.settings.touch_sensitivity, 720.0);
    assert_eq!(loaded.settings.gyro_x_speed, 18.0); // defaulted only the bad field
    assert!(loaded.settings.reverse_scroll);
    assert_eq!(
        loaded.settings.extra.get("future_flag"),
        Some(&serde_json::Value::String("enabled".to_owned()))
    );
    assert_eq!(
        loaded.settings.extra.get("future_count"),
        Some(&serde_json::Value::Number(42.into()))
    );

    // Roundtrip save + reload preserves unknown [settings] keys.
    save_config_to(&cfg_path, &loaded).expect("save recovered");
    let roundtripped = load_config_from(&cfg_path);
    assert_eq!(
        roundtripped.settings.extra.get("future_flag"),
        Some(&serde_json::Value::String("enabled".to_owned()))
    );
    assert_eq!(
        roundtripped.settings.extra.get("future_count"),
        Some(&serde_json::Value::Number(42.into()))
    );

    // 2. Multiple corruptions create distinct timestamped `.bak` files without overwriting the previous
    // backup, and prune to keep the last 3 (`MAX_CONFIG_BACKUPS`).
    let dir2 = TestDir::new();
    let cfg_path2 = dir2.path().join("config.toml");
    for i in 1..=4 {
        let corrupt = format!("corrupt_payload_{i} = [unclosed");
        std::fs::write(&cfg_path2, &corrupt).expect("write corrupt");
        let _ = load_config_from(&cfg_path2);
    }

    let backups = backup_config_paths(&cfg_path2);
    assert_eq!(
        backups.len(),
        MAX_CONFIG_BACKUPS,
        "expected last {MAX_CONFIG_BACKUPS} backups retained, got {backups:?}"
    );
    let contents: Vec<String> = backups
        .iter()
        .map(|p| std::fs::read_to_string(p).expect("read bak"))
        .collect();
    assert_eq!(
        contents,
        vec![
            "corrupt_payload_2 = [unclosed".to_owned(),
            "corrupt_payload_3 = [unclosed".to_owned(),
            "corrupt_payload_4 = [unclosed".to_owned(),
        ]
    );
}

#[cfg(target_os = "macos")]
#[test]
fn macos_clamp_to_display_rects_handles_l_shaped_multi_monitor_layout() {
    // L-shaped display layout:
    // Display A (main): [0, 0]..[1920, 1080]
    // Display B (right, lower): [1920, 500]..[3840, 1580]
    // The upper-right quadrant (x in 1920..3840, y in 0..500) is an unreachable gap outside both displays.
    let rects = [
        DisplayRect::new(0.0, 0.0, 1920.0, 1080.0),
        DisplayRect::new(1920.0, 500.0, 3840.0, 1580.0),
    ];

    // Point inside Display A stays unchanged.
    assert_eq!(clamp_to_display_rects(500.0, 300.0, &rects), (500.0, 300.0));
    // Point inside Display B stays unchanged.
    assert_eq!(
        clamp_to_display_rects(2500.0, 800.0, &rects),
        (2500.0, 800.0)
    );

    // Point in the upper-right gap (2000, 450):
    // - Nearest point on Display A is (1920, 450) -> distance = 80 px
    // - Nearest point on Display B is (2000, 500) -> distance = 50 px
    // Must clamp to Display B's top edge at (2000, 500), never staying in the gap!
    assert_eq!(
        clamp_to_display_rects(2000.0, 450.0, &rects),
        (2000.0, 500.0)
    );

    // Point in the upper-right gap closer to Display A's right edge (1950, 200):
    // - Nearest point on Display A is (1920, 200) -> distance = 30 px
    // - Nearest point on Display B is (1950, 500) -> distance = 300 px
    // Must clamp to Display A's right edge at (1920, 200).
    assert_eq!(
        clamp_to_display_rects(1950.0, 200.0, &rects),
        (1920.0, 200.0)
    );
}

#[test]
fn tick_after_release_all_does_not_repress_held_button() {
    let cfg = Config::for_platform(Platform::Desktop);
    let (inj, fake_arc) = SharedFakeInjector::new();
    let status = Arc::new(Mutex::new(Status::default()));
    let mut pipeline = InputPipeline::new(cfg, Box::new(inj), Arc::clone(&status));

    pipeline.handle_command(InputCommand::Packet {
        bytes: make_packet(0, 0, 0x01),
        t_us: 10_000,
    });
    assert_eq!(fake_arc.lock().unwrap().actions, vec![Action::MouseDown]);

    pipeline.handle_command(InputCommand::ReleaseAll);
    assert_eq!(
        fake_arc.lock().unwrap().actions,
        vec![Action::MouseDown, Action::MouseUp]
    );

    pipeline.handle_command(InputCommand::Tick { t_us: 30_000 });
    pipeline.handle_command(InputCommand::Tick { t_us: 50_000 });
    pipeline.handle_command(InputCommand::Tick { t_us: 70_000 });

    let actual = fake_arc.lock().unwrap().actions.clone();
    assert_eq!(
        actual,
        vec![Action::MouseDown, Action::MouseUp],
        "expected no re-press after ReleaseAll on subsequent ticks, got {actual:?}"
    );
}

#[cfg(target_os = "macos")]
#[test]
fn macos_point_to_maps_display_centre_clamps_and_captures_until_recenter() {
    let display_a = DisplayRect::new(0.0, 0.0, 1920.0, 1080.0);
    let display_b = DisplayRect::new(1920.0, 0.0, 2560.0, 1440.0); // origin (1920, 0), size 2560 x 1440
    let rects = [display_a, display_b];

    assert_eq!(display_containing_point(500.0, 500.0, &rects), display_a);
    assert_eq!(display_containing_point(2500.0, 500.0, &rects), display_b);

    let mut state = MacosPointToState::new();
    assert_eq!(state.captured_display(), None);

    // First PointTo after recenter captures the display containing the cursor (display_b, width 2560, centre (3200, 720)).
    let (px0, py0) = state
        .resolve(0.0, 0.0, || {
            Ok(display_containing_point(2500.0, 500.0, &rects))
        })
        .expect("resolve first PointTo");
    assert_eq!(state.captured_display(), Some(display_b));
    assert_eq!((px0, py0), (3200.0, 720.0));

    // Even if cursor is reported at (100, 100) on display_a, target display remains display_b until recenter.
    // x = +0.25 -> 3200 + 0.25 * 2560 = 3840; y = -0.125 -> 720 - 0.125 * 2560 = 400.
    let (px1, py1) = state
        .resolve(0.25, -0.125, || {
            Ok(display_containing_point(100.0, 100.0, &rects))
        })
        .expect("resolve second PointTo");
    assert_eq!((px1, py1), (3840.0, 400.0));

    // Overshoot past display_b edges clamps to display_b bounds [1920..4480, 0..1440].
    let (px_over, py_over) = state
        .resolve(1.5, -1.5, || {
            Ok(display_containing_point(100.0, 100.0, &rects))
        })
        .expect("resolve overshoot");
    assert_eq!((px_over, py_over), (4480.0, 0.0));
    let (px_under, py_under) = state
        .resolve(-1.5, 1.5, || {
            Ok(display_containing_point(100.0, 100.0, &rects))
        })
        .expect("resolve undershoot");
    assert_eq!((px_under, py_under), (1920.0, 1440.0));

    // Recenter / ToggleGyro resets capture so the next PointTo captures display_a (centre (960, 540), width 1920).
    state.reset_capture();
    assert_eq!(state.captured_display(), None);
    let (px_a, py_a) = state
        .resolve(0.5, 0.0, || {
            Ok(display_containing_point(200.0, 200.0, &rects))
        })
        .expect("resolve after recenter");
    assert_eq!(state.captured_display(), Some(display_a));
    assert_eq!((px_a, py_a), (1920.0, 540.0));
}

#[test]
fn linux_point_to_converter_emits_relative_deltas_and_recenters_without_jump() {
    let mut conv = LinuxPointToConverter::new(1920);
    assert_eq!(conv.screen_width_px(), 1920);

    // First PointTo after recenter at (0.1, -0.05) moves relative to centre (0, 0):
    // dx = 0.1 * 1920 = 192, dy = -0.05 * 1920 = -96.
    assert_eq!(conv.step(0.1, -0.05), (192, -96));
    // Repeated identical PointTo produces (0, 0).
    assert_eq!(conv.step(0.1, -0.05), (0, 0));
    // Next PointTo at (0.25, 0.05) emits delta from (0.1, -0.05):
    // dx = 0.15 * 1920 = 288, dy = 0.10 * 1920 = 192.
    assert_eq!(conv.step(0.25, 0.05), (288, 192));

    // Recenter treats current cursor position as (0, 0) on Linux (no jump).
    conv.recenter();
    assert_eq!(conv.step(0.0, 0.0), (0, 0));
    assert_eq!(conv.step(-0.05, 0.0), (-96, 0));

    // Sub-pixel increments accumulate across consecutive PointTo updates without losing motion.
    conv.recenter();
    conv.set_screen_width_px(1024);
    let mut sum_dx = 0;
    for i in 1..=10 {
        let (dx, _) = conv.step(i as f32 / 2048.0, 0.0); // 0.5 px per step -> 5 px total
        sum_dx += dx;
    }
    assert_eq!(sum_dx, 5);
}

#[test]
fn desktop_config_v2_toml_loads_new_defaults_and_clamps_nan_span() {
    let v2_toml = r#"
version = 2
platform = "desktop"

[settings]
touch_sensitivity = 400.0
ema_smoothing = 0.3
"#;
    let cfg = deserialize_config_toml(v2_toml).expect("parse v2 toml");
    assert_eq!(cfg.settings.pointing_mode, PointingMode::Absolute);
    assert_eq!(cfg.settings.pointing_span_deg, 50.0);
    assert_eq!(cfg.settings.screen_width_px, 1920);

    let bad_span_toml = r#"
version = 3
platform = "desktop"

[settings]
pointing_mode = "relative"
pointing_span_deg = nan
screen_width_px = 100
"#;
    let clamped = deserialize_config_toml(bad_span_toml).expect("parse bad span toml");
    assert_eq!(clamped.settings.pointing_mode, PointingMode::Relative);
    assert_eq!(clamped.settings.pointing_span_deg, 50.0);
    assert_eq!(clamped.settings.screen_width_px, 640);
    assert!(clamped.settings.motion_glide);
}

#[test]
fn glide_linear_interpolation_halfway_exact_target_and_never_overshoots() {
    let mut glide = Glide::new();
    assert_eq!(glide.duration_us(), GLIDE_DEFAULT_DURATION_US);

    // First PointTo after init snaps immediately to (0.0, 0.0).
    assert_eq!(glide.on_point_to((0.0, 0.0), 0), Some((0.0, 0.0)));
    assert!(!glide.is_active());

    // Second PointTo at t = 30_000 µs (30 ms interval -> duration stays 30_000 µs) targets (0.4, -0.2).
    assert_eq!(glide.on_point_to((0.4, -0.2), 30_000), None);
    assert!(glide.is_active());
    assert_eq!(glide.duration_us(), 30_000);
    assert_eq!(glide.from(), (0.0, 0.0));
    assert_eq!(glide.target(), (0.4, -0.2));

    // Halfway through duration (t = 45_000 µs) -> halfway position (0.2, -0.1).
    let half = glide.step(45_000).expect("halfway step must emit");
    assert!((half.0 - 0.2).abs() < 1e-6 && (half.1 - (-0.1)).abs() < 1e-6);
    assert!(glide.is_active());

    // Repeated step at the same timestamp does not re-emit unchanged position.
    assert_eq!(glide.step(45_000), None);

    // Exactly at duration (t = 60_000 µs) -> exact target (0.4, -0.2), glide finishes.
    let end = glide.step(60_000).expect("end step must emit");
    assert_eq!(end, (0.4, -0.2));
    assert!(!glide.is_active());

    // After duration (t = 90_000 µs) -> holds at exact target, no further emission or extrapolation.
    assert_eq!(glide.position_at(90_000), (0.4, -0.2));
    assert_eq!(glide.step(90_000), None);

    // Property-style loop over 500 pseudo-random targets and timings: never overshoots [min(from,to), max(from,to)].
    fn lcg_u64(seed: &mut u64) -> u64 {
        *seed = seed
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        *seed
    }
    fn lcg_f32(seed: &mut u64, lo: f32, hi: f32) -> f32 {
        let unit = ((lcg_u64(seed) >> 40) as f32) / ((1u64 << 24) as f32);
        lo + (hi - lo) * unit
    }

    let mut seed: u64 = 0x9E37_79B9_7F4A_7C15;
    let mut prop_glide = Glide::new();
    let mut now_us = 1_000u64;
    let _ = prop_glide.on_point_to((0.0, 0.0), now_us);

    for _ in 0..500 {
        let dt_arrival = 1_000 + (lcg_u64(&mut seed) % 120_000);
        now_us += dt_arrival;
        let tx = lcg_f32(&mut seed, -1.5, 1.5);
        let ty = lcg_f32(&mut seed, -1.5, 1.5);
        let _ = prop_glide.on_point_to((tx, ty), now_us);

        let (fx, fy) = prop_glide.from();
        let (gx, gy) = prop_glide.target();
        let min_x = fx.min(gx);
        let max_x = fx.max(gx);
        let min_y = fy.min(gy);
        let max_y = fy.max(gy);
        let dur = prop_glide.duration_us();
        assert!(
            (GLIDE_MIN_DURATION_US..=GLIDE_MAX_DURATION_US).contains(&dur),
            "duration {dur} out of [8ms, 60ms]"
        );

        for probe in 0..=12 {
            let probe_t = now_us + (probe * dur) / 8; // probes from 0 to 1.5x duration
            let (px, py) = prop_glide.position_at(probe_t);
            assert!(
                px >= min_x && px <= max_x && py >= min_y && py <= max_y,
                "overshoot at probe_t={probe_t}: pos=({px}, {py}) outside [{min_x}..={max_x}, {min_y}..={max_y}]"
            );
            if probe_t >= now_us + dur {
                assert_eq!((px, py), (gx, gy), "must hold exact target after duration");
            }
        }

        // Advance rendered state partially before the next arrival to exercise mid-glide transitions.
        let step_offset = lcg_u64(&mut seed) % (dur + 20_000);
        let _ = prop_glide.step(now_us + step_offset);
    }
}

#[test]
fn glide_ewma_duration_tracks_irregular_intervals_and_clamps_to_8_60ms() {
    let mut glide = Glide::new();
    assert_eq!(glide.duration_us(), 30_000);

    // Anchor at t = 0.
    let _ = glide.on_point_to((0.0, 0.0), 0);
    assert_eq!(glide.duration_us(), 30_000);

    // 1. Interval = 20 ms (20_000 µs): EWMA = 0.2 * 20_000 + 0.8 * 30_000 = 28_000 µs.
    let _ = glide.on_point_to((0.1, 0.0), 20_000);
    assert_eq!(glide.duration_us(), 28_000);

    // 2. Interval = 50 ms (50_000 µs, t = 70_000): EWMA = 0.2 * 50_000 + 0.8 * 28_000 = 32_400 µs.
    let _ = glide.on_point_to((0.2, 0.0), 70_000);
    assert_eq!(glide.duration_us(), 32_400);

    // 3. Burst of very short intervals (1 ms = 1_000 µs each) clamps at 8 ms (8_000 µs).
    let mut t = 70_000u64;
    for i in 0..30 {
        t += 1_000;
        let _ = glide.on_point_to((0.2 + i as f32 * 0.01, 0.0), t);
        assert!(
            (GLIDE_MIN_DURATION_US..=GLIDE_MAX_DURATION_US).contains(&glide.duration_us()),
            "duration {} fell outside 8..=60 ms",
            glide.duration_us()
        );
    }
    assert_eq!(glide.duration_us(), GLIDE_MIN_DURATION_US);

    // 4. Long stalls (180 ms and 1_000 ms) clamp at 60 ms (60_000 µs).
    for i in 0..20 {
        t += 180_000;
        let _ = glide.on_point_to((i as f32 * 0.05, 0.0), t);
        assert!(
            (GLIDE_MIN_DURATION_US..=GLIDE_MAX_DURATION_US).contains(&glide.duration_us()),
            "duration {} exceeded 8..=60 ms",
            glide.duration_us()
        );
    }
    assert_eq!(glide.duration_us(), GLIDE_MAX_DURATION_US);
}

#[test]
fn glide_new_target_mid_glide_starts_from_current_rendered_position() {
    let mut glide = Glide::new();
    let _ = glide.on_point_to((0.0, 0.0), 0);
    // Start a 30 ms glide from (0.0, 0.0) to (1.0, -0.4) at t = 30_000.
    let _ = glide.on_point_to((1.0, -0.4), 30_000);
    assert_eq!(glide.duration_us(), 30_000);

    // Step to t = 45_000 (halfway): rendered position is (0.5, -0.2).
    assert_eq!(glide.step(45_000), Some((0.5, -0.2)));
    assert_eq!(glide.rendered(), (0.5, -0.2));

    // At t = 45_000, a new target (0.9, 0.2) arrives mid-glide.
    // It must start from the current rendered position (0.5, -0.2), NOT jump back to (0.0, 0.0) or ahead to (1.0, -0.4).
    assert_eq!(glide.on_point_to((0.9, 0.2), 45_000), None);
    assert_eq!(glide.from(), (0.5, -0.2));
    assert_eq!(glide.rendered(), (0.5, -0.2));
    assert_eq!(glide.position_at(45_000), (0.5, -0.2));

    // Halfway through the new glide (interval was 15 ms -> duration = 0.2*15_000 + 0.8*30_000 = 27_000 µs;
    // midpoint is 45_000 + 13_500 = 58_500): rendered position must be midpoint between (0.5, -0.2) and (0.9, 0.2) = (0.7, 0.0).
    assert_eq!(glide.duration_us(), 27_000);
    let mid = glide.step(58_500).expect("mid step on second glide");
    assert!((mid.0 - 0.7).abs() < 1e-6 && mid.1.abs() < 1e-6);
}

#[test]
fn glide_recenter_toggle_gyro_and_release_all_snap_immediately() {
    let mut glide = Glide::new();
    let _ = glide.on_point_to((0.0, 0.0), 0);
    let _ = glide.on_point_to((0.5, 0.5), 30_000);
    assert!(glide.is_active());

    // Resetting Glide (as on Recenter / ToggleGyro / ReleaseAll) snaps the next PointTo immediately.
    glide.reset();
    assert!(!glide.is_active());
    assert_eq!(
        glide.on_point_to((-0.25, 0.125), 50_000),
        Some((-0.25, 0.125))
    );
    assert!(!glide.is_active());
    assert_eq!(glide.rendered(), (-0.25, 0.125));
    assert_eq!(glide.step(58_000), None);

    // End-to-end through InputPipeline: verify Recenter and ReleaseAll snap the next PointTo immediately.
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.ema_smoothing = 0.0;
    cfg.bindings.insert(
        (Button::Home, Press::Short),
        Binding::once(Action::Recenter),
    );
    let (inj, fake_arc) = SharedFakeInjector::new();
    let status = Arc::new(Mutex::new(Status::default()));
    let mut pipeline = InputPipeline::new(cfg, Box::new(inj), status);
    pipeline.handle_command(InputCommand::SetGyroMode(true));

    // Packet with y_gyro = -1000 (turn right): first PointTo after SetGyroMode snaps immediately.
    let mut turn_right = [0u8; 20];
    let raw_y: i16 = -1000;
    let y_u16 = (raw_y as u16) & 0x1FFF;
    // Pack y_gyro into bytes 8..11 (bits 69..82): easier to use daydream_axes packet or helper:
    // In daydream format, x_gyro is bits 56..68, y_gyro is bits 69..81.
    let _ = y_u16;
    // Use first gyro packet from GOLDEN_REPLAY (001c000000000000000000004000000000000000 -> x_gyro = 128).
    turn_right[0] = 0x00;
    turn_right[1] = 0x1c;
    turn_right[12] = 0x40;

    pipeline.handle_command(InputCommand::Packet {
        bytes: turn_right,
        t_us: 10_000,
    });
    assert!(
        !pipeline.is_gliding(),
        "first PointTo after SetGyroMode must snap without starting a glide"
    );
    assert_eq!(fake_arc.lock().unwrap().actions.len(), 1);

    // Second packet at t = 40_000 starts a glide (does not jump immediately on packet arrival).
    pipeline.handle_command(InputCommand::Packet {
        bytes: turn_right,
        t_us: 40_000,
    });
    assert!(pipeline.is_gliding());
    assert_eq!(
        fake_arc.lock().unwrap().actions.len(),
        1,
        "second PointTo starts a glide and waits for 8 ms tick"
    );

    // 8 ms tick advances the glide and emits interpolated PointTo.
    pipeline.handle_command(InputCommand::Tick { t_us: 48_000 });
    assert_eq!(fake_arc.lock().unwrap().actions.len(), 2);

    // ReleaseAll resets glide so the next PointTo snaps immediately.
    pipeline.handle_command(InputCommand::ReleaseAll);
    assert!(!pipeline.is_gliding());
    pipeline.handle_command(InputCommand::Packet {
        bytes: turn_right,
        t_us: 70_000,
    });
    assert!(
        !pipeline.is_gliding(),
        "first PointTo after ReleaseAll must snap immediately"
    );
    assert_eq!(fake_arc.lock().unwrap().actions.len(), 3);
}

#[test]
fn daydream_axes_replay_with_glide_at_125hz_reduces_largest_cursor_step_at_least_3x() {
    let max_step_for = |motion_glide: bool| -> (f32, Option<(f32, f32)>, usize) {
        let mut cfg = Config::for_platform(Platform::Desktop);
        cfg.settings.pointing_mode = PointingMode::Absolute;
        cfg.settings.motion_glide = motion_glide;
        let mut engine = Engine::new(cfg, Platform::Desktop);
        engine.set_gyro_mode(true);
        let mut fake = FakeInjector::new();

        drive_replay_with_injector(&mut engine, DAYDREAM_AXES_REPLAY, &mut fake)
            .expect("drive daydream_axes.replay");

        let mut prev: Option<(f32, f32)> = None;
        let mut max_step = 0.0f32;
        let mut count = 0usize;
        for act in &fake.actions {
            if let Action::PointTo { x, y } = *act {
                if let Some((px, py)) = prev {
                    let step = ((x - px).powi(2) + (y - py).powi(2)).sqrt();
                    max_step = max_step.max(step);
                }
                prev = Some((x, y));
                count += 1;
            }
        }
        assert_eq!(GLIDE_TICK_US, 8_000);
        (max_step, prev, count)
    };

    let (max_step_without, final_without, count_without) = max_step_for(false);
    let (max_step_with, final_with, count_with) = max_step_for(true);
    let ratio = max_step_without / max_step_with;

    println!(
        "daydream_axes largest cursor step: without_glide={max_step_without:.6} screen widths ({count_without} PointTo events), with_glide={max_step_with:.6} screen widths ({count_with} PointTo events), reduction={ratio:.2}x"
    );

    assert_eq!(
        final_with, final_without,
        "final cursor position with glide must match unglided final position"
    );
    assert!(
        max_step_without >= 3.0 * max_step_with,
        "expected largest cursor step with Glide ({max_step_with:.6}) to be at least 3x smaller than without Glide ({max_step_without:.6}), ratio={ratio:.2}x"
    );
}
