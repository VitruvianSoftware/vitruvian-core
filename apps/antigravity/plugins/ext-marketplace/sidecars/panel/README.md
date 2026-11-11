# Panel

## Overview
Component package providing implementation for `apps/antigravity/plugins/ext-marketplace/sidecars/panel`.

## Interface
- Internal implementation components
- Subdirectory: [lib](./lib/README.md)
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [app.js:28]: `const res = await sidecar.fetch(path, {`
- [app.js:60]: `const query = $("search-input").value.trim().toLowerCase();`
- [app.js:69]: `if (!query) return true;`

## Verification
- Run: `bazel test //apps/antigravity/plugins/ext-marketplace/sidecars/panel/...`
