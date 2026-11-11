# Mcp

## Overview
Component package providing implementation for `apps/antigravity/plugins/vitruvian-orchestrator/mcp`.

## Interface
- `[server.mjs:SERVER_INFO]`
- `[server.mjs:TOOLS]`
- `[server.mjs:defaultFlowsDir]`
- `[server.mjs:sanitizeConversationId]`
- `[server.mjs:extractConversationMeta]`
- `[server.mjs:mapProgressToEvents]`
- `[server.mjs:mapStepToEvent]`
- `[server.mjs:readFlowFromJsonlFile]`
- `[server.mjs:appendFlowEvents]`
- `[server.mjs:formatFlowSummary]`
- `[server.mjs:handleJsonRpcMessage]`
- `[server.mjs:parseJsonRpcFrames]`
- `[server.mjs:formatJsonRpcFrame]`
- `[server.mjs:startStdioServer]`

## Invariants
- [server.test.mjs:23]: `import assert from "node:assert/strict";`
- [server.test.mjs:56]: `assert.deepEqual(`
- [server.test.mjs:60]: `assert.equal(events[0].title, "Multi-domain Rollout");`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/vitruvian-orchestrator/mcp/...`
