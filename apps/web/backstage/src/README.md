# Src

## Overview
Component package providing implementation for `apps/web/backstage/src`.

## Interface
- `[lib.rs:BumpReleaseOptions]`
- `[lib.rs:ReleaseManifestSnapshot]`
- `[lib.rs:parse_args]`
- `[lib.rs:manifest_url]`
- `[lib.rs:parse_upstream_manifest]`
- `[lib.rs:format_release_manifest_json]`
- `[lib.rs:format_backstage_json]`
- `[lib.rs:extract_semver_prefix]`
- `[lib.rs:bump_package_json_str]`
- `[lib.rs:release_notes_url]`
- `[lib.rs:run_bump_release]`

## Invariants
- [lib.rs:456]: `assert!(out.contains("bump-release: moving to Backstage 1.56.2"));`
- [lib.rs:457]: `assert!(out.contains("docs/releases/v1.56.0.md"));`
- [lib.rs:460]: `assert!(bj.contains("\"version\": \"1.56.2\""));`

## Side Effects
- [lib.rs:254]: `let output = Command::new("curl")`
- [lib.rs:257]: `.map_err(|e| format!("bump-release: failed to execute curl: {}", e))?;`

## Verification
- Run: `bazel test //apps/web/backstage/src/...`
