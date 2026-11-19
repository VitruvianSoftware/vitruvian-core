# pnpm_lock_gate

## Overview
Fail-open CI gate (`//tools/ci:pnpm_lock_gate`) for web container image workflows (`backstage-image.yaml`, `gods-eye-view-image.yaml`). When a commit touches `pnpm-lock.yaml` alongside no other workflow-relevant files, it computes the transitive dependency closure for each target workspace importer from both base and head `pnpm-lock.yaml` files and emits `verdict=skip` only when the closure and global lockfile settings are identical.

## Interface
- `[lib.rs:run]` — CLI entrypoint (`--workflow <path> --importers <csv> [--base <sha>] [--head <sha>] [--event <name>] [--repo <dir>]`).
- Emits `verdict=run|skip` and `reason=...` to `$GITHUB_OUTPUT` (always fails open to `verdict=run` on uncertainty, missing history, unknown lockfile sections, or unparseable YAML).

## Verification
- Run: `bazel test //tools/ci:pnpm_lock_gate_test`
