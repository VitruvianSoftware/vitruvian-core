# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/savvy-fleet/sidecars/panel/lib`.

## Interface
- `[core.mjs:PHASES]`
- `[core.mjs:TIERS]`
- `[core.mjs:SPECIALIST_DEFAULTS]`
- `[core.mjs:blankFlow]`
- `[core.mjs:normalizeText]`
- `[core.mjs:inferTier]`
- `[core.mjs:mergeFlowProgress]`
- `[core.mjs:estimateRunCost]`
- `[core.mjs:extractSubagentsFromTranscript]`
- `[core.mjs:summariseFleetState]`
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
- [core.test.mjs:38]: `assert.deepEqual(PHASES, ["plan", "design", "delegate", "review", "close"]);`
- [core.test.mjs:47]: `assert.ok(tier in TIERS, `missing tier ${tier}`);`
- [openui.test.mjs:23]: `import assert from "node:assert/strict";`
- [openui.test.mjs:37]: `assert.equal(root.$component, "Card");`
- [openui.test.mjs:51]: `assert.deepEqual(parsed.order, ["root", "title"]);`

## Side Effects
- [core.mjs:123]: `const bracketMatch = /\[(fable|heavy|careful|medium|light)\]/i.exec(`
- [openui.mjs:274]: `if (node.name === "Query") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/savvy-fleet/sidecars/panel/lib/...`
