# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/ext-marketplace/sidecars/panel/lib`.

## Interface
- `[core.mjs:MARKETPLACE_CATALOG]`
- `[core.mjs:inspectPluginDirMeta]`
- `[core.mjs:applyPluginToggleToConfig]`
- `[core.mjs:mergeInstalledWithCatalog]`
- `[core.mjs:summariseMarketplace]`
- `[openui.mjs:escapeHtml]`
- `[openui.mjs:resolveDataPath]`
- `[openui.mjs:parseOpenUILang]`
- `[openui.mjs:renderNodeToHtml]`
- `[openui.mjs:renderOpenUIFragment]`
- `[openui.mjs:compileToHtml]`
- `[openui.mjs:openuiLiteral]`
- `[openui.mjs:toOpenUILang]`

## Invariants
- [core.test.mjs:23]: `import assert from "node:assert/strict";`
- [core.test.mjs:53]: `assert.equal(MARKETPLACE_CATALOG.length, 9);`
- [core.test.mjs:54]: `assert.deepEqual(`
- [openui.test.mjs:23]: `import assert from "node:assert/strict";`
- [openui.test.mjs:37]: `assert.equal(root.$component, "Card");`
- [openui.test.mjs:51]: `assert.deepEqual(parsed.order, ["root", "title"]);`

## Side Effects
- [openui.mjs:274]: `if (node.name === "Query") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/ext-marketplace/sidecars/panel/lib/...`
