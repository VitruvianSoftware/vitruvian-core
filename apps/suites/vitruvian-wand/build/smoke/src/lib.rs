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

//! Build-foundation smoke crate for Vitruvian Wand. Imports every crate in `@vitruvian_wand_crates`
//! applicable to the active target OS across macOS, Linux, and Android.

use futures::future::ready;
use log::Level;
use serde::{Deserialize, Serialize};
use tokio::sync::Notify;
use uuid::Uuid;

#[cfg(any(target_os = "macos", target_os = "linux"))]
use btleplug::api::CentralState;
#[cfg(any(target_os = "macos", target_os = "linux"))]
use eframe::egui as eframe_egui;
#[cfg(any(target_os = "macos", target_os = "linux"))]
use egui::Pos2;
#[cfg(any(target_os = "macos", target_os = "linux"))]
use tray_icon::TrayIconAttributes;

#[cfg(target_os = "macos")]
use core_foundation::base::TCFType;
#[cfg(target_os = "macos")]
use core_foundation::string::CFString;
#[cfg(target_os = "macos")]
use core_graphics::geometry::CGPoint;

#[cfg(target_os = "linux")]
use dbus::strings::BusName;
#[cfg(target_os = "linux")]
use evdev::KeyCode;

#[cfg(target_os = "android")]
use android_logger::Config as AndroidLogConfig;
#[cfg(target_os = "android")]
use jni::sys::jint;

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct SmokePayload {
    pub id: String,
    pub level: String,
}

pub fn smoke_check() -> SmokePayload {
    let _notify = Notify::new();
    let _fut = ready(42u32);
    let id = Uuid::nil().to_string();
    let payload = SmokePayload {
        id,
        level: Level::Info.as_str().to_owned(),
    };
    let json = serde_json::to_string(&payload).expect("serialize json");
    let roundtrip: SmokePayload = serde_json::from_str(&json).expect("deserialize json");
    let toml_str = toml::to_string(&roundtrip).expect("serialize toml");
    let from_toml: SmokePayload = toml::from_str(&toml_str).expect("deserialize toml");

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    {
        let _state = CentralState::Unknown;
        let _pos = Pos2::new(1.0, 2.0);
        let _color = eframe_egui::Color32::WHITE;
        let _attrs = TrayIconAttributes::default();
    }

    #[cfg(target_os = "macos")]
    {
        let s = CFString::new("vitruvian-wand");
        let _type_id = s.as_CFTypeRef();
        let _pt = CGPoint::new(0.0, 0.0);
    }

    #[cfg(target_os = "linux")]
    {
        let _bus = BusName::new("org.freedesktop.DBus").expect("valid bus name");
        let _key = KeyCode::KEY_LEFTMETA;
    }

    #[cfg(target_os = "android")]
    {
        let _cfg = AndroidLogConfig::default();
        let _ver: jint = jni::sys::JNI_VERSION_1_6;
    }

    from_toml
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_wand_WandBridge_smoke() -> jni::sys::jint {
    let payload = smoke_check();
    payload.id.len() as jni::sys::jint
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smoke_check_roundtrips_payload() {
        let payload = smoke_check();
        assert_eq!(payload.id, "00000000-0000-0000-0000-000000000000");
        assert_eq!(payload.level, "INFO");
    }
}
