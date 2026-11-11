# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/hookify/sidecars/panel/lib`.

## Interface
- `[core.mjs:SUPPORTED_OPERATORS]`
- `[core.mjs:SUPPORTED_ACTIONS]`
- `[core.mjs:parseHookifyMarkdown]`
- `[core.mjs:serializeHookifyMarkdown]`
- `[core.mjs:extractFieldFromPayload]`
- `[core.mjs:evaluateCondition]`
- `[core.mjs:evaluateRule]`
- `[core.mjs:evaluatePreToolUse]`
- `[core.mjs:evaluateStop]`
- `[core.mjs:summariseHookifyState]`
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
- [core.test.mjs:57]: `assert.ok(rule);`
- [core.test.mjs:58]: `assert.equal(rule.name, "block-rm-rf");`
- [openui.test.mjs:23]: `import assert from "node:assert/strict";`
- [openui.test.mjs:37]: `assert.equal(root.$component, "Card");`
- [openui.test.mjs:50]: `assert.deepEqual(parsed.order, ["root", "title"]);`

## Side Effects
- [openui.mjs:274]: `if (node.name === "Query") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/hookify/sidecars/panel/lib/...`
