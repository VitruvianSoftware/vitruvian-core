# Src

## Overview
Component package providing implementation for `apps/mobile/android-remote/macagent/scripts/src`.

## Interface
- `[lib.rs:LABEL]`
- `[lib.rs:BIN_REL_DIR]`
- `[lib.rs:BIN_NAME]`
- `[lib.rs:BIN_REL_PATH]`
- `[lib.rs:LOG_REL_DIR]`
- `[lib.rs:LOG_REL_PATH]`
- `[lib.rs:PLIST_REL_DIR]`
- `[lib.rs:SIGN_ID]`
- `[lib.rs:BASE_URL]`
- `[lib.rs:HEALTHZ_URL]`
- `[lib.rs:RUNFILES_PKG_SUBDIR]`
- `[lib.rs:InstallerPaths]`
- `[lib.rs:expand_tilde]`
- `[lib.rs:xml_escape]`
- `[lib.rs:format_args_xml]`
- `[lib.rs:render_plist]`
- `[lib.rs:is_executable]`
- `[lib.rs:resolve_src_dir]`
- `[lib.rs:find_agent_binary]`
- `[lib.rs:validate_pair_args]`

## Invariants
- None

## Side Effects
- [lib.rs:39]: `pub const BASE_URL: &str = "http://127.0.0.1:7411";`
- [lib.rs:40]: `pub const HEALTHZ_URL: &str = "http://127.0.0.1:7411/healthz";`
- [lib.rs:397]: `let healthy = Command::new("curl")`

## Verification
- Run: `bazel test //apps/mobile/android-remote/macagent/scripts/src/...`
