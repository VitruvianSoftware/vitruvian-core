# Src

## Overview
Component package providing implementation for `tools/desktop-package/src`.

## Interface
- `[driver.rs:SYNC_DOWNLOADS_ENV]`
- `[driver.rs:SYNC_ATTEMPTS]`
- `[driver.rs:sync_backoff]`
- `[driver.rs:sync_with_retries]`
- `[driver.rs:USAGE]`
- `[driver.rs:Opts]`
- `[driver.rs:Parsed]`
- `[driver.rs:parse]`
- `[driver.rs:Driver]`
- `[driver.rs:main_with]`
- `[driver.rs:program_path]`
- `[helpers.rs:clean_version]`
- `[helpers.rs:cask_name_for_app]`
- `[helpers.rs:generate_cask_ruby]`
- `[helpers.rs:expected_artifact_names]`
- `[helpers.rs:required_release_assets]`
- `[helpers.rs:missing_assets]`
- `[helpers.rs:developer_id_from]`
- `[helpers.rs:basename]`
- `[helpers.rs:dirname]`

## Invariants
- [driver.rs:134]: `--require-asset <name>  Also require <name> (and <name>.sha256) among the art...`
- [driver.rs:189]: `"--require-asset" => 560,`
- [helpers.rs:166]: `/// the extra names promised with --require-asset.`
- [helpers.rs:332]: `assert!(got.starts_with("cask \"t\" do\n  version \"1.0.0\"\n  sha256 \"sha\"...`
- [helpers.rs:333]: `assert!(got.contains("  desc \"macOS desktop application\"\n"));`
- [shell.rs:331]: `assert!(d.rsplit('/').next().unwrap().starts_with("tmp."), "{d}");`

## Side Effects
- [driver.rs:365]: `&mut cmd_quiet("find", &[bundle, "-exec", "xattr", "-c", "{}", "+"]),`
- [helpers.rs:81]: `/// HomeSpeaker -> home-speaker, HTTPServer -> http-server.`
- [helpers.rs:319]: `("HTTPServer", "http-server"),`

## Verification
- Run: `bazel test //tools/desktop-package/src/...`
