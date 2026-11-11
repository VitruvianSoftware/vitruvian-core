# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/ralph-loop/sidecars/panel/lib`.

## Interface
- `[core.mjs:MIN_ITERATIONS]`
- `[core.mjs:MAX_ITERATIONS_LIMIT]`
- `[core.mjs:DEFAULT_MAX_ITERATIONS]`
- `[core.mjs:createLoopState]`
- `[core.mjs:updateLoopIteration]`
- `[core.mjs:summariseLoops]`
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
- [core.test.mjs:33]: `assert.throws(() => createLoopState({ conversationId: "   " }));`
- [core.test.mjs:42]: `assert.deepEqual(loop, {`
- [openui.test.mjs:23]: `import assert from "node:assert/strict";`
- [openui.test.mjs:37]: `assert.equal(root.$component, "Card");`
- [openui.test.mjs:75]: `assert.deepEqual(parsed.order, ["root", "title"]);`

## Side Effects
- [openui.mjs:276]: `if (node.name === "Query") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/ralph-loop/sidecars/panel/lib/...`
