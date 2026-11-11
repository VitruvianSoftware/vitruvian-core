# Panel

## Overview
Component package providing implementation for `apps/antigravity/plugins/worktree-band/sidecars/panel`.

## Interface
- Internal implementation components
- Subdirectory: [lib](./lib/README.md)
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [app.js:29]: `const res = await sidecar.fetch(path, {`
- [main.mjs:159]: `.exec(rc)?.[1]`

## Verification
- Run: `bazel test //apps/antigravity/plugins/worktree-band/sidecars/panel/...`
