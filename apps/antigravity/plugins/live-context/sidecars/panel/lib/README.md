# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/live-context/sidecars/panel/lib`.

## Interface
- `[core.mjs:DEFAULT_RESPONSE_CONTRACT]`
- `[core.mjs:formatLiveGitSummary]`
- `[core.mjs:buildEphemeralContextPayload]`
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
- [core.test.mjs:52]: `assert.match(`
- [core.test.mjs:56]: `assert.match(text, /2 uncommitted files: README\.md, plugin\.json/);`
- [openui.test.mjs:23]: `import assert from "node:assert/strict";`
- [openui.test.mjs:37]: `assert.equal(root.$component, "Card");`
- [openui.test.mjs:85]: `assert.deepEqual(parsed.order, ["root", "hdr"]);`

## Side Effects
- [core.mjs:67]: ``GitHub state unavailable this turn (gh query failed or timed out).\nTreat al...`
- [core.mjs:98]: ``LIVE ${repo} state, fetched just now — this SUPERSEDES any PR/issue status s...`
- [openui.mjs:274]: `if (node.name === "Query") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/live-context/sidecars/panel/lib/...`
