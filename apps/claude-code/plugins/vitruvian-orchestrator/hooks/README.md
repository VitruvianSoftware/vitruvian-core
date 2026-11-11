# Hooks

## Overview
Component package providing implementation for `apps/claude-code/plugins/vitruvian-orchestrator/hooks`.

## Interface
- `[register.tsx:MASCOTS]`
- `[register.tsx:register]`
- Subdirectory: [lib](./lib/README.md)

## Invariants
- None

## Side Effects
- [register.test.tsx:179]: `on("agent.spawn", async (_, e) => ({`
- [register.test.tsx:204]: `await $.agent.spawn({`
- [register.test.tsx:210]: `await $.agent.spawn({`

## Verification
- Run: `bazel test //apps/claude-code/plugins/vitruvian-orchestrator/hooks/...`
