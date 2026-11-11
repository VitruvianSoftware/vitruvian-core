# Tools

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/tools`.

## Interface
- `[area.js:AREA_SCHEMA]`
- `[area.js:resolveArea]`
- `[area.js:POINT_SCHEMA]`
- `[area.js:resolvePoint]`
- `[area.js:areaRadiusKm]`
- `[area.js:distanceKm]`
- `[area.js:areaCenter]`
- `[area.js:areaContains]`
- `[area.js:lineTouchesArea]`
- `[area.js:polygonsTouchArea]`
- `[catalog.js:TOOL_ERROR_CODES]`
- `[catalog.js:ToolError]`
- `[catalog.js:fromSourceError]`
- `[catalog.js:defineTool]`
- `[catalog.js:composeCatalog]`
- `[functions.js:toFunctionTools]`
- `[functions.js:toFunctionOutput]`
- `[globePanel.js:GLOBE_PANEL_URI]`
- `[globePanel.js:PANEL_BASE]`
- `[globePanel.js:PANEL_WORKER_PRELUDE_PATH]`
- Subdirectory: [mcp](./mcp/README.md)
- Subdirectory: [queries](./queries/README.md)

## Invariants
- [area.test.mjs:23]: `import assert from 'node:assert/strict';`
- [area.test.mjs:42]: `await assert.rejects(`
- [area.test.mjs:47]: `await assert.rejects(`
- [catalog-cancellation.test.mjs:24]: `import assert from 'node:assert/strict';`
- [catalog-cancellation.test.mjs:55]: `await assert.rejects(`
- [catalog-cancellation.test.mjs:59]: `assert.equal(calls, 0);`
- [catalog.test.mjs:23]: `import assert from 'node:assert/strict';`
- [catalog.test.mjs:44]: `assert.equal(Object.isFrozen(tool), true);`
- [catalog.test.mjs:45]: `assert.equal(tool.kind, 'query');`
- [functions.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [area.js:350]: `// Wrapping each vertex around the query point would split a dateline ring`
- [catalog-cancellation.test.mjs:28]: `test(`cancelled query refuses execution${intercept ? ' after an awaited inter...`
- [catalog-cancellation.test.mjs:31]: `const query = defineTool({`
- [catalog-cancellation.test.mjs:33]: `kind: 'query',`
- [catalog.js:35]: `const KINDS = new Set(['query', 'action']);`
- [catalog.js:95]: `kind = 'query',`
- [catalog.js:147]: `readOnlyHint: kind === 'query',`
- [catalog.test.mjs:45]: `assert.equal(tool.kind, 'query');`
- [globePanel.test.mjs:101]: `allows(csp.connectDomains, 'https://fbcdn.net.evil.example/'),`
- [globePanel.test.mjs:117]: `services: { app: { baseUrl: 'http://localhost:5173/' } },`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/tools/...`
