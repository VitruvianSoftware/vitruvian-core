# Mac Stats Daemon

## Overview
Component package providing implementation for `apps/embedded/esp32-s3/host_companion/src/mac_stats_daemon`.

## Interface
- `[lib.rs:MDNS_HOSTNAME]`
- `[lib.rs:NET_TELEMETRY_PORT]`
- `[lib.rs:WIFI_LIVENESS_TIMEOUT_S]`
- `[lib.rs:get_cpu_usage]`
- `[lib.rs:parse_top_cpu]`
- `[lib.rs:get_ram_usage]`
- `[lib.rs:parse_vm_stat]`
- `[lib.rs:get_battery_status]`
- `[lib.rs:parse_pmset]`
- `[lib.rs:get_network_ip]`
- `[lib.rs:get_media_status]`
- `[lib.rs:collect_all_stats]`
- `[lib.rs:find_esp32_serial_port]`
- `[lib.rs:send_over_serial]`
- `[lib.rs:send_over_http]`
- `[lib.rs:parse_networksetup_ssid]`
- `[lib.rs:parse_ipconfig_ssid]`
- `[lib.rs:get_active_wifi_ssid]`
- `[lib.rs:get_wifi_password]`
- `[lib.rs:build_wifi_set_payload]`

## Invariants
- None

## Side Effects
- [main.rs:64]: `"http" => {`
- [main.rs:103]: `"http" => {`

## Verification
- Run: `bazel test //apps/embedded/esp32-s3/host_companion/src/mac_stats_daemon/...`
