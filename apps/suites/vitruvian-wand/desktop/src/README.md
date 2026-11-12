# Src

## Overview
Component package providing implementation for `apps/suites/vitruvian-wand/desktop/src`.

## Interface
- `[ble.rs:BATTERY_POLL_INTERVAL]`
- `[ble.rs:INITIAL_BACKOFF]`
- `[ble.rs:MAX_BACKOFF]`
- `[ble.rs:BleCommand]`
- `[ble.rs:matches_daydream_peripheral]`
- `[ble.rs:next_backoff]`
- `[ble.rs:probe_bluetooth_adapter]`
- `[ble.rs:spawn_ble_thread]`
- `[cli.rs:CliCommand]`
- `[cli.rs:parse_cli_args]`
- `[cli.rs:run_doctor]`
- `[cli.rs:run_replay]`
- `[cli.rs:run_record]`
- `[config.rs:MAX_CONFIG_BACKUPS]`
- `[config.rs:SAVE_DEBOUNCE]`
- `[config.rs:EXTRA_KEY_THEME]`
- `[config.rs:EXTRA_KEY_GYRO_TOUCHPAD_SCROLL]`
- `[config.rs:ThemePreference]`
- `[config.rs:get_theme]`
- `[config.rs:set_theme]`

## Invariants
- None

## Side Effects
- [ble.rs:145]: `.spawn(move || {`
- [ble.rs:153]: `.expect("failed to spawn vitruvian-wand-ble thread");`
- [ble.rs:320]: `.map_err(|e| format!("BLE peripheral query failed: {e}"))?;`
- [cli.rs:228]: `.map_err(|e| format!("Failed to query peripherals: {e}"))?;`
- [input.rs:403]: `.spawn(move || {`
- [input.rs:435]: `.expect("failed to spawn vitruvian-wand-input thread");`
- [launch.rs:76]: `.spawn()`

## Verification
- Run: `bazel test //apps/suites/vitruvian-wand/desktop/src/...`
