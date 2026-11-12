# Uninstall

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/uninstall`.

## Interface
- `[lib.rs:DEFAULT_BUNDLE_ID]`
- `[lib.rs:DEFAULT_APP_PATH]`
- `[lib.rs:CLOSED_LID_RULE_PATHS]`
- `[lib.rs:UninstallConfig]`
- `[lib.rs:PostUninstallWarnings]`
- `[lib.rs:parse_cli_args]`
- `[lib.rs:user_state_paths]`
- `[lib.rs:remove_user_state]`
- `[lib.rs:find_closed_lid_rules]`
- `[lib.rs:parse_sleep_disabled]`
- `[lib.rs:evaluate_sleep_warning]`
- `[lib.rs:PlistValue]`
- `[lib.rs:is_valid_plist_xml]`
- `[lib.rs:lookup_plist_key]`
- `[lib.rs:spaces_recovery_value]`
- `[lib.rs:spaces_leftover]`
- `[lib.rs:run_cli]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/uninstall/...`
