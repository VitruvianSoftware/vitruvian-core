# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/worktree-band/sidecars/panel/lib`.

## Interface
- `[core.mjs:fmtSize]`
- `[core.mjs:countChecks]`
- `[core.mjs:isRemovable]`
- `[core.mjs:judgeCleanup]`
- `[core.mjs:totalCacheKb]`
- `[core.mjs:summariseWorktrees]`
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
- [core.test.mjs:36]: `assert.equal(fmtSize(null), "…");`
- [core.test.mjs:37]: `assert.equal(fmtSize(undefined), "…");`
- [openui.test.mjs:23]: `import assert from "node:assert/strict";`
- [openui.test.mjs:37]: `assert.equal(root.$component, "Card");`
- [openui.test.mjs:85]: `assert.deepEqual(parsed.order, ["root", "title"]);`

## Side Effects
- [openui.mjs:276]: `if (node.name === "Query") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/worktree-band/sidecars/panel/lib/...`
