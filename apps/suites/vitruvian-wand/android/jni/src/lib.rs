// Copyright (c) 2026 VitruvianSoftware

//! JNI entrypoint crate (`libvitruvian_wand_jni.so`) bridging `com.vitruviansoftware.wand.core.WandNative`
//! to the pure Rust [`bridge::Bridge`] over [`vitruvian_wand_core::Engine`].

pub mod bridge;

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::Once;

use jni::EnvUnowned;
use jni::errors::LogErrorAndDefault;
use jni::objects::{JByteArray, JClass, JString, Reference as _};
use jni::sys::{JNI_FALSE, JNI_TRUE, jboolean, jbyte, jint, jlong};

use crate::bridge::{
    Bridge, catch_to_json, create_handle, destroy_handle, error_json, with_bridge,
};

static LOGGER_INIT: Once = Once::new();

fn init_logger() {
    LOGGER_INIT.call_once(|| {
        #[cfg(target_os = "android")]
        {
            android_logger::init_once(
                android_logger::Config::default()
                    .with_max_level(log::LevelFilter::Debug)
                    .with_tag("VitruvianWandNative"),
            );
        }
    });
}

/// Creates a new [`Bridge`] handle (`Box<Mutex<Option<Bridge>>>`) for the given platform
/// (`1` = Android, `2` = AndroidTv) and JSON config string. Returns `0` on error.
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeCreate<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    platform: jint,
    config_json: JString<'local>,
) -> jlong {
    init_logger();
    unowned_env
        .with_env(|env| -> jni::errors::Result<jlong> {
            let result = catch_unwind(AssertUnwindSafe(|| -> Result<jlong, String> {
                let cfg_str = if config_json.is_null() {
                    String::new()
                } else {
                    config_json
                        .try_to_string(env)
                        .map_err(|e| format!("failed to read config_json JString: {e}"))?
                };
                create_handle(platform, &cfg_str)
            }));
            match result {
                Ok(Ok(handle)) => Ok(handle),
                Ok(Err(err)) => {
                    log::error!("nativeCreate error: {err}");
                    Ok(0)
                }
                Err(payload) => {
                    log::error!(
                        "nativeCreate panic: {}",
                        bridge::panic_payload_message(payload.as_ref())
                    );
                    Ok(0)
                }
            }
        })
        .resolve::<LogErrorAndDefault>()
}

/// Destroys a [`Bridge`] handle previously created by `nativeCreate` by taking the inner
/// `Option<Bridge>` out of its `Mutex<Option<Bridge>>` slot so stray post-destroy calls
/// return an error JSON instead of touching freed memory.
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeDestroy<
    'local,
>(
    _unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        destroy_handle(handle);
    }));
}

/// Returns the default `vitruvian_wand_core::Config` JSON for `platform` (`1` = Android, `2` = AndroidTv).
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeDefaultConfig<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    platform: jint,
) -> JString<'local> {
    init_logger();
    unowned_env
        .with_env(|env| -> jni::errors::Result<JString<'local>> {
            let json = catch_to_json(|| Bridge::default_config(platform));
            JString::from_str(env, &json)
        })
        .resolve::<LogErrorAndDefault>()
}

/// Feeds a 20-byte BLE packet and microsecond timestamp into the engine, returning
/// a JSON array of `Action`s (or `{"error": "..."}` on failure).
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeFeed<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
    packet: JByteArray<'local>,
    t_us: jlong,
) -> JString<'local> {
    unowned_env
        .with_env(|env| -> jni::errors::Result<JString<'local>> {
            let json = catch_to_json(|| {
                if packet.is_null() {
                    return Err("packet byte array is null".to_string());
                }
                let len = packet
                    .len(env)
                    .map_err(|e| format!("failed to read packet length: {e}"))?;
                let mut signed_buf = vec![0 as jbyte; len];
                packet
                    .get_region(env, 0, &mut signed_buf)
                    .map_err(|e| format!("failed to copy packet bytes: {e}"))?;
                let bytes: Vec<u8> = signed_buf.into_iter().map(|b| b as u8).collect();
                unsafe { with_bridge(handle, |b| b.feed(&bytes, t_us.max(0) as u64)) }
            });
            JString::from_str(env, &json)
        })
        .resolve::<LogErrorAndDefault>()
}

/// Advances button long-press and double-press timers at `t_us` without a packet, returning
/// a JSON array of `Action`s (or `{"error": "..."}` on failure).
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeTick<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
    t_us: jlong,
) -> JString<'local> {
    unowned_env
        .with_env(|env| -> jni::errors::Result<JString<'local>> {
            let json =
                catch_to_json(|| unsafe { with_bridge(handle, |b| b.tick(t_us.max(0) as u64)) });
            JString::from_str(env, &json)
        })
        .resolve::<LogErrorAndDefault>()
}

/// Releases all held/toggled bindings and resets button/pointer state, returning
/// a JSON array of release `Action`s (such as `MouseUp`).
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeReleaseAll<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
) -> JString<'local> {
    unowned_env
        .with_env(|env| -> jni::errors::Result<JString<'local>> {
            let json = catch_to_json(|| unsafe { with_bridge(handle, |b| b.release_all()) });
            JString::from_str(env, &json)
        })
        .resolve::<LogErrorAndDefault>()
}

/// Replaces the active engine configuration from a JSON string. Returns `{"ok":true}`
/// or `{"error":"..."}`.
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeSetConfig<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
    config_json: JString<'local>,
) -> JString<'local> {
    unowned_env
        .with_env(|env| -> jni::errors::Result<JString<'local>> {
            let json = catch_to_json(|| {
                if config_json.is_null() {
                    return Err("config_json is null".to_string());
                }
                let cfg_str = config_json
                    .try_to_string(env)
                    .map_err(|e| format!("failed to read config_json: {e}"))?;
                unsafe {
                    with_bridge(handle, |b| {
                        b.set_config(&cfg_str)?;
                        Ok("{\"ok\":true}".to_string())
                    })
                }
            });
            JString::from_str(env, &json)
        })
        .resolve::<LogErrorAndDefault>()
}

/// Returns the current engine configuration as a JSON string (or `{"error":"..."}`).
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeGetConfig<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
) -> JString<'local> {
    unowned_env
        .with_env(|env| -> jni::errors::Result<JString<'local>> {
            let json = catch_to_json(|| unsafe { with_bridge(handle, |b| b.get_config()) });
            JString::from_str(env, &json)
        })
        .resolve::<LogErrorAndDefault>()
}

/// Enables or disables test mode on the engine.
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeSetTestMode<
    'local,
>(
    _unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
    enabled: jboolean,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let _ = with_bridge(handle, |b| {
            b.set_test_mode(enabled != JNI_FALSE);
            Ok(())
        });
    }));
}

/// Requests gyro/orientation recentering on the next packet.
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeRecalibrate<
    'local,
>(
    _unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let _ = with_bridge(handle, |b| {
            b.recalibrate();
            Ok(())
        });
    }));
}

/// Returns the most recently decoded `Sample` as JSON (or `"null"` / `{"error":"..."}`).
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeLastSample<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    handle: jlong,
) -> JString<'local> {
    unowned_env
        .with_env(|env| -> jni::errors::Result<JString<'local>> {
            let json = catch_to_json(|| unsafe { with_bridge(handle, |b| b.last_sample()) });
            let out = if json.is_empty() {
                error_json("empty sample response")
            } else {
                json
            };
            JString::from_str(env, &out)
        })
        .resolve::<LogErrorAndDefault>()
}

/// Returns `JNI_TRUE` when `level` (%) is below the low-battery threshold (< 15%).
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_vitruviansoftware_vitruvian_wand_core_WandNative_nativeBatteryLow<
    'local,
>(
    _unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    level: jint,
) -> jboolean {
    match catch_unwind(AssertUnwindSafe(|| Bridge::battery_low(level))) {
        Ok(true) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}
