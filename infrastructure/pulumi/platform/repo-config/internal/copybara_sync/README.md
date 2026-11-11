# Copybara Sync

## Overview
Component package providing implementation for `infrastructure/pulumi/platform/repo-config/internal/copybara_sync`.

## Interface
- `[sync.go:ManageSyncAuth]`

## Invariants
- [sync.go:39]: `// protection on the standalone repo's main (require-a-PR, EnforceAdmins=fals...`

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/platform/repo-config/internal/copybara_sync/...`
