# Publish

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/scripts/src/publish`.

## Interface
- `[lib.rs:Config]`
- `[lib.rs:derive_version]`
- `[lib.rs:read_version_from_swift]`
- `[lib.rs:read_manifest_version]`
- `[lib.rs:json_escape]`
- `[lib.rs:parse_config]`
- `[lib.rs:resolve_app_dir]`
- `[lib.rs:resolve_repo_root]`
- `[lib.rs:build_gh_create_args]`
- `[lib.rs:build_gh_upload_args]`
- `[lib.rs:dry_run_message]`
- `[lib.rs:check_universal_archs]`
- `[lib.rs:compute_sha256]`
- `[lib.rs:zip_tool_bundle]`
- `[lib.rs:bundle_app]`
- `[lib.rs:expected_dist_files]`
- `[lib.rs:verify_dist_artifacts]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/scripts/src/publish/...`
