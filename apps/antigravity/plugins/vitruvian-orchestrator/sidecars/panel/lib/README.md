# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/vitruvian-orchestrator/sidecars/panel/lib`.

## Interface
- `[orchestrator-core.mjs:DEFAULT_QUIET_MS]`
- `[orchestrator-core.mjs:DEFAULT_STALL_MS]`
- `[orchestrator-core.mjs:DEFAULT_WAITING_STALL_MS]`
- `[orchestrator-core.mjs:initialFlow]`
- `[orchestrator-core.mjs:reduce]`
- `[orchestrator-core.mjs:remaining]`
- `[orchestrator-core.mjs:burnDown]`
- `[orchestrator-core.mjs:taskBoard]`
- `[orchestrator-core.mjs:delegateCost]`
- `[orchestrator-core.mjs:runCost]`
- `[orchestrator-core.mjs:spend]`
- `[orchestrator-core.mjs:stalls]`
- `[prices.mjs:PRICES_UPDATED]`
- `[prices.mjs:PRICES]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/vitruvian-orchestrator/sidecars/panel/lib/...`
