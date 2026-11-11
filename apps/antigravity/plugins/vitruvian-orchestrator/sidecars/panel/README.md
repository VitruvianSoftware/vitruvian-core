# Panel

## Overview
Component package providing implementation for `apps/antigravity/plugins/vitruvian-orchestrator/sidecars/panel`.

## Interface
- `[main.mjs:WATCHDOG_MAX_FLOW_AGE_MS]`
- `[main.mjs:WATCHDOG_MAX_IDLE_MS]`
- `[main.mjs:PHASES]`
- `[main.mjs:resolveFlowsDir]`
- `[main.mjs:formatElapsed]`
- `[main.mjs:parseFlowJsonl]`
- `[main.mjs:extractTranscriptRunEvents]`
- `[main.mjs:foldFlowEvents]`
- `[main.mjs:buildPanelState]`
- `[main.mjs:selectFlowFile]`
- `[main.mjs:readTranscriptForConversation]`
- `[main.mjs:readChildTranscriptState]`
- `[main.mjs:readChildTranscriptActivityAt]`
- `[main.mjs:loadLivePanelState]`
- `[main.mjs:checkAndWakeStalledRuns]`
- `[main.mjs:Watchdog]`
- `[main.mjs:createStandaloneServer]`
- Subdirectory: [lib](./lib/README.md)

## Invariants
- [main.test.mjs:23]: `import assert from "node:assert/strict";`
- [main.test.mjs:53]: `assert.equal(formatElapsed(0), "0s");`
- [main.test.mjs:54]: `assert.equal(formatElapsed(45_000), "45s");`

## Side Effects
- [app.js:27]: `const SVG_NS = "http://www.w3.org/2000/svg";`
- [app.js:44]: `const fetcher = sidecar?.fetch`
- [app.js:45]: `? sidecar.fetch.bind(sidecar)`
- [main.mjs:37]: `import { createServer } from "node:http";`
- [main.mjs:268]: `const senderMatch = /\bsender=([a-zA-Z0-9_-]+)/.exec(entry.content);`
- [main.mjs:312]: `const cidMatch = /"conversationId"\s*:\s*"([^"]+)"/.exec(`

## Verification
- Run: `bazel test //apps/antigravity/plugins/vitruvian-orchestrator/sidecars/panel/...`
