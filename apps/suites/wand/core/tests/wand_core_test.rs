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

use wand_core::bindings::{
    default_bindings, Action, Binding, BrightnessAction, Button, Direction, KeyChord, MediaAction,
    NavAction, Platform, Press, SystemAction, VolumeAction,
};
use wand_core::calibration::{calibrate, calibrate_gyro, CalibrationError, TooMuchMotion};
use wand_core::config::{Config, PointingMode, Settings, CONFIG_VERSION};
use wand_core::controller::{
    Controller, Daydream, BATTERY_CHAR_ID, BATTERY_CHAR_UUID, BATTERY_SERVICE_ID,
    BATTERY_SERVICE_UUID,
};
use wand_core::engine::{battery_low, Engine};
use wand_core::pointer::{PointerEngine, PointerMode};
use wand_core::protocol::daydream::{
    decode, sign_extend_13, Sample, Vec3, ACC_SCALE, GYRO_SCALE, ORI_SCALE,
};
use wand_core::radial::{slot_for, RadialSlot};
use wand_core::replay::{format_line, parse, parse_line, replay_into, write, ReplayRecord};

const EPS: f32 = 1e-5;

fn assert_approx(actual: f32, expected: f32) {
    assert!(
        (actual - expected).abs() <= EPS,
        "expected {expected}, got {actual} (diff {})",
        (actual - expected).abs()
    );
}

/// Helper to pack fields into a 20-byte Daydream packet by hand.
#[derive(Default, Clone, Copy)]
struct RawPacketBuilder {
    time: u16,
    seq: u8,
    x_ori: i16,
    y_ori: i16,
    z_ori: i16,
    x_acc: i16,
    y_acc: i16,
    z_acc: i16,
    x_gyro: i16,
    y_gyro: i16,
    z_gyro: i16,
    touch_x: u8,
    touch_y: u8,
    buttons: u8,
}

impl RawPacketBuilder {
    fn pack13(v: i16) -> u16 {
        (v as u16) & 0x1FFF
    }

    fn build(self) -> [u8; 20] {
        let mut b = [0u8; 20];
        let t = self.time & 0x01FF;
        let s = self.seq & 0x1F;
        let xo = Self::pack13(self.x_ori);
        let yo = Self::pack13(self.y_ori);
        let zo = Self::pack13(self.z_ori);
        let xa = Self::pack13(self.x_acc);
        let ya = Self::pack13(self.y_acc);
        let za = Self::pack13(self.z_acc);
        let xg = Self::pack13(self.x_gyro);
        let yg = Self::pack13(self.y_gyro);
        let zg = Self::pack13(self.z_gyro);

        b[0] = (t >> 1) as u8;
        b[1] = (((t & 1) as u8) << 7) | ((s & 0x1F) << 2) | ((xo >> 11) as u8 & 0x03);
        b[2] = ((xo >> 3) & 0xFF) as u8;
        // Note: bit 0 of x_ori goes into bit 7 of byte 3 (`>> 7` on decode); y_ori upper 5 bits go into bits 4..0 of byte 3.
        b[3] = (((xo & 0x01) as u8) << 7) | (((yo >> 8) as u8) & 0x1F);
        b[4] = (yo & 0xFF) as u8;
        b[5] = ((zo >> 5) & 0xFF) as u8;
        b[6] = (((zo & 0x1F) as u8) << 3) | (((xa >> 10) as u8) & 0x07);
        b[7] = ((xa >> 2) & 0xFF) as u8;
        b[8] = (((xa & 0x03) as u8) << 6) | (((ya >> 7) as u8) & 0x3F);
        b[9] = (((ya & 0x7F) as u8) << 1) | (((za >> 12) as u8) & 0x01);
        b[10] = ((za >> 4) & 0xFF) as u8;
        b[11] = (((za & 0x0F) as u8) << 4) | (((xg >> 9) as u8) & 0x0F);
        b[12] = ((xg >> 1) & 0xFF) as u8;
        b[13] = (((xg & 0x01) as u8) << 7) | (((yg >> 6) as u8) & 0x7F);
        b[14] = (((yg & 0x3F) as u8) << 2) | (((zg >> 11) as u8) & 0x03);
        b[15] = ((zg >> 3) & 0xFF) as u8;
        b[16] = (((zg & 0x07) as u8) << 5) | ((self.touch_x >> 3) & 0x1F);
        b[17] = ((self.touch_x & 0x07) << 5) | ((self.touch_y >> 3) & 0x1F);
        b[18] = ((self.touch_y & 0x07) << 5) | (self.buttons & 0x1F);
        b[19] = 0;
        b
    }
}

#[test]
fn sign_extend_13_extremes() {
    assert_eq!(sign_extend_13(0x0000), 0);
    assert_eq!(sign_extend_13(0x0001), 1);
    assert_eq!(sign_extend_13(0x0FFF), 4095);
    assert_eq!(sign_extend_13(0x1000), -4096);
    assert_eq!(sign_extend_13(0x1FFF), -1);
}

#[test]
fn decoder_x_ori_shift_7_pinned() {
    // Explicitly test the xOri low-bit shift `>> 7` vs mrdoob's `>> 5`:
    // Setting only bit 7 of byte 3 (`b[3] = 0x80`) must produce raw xOri = 1 (not 4).
    let mut pkt = [0u8; 20];
    pkt[3] = 0x80;
    let s = decode(&pkt);
    assert_approx(s.orientation.x, 1.0 * ORI_SCALE);
}

#[test]
fn decoder_golden_all_fields() {
    // Golden packet testing every field independently and together, including negative 13-bit values.
    // Note: x_ori bits 2..1 are unpopulated when b[3] is masked with 0x80 and shifted >> 7,
    // so -1031 (0x1BF9) has bits 2..1 == 0 and bit 0 == 1.
    let full = RawPacketBuilder {
        time: 0x01AB,
        seq: 19,
        x_ori: -1031,
        y_ori: 2047,
        z_ori: -4096,
        x_acc: 512,
        y_acc: -512,
        z_acc: 4095,
        x_gyro: -300,
        y_gyro: 1500,
        z_gyro: -1,
        touch_x: 200,
        touch_y: 100,
        buttons: 0x1F,
    }
    .build();

    let decoded = decode(&full);
    assert_eq!(decoded.time, 0x01AB);
    assert_eq!(decoded.seq, 19);
    assert_approx(decoded.orientation.x, -1031.0 * ORI_SCALE);
    assert_approx(decoded.orientation.y, 2047.0 * ORI_SCALE);
    assert_approx(decoded.orientation.z, -4096.0 * ORI_SCALE);
    assert_approx(decoded.accel.x, 512.0 * ACC_SCALE);
    assert_approx(decoded.accel.y, -512.0 * ACC_SCALE);
    assert_approx(decoded.accel.z, 4095.0 * ACC_SCALE);
    assert_approx(decoded.gyro.x, -300.0 * GYRO_SCALE);
    assert_approx(decoded.gyro.y, 1500.0 * GYRO_SCALE);
    assert_approx(decoded.gyro.z, -1.0 * GYRO_SCALE);
    assert_approx(decoded.touch_x, 200.0 / 255.0);
    assert_approx(decoded.touch_y, 100.0 / 255.0);
    assert!(decoded.touching);
    assert!(decoded.click);
    assert!(decoded.home);
    assert!(decoded.app);
    assert!(decoded.vol_down);
    assert!(decoded.vol_up);
}

#[test]
fn decoder_individual_buttons_and_untouched() {
    for (mask, check) in [
        (0x01u8, fn_click as fn(&Sample) -> bool),
        (0x02u8, fn_home),
        (0x04u8, fn_app),
        (0x08u8, fn_vol_down),
        (0x10u8, fn_vol_up),
    ] {
        let p = RawPacketBuilder {
            buttons: mask,
            ..Default::default()
        }
        .build();
        let d = decode(&p);
        assert!(!d.touching);
        assert_eq!(d.touch_x, 0.0);
        assert_eq!(d.touch_y, 0.0);
        assert!(check(&d));
    }
}

fn fn_click(s: &Sample) -> bool {
    s.click && !s.home && !s.app && !s.vol_down && !s.vol_up
}
fn fn_home(s: &Sample) -> bool {
    s.home && !s.click && !s.app && !s.vol_down && !s.vol_up
}
fn fn_app(s: &Sample) -> bool {
    s.app && !s.click && !s.home && !s.vol_down && !s.vol_up
}
fn fn_vol_down(s: &Sample) -> bool {
    s.vol_down && !s.click && !s.home && !s.app && !s.vol_up
}
fn fn_vol_up(s: &Sample) -> bool {
    s.vol_up && !s.click && !s.home && !s.app && !s.vol_down
}

#[test]
fn controller_trait_and_constants() {
    let ctrl = Daydream;
    assert_eq!(ctrl.name(), "Daydream controller");
    assert_eq!(ctrl.service_uuid(), "0000fe55-0000-1000-8000-00805f9b34fb");
    assert_eq!(ctrl.notify_uuid(), "00000001-1000-1000-8000-00805f9b34fb");
    assert_eq!(BATTERY_SERVICE_ID, 0x180F);
    assert_eq!(BATTERY_CHAR_ID, 0x2A19);
    assert_eq!(BATTERY_SERVICE_UUID, "0000180f-0000-1000-8000-00805f9b34fb");
    assert_eq!(BATTERY_CHAR_UUID, "00002a19-0000-1000-8000-00805f9b34fb");

    let pkt = RawPacketBuilder {
        seq: 7,
        ..Default::default()
    }
    .build();
    assert_eq!(ctrl.decode(&pkt).seq, 7);
}

#[test]
fn calibration_computes_stationary_bias() {
    let still = [
        Vec3::new(0.02, -0.01, 0.005),
        Vec3::new(0.04, -0.03, 0.015),
        Vec3::new(0.03, -0.02, 0.010),
    ];
    let bias = calibrate_gyro(&still, 0.20).expect("should calibrate when still");
    assert_approx(bias.x, 0.03);
    assert_approx(bias.y, -0.02);
    assert_approx(bias.z, 0.01);
}

#[test]
fn calibration_rejects_excessive_motion_and_empty_input() {
    let moving = [
        Sample {
            gyro: Vec3::new(0.01, 0.0, 0.0),
            ..Default::default()
        },
        Sample {
            gyro: Vec3::new(0.85, 0.0, 0.0),
            ..Default::default()
        },
    ];
    assert_eq!(calibrate(&moving, 0.25), Err(TooMuchMotion));
    assert_eq!(calibrate(&[], 0.25), Err(CalibrationError::EmptySamples));
}

#[test]
fn touch_down_does_not_jump() {
    let mut ptr = PointerEngine::new();
    let settings = Settings {
        touch_sensitivity: 200.0,
        touch_deadzone: 0.02,
        ..Default::default()
    };

    // First sample after touch-down drops delta to prevent jump.
    let s1 = Sample {
        touching: true,
        touch_x: 0.5,
        touch_y: 0.5,
        ..Default::default()
    };
    assert_eq!(
        ptr.update(&s1, PointerMode::Touch, &settings, Vec3::default()),
        None
    );

    // Touch release then new touch-down at far location also drops the first delta.
    let s_up = Sample::default();
    assert_eq!(
        ptr.update(&s_up, PointerMode::Touch, &settings, Vec3::default()),
        None
    );
    let s_re_down = Sample {
        touching: true,
        touch_x: 0.1,
        touch_y: 0.9,
        ..Default::default()
    };
    assert_eq!(
        ptr.update(&s_re_down, PointerMode::Touch, &settings, Vec3::default()),
        None
    );
}

#[test]
fn touch_deadzone_and_sensitivity() {
    let mut ptr = PointerEngine::new();
    let settings = Settings {
        touch_sensitivity: 200.0,
        touch_deadzone: 0.02,
        ..Default::default()
    };

    let s1 = Sample {
        touching: true,
        touch_x: 0.5,
        touch_y: 0.5,
        ..Default::default()
    };
    assert_eq!(
        ptr.update(&s1, PointerMode::Touch, &settings, Vec3::default()),
        None
    );

    // Touch delta inside deadzone (0.01 <= 0.02) produces None.
    let s2 = Sample {
        touching: true,
        touch_x: 0.51,
        touch_y: 0.5,
        ..Default::default()
    };
    assert_eq!(
        ptr.update(&s2, PointerMode::Touch, &settings, Vec3::default()),
        None
    );

    // Touch delta above deadzone (0.11 > 0.02) scales by touch_sensitivity (200.0).
    let s3 = Sample {
        touching: true,
        touch_x: 0.62,
        touch_y: 0.46,
        ..Default::default()
    };
    match ptr.update(&s3, PointerMode::Touch, &settings, Vec3::default()) {
        Some(Action::Move { dx, dy }) => {
            assert_approx(dx, (0.62 - 0.51) * 200.0);
            assert_approx(dy, (0.46 - 0.50) * 200.0);
        }
        other => panic!("expected Move, got {other:?}"),
    }
}

#[test]
fn gyro_deadzone_bias_curve_and_ema_smoothing() {
    let mut ptr = PointerEngine::new();
    let mut settings = Settings {
        pointing_mode: PointingMode::Relative,
        gyro_x_speed: 10.0,
        gyro_y_speed: 20.0,
        gyro_deadzone: 0.05,
        acceleration_curve: 2.0,
        ema_smoothing: 0.5,
        ..Default::default()
    };

    let bias = Vec3::new(0.1, -0.1, 0.0);
    let tremor = Sample {
        gyro: Vec3::new(0.12, -0.09, 0.0), // net (0.02, 0.01), norm < 0.05 deadzone
        ..Default::default()
    };
    assert_eq!(
        ptr.update(&tremor, PointerMode::Gyro, &settings, bias),
        None
    );

    // Raw gyro (x=pitch 3.1, y=yaw -2.1) minus bias -> pointer (dx=-yaw, dy=-pitch)... see pointer.rs.
    // Pointer-space net = (2.0, -3.0) -> curved (4.0, -9.0) -> target (40.0, -180.0) -> EMA step 1 (alpha=0.5): (20.0, -90.0)
    let wave = Sample {
        gyro: Vec3::new(3.1, -2.1, 0.0),
        ..Default::default()
    };
    match ptr.update(&wave, PointerMode::Gyro, &settings, bias) {
        Some(Action::Move { dx, dy }) => {
            assert_approx(dx, 20.0);
            assert_approx(dy, -90.0);
        }
        other => panic!("expected gyro Move, got {other:?}"),
    }
    // EMA step 2 with same input -> (30.0, -135.0)
    match ptr.update(&wave, PointerMode::Gyro, &settings, bias) {
        Some(Action::Move { dx, dy }) => {
            assert_approx(dx, 30.0);
            assert_approx(dy, -135.0);
        }
        other => panic!("expected gyro Move, got {other:?}"),
    }

    // Linear curve (1.0) and unsmoothed (1.0)
    settings.acceleration_curve = 1.0;
    settings.ema_smoothing = 0.0;
    ptr.reset();
    match ptr.update(&wave, PointerMode::Gyro, &settings, bias) {
        Some(Action::Move { dx, dy }) => {
            assert_approx(dx, 20.0);
            assert_approx(dy, -60.0);
        }
        other => panic!("expected linear gyro Move, got {other:?}"),
    }
}

#[test]
fn short_fires_immediately_without_double_binding() {
    let cfg = Config::for_platform(Platform::Desktop);
    let mut engine = Engine::new(cfg, Platform::Desktop);

    // Home on Desktop has no Double binding -> Short (RightClick) fires immediately on release without waiting 300ms.
    let home_down = RawPacketBuilder {
        buttons: 0x02,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];
    assert_eq!(engine.feed(&home_down, 1_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 100_000), vec![Action::RightClick]);
}

#[test]
fn double_press_inside_gap() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::Home, Press::Double),
        Binding::once(Action::Media(MediaAction::PlayPause)),
    );
    let mut engine = Engine::new(cfg, Platform::Desktop);

    let home_down = RawPacketBuilder {
        buttons: 0x02,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];

    // Press at 200ms, release at 250ms -> waits for double-press window.
    // At 550ms (exact 300ms boundary: 550_000 - 250_000 == 300_000), second press counts as Double.
    assert_eq!(engine.feed(&home_down, 200_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 250_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&home_down, 550_000), Vec::<Action>::new());
    assert_eq!(
        engine.feed(&idle, 600_000),
        vec![Action::Media(MediaAction::PlayPause)]
    );
}

#[test]
fn double_press_just_outside_gap() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::Home, Press::Double),
        Binding::once(Action::Media(MediaAction::PlayPause)),
    );
    let mut engine = Engine::new(cfg, Platform::Desktop);

    let home_down = RawPacketBuilder {
        buttons: 0x02,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];

    assert_eq!(engine.feed(&home_down, 1_000_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 1_050_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 1_350_000), Vec::<Action>::new()); // exactly 300ms: still waiting
    assert_eq!(
        engine.feed(&idle, 1_350_001),
        vec![Action::RightClick] // 300.001ms: fires Short
    );
}

#[test]
fn click_hold_and_move_is_drag() {
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);

    // Pressing Click immediately emits MouseDown (before the first Move and without waiting 500ms).
    let click_touch1 = RawPacketBuilder {
        buttons: 0x01,
        touch_x: 64,
        touch_y: 64,
        ..Default::default()
    }
    .build();
    let click_touch2 = RawPacketBuilder {
        buttons: 0x01,
        touch_x: 128,
        touch_y: 64,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];

    assert_eq!(engine.feed(&click_touch1, 10_000), vec![Action::MouseDown]);
    let move_actions = engine.feed(&click_touch2, 50_000);
    assert_eq!(move_actions.len(), 1);
    assert!(matches!(move_actions[0], Action::Move { dx, dy } if dx > 0.0 && dy == 0.0));
    assert_eq!(engine.feed(&idle, 120_000), vec![Action::MouseUp]);
}

#[test]
fn android_click_hold_is_physical_down_and_up() {
    let cfg = Config::for_platform(Platform::Android);
    assert_eq!(
        cfg.bindings.get(&(Button::Click, Press::Short)),
        Some(&Binding::hold(Action::LeftClick))
    );
    assert_eq!(cfg.bindings.get(&(Button::Click, Press::Long)), None);

    let mut engine = Engine::new(cfg, Platform::Android);
    let click_down = RawPacketBuilder {
        buttons: 0x01,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];

    // Physical down immediately starts hold (MouseDown); holding past 600ms keeps it held until release (MouseUp).
    assert_eq!(engine.feed(&click_down, 0), vec![Action::MouseDown]);
    assert_eq!(engine.feed(&click_down, 600_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 700_000), vec![Action::MouseUp]);
}

#[test]
fn long_hold_without_long_binding_is_short() {
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);

    // App has (App, Short) = ToggleGyro and NO (App, Long) binding.
    // Holding App for 600ms (> 500ms threshold) and releasing must still fire Short (ToggleGyro).
    let app_down = RawPacketBuilder {
        buttons: 0x04,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];

    assert_eq!(engine.feed(&app_down, 0), Vec::<Action>::new());
    assert_eq!(engine.feed(&app_down, 600_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 650_000), vec![Action::ToggleGyro]);
}

#[test]
fn long_binding_fires_at_threshold() {
    let mut engine = Engine::new(Config::for_platform(Platform::Android), Platform::Android);

    // On Android, Home has Short = Nav(Back) and Long = Nav(Home).
    // Holding Home to 500ms fires Nav(Home) at the threshold, and releasing does not fire Short.
    let home_down = RawPacketBuilder {
        buttons: 0x02,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];

    assert_eq!(engine.feed(&home_down, 0), Vec::<Action>::new());
    assert_eq!(engine.feed(&home_down, 499_999), Vec::<Action>::new());
    assert_eq!(
        engine.feed(&home_down, 500_000),
        vec![Action::Nav(NavAction::Home)]
    );
    assert_eq!(engine.feed(&idle, 600_000), Vec::<Action>::new());
}

#[test]
fn touchpad_tap_within_limits_fires_short() {
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
    let tap_down = RawPacketBuilder {
        touch_x: 100,
        touch_y: 100,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];

    // Touchpad tap (< 200ms, small movement, no click) -> LeftClick.
    assert_eq!(engine.feed(&tap_down, 3_000_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 3_150_000), vec![Action::LeftClick]);

    // Touch held > 200ms does NOT tap.
    assert_eq!(engine.feed(&tap_down, 4_000_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 4_250_000), Vec::<Action>::new());
}

#[test]
fn toggle_alternates() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::VolUp, Press::Short),
        Binding::toggle(Action::LeftClick),
    );
    let mut engine = Engine::new(cfg, Platform::Desktop);

    let vol_up = RawPacketBuilder {
        buttons: 0x10,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];

    assert_eq!(engine.feed(&vol_up, 5_000_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 5_050_000), vec![Action::MouseDown]);
    assert_eq!(engine.feed(&vol_up, 5_100_000), Vec::<Action>::new());
    assert_eq!(engine.feed(&idle, 5_150_000), vec![Action::MouseUp]);
}

#[test]
fn radial_dead_centre_is_none() {
    assert_eq!(slot_for(0.0, 0.0, 10.0), None);
    assert_eq!(slot_for(6.0, -8.0, 10.0), None); // exact radius 10.0 <= 10.0
}

#[test]
fn radial_eight_slices_and_boundaries() {
    // 8 cardinal & diagonal directions (0 = Up, clockwise)
    assert_eq!(slot_for(0.0, -20.0, 5.0), Some(0)); // Up
    assert_eq!(slot_for(20.0, -20.0, 5.0), Some(1)); // Up-Right
    assert_eq!(slot_for(20.0, 0.0, 5.0), Some(2)); // Right
    assert_eq!(slot_for(20.0, 20.0, 5.0), Some(3)); // Down-Right
    assert_eq!(slot_for(0.0, 20.0, 5.0), Some(4)); // Down
    assert_eq!(slot_for(-20.0, 20.0, 5.0), Some(5)); // Down-Left
    assert_eq!(slot_for(-20.0, 0.0, 5.0), Some(6)); // Left
    assert_eq!(slot_for(-20.0, -20.0, 5.0), Some(7)); // Up-Left

    // Just before and after the +22.5 deg boundary between slot 0 and slot 1
    let r = 100.0f32;
    let deg22 = 22.0f32.to_radians();
    let deg23 = 23.0f32.to_radians();
    assert_eq!(slot_for(r * deg22.sin(), -r * deg22.cos(), 5.0), Some(0));
    assert_eq!(slot_for(r * deg23.sin(), -r * deg23.cos(), 5.0), Some(1));
}

#[test]
fn radial_menu_hold_move_release_executes_slot() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::Home, Press::Long),
        Binding::hold(Action::RadialMenu),
    );
    cfg.radial_slots[2] = RadialSlot {
        label: "Paste".to_string(),
        color: "accent".to_string(),
        action: Some(Action::System(SystemAction::Paste)),
    };
    let mut engine = Engine::new(cfg, Platform::Desktop);
    let home_down = RawPacketBuilder {
        buttons: 0x02,
        touch_x: 64,
        touch_y: 128,
        ..Default::default()
    }
    .build();
    let home_move_right = RawPacketBuilder {
        buttons: 0x02,
        touch_x: 200,
        touch_y: 128,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];
    assert!(engine.feed(&home_down, 0).is_empty());
    let long_out = engine.feed(&home_move_right, 500_000);
    assert_eq!(long_out[0], Action::RadialMenu);
    assert_eq!(
        engine.feed(&idle, 550_000),
        vec![Action::System(SystemAction::Paste)]
    );
}

#[test]
fn default_bindings_per_platform() {
    let desktop_bindings = default_bindings(Platform::Desktop);
    assert_eq!(
        desktop_bindings.get(&(Button::Click, Press::Short)),
        Some(&Binding::hold(Action::LeftClick))
    );
    assert_eq!(desktop_bindings.get(&(Button::Click, Press::Long)), None);
    assert_eq!(
        desktop_bindings.get(&(Button::Home, Press::Short)),
        Some(&Binding::once(Action::RightClick))
    );

    let android_bindings = default_bindings(Platform::Android);
    assert_eq!(
        android_bindings.get(&(Button::Click, Press::Short)),
        Some(&Binding::hold(Action::LeftClick))
    );
    assert_eq!(android_bindings.get(&(Button::Click, Press::Long)), None);
    assert_eq!(
        android_bindings.get(&(Button::Home, Press::Short)),
        Some(&Binding::once(Action::Nav(NavAction::Back)))
    );
    assert_eq!(
        android_bindings.get(&(Button::Home, Press::Long)),
        Some(&Binding::once(Action::Nav(NavAction::Home)))
    );
}

#[test]
fn config_serde_roundtrip_and_reset_to_defaults() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    assert_eq!(cfg.version, CONFIG_VERSION);

    cfg.settings.touch_sensitivity = 555.0;
    cfg.radial_slots[2] = RadialSlot {
        label: "Copy".to_string(),
        color: "accent".to_string(),
        action: Some(Action::System(SystemAction::Copy)),
    };
    cfg.bindings.insert(
        (Button::App, Press::Long),
        Binding::once(Action::Key(KeyChord::with_modifiers(
            "c", true, false, false, true,
        ))),
    );
    cfg.extra.insert(
        "custom_future_flag".to_string(),
        serde_json::Value::Bool(true),
    );

    let json = serde_json::to_string_pretty(&cfg).expect("serialize Config");
    let parsed: Config = serde_json::from_str(&json).expect("deserialize Config");
    assert_eq!(parsed, cfg);

    let actions = vec![
        Action::Volume(VolumeAction::Up),
        Action::Brightness(BrightnessAction::Down),
        Action::LaunchApp("com.example.app".to_string()),
        Action::RadialMenu,
        Action::DPad(Direction::Right),
        Action::ScreenOff,
        Action::Assistant,
        Action::VoiceTyping,
    ];
    let actions_json = serde_json::to_string(&actions).unwrap();
    let actions_back: Vec<Action> = serde_json::from_str(&actions_json).unwrap();
    assert_eq!(actions_back, actions);

    let mut dirty = parsed;
    dirty.reset_to_defaults();
    assert_eq!(dirty.settings, Settings::default());
    assert_eq!(dirty.bindings, default_bindings(Platform::Desktop));
}

#[test]
fn test_mode_emits_no_actions_but_updates_sample() {
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
    engine.set_test_mode(true);
    let click_pkt = RawPacketBuilder {
        seq: 12,
        buttons: 0x01,
        ..Default::default()
    }
    .build();
    assert!(engine.feed(&click_pkt, 10_000).is_empty());
    assert_eq!(engine.last_sample().unwrap().seq, 12);
    assert!(engine.last_sample().unwrap().click);
}

#[test]
fn engine_recalibrate_updates_gyro_bias() {
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
    engine.recalibrate_with(3, 0.25);
    assert!(engine.is_calibrating());
    let bias_pkt = RawPacketBuilder {
        x_gyro: 10,
        y_gyro: -10,
        ..Default::default()
    }
    .build();
    for t in [20_000, 30_000, 40_000] {
        engine.feed(&bias_pkt, t);
    }
    assert!(!engine.is_calibrating());
    assert_eq!(engine.last_calibration_error(), None);
    assert_approx(engine.gyro_bias().x, 10.0 * GYRO_SCALE);
}

#[test]
fn engine_gyro_mode_touchpad_scroll() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.horizontal_scroll = true;
    cfg.settings.reverse_scroll = true;
    cfg.settings.scroll_strength = 2.0;

    let mut engine = Engine::new(cfg, Platform::Desktop);
    engine.set_gyro_mode(true);
    let t1 = RawPacketBuilder {
        touch_x: 64,
        touch_y: 64,
        ..Default::default()
    }
    .build();
    let t2 = RawPacketBuilder {
        touch_x: 128,
        touch_y: 96,
        ..Default::default()
    }
    .build();
    assert!(engine.feed(&t1, 50_000).is_empty());
    let scroll_out = engine.feed(&t2, 60_000);
    assert_eq!(scroll_out.len(), 1);
    match scroll_out[0] {
        Action::Scroll { dx, dy } => {
            assert_approx(dx, -((64.0 / 255.0) * 2.0));
            assert_approx(dy, -((32.0 / 255.0) * 2.0));
        }
        ref other => panic!("expected Scroll, got {other:?}"),
    }
}

#[test]
fn engine_android_tv_gyro_touchpad_dpad() {
    let mut tv_engine = Engine::new(
        Config::for_platform(Platform::AndroidTv),
        Platform::AndroidTv,
    );
    tv_engine.set_gyro_mode(true);
    let tv_start = RawPacketBuilder {
        touch_x: 64,
        touch_y: 128,
        ..Default::default()
    }
    .build();
    let tv_right = RawPacketBuilder {
        touch_x: 200,
        touch_y: 128,
        ..Default::default()
    }
    .build();
    assert!(tv_engine.feed(&tv_start, 10_000).is_empty());
    assert_eq!(
        tv_engine.feed(&tv_right, 20_000),
        vec![Action::DPad(Direction::Right)]
    );
}

#[test]
fn battery_low_threshold() {
    assert!(battery_low(0));
    assert!(battery_low(14));
    assert!(!battery_low(15));
    assert!(!battery_low(100));
    assert!(Engine::battery_low(10));
}

#[test]
fn replay_format_roundtrip_and_testdata_session() {
    let pkt = RawPacketBuilder {
        time: 42,
        seq: 3,
        buttons: 0x04,
        ..Default::default()
    }
    .build();
    let line = format_line(123_456, &pkt);
    let parsed = parse_line(&line).unwrap().unwrap();
    assert_eq!(
        parsed,
        ReplayRecord {
            t_us: 123_456,
            packet: pkt
        }
    );

    let transcript = write(&[parsed]);
    assert_eq!(parse(&transcript).unwrap(), vec![parsed]);

    // Drive the full engine from testdata/session.replay
    let session_data = include_str!("../testdata/session.replay");
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
    let actions = replay_into(&mut engine, session_data).expect("replay session.replay");

    // Expected sequence from testdata/session.replay:
    // 1. Touch move -> Action::Move
    // 2. Click press & release -> Action::MouseDown, Action::MouseUp
    // 3. App button -> Action::ToggleGyro
    // 4. Gyro motion -> Action::PointTo (default Desktop mode is Absolute)
    // 5. VolUp -> Action::Scroll { dx: 0.0, dy: 1.0 }
    assert_eq!(actions.len(), 6);
    assert!(matches!(actions[0], Action::Move { dx, dy } if dx > 0.0 && dy == 0.0));
    assert_eq!(actions[1], Action::MouseDown);
    assert_eq!(actions[2], Action::MouseUp);
    assert_eq!(actions[3], Action::ToggleGyro);
    assert!(matches!(actions[4], Action::PointTo { x, y } if x == 0.0 && y < 0.0));
    assert_eq!(actions[5], Action::Scroll { dx: 0.0, dy: 1.0 });
    assert!(engine.gyro_mode());
}

fn make_packet(touch_x: u8, touch_y: u8, buttons: u8) -> [u8; 20] {
    RawPacketBuilder {
        touch_x,
        touch_y,
        buttons,
        ..Default::default()
    }
    .build()
}

#[test]
fn known_defect_test_mode_toggle_mid_drag_releases_mouse() {
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
    let click_down = make_packet(0, 0, 0x01);
    let click_up = make_packet(0, 0, 0x00);

    assert_eq!(engine.feed(&click_down, 0), vec![Action::MouseDown]);

    engine.set_test_mode(true);
    engine.set_test_mode(false);

    let release_out = engine.feed(&click_up, 100_000);
    assert!(
        release_out.contains(&Action::MouseUp),
        "expected MouseUp in release output after test mode toggle, got {release_out:?}"
    );
}

#[test]
/// With Long also bound on Click, a Short Hold cannot press immediately (the engine must wait
/// to see whether the press becomes Long), so a short press resolves on release as a click.
/// Immediate drag needs Long and Double unbound; the Bindings UI says so.
fn hold_short_with_long_binding_clicks_on_release() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::Click, Press::Long),
        Binding::once(Action::Key(KeyChord::new("a"))),
    );
    let mut engine = Engine::new(cfg, Platform::Desktop);

    let click_down = make_packet(0, 0, 0x01);
    let click_up = make_packet(0, 0, 0x00);

    let down_out = engine.feed(&click_down, 0);
    let up_out = engine.feed(&click_up, 100_000);
    assert_eq!(
        (down_out, up_out),
        (
            Vec::<Action>::new(),
            vec![Action::MouseDown, Action::MouseUp]
        )
    );
}

#[test]
fn known_defect_tap_double_binding_fires() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::Tap, Press::Double),
        Binding::once(Action::Key(KeyChord::new("b"))),
    );
    let mut engine = Engine::new(cfg, Platform::Desktop);

    let touch = make_packet(100, 100, 0x00);
    let release = make_packet(0, 0, 0x00);

    let mut outputs = Vec::new();
    outputs.extend(engine.feed(&touch, 0));
    outputs.extend(engine.feed(&release, 50_000));
    outputs.extend(engine.feed(&touch, 150_000));
    outputs.extend(engine.feed(&release, 200_000));

    let expected = Action::Key(KeyChord::new("b"));
    assert!(
        outputs.contains(&expected),
        "expected {expected:?} in outputs for double tap, got {outputs:?}"
    );
}

#[test]
fn known_defect_radial_hold_non_finite_settings() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.touch_sensitivity = f32::NAN;
    let mut engine = Engine::new(cfg, Platform::Desktop);

    let p1 = make_packet(100, 100, 0x00);
    let p2 = make_packet(140, 100, 0x00);

    let mut outputs = Vec::new();
    outputs.extend(engine.feed(&p1, 0));
    outputs.extend(engine.feed(&p2, 20_000));

    for action in &outputs {
        if let Action::Move { dx, dy } = action {
            assert!(
                dx.is_finite() && dy.is_finite(),
                "expected finite Move deltas, got dx={dx}, dy={dy}"
            );
        }
    }
}

#[test]
fn release_all_releases_active_holds_toggles_and_closes_radial_without_slot() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::VolUp, Press::Short),
        Binding::toggle(Action::LeftClick),
    );
    cfg.bindings.insert(
        (Button::Home, Press::Short),
        Binding::hold(Action::RadialMenu),
    );
    cfg.radial_slots[2] = RadialSlot {
        label: "Paste".to_string(),
        color: "accent".to_string(),
        action: Some(Action::System(SystemAction::Paste)),
    };
    let mut engine = Engine::new(cfg, Platform::Desktop);

    // 1. Activate Toggle on VolUp -> MouseDown
    let vol_up = make_packet(0, 0, 0x10);
    let idle = make_packet(0, 0, 0x00);
    assert!(engine.feed(&vol_up, 0).is_empty());
    assert_eq!(engine.feed(&idle, 20_000), vec![Action::MouseDown]);

    // 2. Hold Home + move right to select radial slot 2
    let home_touch1 = make_packet(64, 128, 0x02);
    let home_touch2 = make_packet(200, 128, 0x02);
    assert_eq!(engine.feed(&home_touch1, 40_000), vec![Action::RadialMenu]);
    assert!(engine.is_radial_active());
    let _ = engine.feed(&home_touch2, 60_000);

    // 3. release_all must emit MouseUp for the active toggle and close radial WITHOUT running slot 2.
    let released = engine.release_all();
    assert_eq!(released, vec![Action::MouseUp]);
    assert!(!engine.is_radial_active());
    assert!(engine.feed(&idle, 80_000).is_empty());
}

#[test]
fn tick_fires_long_press_and_double_expiry_without_further_packets() {
    let mut cfg = Config::for_platform(Platform::Android);
    cfg.bindings.insert(
        (Button::App, Press::Double),
        Binding::once(Action::Media(MediaAction::PlayPause)),
    );
    let mut engine = Engine::new(cfg, Platform::Android);

    // 1. Long press on Home with no further packets after press-down at t=0:
    let home_down = make_packet(0, 0, 0x02);
    let idle = make_packet(0, 0, 0x00);
    assert!(engine.feed(&home_down, 0).is_empty());
    assert!(engine.tick(499_999).is_empty());
    assert_eq!(engine.tick(500_000), vec![Action::Nav(NavAction::Home)]);
    // Releasing later does not re-fire Short or Long.
    assert!(engine.feed(&idle, 600_000).is_empty());

    // 2. Double-press window expiry on App with no further packets after release:
    let app_down = make_packet(0, 0, 0x04);
    assert!(engine.feed(&app_down, 1_000_000).is_empty());
    assert!(engine.feed(&idle, 1_050_000).is_empty());
    assert!(engine.tick(1_350_000).is_empty());
    assert_eq!(engine.tick(1_350_001), vec![Action::ToggleGyro]);
}

#[test]
fn tap_long_fires_when_touch_held_stationary_without_click() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::Tap, Press::Long),
        Binding::once(Action::RightClick),
    );
    let mut engine = Engine::new(cfg, Platform::Desktop);

    let touch = make_packet(120, 120, 0x00);
    let release = make_packet(0, 0, 0x00);

    assert!(engine.feed(&touch, 0).is_empty());
    // Tick past long_press_ms (500ms) while touch is held still without click:
    assert!(engine.tick(499_999).is_empty());
    assert_eq!(engine.tick(500_000), vec![Action::RightClick]);
    // Releasing touch after Tap Long must not fire Tap Short.
    assert!(engine.feed(&release, 550_000).is_empty());
}

#[test]
fn settings_validation_clamps_nan_inf_and_out_of_range_and_preserves_extra() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.touch_sensitivity = f32::NAN;
    cfg.settings.gyro_x_speed = f32::INFINITY;
    cfg.settings.gyro_y_speed = f32::NEG_INFINITY;
    cfg.settings.scroll_strength = -10.0;
    cfg.settings.long_press_ms = 10;
    cfg.settings.double_press_ms = 99_999;
    cfg.settings
        .extra
        .insert("experimental_knob".to_string(), serde_json::json!(42));

    let mut engine = Engine::new(cfg, Platform::Desktop);
    let s = &engine.config().settings;
    assert_eq!(s.touch_sensitivity, 400.0);
    assert_eq!(s.gyro_x_speed, 60.0);
    assert_eq!(s.gyro_y_speed, 1.0);
    assert_eq!(s.scroll_strength, 0.1);
    assert_eq!(s.long_press_ms, 100);
    assert_eq!(s.double_press_ms, 2000);
    assert_eq!(
        s.extra.get("experimental_knob"),
        Some(&serde_json::json!(42))
    );

    let mut bad_update = engine.config().clone();
    bad_update.settings.ema_smoothing = f32::NAN;
    bad_update.settings.acceleration_curve = 99.0;
    engine.set_config(bad_update);
    assert_eq!(engine.config().settings.ema_smoothing, 0.3);
    assert_eq!(engine.config().settings.acceleration_curve, 3.0);
}

#[test]
fn feed_never_panics_on_arbitrary_packets() {
    for gyro_mode in [false, true] {
        let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
        engine.set_gyro_mode(gyro_mode);

        let mut state: u64 = 0xDEAD_BEEF_CAFE_BABEu64 ^ (gyro_mode as u64);
        let mut next_u64 = || -> u64 {
            state = state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            state
        };

        let mut t_us: u64 = 0;
        for i in 0..20_000u32 {
            let mut pkt = [0u8; 20];
            let w0 = next_u64().to_le_bytes();
            let w1 = next_u64().to_le_bytes();
            let w2 = next_u64().to_le_bytes();
            pkt[0..8].copy_from_slice(&w0);
            pkt[8..16].copy_from_slice(&w1);
            pkt[16..20].copy_from_slice(&w2[0..4]);

            let dt = match i % 20 {
                0 => 0,
                1 => 10_000_000,
                _ => (next_u64() % 50_000) + 1,
            };
            t_us = t_us.saturating_add(dt);

            for action in engine.feed(&pkt, t_us) {
                match action {
                    Action::Move { dx, dy } => {
                        assert!(
                            dx.is_finite() && dy.is_finite(),
                            "non-finite Move at step {i} (gyro={gyro_mode}): dx={dx}, dy={dy}"
                        );
                    }
                    Action::PointTo { x, y } => {
                        assert!(
                            x.is_finite() && y.is_finite(),
                            "non-finite PointTo at step {i} (gyro={gyro_mode}): x={x}, y={y}"
                        );
                    }
                    _ => {}
                }
            }
        }
    }
}

#[test]
fn set_config_mid_drag_releases_with_old_binding() {
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
    let click_down = make_packet(0, 0, 0x01);
    let click_up = make_packet(0, 0, 0x00);
    assert_eq!(engine.feed(&click_down, 0), vec![Action::MouseDown]);

    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.bindings.insert(
        (Button::Click, Press::Short),
        Binding::once(Action::RightClick),
    );
    engine.set_config(cfg);

    // The queued release comes out on the next packet; releasing the button afterwards must not
    // fire the new binding as a fresh press.
    let out = engine.feed(&click_up, 50_000);
    assert_eq!(out.first(), Some(&Action::MouseUp), "got {out:?}");
    assert!(!out.contains(&Action::RightClick), "got {out:?}");
}

#[test]
fn tick_after_release_all_is_quiet() {
    let mut engine = Engine::new(Config::for_platform(Platform::Desktop), Platform::Desktop);
    assert_eq!(
        engine.feed(&make_packet(0, 0, 0x01), 0),
        vec![Action::MouseDown]
    );
    assert_eq!(engine.release_all(), vec![Action::MouseUp]);
    for t in [20_000, 40_000, 600_000] {
        assert_eq!(engine.tick(t), Vec::<Action>::new());
    }
}

/// Pins the gyro axis mapping to a real controller recording: turning left/right must move the
/// pointer mostly sideways, and tilting up/down mostly vertically.
#[test]
fn real_recording_yaw_moves_sideways_and_pitch_moves_vertically() {
    let records = parse(include_str!("../testdata/daydream_axes.replay")).expect("parse recording");
    let t0 = records[0].t_us;
    let window = |from_s: f64, to_s: f64| -> (f32, f32) {
        let mut cfg = Config::for_platform(Platform::Desktop);
        cfg.settings.pointing_mode = PointingMode::Relative;
        let mut engine = Engine::new(cfg, Platform::Desktop);
        engine.set_gyro_mode(true);
        let (mut sx, mut sy) = (0.0f32, 0.0f32);
        for r in &records {
            let t = (r.t_us - t0) as f64 / 1e6;
            let actions = engine.feed(&r.packet, r.t_us);
            if t < from_s || t > to_s {
                continue;
            }
            for a in actions {
                if let Action::Move { dx, dy } = a {
                    sx += dx.abs();
                    sy += dy.abs();
                }
            }
        }
        (sx, sy)
    };
    let (yaw_x, yaw_y) = window(17.5, 19.5);
    assert!(
        yaw_x > 2.0 * yaw_y,
        "turning left/right: |dx|={yaw_x} should dominate |dy|={yaw_y}"
    );
    let (pitch_x, pitch_y) = window(25.0, 29.0);
    assert!(
        pitch_y > 2.0 * pitch_x,
        "tilting up/down: |dy|={pitch_y} should dominate |dx|={pitch_x}"
    );
}

/// Gyro readings are rates, so a late packet must carry the rotation from the whole gap:
/// the same turn delivered at 30 Hz must move the pointer as far as at 60 Hz.
#[test]
fn gyro_motion_is_independent_of_packet_rate() {
    let mut settings = Settings {
        pointing_mode: PointingMode::Relative,
        ..Default::default()
    };
    settings.ema_smoothing = 0.0;
    settings.gyro_deadzone = 0.0;
    let turn = Sample {
        gyro: Vec3::new(0.0, 1.0, 0.0),
        ..Default::default()
    };
    let travel = |interval_us: u64, packets: u64| -> f32 {
        let mut ptr = PointerEngine::new();
        let mut total = 0.0;
        for i in 0..packets {
            if let Some(Action::Move { dx, .. }) = ptr.update_at(
                &turn,
                PointerMode::Gyro,
                &settings,
                Vec3::default(),
                i * interval_us,
            ) {
                total += dx;
            }
        }
        total
    };
    // One second of turning: 60 packets at 60 Hz vs 30 packets at 30 Hz (first packet counts as one nominal interval).
    let fast = travel(16_667, 61);
    let slow = travel(33_333, 31);
    assert!(
        (fast - slow).abs() / fast.abs() < 0.05,
        "60 Hz moved {fast}, 30 Hz moved {slow}"
    );
}

#[test]
fn real_recording_absolute_mode_yaw_and_pitch_windows() {
    let records = parse(include_str!("../testdata/daydream_axes.replay")).expect("parse recording");
    let t0 = records[0].t_us;

    let run_window = |from_s: f64, to_s: f64| -> (f32, f32, f32, f32, f32, f32) {
        let cfg = Config::for_platform(Platform::Desktop);
        assert_eq!(cfg.settings.pointing_mode, PointingMode::Absolute);
        let mut engine = Engine::new(cfg, Platform::Desktop);
        let mut entered = false;
        let mut start_x = None;
        let mut end_x = 0.0f32;
        let mut min_x = f32::INFINITY;
        let mut max_x = f32::NEG_INFINITY;
        let mut min_y = f32::INFINITY;
        let mut max_y = f32::NEG_INFINITY;

        for r in &records {
            let t = (r.t_us - t0) as f64 / 1e6;
            if t >= from_s && !entered {
                engine.set_gyro_mode(true);
                entered = true;
            }
            let actions = engine.feed(&r.packet, r.t_us);
            if t < from_s || t > to_s {
                continue;
            }
            for a in actions {
                if let Action::PointTo { x, y } = a {
                    start_x.get_or_insert(x);
                    end_x = x;
                    min_x = min_x.min(x);
                    max_x = max_x.max(x);
                    min_y = min_y.min(y);
                    max_y = max_y.max(y);
                }
            }
        }
        (start_x.unwrap_or(0.0), end_x, min_x, max_x, min_y, max_y)
    };

    // Yaw window (~17.5–23 s): x swings both ways, returns near its starting value, and |x| range dominates |y| range.
    let (start_x, end_x, min_x, max_x, min_y, max_y) = run_window(17.5, 23.0);
    let yaw_x_range = max_x - min_x;
    let yaw_y_range = max_y - min_y;
    assert!(
        min_x < -0.15 && max_x > 0.15,
        "expected yaw window x to swing both ways around 0, got min_x={min_x}, max_x={max_x}"
    );
    assert!(
        (end_x - start_x).abs() < 0.20,
        "expected yaw window x to return near start ({start_x}), got end_x={end_x}"
    );
    assert!(
        yaw_x_range > 2.0 * yaw_y_range,
        "yaw window: |x| range ({yaw_x_range}) must dominate |y| range ({yaw_y_range})"
    );

    // Pitch window (~25–30 s): |y| range dominates |x| range.
    let (_, _, p_min_x, p_max_x, p_min_y, p_max_y) = run_window(25.0, 30.0);
    let pitch_x_range = p_max_x - p_min_x;
    let pitch_y_range = p_max_y - p_min_y;
    assert!(
        pitch_y_range > 2.0 * pitch_x_range,
        "pitch window: |y| range ({pitch_y_range}) must dominate |x| range ({pitch_x_range})"
    );
}

#[test]
fn absolute_mode_overshoot_past_edge_and_return_realigns_to_zero() {
    let settings = Settings {
        pointing_mode: PointingMode::Absolute,
        pointing_span_deg: 50.0,
        gyro_deadzone: 0.02,
        ema_smoothing: 0.0,
        ..Default::default()
    };
    let mut ptr = PointerEngine::new();
    let dt_us = 16_667u64;
    let mut t_us = 0u64;

    // Turn right (yaw = gyro.y < 0 -> screen dx = -yaw > 0) fast enough to overshoot past x = +1.0.
    let turn_right = Sample {
        gyro: Vec3::new(0.0, -2.0, 0.0),
        ..Default::default()
    };
    let mut peak_x = 0.0f32;
    for _ in 0..45 {
        t_us += dt_us;
        if let Some(Action::PointTo { x, .. }) = ptr.update_at(
            &turn_right,
            PointerMode::Gyro,
            &settings,
            Vec3::default(),
            t_us,
        ) {
            peak_x = peak_x.max(x);
        }
    }
    assert!(
        peak_x > 1.2,
        "expected overshoot well past right edge (+1.0), got peak_x={peak_x}"
    );

    // Turn back left by the exact same rate and packet count -> x must return to ~0.0 (no clamped/lost motion).
    let turn_left = Sample {
        gyro: Vec3::new(0.0, 2.0, 0.0),
        ..Default::default()
    };
    let mut final_x = peak_x;
    for _ in 0..45 {
        t_us += dt_us;
        if let Some(Action::PointTo { x, .. }) = ptr.update_at(
            &turn_left,
            PointerMode::Gyro,
            &settings,
            Vec3::default(),
            t_us,
        ) {
            final_x = x;
        }
    }
    assert!(
        final_x.abs() < 1e-4,
        "expected x to return to ~0 after equal and opposite turn from overshoot, got {final_x}"
    );
}

#[test]
fn absolute_mode_packet_rate_independence_30hz_vs_60hz() {
    let settings = Settings {
        pointing_mode: PointingMode::Absolute,
        pointing_span_deg: 50.0,
        gyro_deadzone: 0.0,
        ema_smoothing: 0.0,
        ..Default::default()
    };
    let turn = Sample {
        gyro: Vec3::new(0.0, -1.0, 0.0),
        ..Default::default()
    };
    let final_x_at_rate = |interval_us: u64, packets: u64| -> f32 {
        let mut ptr = PointerEngine::new();
        let mut last_x = 0.0f32;
        for i in 0..packets {
            if let Some(Action::PointTo { x, .. }) = ptr.update_at(
                &turn,
                PointerMode::Gyro,
                &settings,
                Vec3::default(),
                i * interval_us,
            ) {
                last_x = x;
            }
        }
        last_x
    };
    let x_60hz = final_x_at_rate(16_667, 61);
    let x_30hz = final_x_at_rate(33_333, 31);
    assert!(
        x_60hz > 0.5,
        "expected positive x displacement, got {x_60hz}"
    );
    assert!(
        (x_60hz - x_30hz).abs() / x_60hz.abs() < 0.05,
        "expected 30 Hz ({x_30hz}) and 60 Hz ({x_60hz}) final x to match within ±5%"
    );
}

#[test]
fn entering_gyro_mode_and_recenter_action_reset_aim_to_zero_and_radial_uses_point_to_deltas() {
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.ema_smoothing = 0.0;
    cfg.bindings.insert(
        (Button::Home, Press::Short),
        Binding::once(Action::Recenter),
    );
    cfg.bindings.insert(
        (Button::VolDown, Press::Short),
        Binding::hold(Action::RadialMenu),
    );
    cfg.radial_slots[2] = RadialSlot {
        label: "Paste".to_string(),
        color: "accent".to_string(),
        action: Some(Action::System(SystemAction::Paste)),
    };
    let mut engine = Engine::new(cfg, Platform::Desktop);
    engine.set_gyro_mode(true);

    // Rotate right so aim is non-zero.
    let turn_pkt = RawPacketBuilder {
        y_gyro: -1000,
        ..Default::default()
    }
    .build();
    let out = engine.feed(&turn_pkt, 16_667);
    assert!(matches!(out.as_slice(), [Action::PointTo { x, .. }] if *x > 0.01));
    assert!(engine.pointer_aim().0 > 0.01);

    // 1. Pressing Home (bound to Action::Recenter) resets aim to (0, 0) and emits Action::Recenter.
    let home_down = RawPacketBuilder {
        buttons: 0x02,
        ..Default::default()
    }
    .build();
    let idle = [0u8; 20];
    assert!(engine.feed(&home_down, 33_334).is_empty());
    let recenter_out = engine.feed(&idle, 50_000);
    assert_eq!(recenter_out, vec![Action::Recenter]);
    assert_eq!(engine.pointer_aim(), (0.0, 0.0));

    // Rotate again, then toggle gyro off and back on via App button -> aim resets to (0, 0).
    let _ = engine.feed(&turn_pkt, 66_667);
    assert!(engine.pointer_aim().0 > 0.01);
    engine.set_gyro_mode(false);
    engine.set_gyro_mode(true);
    assert_eq!(engine.pointer_aim(), (0.0, 0.0));

    // 2. Radial menu in absolute gyro mode accumulates PointTo deltas to select slot 2 (East).
    let vol_down_hold = RawPacketBuilder {
        buttons: 0x08,
        ..Default::default()
    }
    .build();
    let vol_down_turn_right = RawPacketBuilder {
        y_gyro: -1500,
        buttons: 0x08,
        ..Default::default()
    }
    .build();
    assert_eq!(
        engine.feed(&vol_down_hold, 100_000),
        vec![Action::RadialMenu]
    );
    for step in 1..=5 {
        let _ = engine.feed(&vol_down_turn_right, 100_000 + step * 16_667);
    }
    let release_out = engine.feed(&idle, 200_000);
    assert_eq!(release_out, vec![Action::System(SystemAction::Paste)]);
}

#[test]
fn config_v2_migration_defaults_new_fields_and_clamps_nan_span() {
    assert_eq!(CONFIG_VERSION, 4);
    assert_eq!(
        Config::for_platform(Platform::Desktop)
            .settings
            .pointing_mode,
        PointingMode::Absolute
    );
    assert!(
        Config::for_platform(Platform::Desktop)
            .settings
            .motion_glide
    );
    assert_eq!(
        Config::for_platform(Platform::Android)
            .settings
            .pointing_mode,
        PointingMode::Relative
    );
    assert_eq!(
        Config::for_platform(Platform::AndroidTv)
            .settings
            .pointing_mode,
        PointingMode::Relative
    );

    // v2 JSON config missing pointing_mode, pointing_span_deg, screen_width_px, and motion_glide loads with defaults.
    let v2_desktop_json = r#"{
        "version": 2,
        "platform": "desktop",
        "settings": {
            "touch_sensitivity": 400.0,
            "ema_smoothing": 0.3
        },
        "bindings": {},
        "radial_slots": []
    }"#;
    let parsed_desktop: Config =
        serde_json::from_str(v2_desktop_json).expect("deserialize v2 desktop config");
    assert_eq!(
        parsed_desktop.settings.pointing_mode,
        PointingMode::Absolute
    );
    assert_eq!(parsed_desktop.settings.pointing_span_deg, 50.0);
    assert_eq!(parsed_desktop.settings.screen_width_px, 1920);
    assert!(parsed_desktop.settings.motion_glide);

    let v2_android_json = r#"{
        "version": 2,
        "platform": "android",
        "settings": {
            "touch_sensitivity": 400.0,
            "ema_smoothing": 0.3
        },
        "bindings": {},
        "radial_slots": []
    }"#;
    let parsed_android: Config =
        serde_json::from_str(v2_android_json).expect("deserialize v2 android config");
    assert_eq!(
        parsed_android.settings.pointing_mode,
        PointingMode::Relative
    );
    assert_eq!(parsed_android.settings.pointing_span_deg, 50.0);

    // NaN and out-of-range pointing_span_deg / screen_width_px are clamped by sanitize().
    let mut cfg = Config::for_platform(Platform::Desktop);
    cfg.settings.pointing_span_deg = f32::NAN;
    cfg.settings.screen_width_px = 100;
    let mut engine = Engine::new(cfg, Platform::Desktop);
    assert_eq!(engine.config().settings.pointing_span_deg, 50.0);
    assert_eq!(engine.config().settings.screen_width_px, 640);

    let mut low = engine.config().clone();
    low.settings.pointing_span_deg = 5.0;
    low.settings.screen_width_px = 99_999;
    engine.set_config(low);
    assert_eq!(engine.config().settings.pointing_span_deg, 15.0);
    assert_eq!(engine.config().settings.screen_width_px, 7680);

    let mut high = engine.config().clone();
    high.settings.pointing_span_deg = 250.0;
    engine.set_config(high);
    assert_eq!(engine.config().settings.pointing_span_deg, 150.0);
}
