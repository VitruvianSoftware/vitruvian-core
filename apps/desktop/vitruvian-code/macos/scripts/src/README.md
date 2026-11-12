# Src

## Overview
Component package providing implementation for `apps/desktop/vitruvian-code/macos/scripts/src`.

## Interface
- `[bazel_app_holds_mermaid.rs:run]`
- `[bundle.rs:run]`
- `[check_packaged_app.rs:extract_sha256_from_notices]`
- `[check_packaged_app.rs:find_mermaid]`
- `[check_packaged_app.rs:run]`
- `[lib.rs:sha256_hex]`
- `[lib.rs:sha256_hex_file]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [lib.rs:198]: `assert!(status.success(), "zip failed");`
- [lib.rs:339]: `assert!(app.join("Contents/MacOS/VitruvianCode").exists());`
- [lib.rs:340]: `assert!(app.join("Contents/Resources").exists());`

## Side Effects
- [bundle.rs:135]: `<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DT...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-code/macos/scripts/src/...`
