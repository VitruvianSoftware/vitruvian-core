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
// SPDX-License-Identifier: MIT

//! Names for the codes a V1 vacuum reports, and the feature flags that decide
//! which names apply to a given model.
//!
//! A port of python-roborock 7.12.1's `data/v1/v1_code_mappings.py` (state
//! and error names), `data/v1/v1_clean_modes.py` (fan speed, water mode and
//! mop route names) and the parts of `device_features.py` those depend on.
//! The state and error tables were generated from the Python enum source.

/// `RoborockStateCode` display names (python-roborock 7.12.1).
pub fn state_name(code: i64) -> Option<&'static str> {
    Some(match code {
        0 => "unknown",
        1 => "starting",
        2 => "charger_disconnected",
        3 => "idle",
        4 => "remote_control_active",
        5 => "cleaning",
        6 => "returning_home",
        7 => "manual_mode",
        8 => "charging",
        9 => "charging_problem",
        10 => "paused",
        11 => "spot_cleaning",
        12 => "error",
        13 => "shutting_down",
        14 => "updating",
        15 => "docking",
        16 => "going_to_target",
        17 => "zoned_cleaning",
        18 => "segment_cleaning",
        22 => "emptying_the_bin",
        23 => "washing_the_mop",
        25 => "washing_the_mop",
        26 => "going_to_wash_the_mop",
        28 => "in_call",
        29 => "mapping",
        30 => "egg_attack",
        32 => "patrol",
        33 => "attaching_the_mop",
        34 => "detaching_the_mop",
        100 => "charging_complete",
        101 => "device_offline",
        103 => "locked",
        202 => "air_drying_stopping",
        6301 => "robot_status_mopping",
        6302 => "clean_mop_cleaning",
        6303 => "clean_mop_mopping",
        6304 => "segment_mopping",
        6305 => "segment_clean_mop_cleaning",
        6306 => "segment_clean_mop_mopping",
        6307 => "zoned_mopping",
        6308 => "zoned_clean_mop_cleaning",
        6309 => "zoned_clean_mop_mopping",
        6310 => "back_to_dock_washing_duster",
        _ => return None,
    })
}

/// `RoborockErrorCode` display names (python-roborock 7.12.1).
pub fn error_name(code: i64) -> Option<&'static str> {
    Some(match code {
        0 => "none",
        1 => "lidar_blocked",
        2 => "bumper_stuck",
        3 => "wheels_suspended",
        4 => "cliff_sensor_error",
        5 => "main_brush_jammed",
        6 => "side_brush_jammed",
        7 => "wheels_jammed",
        8 => "robot_trapped",
        9 => "no_dustbin",
        10 => "strainer_error",
        11 => "compass_error",
        12 => "low_battery",
        13 => "charging_error",
        14 => "battery_error",
        15 => "wall_sensor_dirty",
        16 => "robot_tilted",
        17 => "side_brush_error",
        18 => "fan_error",
        19 => "dock",
        20 => "optical_flow_sensor_dirt",
        21 => "vertical_bumper_pressed",
        22 => "dock_locator_error",
        23 => "return_to_dock_fail",
        24 => "nogo_zone_detected",
        25 => "visual_sensor",
        26 => "light_touch",
        27 => "vibrarise_jammed",
        28 => "robot_on_carpet",
        29 => "filter_blocked",
        30 => "invisible_wall_detected",
        31 => "cannot_cross_carpet",
        32 => "internal_error",
        34 => "collect_dust_error_3",
        35 => "collect_dust_error_4",
        36 => "mopping_roller_1",
        37 => "mopping_roller_error_2",
        38 => "clear_water_box_hoare",
        39 => "dirty_water_box_hoare",
        40 => "sink_strainer_hoare",
        41 => "clear_water_box_exception",
        42 => "clear_brush_exception",
        43 => "clear_brush_exception_2",
        44 => "filter_screen_exception",
        45 => "mopping_roller_1",
        48 => "up_water_exception",
        49 => "drain_water_exception",
        51 => "temperature_protection",
        52 => "clean_carousel_exception",
        53 => "clean_carousel_water_full",
        54 => "water_carriage_drop",
        55 => "check_clean_carouse",
        56 => "audio_error",
        _ => return None,
    })
}

/// `RoborockProductNickname`: the model family, from the last part of the
/// model id (`roborock.vacuum.a15` -> `a15` -> TanosS). Unknown models are
/// treated as PearlPlus, as python-roborock does.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Nickname {
    Coral,
    CoralPro,
    Pearl,
    PearlC,
    PearlE,
    PearlELite,
    PearlPlus,
    PearlPlusS,
    PearlS,
    PearlSLite,
    RubyPlus,
    RubySC,
    RubySE,
    RubySLite,
    Tanos,
    TanosE,
    TanosS,
    TanosSC,
    TanosSE,
    TanosSMax,
    TanosSLite,
    TanosSPlus,
    TanosV,
    TopazS,
    TopazSC,
    TopazSPlus,
    TopazSPower,
    TopazSV,
    Ultron,
    UltronE,
    UltronLite,
    UltronSC,
    UltronSE,
    UltronSPlus,
    UltronSV,
    Verdelite,
    Vivian,
    VivianC,
}

pub fn nickname(model: &str) -> Nickname {
    use Nickname::*;
    let short = model.rsplit('.').next().unwrap_or(model);
    match short {
        "a20" | "a21" => Coral,
        "a143" | "a144" => CoralPro,
        "a74" | "a75" => Pearl,
        "a103" | "a104" => PearlC,
        "a167" | "a168" => PearlE,
        "a169" | "a170" => PearlELite,
        "a86" | "a87" => PearlPlus,
        "a116" | "a117" | "a136" => PearlPlusS,
        "a100" | "a101" => PearlS,
        "a122" | "a123" => PearlSLite,
        "t4" | "s4" => RubyPlus,
        "p5" | "a08" => RubySC,
        "a19" => RubySE,
        "p6" | "s5e" | "a05" => RubySLite,
        "t6" | "s6" => Tanos,
        "t7" | "a11" => TanosE,
        "a14" | "a15" => TanosS,
        "a39" | "a40" => TanosSC,
        "a33" | "a34" => TanosSE,
        "a52" => TanosSMax,
        "a37" | "a38" => TanosSLite,
        "a23" | "a24" => TanosSPlus,
        "t7p" | "a09" | "a10" => TanosV,
        "a29" | "a30" | "a76" => TopazS,
        "a64" | "a65" => TopazSC,
        "a46" | "a47" | "a66" => TopazSPlus,
        "a62" => TopazSPower,
        "a26" | "a27" => TopazSV,
        "a50" | "a51" => Ultron,
        "a72" | "a84" => UltronE,
        "a73" | "a85" => UltronLite,
        "a94" | "a95" => UltronSC,
        "a124" | "a125" | "a139" | "a140" => UltronSE,
        "a68" | "a69" | "a70" => UltronSPlus,
        "a96" | "a97" => UltronSV,
        "a146" | "a147" => Verdelite,
        "a134" | "a135" | "a155" | "a156" => Vivian,
        "a158" | "a159" => VivianC,
        _ => PearlPlus,
    }
}

/// The product-level features (`PRODUCT_FEATURE_MAP`) the mode names need.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ProductFeatures {
    pub max_plus: bool,
    pub pure_clean_mop: bool,
    pub none_pure_clean_mop_with_max_plus: bool,
    pub mop_shake_module: bool,
    pub mop_spin_module: bool,
}

pub fn product_features(nick: Nickname) -> ProductFeatures {
    use Nickname::*;
    // The base lists: PEARL_FEATURES = maxplus + spin; PEARL_PLUS_FEATURES =
    // NEW_DEFAULT (maxplus) + spin; ULTRON/ULTRONSV = NEW_DEFAULT + shake;
    // TANOSS = shake; TOPAZSPOWER = maxplus + shake. Camera and remote-view
    // features are irrelevant here and left out.
    let (max_plus, none_pure_with_max_plus, shake, spin) = match nick {
        Pearl | PearlS | PearlC | PearlSLite | PearlE | PearlELite => (true, false, false, true),
        PearlPlus | Vivian | Coral | PearlPlusS | CoralPro => (true, false, false, true),
        Ultron | UltronSC | UltronSPlus | UltronSV | Verdelite => (true, false, true, false),
        UltronE | UltronSE | UltronLite => (false, true, false, false),
        TopazSPower | TopazSC => (true, false, true, false),
        TanosS | TanosSPlus => (false, false, true, false),
        VivianC => (true, false, false, true),
        TopazS => (false, false, true, false),
        TopazSPlus | TopazSV | TanosSMax => (true, false, true, false),
        TanosSLite | TanosSC | TanosSE | Tanos | TanosE | TanosV => (false, false, false, false),
        RubyPlus | RubySC | RubySE | RubySLite => (false, false, false, false),
    };
    // PRODUCTS_WITHOUT_PURE_CLEAN_MOP; every other product gets the feature.
    let pure_clean_mop = !matches!(
        nick,
        Tanos
            | TanosE
            | TanosV
            | TanosSLite
            | TanosSE
            | TanosSC
            | UltronLite
            | UltronE
            | RubyPlus
            | RubySLite
            | RubySC
            | RubySE
    );
    ProductFeatures {
        max_plus,
        pure_clean_mop,
        none_pure_clean_mop_with_max_plus: none_pure_with_max_plus,
        mop_shake_module: shake,
        mop_spin_module: spin,
    }
}

/// The subset of `DeviceFeatures` the status names depend on.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Features {
    pub max_plus_mode: bool,
    pub none_pure_clean_mop_with_max_plus: bool,
    pub pure_clean_mop: bool,
    pub smart_clean_mode_set: bool,
    pub customized_clean: bool,
    pub clean_route_setting: bool,
    pub clean_efficiency: bool,
    pub careful_slow_mop: bool,
    pub corner_clean_mode: bool,
    pub clean_route_deep_slow_plus: bool,
    pub clean_route_fast_mode: bool,
    pub water_slide_mode: bool,
    pub mop_shake_module: bool,
    pub custom_water_box_distance: bool,
    pub mop_shake_water_max: bool,
}

/// Bit `bit` of the hex feature string, counted from its last character.
fn str_bit(feature_str: &str, bit: u32) -> bool {
    let idx_from_end = 1 + (bit / 4) as usize;
    if idx_from_end > feature_str.len() {
        return false;
    }
    let ch = feature_str.as_bytes()[feature_str.len() - idx_from_end] as char;
    ch.to_digit(16)
        .map(|nibble| (nibble >> (bit % 4)) & 1 == 1)
        .unwrap_or(false)
}

/// `mask` against the integer in the last `chars` hex digits.
fn str_mask(feature_str: &str, mask: u64, chars: usize) -> bool {
    if feature_str.len() < chars {
        return false;
    }
    u64::from_str_radix(&feature_str[feature_str.len() - chars..], 16)
        .map(|v| v & mask != 0)
        .unwrap_or(false)
}

impl Features {
    /// `DeviceFeatures.from_feature_flags` for the fields this crate uses.
    pub fn from_flags(new_feature_info: u64, new_feature_info_str: &str, model: &str) -> Self {
        let product = product_features(nickname(model));
        let shake_mop_set = new_feature_info & 262_144 != 0;
        let roller_mop = str_bit(new_feature_info_str, 128);
        Self {
            max_plus_mode: product.max_plus,
            none_pure_clean_mop_with_max_plus: product.none_pure_clean_mop_with_max_plus,
            pure_clean_mop: product.pure_clean_mop,
            smart_clean_mode_set: str_bit(new_feature_info_str, 55),
            customized_clean: product.mop_shake_module || product.mop_spin_module,
            clean_route_setting: product.mop_shake_module
                || product.mop_spin_module
                || shake_mop_set
                || roller_mop,
            clean_efficiency: str_bit(new_feature_info_str, 108),
            careful_slow_mop: new_feature_info != 0 && ((new_feature_info >> 32) >> 9) & 1 == 1,
            corner_clean_mode: str_mask(new_feature_info_str, 2_147_483_648, 8),
            clean_route_deep_slow_plus: str_mask(new_feature_info_str, 16_777_216, 8),
            clean_route_fast_mode: str_mask(new_feature_info_str, 256, 8),
            water_slide_mode: str_bit(new_feature_info_str, 106),
            mop_shake_module: product.mop_shake_module,
            custom_water_box_distance: new_feature_info & 2_147_483_648 != 0,
            mop_shake_water_max: str_bit(new_feature_info_str, 45),
        }
    }

    /// The features from an `app_get_init_status` reply (`[{...}]`).
    pub fn from_init_status(reply: &serde_json::Value, model: &str) -> Option<Self> {
        let status = reply.as_array()?.first()?.as_object()?;
        let info = status
            .get("new_feature_info")
            .and_then(serde_json::Value::as_u64)
            .unwrap_or(0);
        let info_str = status
            .get("new_feature_info_str")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("");
        Some(Self::from_flags(info, info_str, model))
    }

    /// `get_clean_modes` as a code -> name map (the fan speed names).
    pub fn fan_speed_name(&self, code: i64) -> Option<&'static str> {
        let mut modes: Vec<(i64, &'static str)> = vec![
            (101, "quiet"),
            (102, "balanced"),
            (103, "turbo"),
            (104, "max"),
        ];
        if self.max_plus_mode || self.none_pure_clean_mop_with_max_plus {
            modes.push((108, "max_plus"));
        }
        modes.push((105, if self.pure_clean_mop { "off" } else { "gentle" }));
        if self.smart_clean_mode_set {
            modes.push((110, "smart_mode"));
        }
        if self.customized_clean {
            modes.push((106, "custom"));
        }
        modes.into_iter().find(|(c, _)| *c == code).map(|(_, n)| n)
    }

    /// `get_water_modes` / `get_water_slide_mode_name` (the water flow names).
    pub fn water_mode_name(&self, code: i64) -> Option<&'static str> {
        if self.water_slide_mode {
            if code == 200 {
                return Some("off");
            }
            let position = code - 220;
            if position < 1 {
                return None;
            }
            const RANGES: [(i64, &str); 7] = [
                (3, "slight"),
                (7, "low"),
                (12, "gentle"),
                (17, "medium"),
                (22, "moderate"),
                (27, "high"),
                (30, "extreme"),
            ];
            return RANGES
                .iter()
                .find(|(last, _)| position <= *last)
                .map(|(_, n)| *n);
        }
        let mut modes: Vec<(i64, &'static str)> = vec![(200, "off")];
        if self.mop_shake_module {
            modes.extend([(201, "mild"), (202, "standard"), (203, "intense")]);
        } else {
            modes.extend([(201, "low"), (202, "medium"), (203, "high")]);
        }
        if self.custom_water_box_distance {
            modes.push((207, "custom_water_flow"));
        }
        if self.mop_shake_module && self.mop_shake_water_max {
            modes.push((208, "extreme"));
        }
        if self.smart_clean_mode_set {
            modes.push((209, "smart_mode"));
        }
        if self.customized_clean {
            modes.push((204, "custom"));
        }
        modes.into_iter().find(|(c, _)| *c == code).map(|(_, n)| n)
    }

    /// `get_clean_routes` (the mop route names). `region` is the account's.
    pub fn mop_route_name(&self, code: i64, region: &str) -> Option<&'static str> {
        if !self.clean_route_setting {
            return None;
        }
        let routes: Vec<(i64, &'static str)> = if self.none_pure_clean_mop_with_max_plus {
            vec![(304, "fast"), (300, "standard")]
        } else {
            let mut r = vec![(300, "standard")];
            if !self.clean_efficiency {
                r.push((301, "deep"));
            }
            if self.careful_slow_mop {
                if !self.corner_clean_mode && self.clean_route_deep_slow_plus && region == "cn" {
                    // DEEP_PLUS_CN's display name is "deep_plus".
                    r.push((305, "deep_plus"));
                } else {
                    r.push((303, "deep_plus"));
                }
            }
            if self.clean_route_fast_mode {
                r.push((304, "fast"));
            }
            if self.smart_clean_mode_set {
                r.push((306, "smart_mode"));
            }
            if self.customized_clean {
                r.push((302, "custom"));
            }
            r
        };
        routes.into_iter().find(|(c, _)| *c == code).map(|(_, n)| n)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_and_error_names_follow_python_roborock() {
        assert_eq!(state_name(8), Some("charging"));
        assert_eq!(state_name(25), Some("washing_the_mop"));
        assert_eq!(state_name(6304), Some("segment_mopping"));
        assert_eq!(state_name(19), None);
        assert_eq!(error_name(45), Some("mopping_roller_1"));
        assert_eq!(error_name(2), Some("bumper_stuck"));
    }

    #[test]
    fn unknown_models_default_to_pearl_plus() {
        assert_eq!(nickname("roborock.vacuum.a15"), Nickname::TanosS);
        assert_eq!(nickname("roborock.vacuum.zzz"), Nickname::PearlPlus);
    }

    #[test]
    fn feature_string_bits_count_from_the_end() {
        // Bit 55 lives in character 14 from the end (1 + 55/4), bit 3 of it.
        let mut s = vec!['0'; 32];
        let n = s.len();
        s[n - 14] = '8';
        let s: String = s.into_iter().collect();
        assert!(str_bit(&s, 55));
        assert!(!str_bit(&s, 54));
        assert!(!str_bit("", 55));
        assert!(str_mask("00000100", 256, 8));
    }

    #[test]
    fn fan_speed_names_depend_on_the_model() {
        // S7 (a15, TanosS): mop shake module, no max+, pure clean mop.
        let s7 = Features::from_flags(0, "", "roborock.vacuum.a15");
        assert_eq!(s7.fan_speed_name(105), Some("off"));
        assert_eq!(s7.fan_speed_name(108), None);
        assert_eq!(s7.fan_speed_name(106), Some("custom"));
        // S6 (Tanos): no pure clean mop, so 105 is "gentle".
        let s6 = Features::from_flags(0, "", "roborock.vacuum.s6");
        assert_eq!(s6.fan_speed_name(105), Some("gentle"));
        assert_eq!(s6.fan_speed_name(106), None);
    }

    #[test]
    fn water_and_route_names_depend_on_the_model() {
        let s7 = Features::from_flags(0, "", "roborock.vacuum.a15");
        assert_eq!(s7.water_mode_name(202), Some("standard"));
        assert_eq!(s7.mop_route_name(301, "us"), Some("deep"));
        let s6 = Features::from_flags(0, "", "roborock.vacuum.s6");
        assert_eq!(s6.water_mode_name(202), Some("medium"));
        assert_eq!(s6.mop_route_name(300, "us"), None);
        let mut slide = s7;
        slide.water_slide_mode = true;
        assert_eq!(slide.water_mode_name(235), Some("medium"));
        assert_eq!(slide.water_mode_name(219), None);
    }
}
