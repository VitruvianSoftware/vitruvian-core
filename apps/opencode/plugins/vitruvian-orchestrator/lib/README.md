# Lib

## Overview
Component package providing implementation for `apps/opencode/plugins/vitruvian-orchestrator/lib`.

## Interface
- `[adapter.mjs:PHASES]`
- `[adapter.mjs:EMPTY_PANEL_MESSAGE]`
- `[adapter.mjs:statusColorToken]`
- `[adapter.mjs:parseModelAndEffort]`
- `[adapter.mjs:shortModelName]`
- `[adapter.mjs:mapOpenCodeTokens]`
- `[adapter.mjs:mergeTokenSnapshots]`
- `[adapter.mjs:mapProgressInputToEvents]`
- `[adapter.mjs:applyProgressCall]`
- `[adapter.mjs:applyStepCall]`
- `[adapter.mjs:sparkline]`
- `[adapter.mjs:formatTokensCompact]`
- `[adapter.mjs:formatUsd]`
- `[adapter.mjs:formatDuration]`
- `[adapter.mjs:formatSidebarTitle]`
- `[adapter.mjs:formatSidebarData]`
- `[adapter.mjs:formatSidebarLines]`
- `[orchestrator-core.mjs:DEFAULT_QUIET_MS]`
- `[orchestrator-core.mjs:DEFAULT_STALL_MS]`
- `[orchestrator-core.mjs:DEFAULT_WAITING_STALL_MS]`

## Invariants
- [adapter.test.mjs:21]: `import assert from "node:assert/strict";`
- [adapter.test.mjs:49]: `assert.ok(row, `missing PRICES entry for match=${JSON.stringify(match)}`);`
- [adapter.test.mjs:70]: `assert.deepEqual(`

## Side Effects
- [adapter.test.mjs:429]: `const tmpDir = fs.mkdtempSync(`

## Verification
- Run: `bazel test //apps/opencode/plugins/vitruvian-orchestrator/lib/...`
