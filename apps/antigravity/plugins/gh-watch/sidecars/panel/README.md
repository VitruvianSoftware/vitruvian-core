# Panel

## Overview
Component package providing implementation for `apps/antigravity/plugins/gh-watch/sidecars/panel`.

## Interface
- Internal implementation components
- Subdirectory: [lib](./lib/README.md)
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [app.js:24]: `// window.sidecar; window.sidecar.fetch adds the token non-GET routes need.`
- [app.js:37]: `const res = await sidecar.fetch(path, {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/gh-watch/sidecars/panel/...`
