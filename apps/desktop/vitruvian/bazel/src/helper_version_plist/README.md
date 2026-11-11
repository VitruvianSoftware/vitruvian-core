# Helper Version Plist

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/helper_version_plist`.

## Interface
- `[lib.rs:Config]`
- `[lib.rs:parse_args]`
- `[lib.rs:sha256_hex]`
- `[lib.rs:compute_helper_version_from_bytes]`
- `[lib.rs:compute_helper_version]`
- `[lib.rs:render_version_plist]`
- `[lib.rs:run]`
- `[lib.rs:run_cli]`

## Invariants
- [lib.rs:208]: `assert!(xml.contains("<key>VitruvianFanControlHelperVersion</key>"));`
- [lib.rs:209]: `assert!(xml.contains(&format!("<string>{}</string>", v)));`

## Side Effects
- [lib.rs:147]: `<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/helper_version_plist/...`
