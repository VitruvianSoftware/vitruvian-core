# Src

## Overview
Component package providing implementation for `tools/ops/macos-power-agent/src`.

## Interface
- `[lib.rs:PowerMetrics]`
- `[lib.rs:BatteryMetrics]`
- `[lib.rs:which_or_default]`
- `[lib.rs:short_hostname_lower]`
- `[lib.rs:unix_timestamp_secs]`
- `[lib.rs:parse_conf_str]`
- `[lib.rs:mw_to_watts_str]`
- `[lib.rs:parse_domain_mw]`
- `[lib.rs:parse_powermetrics]`
- `[lib.rs:parse_pmset]`
- `[lib.rs:parse_ioreg]`
- `[lib.rs:assemble_metrics]`
- `[lib.rs:run_power_agent]`
- `[lib.rs:run_install]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- None

## Side Effects
- [lib.rs:479]: `env_nonempty("CURL_BIN").unwrap_or_else(|| which_or_default("curl", "/usr/bin...`

## Verification
- Run: `bazel test //tools/ops/macos-power-agent/src/...`
