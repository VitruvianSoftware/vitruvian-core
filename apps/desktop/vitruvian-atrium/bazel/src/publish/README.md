# Publish

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/publish`.

## Interface
- `[lib.rs:TAG_PREFIX]`
- `[lib.rs:DEFAULT_BETA_TAG]`
- `[lib.rs:TAP]`
- `[lib.rs:USAGE]`
- `[lib.rs:PublishGrade]`
- `[lib.rs:PublishPlan]`
- `[lib.rs:resolve_publish_plan]`
- `[lib.rs:render_homebrew_cask]`
- `[lib.rs:render_beta_release_notes]`
- `[lib.rs:Packager]`
- `[lib.rs:ReleasePackager]`
- `[lib.rs:publish]`
- `[lib.rs:dry_run_lines]`
- `[lib.rs:run_cli]`

## Invariants
- None

## Side Effects
- [lib.rs:291]: `} else if tag_ref.stderr.contains("HTTP 404") {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/publish/...`
