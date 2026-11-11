# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/receipts-report/sidecars/panel/lib`.

## Interface
- `[core.mjs:projectFromPath]`
- `[core.mjs:parseTranscriptJsonl]`
- `[core.mjs:aggregateProjectReceipts]`
- `[core.mjs:detectTokenHotspots]`
- `[core.mjs:formatCsvReceipt]`
- `[core.mjs:renderHtmlReceipt]`
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
- [core.test.mjs:96]: `assert.equal(`
- [core.test.mjs:102]: `assert.equal(projectFromPath(""), "unassigned");`
- [openui.test.mjs:23]: `import assert from "node:assert/strict";`
- [openui.test.mjs:37]: `assert.equal(root.$component, "Card");`
- [openui.test.mjs:104]: `assert.deepEqual(parsed.order, ["root", "title"]);`

## Side Effects
- [openui.mjs:274]: `if (node.name === "Query") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/receipts-report/sidecars/panel/lib/...`
