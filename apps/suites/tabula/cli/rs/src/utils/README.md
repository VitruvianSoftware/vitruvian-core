# Utils

## Overview
Component package providing implementation for `apps/suites/tabula/cli/rs/src/utils`.

## Interface
- `[config.rs:VALID_CONFIG_KEYS]`
- `[config.rs:EnvironmentConfig]`
- `[config.rs:Config]`
- `[config.rs:config_file_path]`
- `[config.rs:get_config]`
- `[config.rs:get_config_from]`
- `[config.rs:save_config]`
- `[config.rs:save_config_to]`
- `[config.rs:escape_shell_arg]`
- `[config.rs:json_quote]`
- `[config.rs:unquote_json_string]`
- `[config.rs:parse_top_level_json_object]`
- `[extension.rs:DEV_LATEST_TAG]`
- `[extension.rs:DEFAULT_REPO]`
- `[extension.rs:STABLE_CHANNEL_MESSAGE]`
- `[extension.rs:EXTENSION_RELEASE_TAG_PREFIX]`
- `[extension.rs:default_extension_dir]`
- `[extension.rs:BundleInfo]`
- `[extension.rs:read_bundle_info]`
- `[extension.rs:validate_bundle_dir]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/suites/tabula/cli/rs/src/utils/...`
