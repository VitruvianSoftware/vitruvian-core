# Macos

## Overview
Component package providing implementation for `apps/desktop/vitruvian-code/macos`.

## Interface
- Internal implementation components
- Subdirectory: [Sources](./Sources/README.md). The agent connections (ACP client, Claude SDK connection, registry installs) are in `Sources/VitruvianCodeCore/ACP/`
- Subdirectory: [claude-helper](./claude-helper/README.md): the bundled Node helper that runs the Claude Agent SDK and speaks ACP to the app
- Subdirectory: [scripts](./scripts/README.md)

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-code/macos/...`
