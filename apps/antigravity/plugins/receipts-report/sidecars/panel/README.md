# Panel

## Overview
Component package providing implementation for `apps/antigravity/plugins/receipts-report/sidecars/panel`.

## Interface
- Internal implementation components
- Subdirectory: [lib](./lib/README.md)
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [app.js:29]: `const res = await sidecar.fetch(path, {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/receipts-report/sidecars/panel/...`
