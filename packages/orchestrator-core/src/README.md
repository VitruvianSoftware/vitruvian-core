# Src

## Overview
Component package providing implementation for `packages/orchestrator-core/src`.

## Interface
- `[core.mjs:DEFAULT_QUIET_MS]`
- `[core.mjs:DEFAULT_STALL_MS]`
- `[core.mjs:DEFAULT_WAITING_STALL_MS]`
- `[core.mjs:initialFlow]`
- `[core.mjs:reduce]`
- `[core.mjs:remaining]`
- `[core.mjs:burnDown]`
- `[core.mjs:taskBoard]`
- `[core.mjs:delegateCost]`
- `[core.mjs:runCost]`
- `[core.mjs:spend]`
- `[core.mjs:stalls]`
- `[prices.mjs:PRICES_UPDATED]`
- `[prices.mjs:PRICES]`

## Invariants
- [core.test.mjs:23]: `import assert from "node:assert/strict";`
- [core.test.mjs:46]: `assert.ok(row, `missing PRICES entry for match=${JSON.stringify(match)}`);`
- [core.test.mjs:51]: `assert.equal(typeof actual, "number");`

## Side Effects
- None

## Verification
- Run: `bazel test //packages/orchestrator-core/src/...`
