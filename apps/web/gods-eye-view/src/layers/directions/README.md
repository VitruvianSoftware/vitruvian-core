# Directions

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/directions`.

## Interface
- `[index.js:DIRECTIONS_STEP_OVERLAY_SOURCE_ID]`
- `[index.js:DIRECTIONS_STEP_OVERLAY_SOURCE_OPTIONS]`
- `[index.js:DIRECTIONS_MODES]`
- `[index.js:DEFAULT_DIRECTIONS_MODE]`
- `[index.js:presentRoutingFailure]`
- `[index.js:DIRECTIONS_ROUTE_COLOR]`
- `[index.js:DIRECTIONS_POINTER_OWNER]`
- `[index.js:STEP_ANCHOR_DEADLINE_MS]`
- `[index.js:STEP_ANCHOR_RETRY_MS]`
- `[index.js:STEP_ANCHOR_SLOW_RETRY_MS]`
- `[index.js:STEP_ANCHOR_FAST_ATTEMPTS]`
- `[index.js:FLIGHT_PROGRESS_MS]`
- `[index.js:routeDistanceText]`
- `[index.js:routeDurationText]`
- `[index.js:directionsInstruction]`
- `[index.js:normalizeDirectionsParams]`
- `[index.js:directionsRowControls]`
- `[index.js:POINTER_TOOL_EXITS]`
- `[index.js:pointerBlockedMessage]`
- `[index.js:stepMarkerIndices]`

## Invariants
- [source.test.mjs:24]: `import assert from 'node:assert/strict';`
- [source.test.mjs:37]: `assert.deepEqual(await source.getRoute(query, { signal: controller.signal }),...`
- [source.test.mjs:38]: `assert.equal(calls.length, 1);`
- [statusLocale.test.mjs:26]: `import assert from 'node:assert/strict';`
- [statusLocale.test.mjs:97]: `assert.equal(stats.error, english);`
- [statusLocale.test.mjs:99]: `assert.ok(row.includes(translate(english)), `${locale}: ${row}`);`

## Side Effects
- [index.js:87]: `return `Routing unavailable (HTTP ${error.status})`;`
- [source.js:27]: `/** Build the existing route-proxy query from geographic endpoints. */`
- [source.js:35]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:41]: `const query = directionsRequestUrl(mode, a, b).split('?')[1];`
- [source.test.mjs:27]: `const query = { mode: 'foot', a: { lon: 1, lat: 2 }, b: { lon: 3, lat: 4 } };`
- [source.test.mjs:37]: `assert.deepEqual(await source.getRoute(query, { signal: controller.signal }),...`
- [source.test.mjs:52]: `await assert.rejects(source.getRoute(query, { signal: controller.signal }), {...`
- [statusLocale.test.mjs:64]: `// Route request failures with the proxy's refusal or an HTTP status in them:`
- [statusLocale.test.mjs:81]: `'Routing unavailable (HTTP 503)',`
- [statusLocale.test.mjs:82]: `translate('Routing unavailable (HTTP {status})', { status: 503 }),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/directions/...`
