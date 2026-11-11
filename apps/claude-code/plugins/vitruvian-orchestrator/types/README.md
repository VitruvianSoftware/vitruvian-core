# Types

## Overview
Component package providing implementation for `apps/claude-code/plugins/vitruvian-orchestrator/types`.

## Interface
- `[index.d.ts:Phase]`
- `[index.d.ts:Tier]`
- `[index.d.ts:TaskState]`
- `[index.d.ts:Harness]`
- `[index.d.ts:RunStatus]`
- `[index.d.ts:RunRole]`
- `[index.d.ts:TokenCounts]`
- `[index.d.ts:DelegateTokenCounts]`
- `[index.d.ts:StepProgress]`
- `[index.d.ts:ReplanPoint]`
- `[index.d.ts:HistoryPoint]`
- `[index.d.ts:Task]`
- `[index.d.ts:Run]`
- `[index.d.ts:Flow]`
- `[index.d.ts:PlanTaskInput]`
- `[index.d.ts:BurnDown]`
- `[index.d.ts:TaskBoardRow]`
- `[index.d.ts:UnpricedSummary]`
- `[index.d.ts:DelegatedSummary]`
- `[index.d.ts:SpendSummary]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/claude-code/plugins/vitruvian-orchestrator/types/...`
